import cv2
import cv2.aruco as aruco
import numpy as np
import json
import math
import os
import socket
import sys
import threading
import time
import struct
from multiprocessing import shared_memory

try:
    import pyrealsense2 as rs
except ImportError:
    rs = None

dai = None

def ensure_depthai():
    global dai
    if dai is not None:
        return dai
    try:
        import depthai as depthai_module
    except ImportError as exc:
        raise RuntimeError("depthai is not installed") from exc
    dai = depthai_module
    return dai

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None

try:
    from experiments.realsense_head_tracker_demo.realsense_head_tracker_demo import (
        DEFAULT_POSE_MODEL_PATH as REALSENSE_POSE_MODEL_DEFAULT,
        AsyncTrackerWorker as DemoRealSenseTrackerWorker,
    )
except Exception as exc:
    REALSENSE_POSE_MODEL_DEFAULT = os.path.join(
        "experiments",
        "realsense_head_tracker_demo",
        "models",
        "pose_landmarker_lite.task",
    )
    DemoRealSenseTrackerWorker = None
    print(f">>> Demo RealSense tracker worker unavailable: {exc} <<<")

if os.name == "nt":
    import msvcrt

TRACKER_CONTROL_PORT = 4244
REALSENSE_POINT_CLOUD_PORT = int(os.environ.get("REALSENSE_POINT_CLOUD_PORT", "4245"))
REALSENSE_POINT_CLOUD_TCP_PORT = int(os.environ.get("REALSENSE_POINT_CLOUD_TCP_PORT", "4246"))
REALSENSE_POINT_CLOUD_MAGIC = b"RSPC01\x00\x00"
REALSENSE_POINT_CLOUD_FRAME_MAGIC = b"RSPF01\x00\x00"
REALSENSE_POINT_CLOUD_SHM_NAME = os.environ.get("REALSENSE_POINT_CLOUD_SHM_NAME", "realsense_point_cloud_grid")
OAKD_POINT_CLOUD_SHM_NAME = os.environ.get("OAKD_POINT_CLOUD_SHM_NAME", "oakd_point_cloud_grid")
REALSENSE_POINT_CLOUD_SHM_MAGIC = b"RSPG01\x00\x00"
REALSENSE_POINT_CLOUD_SHM_HEADER_SIZE = 128
REALSENSE_POINT_CLOUD_SHM_MAX_BYTES = int(os.environ.get("REALSENSE_POINT_CLOUD_SHM_BYTES", str(16 * 1024 * 1024)))
# Keep UDP datagrams below the usual 1500-byte MTU:
# 28-byte app header + 90 * 16-byte point records = 1468 bytes.
# Larger datagrams work on localhost sometimes, but rely on IP fragmentation and
# make complete point-cloud frames collapse when a single fragment is late/lost.
REALSENSE_POINT_CLOUD_DEFAULT_PACKET_POINTS = int(os.environ.get("REALSENSE_POINT_CLOUD_PACKET_POINTS", "90"))
TRACKER_WINDOW_NAME = "Multi-Monitor ArUco Constellation Tracker"
ROOM_MAP_WINDOW_NAME = "3D Room Spatial Map"
TRACKER_WINDOW_DEFAULT_WIDTH = 640
TRACKER_WINDOW_DEFAULT_HEIGHT = 360
ROOM_MAP_WINDOW_DEFAULT_WIDTH = 400
ROOM_MAP_WINDOW_DEFAULT_HEIGHT = 320
WINDOW_DEFAULT_X = 60
WINDOW_DEFAULT_Y = 60
WINDOW_DEFAULT_GAP = 16
ROOM_MAP_DEFAULT_VIEW_DIST = 60.0
CAMERA_TOGGLE_KEY = ord('v')
CAMERA_KEY_LEFT = 81
CAMERA_KEY_UP = 82
CAMERA_KEY_RIGHT = 83
CAMERA_KEY_DOWN = 84
CAMERA_KEY_LEFT_EX = 2424832
CAMERA_KEY_UP_EX = 2490368
CAMERA_KEY_RIGHT_EX = 2555904
CAMERA_KEY_DOWN_EX = 2621440
CAMERA_PICKER_KEY = ord('y')
CAMERA_SOURCE_TOGGLE_KEY = ord('s')
CAMERA_INDEX_DEFAULT = 0
CAMERA_INDEX_ENV = "CAMERA_INDEX"
CAMERA_SOURCE_ENV = "TRACKER_CAMERA_SOURCE"
CAMERA_SOURCE_WEBCAM = "webcam"
CAMERA_SOURCE_REALSENSE = "realsense"
REALSENSE_TRACKING_MODE_KEY = ord('m')
REALSENSE_TRACKING_ENABLE_KEY = ord('n')
STEREO_SCREEN_SIZE_TOGGLE_KEY = ord('h')
REALSENSE_TRACKING_MODE_ENV = "REALSENSE_TRACKING_MODE"
REALSENSE_TRACKING_ENABLED_ENV = "REALSENSE_TRACKING_ENABLED"
STEREO_SCREEN_SIZE_AUTO_ENV = "STEREO_SCREEN_SIZE_AUTO"
REALSENSE_TRACKING_MODES = ["ml", "yolo"]
REALSENSE_HEAD_MODEL_ENV = "REALSENSE_HEAD_MODEL"
REALSENSE_HEAD_MODEL_DEFAULT = os.path.join(
    "experiments",
    "realsense_head_tracker_demo",
    "models",
    "yolov8_head_nano.pt",
)
CAMERA_INDEX_AUTO_MAX = 6
HEAD_TO_CAMERA_DEBUG_KEY = ord('f')
ANCHOR_POSE_MODE_BUTTON_LABEL = "Anchor"
ANCHOR_POSE_MODES = ["smooth", "stable", "raw"]
ANCHOR_POSE_MODE_LABELS = {
    "smooth": "Smooth",
    "stable": "Stable",
    "raw": "Raw",
}
ANCHOR_POSE_GUESS_TIMEOUT_SEC = 0.25
ANCHOR_STABLE_BLEND_ALPHA = 0.18
PREFERRED_CAMERA_MODES = [
    (2560, 1440),
    (2560, 1080),
    (2304, 1296),
    (1920, 1080),
    (1600, 1200),
    (1280, 960),
    (1280, 720),
]
PREFERRED_CAMERA_FPS = 60
REALSENSE_CAMERA_FPS = int(os.environ.get("REALSENSE_CAMERA_FPS", "60"))
REALSENSE_DEPTH_WIDTH = int(os.environ.get("REALSENSE_DEPTH_WIDTH", "640"))
REALSENSE_DEPTH_HEIGHT = int(os.environ.get("REALSENSE_DEPTH_HEIGHT", "480"))
REALSENSE_COLOR_WIDTH = int(os.environ.get("REALSENSE_COLOR_WIDTH", "1280"))
REALSENSE_COLOR_HEIGHT = int(os.environ.get("REALSENSE_COLOR_HEIGHT", "720"))
REALSENSE_COLOR_FPS = int(os.environ.get("REALSENSE_COLOR_FPS", str(REALSENSE_CAMERA_FPS)))
FUSION_CHARUCO_MIN_CORNERS = int(os.environ.get("FUSION_CHARUCO_MIN_CORNERS", "12"))
FUSION_CHARUCO_SAMPLE_FRAMES = int(os.environ.get("FUSION_CHARUCO_SAMPLE_FRAMES", "12"))
WORLD_ANCHOR_MARKER_IDS = [45, 46, 47, 48, 49]
WORLD_ANCHOR_MARKER_SIZE_INCHES = 6.0
BIG_ARUCO_MARKER_SIZE_M = float(os.environ.get("BIG_ARUCO_MARKER_SIZE_M", "0.15"))
DEFAULT_VIEWER_DISTANCE_METERS = 0.5
METERS_TO_WORLD_UNITS = 39.37007874015748
CM_TO_WORLD_UNITS = 0.3937007874015748
TRACKING_POSE_TIMEOUT_SEC = 0.5
TRACKING_DEFAULT_HEAD_DISTANCE = DEFAULT_VIEWER_DISTANCE_METERS * METERS_TO_WORLD_UNITS
TRACKER_CAMERA_POSE_SEND_INTERVAL_SEC = 0.1
RESOLVED_HEAD_POSE_SEND_INTERVAL_SEC = 1.0 / 60.0
REALSENSE_TRACKING_SEND_INTERVAL_SEC = 1.0 / 60.0
REALSENSE_POINT_CLOUD_SEND_INTERVAL_SEC = 1.0 / float(os.environ.get("REALSENSE_POINT_CLOUD_FPS", str(REALSENSE_CAMERA_FPS)))
REALSENSE_POINT_CLOUD_DEFAULT_STRIDE = int(os.environ.get("REALSENSE_POINT_CLOUD_STRIDE", "1"))
REALSENSE_POINT_CLOUD_MIN_DEPTH_M = float(os.environ.get("REALSENSE_POINT_CLOUD_MIN_DEPTH", "0.20"))
REALSENSE_POINT_CLOUD_MAX_DEPTH_M = float(os.environ.get("REALSENSE_POINT_CLOUD_MAX_DEPTH", "4.50"))
REALSENSE_POINT_CLOUD_MAX_POINTS = int(os.environ.get("REALSENSE_POINT_CLOUD_MAX_POINTS", "0"))
REALSENSE_POINT_CLOUD_MESH_MAX_EDGE_M = float(os.environ.get("REALSENSE_POINT_CLOUD_MESH_MAX_EDGE", "0.08"))
REALSENSE_DEPTH_FILTERS_ENABLED = os.environ.get("REALSENSE_DEPTH_FILTERS", "1").strip().lower() not in ("0", "false", "no", "off")
REALSENSE_DEPTH_SPATIAL_ALPHA = float(os.environ.get("REALSENSE_DEPTH_SPATIAL_ALPHA", "0.55"))
REALSENSE_DEPTH_SPATIAL_DELTA = float(os.environ.get("REALSENSE_DEPTH_SPATIAL_DELTA", "18"))
REALSENSE_DEPTH_TEMPORAL_ALPHA = float(os.environ.get("REALSENSE_DEPTH_TEMPORAL_ALPHA", "0.35"))
REALSENSE_DEPTH_TEMPORAL_DELTA = float(os.environ.get("REALSENSE_DEPTH_TEMPORAL_DELTA", "25"))
REALSENSE_DEPTH_HOLE_FILLING = int(os.environ.get("REALSENSE_DEPTH_HOLE_FILLING", "1"))
REALSENSE_DEPTH_DISPARITY_FILTERS = os.environ.get("REALSENSE_DEPTH_DISPARITY_FILTERS", "1").strip().lower() not in ("0", "false", "no", "off")
REALSENSE_FILTERS_FOR_POINT_CLOUD_GEOMETRY = os.environ.get("REALSENSE_FILTERS_FOR_POINT_CLOUD_GEOMETRY", "0").strip().lower() not in ("0", "false", "no", "off")
REALSENSE_FILTER_GEOMETRY_EDGE_GUARD_M = float(os.environ.get("REALSENSE_FILTER_GEOMETRY_EDGE_GUARD_M", "0.07"))
OAKD_POINT_CLOUD_DEFAULT_STRIDE = int(os.environ.get("OAKD_POINT_CLOUD_STRIDE", "1"))
OAKD_POINT_CLOUD_MIN_DEPTH_M = float(os.environ.get("OAKD_POINT_CLOUD_MIN_DEPTH", "0.20"))
OAKD_POINT_CLOUD_MAX_DEPTH_M = float(os.environ.get("OAKD_POINT_CLOUD_MAX_DEPTH", "4.50"))
OAKD_WIDTH = int(os.environ.get("OAKD_WIDTH", "1024"))
OAKD_HEIGHT = int(os.environ.get("OAKD_HEIGHT", "576"))
OAKD_FPS = float(os.environ.get("OAKD_FPS", "30"))
OAKD_POINT_CLOUD_SEND_INTERVAL_SEC = 1.0 / float(os.environ.get("OAKD_POINT_CLOUD_FPS", str(OAKD_FPS)))
OAKD_LR_CHECK = os.environ.get("OAKD_LR_CHECK", "1").strip().lower() not in ("0", "false", "no", "off")
OAKD_SUBPIXEL = os.environ.get("OAKD_SUBPIXEL", "1").strip().lower() not in ("0", "false", "no", "off")
OAKD_SUBPIXEL_BITS = int(os.environ.get("OAKD_SUBPIXEL_BITS", "3"))
OAKD_CONFIDENCE_THRESHOLD = int(os.environ.get("OAKD_CONFIDENCE_THRESHOLD", "120"))
OAKD_MEDIAN_FILTER = os.environ.get("OAKD_MEDIAN_FILTER", "7x7").strip().lower()
OAKD_SPECKLE_FILTER = os.environ.get("OAKD_SPECKLE_FILTER", "1").strip().lower() not in ("0", "false", "no", "off")
OAKD_SPECKLE_RANGE = int(os.environ.get("OAKD_SPECKLE_RANGE", "50"))
OAKD_DEMO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "experiments", "oakd_head_tracker_demo")
DEFAULT_FAST_FOUNDATION_DIR = os.path.join(OAKD_DEMO_DIR, "external", "Fast-FoundationStereo")
DEFAULT_FAST_FOUNDATION_MODEL = os.path.join(DEFAULT_FAST_FOUNDATION_DIR, "weights", "20-30-48", "model_best_bp2_serialize.pth")
DEFAULT_FAST_FOUNDATION_ONNX = os.path.join(
    DEFAULT_FAST_FOUNDATION_DIR,
    "weights",
    "onnx",
    "20_30_48",
    "320x736",
    "20_30_48_iters_4_res_320x736.onnx",
)
DEFAULT_FAST_FOUNDATION_TRT_ENGINE = os.path.splitext(DEFAULT_FAST_FOUNDATION_ONNX)[0] + "_fp16.engine"
FAST_FOUNDATION_MODEL_PROFILES = {
    "full_320x736_i4": {
        "onnx": DEFAULT_FAST_FOUNDATION_ONNX,
        "engine": DEFAULT_FAST_FOUNDATION_TRT_ENGINE,
        "label": "full 320x736 iters=4",
    },
    "rt_256x512_i2": {
        "onnx": os.path.join(
            DEFAULT_FAST_FOUNDATION_DIR,
            "weights",
            "onnx",
            "20_30_48",
            "256x512",
            "20_30_48_iters_2_res_256x512.onnx",
        ),
        "engine": os.path.join(
            DEFAULT_FAST_FOUNDATION_DIR,
            "weights",
            "onnx",
            "20_30_48",
            "256x512",
            "20_30_48_iters_2_res_256x512_fp16.engine",
        ),
        "label": "realtime 256x512 iters=2",
    },
    "fast_192x384_i2": {
        "onnx": os.path.join(
            DEFAULT_FAST_FOUNDATION_DIR,
            "weights",
            "onnx",
            "20_30_48",
            "192x384",
            "20_30_48_iters_2_res_192x384.onnx",
        ),
        "engine": os.path.join(
            DEFAULT_FAST_FOUNDATION_DIR,
            "weights",
            "onnx",
            "20_30_48",
            "192x384",
            "20_30_48_iters_2_res_192x384_fp16.engine",
        ),
        "label": "fast 192x384 iters=2",
    },
}
_FAST_FOUNDATION_ONNX_DLL_HANDLES = []

def ensure_fast_foundation_onnx_dll_paths():
    if os.name != "nt":
        return []
    extra_dirs = []
    env_dirs = os.environ.get("FAST_FOUNDATIONSTEREO_DLL_DIRS", "").strip()
    if env_dirs:
        extra_dirs.extend(path for path in env_dirs.split(os.pathsep) if path)
    try:
        import site
        site_dirs = [sys.prefix, site.getusersitepackages()]
    except Exception:
        site_dirs = [sys.prefix]
    for base in site_dirs:
        extra_dirs.append(os.path.join(base, "Lib", "site-packages", "tensorrt_libs"))
        extra_dirs.append(os.path.join(base, "Lib", "site-packages", "torch", "lib"))
        extra_dirs.append(os.path.join(base, "tensorrt_libs"))
        extra_dirs.append(os.path.join(base, "torch", "lib"))

    used = []
    path_parts_lower = {part.lower() for part in os.environ.get("PATH", "").split(os.pathsep) if part}
    for dll_dir in extra_dirs:
        dll_dir = os.path.abspath(dll_dir)
        if not os.path.isdir(dll_dir) or dll_dir in used:
            continue
        used.append(dll_dir)
        if dll_dir.lower() not in path_parts_lower:
            os.environ["PATH"] = dll_dir + os.pathsep + os.environ.get("PATH", "")
            path_parts_lower.add(dll_dir.lower())
        try:
            _FAST_FOUNDATION_ONNX_DLL_HANDLES.append(os.add_dll_directory(dll_dir))
        except Exception:
            pass
    return used

CHARUCO_SQUARES_X = int(os.environ.get("FUSION_CHARUCO_SQUARES_X", "8"))
CHARUCO_SQUARES_Y = int(os.environ.get("FUSION_CHARUCO_SQUARES_Y", "6"))
CHARUCO_SQUARE_M = float(os.environ.get("FUSION_CHARUCO_SQUARE_M", "0.030"))
CHARUCO_MARKER_M = float(os.environ.get("FUSION_CHARUCO_MARKER_M", "0.022"))
CAMERA_AUTO_CALIBRATE_INTRINSICS = os.environ.get("CAMERA_AUTO_CALIBRATE_INTRINSICS", "0").strip().lower() in ("1", "true", "yes", "on")
REALSENSE_VISUAL_PRESET = int(os.environ.get("REALSENSE_VISUAL_PRESET", "-1"))
REALSENSE_EMITTER_ENABLED = int(os.environ.get("REALSENSE_EMITTER_ENABLED", "-1"))
REALSENSE_LASER_POWER = float(os.environ.get("REALSENSE_LASER_POWER", "-1"))
REALSENSE_COLOR_AUTO_EXPOSURE = int(os.environ.get("REALSENSE_COLOR_AUTO_EXPOSURE", "-1"))
REALSENSE_COLOR_EXPOSURE = float(os.environ.get("REALSENSE_COLOR_EXPOSURE", "-1"))
REALSENSE_COLOR_GAIN = float(os.environ.get("REALSENSE_COLOR_GAIN", "-1"))
REALSENSE_COLOR_AUTO_WHITE_BALANCE = int(os.environ.get("REALSENSE_COLOR_AUTO_WHITE_BALANCE", "-1"))
REALSENSE_COLOR_WHITE_BALANCE = float(os.environ.get("REALSENSE_COLOR_WHITE_BALANCE", "-1"))
REALSENSE_DEFAULT_SETTINGS_JSON = os.environ.get("REALSENSE_DEFAULT_SETTINGS_JSON", "default_settings.json")
REALSENSE_APPLY_DEFAULT_SETTINGS = os.environ.get("REALSENSE_APPLY_DEFAULT_SETTINGS", "1").strip().lower() not in ("0", "false", "no", "off")
TRACKING_INVERT_X = True
TRACKING_INVERT_Y = True
TRACKING_INVERT_Z = False
TRACKING_INVERT_ROLL = True
TRACKING_FORWARD_FLIP = True
# The solved room graph is already correct. Keep the Python room-map in the
# raw solved frame instead of applying an extra display-only Y flip that
# distorts screen/camera/head placement during calibration.
ROOM_MAP_FLIP_LIVE_CALIBRATION_CAMERA_Y = False
CANONICAL_Y_UP_PAYLOADS = True
Y_UP_FRAME_FLIP_4 = np.diag([1.0, -1.0, 1.0, 1.0]).astype(np.float32)
Y_UP_FRAME_FLIP_3 = np.diag([1.0, -1.0, 1.0]).astype(np.float32)
SUBPIX_WIN_SIZE = (5, 5)
SUBPIX_ZERO_ZONE = (-1, -1)
SUBPIX_CRITERIA = (
    cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER,
    40,
    0.001,
)

def make_detector_params():
    params = cv2.aruco.DetectorParameters()
    params.adaptiveThreshWinSizeMin = 3
    params.adaptiveThreshWinSizeMax = 45
    params.adaptiveThreshWinSizeStep = 4
    params.minMarkerPerimeterRate = 0.01
    params.maxMarkerPerimeterRate = 6.0
    params.minDistanceToBorder = 2
    params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    params.cornerRefinementWinSize = 5
    params.cornerRefinementMaxIterations = 50
    params.cornerRefinementMinAccuracy = 0.01
    if hasattr(params, "detectInvertedMarker"):
        params.detectInvertedMarker = True
    return params

def detect_markers_robust(gray, detector, dictionary, params):
    variants = [gray, cv2.equalizeHist(gray)]
    best_corners = []
    best_ids = None
    best_count = -1
    for variant in variants:
        corners, ids, _ = detector.detectMarkers(variant)
        count = 0 if ids is None else int(len(ids))
        if count > best_count:
            best_count = count
            best_corners = corners
            best_ids = ids
        if count > 0:
            continue

        if hasattr(cv2.aruco, "detectMarkers"):
            corners2, ids2, _ = cv2.aruco.detectMarkers(variant, dictionary, parameters=params)
            count2 = 0 if ids2 is None else int(len(ids2))
            if count2 > best_count:
                best_count = count2
                best_corners = corners2
                best_ids = ids2
    if best_ids is not None and len(best_corners) > 0:
        refined_corners = []
        for marker_corners in best_corners:
            pts = np.ascontiguousarray(marker_corners.reshape(-1, 1, 2).astype(np.float32))
            cv2.cornerSubPix(gray, pts, SUBPIX_WIN_SIZE, SUBPIX_ZERO_ZONE, SUBPIX_CRITERIA)
            refined_corners.append(pts.reshape(1, 4, 2))
        best_corners = refined_corners
    return best_corners, best_ids

def detect_charuco_corners_compat(gray, charuco_board, charuco_detector, aruco_detector, dictionary, params):
    if hasattr(cv2.aruco, "CharucoDetector"):
        try:
            ch_corners, ch_ids, marker_corners, marker_ids = charuco_detector.detectBoard(gray)
            count = 0 if ch_ids is None else int(len(ch_ids))
            if count > 0:
                return count, ch_corners, ch_ids
        except Exception:
            pass

    c_corners, c_ids = detect_markers_robust(gray, aruco_detector, dictionary, params)
    if c_ids is None or len(c_ids) <= 6 or not hasattr(cv2.aruco, "interpolateCornersCharuco"):
        return 0, None, None
    ret, ch_corners, ch_ids = cv2.aruco.interpolateCornersCharuco(c_corners, c_ids, gray, charuco_board)
    return int(ret), ch_corners, ch_ids

def intrinsics_camera_matrix(intrinsics):
    return np.array(
        [
            [float(intrinsics.fx), 0.0, float(intrinsics.ppx)],
            [0.0, float(intrinsics.fy), float(intrinsics.ppy)],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )

def intrinsics_dist_coeffs(intrinsics):
    coeffs = getattr(intrinsics, "coeffs", None)
    if coeffs is None:
        return np.zeros((5, 1), dtype=np.float64)
    coeffs = np.asarray(coeffs, dtype=np.float64).reshape(-1, 1)
    if coeffs.size <= 0:
        return np.zeros((5, 1), dtype=np.float64)
    return coeffs

def scale_camera_matrix(camera_matrix, scale):
    scaled = np.asarray(camera_matrix, dtype=np.float64).copy()
    scaled[0, 0] *= float(scale)
    scaled[1, 1] *= float(scale)
    scaled[0, 2] *= float(scale)
    scaled[1, 2] *= float(scale)
    return scaled

def write_fusion_charuco_debug(name, image, status):
    try:
        debug_dir = os.path.join(os.getcwd(), "logs")
        os.makedirs(debug_dir, exist_ok=True)
        cv2.imwrite(os.path.join(debug_dir, f"charuco_godot_{name}.png"), image)
        with open(os.path.join(debug_dir, "charuco_godot_status.txt"), "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {name}: {status}\n")
    except Exception:
        pass

def detect_fusion_charuco_pose_for_scale(gray, camera_matrix, label, board, dictionary, image_scale, debug_bgr, variant_name="raw"):
    params = cv2.aruco.DetectorParameters()
    params.adaptiveThreshWinSizeMin = 3
    params.adaptiveThreshWinSizeMax = 53
    params.adaptiveThreshWinSizeStep = 4
    params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    if hasattr(params, "detectInvertedMarker"):
        params.detectInvertedMarker = True

    if abs(float(image_scale) - 1.0) > 1e-6:
        detect_gray = cv2.resize(gray, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        detect_k = scale_camera_matrix(camera_matrix, image_scale)
        detect_debug = cv2.resize(debug_bgr, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
    else:
        detect_gray = gray
        detect_k = camera_matrix
        detect_debug = debug_bgr.copy()

    if hasattr(cv2.aruco, "detectMarkers"):
        corners, ids, _rejected = cv2.aruco.detectMarkers(detect_gray, dictionary, parameters=params)
    else:
        detector = cv2.aruco.ArucoDetector(dictionary, params)
        corners, ids, _rejected = detector.detectMarkers(detect_gray)
    marker_count = 0 if ids is None else int(len(ids))
    if ids is not None:
        cv2.aruco.drawDetectedMarkers(detect_debug, corners, ids)
    variant_suffix = "" if variant_name == "raw" else f" {variant_name}"
    if ids is None or marker_count < 4:
        return None, f"{label}: 6x6_250 {CHARUCO_SQUARES_X}x{CHARUCO_SQUARES_Y} scale={image_scale:g}{variant_suffix} markers={marker_count}", detect_debug, marker_count

    _ret, ch_corners, ch_ids = cv2.aruco.interpolateCornersCharuco(
        corners,
        ids,
        detect_gray,
        board,
        detect_k,
        np.zeros((5, 1), dtype=np.float64),
    )
    corner_count = 0 if ch_ids is None else int(len(ch_ids))
    if ch_ids is not None and hasattr(cv2.aruco, "drawDetectedCornersCharuco"):
        cv2.aruco.drawDetectedCornersCharuco(detect_debug, ch_corners, ch_ids, (0, 0, 255))
    if ch_ids is None or corner_count < 6:
        return None, f"{label}: 6x6_250 {CHARUCO_SQUARES_X}x{CHARUCO_SQUARES_Y} scale={image_scale:g}{variant_suffix} markers={marker_count} corners={corner_count}", detect_debug, 1000 + corner_count

    ok, rvec, tvec = cv2.aruco.estimatePoseCharucoBoard(
        ch_corners,
        ch_ids,
        board,
        detect_k,
        np.zeros((5, 1), dtype=np.float64),
        None,
        None,
    )
    if not ok:
        return None, f"{label}: 6x6_250 {CHARUCO_SQUARES_X}x{CHARUCO_SQUARES_Y} scale={image_scale:g}{variant_suffix} pose failed markers={marker_count} corners={corner_count}", detect_debug, 1000 + corner_count

    rot, _ = cv2.Rodrigues(rvec)
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rot
    transform[:3, 3] = np.asarray(tvec, dtype=np.float64).reshape(3)
    status = f"{label}: 6x6_250 {CHARUCO_SQUARES_X}x{CHARUCO_SQUARES_Y} scale={image_scale:g}{variant_suffix} markers={marker_count} corners={corner_count}"
    return transform, status, detect_debug, 1000 + corner_count

def detect_fusion_checkerboard_pose_for_scale(gray, camera_matrix, label, image_scale, debug_bgr, variant_name="raw"):
    inner_cols = max(2, int(CHARUCO_SQUARES_X) - 1)
    inner_rows = max(2, int(CHARUCO_SQUARES_Y) - 1)
    pattern_size = (inner_cols, inner_rows)
    if abs(float(image_scale) - 1.0) > 1e-6:
        detect_gray = cv2.resize(gray, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        detect_k = scale_camera_matrix(camera_matrix, image_scale)
        detect_debug = cv2.resize(debug_bgr, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
    else:
        detect_gray = gray
        detect_k = camera_matrix
        detect_debug = debug_bgr.copy()

    corners = None
    ok = False
    try:
        if hasattr(cv2, "findChessboardCornersSB"):
            ok, corners = cv2.findChessboardCornersSB(
                detect_gray,
                pattern_size,
                flags=cv2.CALIB_CB_EXHAUSTIVE | cv2.CALIB_CB_NORMALIZE_IMAGE,
            )
    except Exception:
        ok = False
        corners = None
    if not ok:
        try:
            ok, corners = cv2.findChessboardCorners(
                detect_gray,
                pattern_size,
                cv2.CALIB_CB_ADAPTIVE_THRESH | cv2.CALIB_CB_NORMALIZE_IMAGE,
            )
            if ok:
                cv2.cornerSubPix(detect_gray, corners, SUBPIX_WIN_SIZE, SUBPIX_ZERO_ZONE, SUBPIX_CRITERIA)
        except Exception:
            ok = False
            corners = None
    corner_count = 0 if corners is None else int(len(corners))
    variant_suffix = "" if variant_name == "raw" else f" {variant_name}"
    if not ok or corners is None or corner_count != inner_cols * inner_rows:
        return None, f"{label}: checkerboard {inner_cols}x{inner_rows} scale={image_scale:g}{variant_suffix} corners={corner_count}", detect_debug, 2000 + corner_count

    obj = np.zeros((inner_cols * inner_rows, 3), dtype=np.float32)
    index = 0
    for row in range(inner_rows):
        for col in range(inner_cols):
            obj[index, 0] = float(col + 1) * float(CHARUCO_SQUARE_M)
            obj[index, 1] = float(row + 1) * float(CHARUCO_SQUARE_M)
            index += 1

    image_points = np.asarray(corners, dtype=np.float32).reshape(-1, 2)
    ok, rvec, tvec = cv2.solvePnP(
        obj,
        image_points,
        detect_k,
        np.zeros((5, 1), dtype=np.float64),
        flags=cv2.SOLVEPNP_ITERATIVE,
    )
    if not ok:
        return None, f"{label}: checkerboard {inner_cols}x{inner_rows} scale={image_scale:g}{variant_suffix} pose failed corners={corner_count}", detect_debug, 2000 + corner_count

    cv2.drawChessboardCorners(detect_debug, pattern_size, corners, ok)
    rot, _ = cv2.Rodrigues(rvec)
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rot
    transform[:3, 3] = np.asarray(tvec, dtype=np.float64).reshape(3)
    status = f"{label}: checkerboard fallback {inner_cols}x{inner_rows} scale={image_scale:g}{variant_suffix} corners={corner_count}"
    return transform, status, detect_debug, 3000 + corner_count

def detect_fusion_charuco_pose(image_bgr, intrinsics, label):
    if image_bgr is None:
        return None, f"{label}: no image"
    if not hasattr(aruco, "CharucoBoard"):
        return None, f"{label}: ChArUco unavailable in this OpenCV build"

    dictionary = aruco.getPredefinedDictionary(aruco.DICT_6X6_250)
    board = aruco.CharucoBoard((CHARUCO_SQUARES_X, CHARUCO_SQUARES_Y), CHARUCO_SQUARE_M, CHARUCO_MARKER_M, dictionary)
    if image_bgr.ndim == 3:
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        debug_bgr = image_bgr.copy()
    else:
        gray = image_bgr
        debug_bgr = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)

    camera_matrix = intrinsics_camera_matrix(intrinsics)
    best_status = f"{label}: no ChArUco attempts"
    best_score = -1
    best_debug = debug_bgr.copy()
    attempted_variant_names = []
    attempted_scales = []
    variants = [("raw", gray)]
    try:
        variants.append(("eq", cv2.equalizeHist(gray)))
    except Exception:
        pass
    try:
        variants.append(("clahe", cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(gray)))
    except Exception:
        pass
    for variant_name, detect_gray in variants:
        attempted_variant_names.append(variant_name)
        for image_scale in (1.0, 1.5, 2.0, 3.0, 4.0):
            if image_scale not in attempted_scales:
                attempted_scales.append(image_scale)
            transform, status, attempt_debug, score = detect_fusion_charuco_pose_for_scale(
                detect_gray,
                camera_matrix,
                label,
                board,
                dictionary,
                image_scale,
                debug_bgr,
                variant_name,
            )
            if transform is not None:
                write_fusion_charuco_debug(label.lower().replace("-", "_"), attempt_debug, status)
                return transform, status
            if score > best_score:
                best_score = score
                best_status = status
                best_debug = attempt_debug
    for variant_name, detect_gray in variants:
        for image_scale in (1.0, 1.5, 2.0, 3.0, 4.0):
            transform, status, attempt_debug, score = detect_fusion_checkerboard_pose_for_scale(
                detect_gray,
                camera_matrix,
                label,
                image_scale,
                debug_bgr,
                variant_name,
            )
            if transform is not None:
                write_fusion_charuco_debug(label.lower().replace("-", "_"), attempt_debug, status)
                return transform, status
            if score > best_score:
                best_score = score
                best_status = status
                best_debug = attempt_debug

    write_fusion_charuco_debug(label.lower().replace("-", "_"), best_debug, best_status)
    attempts = "tried variants=%s scales=%s" % (
        ",".join(attempted_variant_names),
        ",".join(f"{scale:g}" for scale in attempted_scales),
    )
    return None, f"{best_status} | {attempts}"

def fusion_charuco_corner_count(status):
    try:
        if "corners=" not in str(status):
            return 0
        tail = str(status).rsplit("corners=", 1)[-1]
        value = tail.split()[0].split("|")[0].strip()
        return int(value)
    except Exception:
        return 0

def detect_best_fusion_charuco_pose_from_realsense(capture, sample_frames=FUSION_CHARUCO_SAMPLE_FRAMES):
    best_pose = None
    best_status = "RealSense: no frames sampled"
    best_corners = -1
    frame_count = max(1, int(sample_frames))
    last_frame_id = -1
    for _idx in range(frame_count):
        if hasattr(capture, "read_latest_color_for_alignment"):
            rs_color, last_frame_id = capture.read_latest_color_for_alignment(last_frame_id, timeout=0.35)
        else:
            capture.read()
            rs_color = None if capture.latest_color_bgr is None else capture.latest_color_bgr.copy()
        pose, status = detect_fusion_charuco_pose(rs_color, getattr(capture, "charuco_intrinsics", capture.intrinsics), "RealSense")
        corners = fusion_charuco_corner_count(status)
        if corners > best_corners:
            best_pose = pose
            best_status = status
            best_corners = corners
        if pose is not None and corners >= FUSION_CHARUCO_MIN_CORNERS:
            return pose, status
        time.sleep(0.025)
    if best_pose is not None and best_corners < FUSION_CHARUCO_MIN_CORNERS:
        return None, f"{best_status} below min corners={FUSION_CHARUCO_MIN_CORNERS}"
    return best_pose, best_status

def write_oakd_alignment_result(result_path, method, ok, status, oakd_to_realsense=None, details=None):
    if not result_path:
        return
    payload = {
        "type": "oakd_realsense_alignment",
        "method": str(method),
        "ok": bool(ok),
        "status": str(status),
        "timestamp": time.time(),
    }
    if oakd_to_realsense is not None:
        transform = np.asarray(oakd_to_realsense, dtype=np.float64)
        payload["R"] = transform[:3, :3].tolist()
        payload["T"] = transform[:3, 3].tolist()
    if details:
        payload["details"] = details
    try:
        result_path = os.path.abspath(str(result_path))
        os.makedirs(os.path.dirname(result_path), exist_ok=True)
        tmp_path = result_path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        os.replace(tmp_path, result_path)
    except Exception as exc:
        print(f">>> Could not write OAK-D/RealSense alignment result: {exc} <<<")

def frame_signature(charuco_corners, image_size):
    width, height = image_size
    pts = charuco_corners.reshape(-1, 2).astype(np.float32)

    cx, cy = pts.mean(axis=0)
    min_xy = pts.min(axis=0)
    max_xy = pts.max(axis=0)
    box_w = max(1.0, float(max_xy[0] - min_xy[0]))
    box_h = max(1.0, float(max_xy[1] - min_xy[1]))
    area_norm = (box_w * box_h) / float(width * height)

    centered = pts - np.array([[cx, cy]], dtype=np.float32)
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    principal = vt[0]
    angle = float(np.arctan2(principal[1], principal[0]))

    return np.array([
        float(cx / width),
        float(cy / height),
        float(np.sqrt(max(0.0, area_norm))),
        float(np.sin(angle)),
        float(np.cos(angle)),
    ], dtype=np.float32)

def is_diverse(sig, accepted_sigs, threshold):
    if not accepted_sigs:
        return True
    dmin = min(float(np.linalg.norm(sig - s)) for s in accepted_sigs)
    return dmin >= threshold

def create_transform_matrix(rvec, tvec):
    rmat, _ = cv2.Rodrigues(rvec)
    T = np.eye(4, dtype=np.float32)
    T[:3, :3] = rmat
    T[:3, 3] = tvec.flatten()
    return T

ARUCO_DICT_NAMES = {
    "4x4_50": aruco.DICT_4X4_50,
    "4x4_100": aruco.DICT_4X4_100,
    "4x4_250": aruco.DICT_4X4_250,
    "4x4_1000": aruco.DICT_4X4_1000,
    "5x5_50": aruco.DICT_5X5_50,
    "5x5_100": aruco.DICT_5X5_100,
    "5x5_250": aruco.DICT_5X5_250,
    "5x5_1000": aruco.DICT_5X5_1000,
    "6x6_50": aruco.DICT_6X6_50,
    "6x6_100": aruco.DICT_6X6_100,
    "6x6_250": aruco.DICT_6X6_250,
    "6x6_1000": aruco.DICT_6X6_1000,
    "7x7_50": aruco.DICT_7X7_50,
    "7x7_100": aruco.DICT_7X7_100,
    "7x7_250": aruco.DICT_7X7_250,
    "7x7_1000": aruco.DICT_7X7_1000,
}

def normalize_aruco_dict_name(name):
    text = str(name or "auto").strip().lower()
    text = text.replace("dict_", "").replace("aruco_", "").replace("-", "_")
    if text in ("", "any", "auto"):
        return "auto"
    return text if text in ARUCO_DICT_NAMES else "auto"

def aruco_dictionary_candidates(name):
    normalized = normalize_aruco_dict_name(name)
    if normalized != "auto":
        return [(normalized, aruco.getPredefinedDictionary(ARUCO_DICT_NAMES[normalized]))]
    preferred = [
        "4x4_50", "4x4_100", "5x5_100", "5x5_250",
        "6x6_250", "6x6_1000", "7x7_250",
    ]
    return [(key, aruco.getPredefinedDictionary(ARUCO_DICT_NAMES[key])) for key in preferred]

def parse_marker_id_filter(marker_id=-1, marker_ids=None):
    ids = set()
    try:
        single_id = int(marker_id)
    except Exception:
        single_id = -1
    if single_id >= 0:
        ids.add(single_id)
    if marker_ids is not None:
        if isinstance(marker_ids, str):
            raw_items = marker_ids.replace(";", ",").split(",")
        elif isinstance(marker_ids, (list, tuple, set)):
            raw_items = list(marker_ids)
        else:
            raw_items = [marker_ids]
        for item in raw_items:
            text = str(item).strip()
            if not text:
                continue
            try:
                ids.add(int(text))
            except ValueError:
                continue
    return ids if ids else None

def camera_matrix_from_intrinsics(intrinsics):
    return np.array(
        [
            [float(intrinsics.fx), 0.0, float(intrinsics.ppx)],
            [0.0, float(intrinsics.fy), float(intrinsics.ppy)],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float32,
    )

def detect_aruco_markers(gray, dictionary):
    params = aruco.DetectorParameters()
    if hasattr(aruco, "ArucoDetector"):
        detector = aruco.ArucoDetector(dictionary, params)
        corners, ids, rejected = detector.detectMarkers(gray)
    else:
        corners, ids, rejected = aruco.detectMarkers(gray, dictionary, parameters=params)
    return corners, ids, rejected

def detect_single_aruco_pose_for_scale(image_bgr, intrinsics, label, marker_size_m, dictionary_name, marker_id, image_scale):
    if image_bgr is None:
        return None, f"{label}: single ArUco no image", None, -1
    if marker_size_m <= 0.0:
        return None, f"{label}: single ArUco marker_size_m must be measured first", None, -1

    if image_bgr.ndim == 2:
        gray = image_bgr
        debug_bgr = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    else:
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        debug_bgr = image_bgr.copy()
    if abs(float(image_scale) - 1.0) > 1e-6:
        detect_gray = cv2.resize(gray, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        detect_debug = cv2.resize(debug_bgr, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        camera_matrix = camera_matrix_from_intrinsics(intrinsics).copy()
        camera_matrix[0, 0] *= float(image_scale)
        camera_matrix[1, 1] *= float(image_scale)
        camera_matrix[0, 2] *= float(image_scale)
        camera_matrix[1, 2] *= float(image_scale)
    else:
        detect_gray = gray
        detect_debug = debug_bgr.copy()
        camera_matrix = camera_matrix_from_intrinsics(intrinsics)

    best = None
    requested_id = int(marker_id)
    for dict_label, dictionary in aruco_dictionary_candidates(dictionary_name):
        corners, ids, _rejected = detect_aruco_markers(detect_gray, dictionary)
        count = 0 if ids is None else int(len(ids))
        if count <= 0:
            continue
        ids_flat = ids.flatten().astype(np.int32)
        for index, detected_id in enumerate(ids_flat):
            if requested_id >= 0 and int(detected_id) != requested_id:
                continue
            pts = corners[index].reshape(4, 2).astype(np.float32)
            area = float(abs(cv2.contourArea(pts)))
            if best is None or area > best[0]:
                best = (area, dict_label, int(detected_id), [corners[index]], count)

    if best is None:
        dict_status = normalize_aruco_dict_name(dictionary_name)
        id_status = "any" if requested_id < 0 else str(requested_id)
        return None, f"{label}: single ArUco dict={dict_status} id={id_status} markers=0", detect_debug, 0

    area, dict_label, detected_id, marker_corners, detected_count = best
    cv2.aruco.drawDetectedMarkers(detect_debug, marker_corners, np.array([[detected_id]], dtype=np.int32))
    obj = np.array(
        [
            [-marker_size_m * 0.5, marker_size_m * 0.5, 0.0],
            [marker_size_m * 0.5, marker_size_m * 0.5, 0.0],
            [marker_size_m * 0.5, -marker_size_m * 0.5, 0.0],
            [-marker_size_m * 0.5, -marker_size_m * 0.5, 0.0],
        ],
        dtype=np.float32,
    )
    img = marker_corners[0].reshape(4, 2).astype(np.float32)
    ok, rvec, tvec = cv2.solvePnP(obj, img, camera_matrix, None, flags=cv2.SOLVEPNP_IPPE_SQUARE)
    if not ok:
        ok, rvec, tvec = cv2.solvePnP(obj, img, camera_matrix, None, flags=cv2.SOLVEPNP_ITERATIVE)
    if not ok:
        return None, f"{label}: single ArUco dict={dict_label} id={detected_id} pose failed", detect_debug, detected_count
    cv2.drawFrameAxes(detect_debug, camera_matrix, None, rvec, tvec, float(marker_size_m) * 0.5)
    transform = create_transform_matrix(rvec, tvec).astype(np.float64)
    status = f"{label}: single ArUco dict={dict_label} id={detected_id} size={marker_size_m:.4f}m markers={detected_count}"
    return transform, status, detect_debug, detected_count

def detect_single_aruco_pose(image_bgr, intrinsics, label, marker_size_m, dictionary_name="auto", marker_id=-1):
    best_pose = None
    best_status = f"{label}: single ArUco not detected"
    best_score = -1
    best_debug = image_bgr.copy() if image_bgr is not None and image_bgr.ndim == 3 else None
    for scale in (1.0, 1.5, 2.0, 3.0, 4.0):
        pose, status, debug_bgr, score = detect_single_aruco_pose_for_scale(
            image_bgr,
            intrinsics,
            label,
            float(marker_size_m),
            dictionary_name,
            int(marker_id),
            scale,
        )
        if debug_bgr is not None and score > best_score:
            best_debug = debug_bgr
            best_score = score
            best_status = status
        if pose is not None:
            write_fusion_charuco_debug(f"{label.lower().replace('-', '_')}_single_aruco", debug_bgr, status)
            return pose, status
    if best_debug is not None:
        write_fusion_charuco_debug(f"{label.lower().replace('-', '_')}_single_aruco", best_debug, best_status)
    return best_pose, best_status

def detect_aruco_poses_for_scale(image_bgr, intrinsics, label, marker_size_m, dictionary_name, marker_id, image_scale, marker_ids=None):
    if image_bgr is None:
        return {}, f"{label}: big ArUco no image", None, -1
    if marker_size_m <= 0.0:
        return {}, f"{label}: big ArUco marker_size_m must be measured first", None, -1

    if image_bgr.ndim == 2:
        gray = image_bgr
        debug_bgr = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    else:
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        debug_bgr = image_bgr.copy()
    if abs(float(image_scale) - 1.0) > 1e-6:
        detect_gray = cv2.resize(gray, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        detect_debug = cv2.resize(debug_bgr, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        camera_matrix = camera_matrix_from_intrinsics(intrinsics).copy()
        camera_matrix[0, 0] *= float(image_scale)
        camera_matrix[1, 1] *= float(image_scale)
        camera_matrix[0, 2] *= float(image_scale)
        camera_matrix[1, 2] *= float(image_scale)
    else:
        detect_gray = gray
        detect_debug = debug_bgr.copy()
        camera_matrix = camera_matrix_from_intrinsics(intrinsics)

    requested_ids = parse_marker_id_filter(marker_id, marker_ids)
    detections = {}
    detected_total = 0
    obj = np.array(
        [
            [-marker_size_m * 0.5, marker_size_m * 0.5, 0.0],
            [marker_size_m * 0.5, marker_size_m * 0.5, 0.0],
            [marker_size_m * 0.5, -marker_size_m * 0.5, 0.0],
            [-marker_size_m * 0.5, -marker_size_m * 0.5, 0.0],
        ],
        dtype=np.float32,
    )

    for dict_label, dictionary in aruco_dictionary_candidates(dictionary_name):
        corners, ids, _rejected = detect_aruco_markers(detect_gray, dictionary)
        if ids is None:
            continue
        ids_flat = ids.flatten().astype(np.int32)
        selected_corners = []
        selected_ids = []
        for index, detected_id in enumerate(ids_flat):
            if requested_ids is not None and int(detected_id) not in requested_ids:
                continue
            img = corners[index].reshape(4, 2).astype(np.float32)
            ok, rvec, tvec = cv2.solvePnP(obj, img, camera_matrix, None, flags=cv2.SOLVEPNP_IPPE_SQUARE)
            if not ok:
                ok, rvec, tvec = cv2.solvePnP(obj, img, camera_matrix, None, flags=cv2.SOLVEPNP_ITERATIVE)
            if not ok:
                continue
            area = float(abs(cv2.contourArea(img)))
            key = (dict_label, int(detected_id))
            transform = create_transform_matrix(rvec, tvec).astype(np.float64)
            previous = detections.get(key)
            if previous is None or area > previous["area_px"]:
                detections[key] = {
                    "transform": transform,
                    "area_px": area,
                    "dictionary": dict_label,
                    "marker_id": int(detected_id),
                    "center_px": np.mean(img, axis=0).astype(np.float64),
                }
            selected_corners.append(corners[index])
            selected_ids.append([int(detected_id)])
            detected_total += 1
        if selected_corners:
            cv2.aruco.drawDetectedMarkers(detect_debug, selected_corners, np.array(selected_ids, dtype=np.int32))
            for marker_corners, marker_id_item in zip(selected_corners, selected_ids):
                center = np.mean(marker_corners.reshape(4, 2), axis=0).astype(int)
                cv2.putText(
                    detect_debug,
                    f"{dict_label}:{marker_id_item[0]}",
                    (int(center[0]) + 8, int(center[1]) - 8),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.65,
                    (0, 255, 0),
                    2,
                    cv2.LINE_AA,
                )

    if not detections:
        dict_status = normalize_aruco_dict_name(dictionary_name)
        id_status = "any" if requested_ids is None else ",".join(str(item) for item in sorted(requested_ids))
        return {}, f"{label}: big ArUco dict={dict_status} id={id_status} markers=0", detect_debug, 0

    if str(dictionary_name).strip().lower() == "auto":
        by_dictionary = {}
        for key, detection in detections.items():
            by_dictionary.setdefault(str(key[0]), {})[key] = detection
        if len(by_dictionary) > 1:
            preferred_order = {
                "4x4_50": 0,
                "4x4_100": 1,
                "4x4_250": 2,
                "5x5_100": 3,
                "5x5_250": 4,
                "6x6_250": 5,
                "6x6_1000": 6,
                "7x7_250": 7,
            }
            best_dict, best_dict_detections = max(
                by_dictionary.items(),
                key=lambda item: (
                    len(item[1]),
                    sum(float(det.get("area_px", 0.0)) for det in item[1].values()),
                    -preferred_order.get(item[0], 99),
                ),
            )
            detections = best_dict_detections
            cv2.putText(
                detect_debug,
                f"auto selected {best_dict}",
                (12, 28),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (0, 255, 255),
                2,
                cv2.LINE_AA,
            )

    ids_text = ",".join(f"{key[0]}:{key[1]}" for key in sorted(detections.keys()))
    status = f"{label}: big ArUco size={marker_size_m:.4f}m markers={len(detections)} ids={ids_text}"
    return detections, status, detect_debug, len(detections)

def detect_big_aruco_poses(image_bgr, intrinsics, label, marker_size_m, dictionary_name="auto", marker_id=-1, marker_ids=None):
    best_poses = {}
    best_status = f"{label}: big ArUco not detected"
    best_score = -1
    best_debug = image_bgr.copy() if image_bgr is not None and image_bgr.ndim == 3 else None
    for scale in (1.0, 1.5, 2.0, 3.0, 4.0):
        poses, status, debug_bgr, score = detect_aruco_poses_for_scale(
            image_bgr,
            intrinsics,
            label,
            float(marker_size_m),
            dictionary_name,
            int(marker_id),
            scale,
            marker_ids,
        )
        if debug_bgr is not None and score > best_score:
            best_debug = debug_bgr
            best_score = score
            best_status = status
            best_poses = poses
        if poses:
            write_fusion_charuco_debug(f"{label.lower().replace('-', '_')}_big_aruco", debug_bgr, status)
            return poses, status
    if best_debug is not None:
        write_fusion_charuco_debug(f"{label.lower().replace('-', '_')}_big_aruco", best_debug, best_status)
    return best_poses, best_status

def rotation_matrix_to_quaternion(matrix):
    m = np.asarray(matrix, dtype=np.float64)
    trace = float(np.trace(m))
    if trace > 0.0:
        s = math.sqrt(trace + 1.0) * 2.0
        return np.array([
            0.25 * s,
            (m[2, 1] - m[1, 2]) / s,
            (m[0, 2] - m[2, 0]) / s,
            (m[1, 0] - m[0, 1]) / s,
        ], dtype=np.float64)
    if m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(max(1e-12, 1.0 + m[0, 0] - m[1, 1] - m[2, 2])) * 2.0
        return np.array([
            (m[2, 1] - m[1, 2]) / s,
            0.25 * s,
            (m[0, 1] + m[1, 0]) / s,
            (m[0, 2] + m[2, 0]) / s,
        ], dtype=np.float64)
    if m[1, 1] > m[2, 2]:
        s = math.sqrt(max(1e-12, 1.0 + m[1, 1] - m[0, 0] - m[2, 2])) * 2.0
        return np.array([
            (m[0, 2] - m[2, 0]) / s,
            (m[0, 1] + m[1, 0]) / s,
            0.25 * s,
            (m[1, 2] + m[2, 1]) / s,
        ], dtype=np.float64)
    s = math.sqrt(max(1e-12, 1.0 + m[2, 2] - m[0, 0] - m[1, 1])) * 2.0
    return np.array([
        (m[1, 0] - m[0, 1]) / s,
        (m[0, 2] + m[2, 0]) / s,
        (m[1, 2] + m[2, 1]) / s,
        0.25 * s,
    ], dtype=np.float64)

def quaternion_to_rotation_matrix(quaternion):
    q = np.asarray(quaternion, dtype=np.float64)
    norm = float(np.linalg.norm(q))
    if norm <= 1e-12:
        return np.eye(3, dtype=np.float64)
    w, x, y, z = q / norm
    return np.array(
        [
            [1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w)],
            [2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w)],
            [2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)],
        ],
        dtype=np.float64,
    )

def average_rigid_transforms(transforms):
    if not transforms:
        return None
    if len(transforms) == 1:
        return np.asarray(transforms[0], dtype=np.float64).copy()
    translations = []
    quaternions = []
    reference_quat = None
    for transform in transforms:
        t = np.asarray(transform, dtype=np.float64)
        translations.append(t[:3, 3])
        quat = rotation_matrix_to_quaternion(t[:3, :3])
        if reference_quat is None:
            reference_quat = quat
        elif float(np.dot(reference_quat, quat)) < 0.0:
            quat = -quat
        quaternions.append(quat)
    averaged = np.eye(4, dtype=np.float64)
    averaged[:3, :3] = quaternion_to_rotation_matrix(np.mean(np.stack(quaternions, axis=0), axis=0))
    averaged[:3, 3] = np.mean(np.stack(translations, axis=0), axis=0)
    return averaged

def depth_to_view_points(depth_m, intrinsics, min_depth, max_depth, stride=1, max_points=60000):
    if depth_m is None:
        return None
    stride = max(1, int(stride))
    rows = np.arange(0, depth_m.shape[0], stride, dtype=np.int32)
    cols = np.arange(0, depth_m.shape[1], stride, dtype=np.int32)
    sampled_depth = depth_m[np.ix_(rows, cols)].astype(np.float32, copy=False)
    valid = np.isfinite(sampled_depth) & (sampled_depth >= float(min_depth)) & (sampled_depth <= float(max_depth))
    if int(valid.sum()) <= 0:
        return None
    grid_x = cols[np.newaxis, :].astype(np.float32)
    grid_y = rows[:, np.newaxis].astype(np.float32)
    z = sampled_depth
    x = (grid_x - float(intrinsics.ppx)) * z / max(1e-6, float(intrinsics.fx))
    y = (grid_y - float(intrinsics.ppy)) * z / max(1e-6, float(intrinsics.fy))
    points = np.stack([x, -y, -z], axis=2)[valid].astype(np.float64, copy=False)
    max_points = int(max_points)
    if max_points > 0 and points.shape[0] > max_points:
        indices = np.linspace(0, points.shape[0] - 1, max_points, dtype=np.int64)
        points = points[indices]
    return points

def read_realsense_point_cloud_snapshot(capture):
    with capture._frame_lock:
        color = None if capture._latest_color_bgr is None else capture._latest_color_bgr.copy()
        depth = None if capture._latest_depth_m is None else capture._latest_depth_m.copy()
    intrinsics = getattr(capture, "point_cloud_intrinsics", capture.intrinsics)
    return color, depth, intrinsics

def robust_depth_at_pixel(depth_m, pixel, radius_px=10, min_depth=0.15, max_depth=6.0):
    if depth_m is None or pixel is None:
        return None
    image_h, image_w = depth_m.shape[:2]
    x = int(round(float(pixel[0])))
    y = int(round(float(pixel[1])))
    x0 = max(0, x - int(radius_px))
    x1 = min(image_w, x + int(radius_px) + 1)
    y0 = max(0, y - int(radius_px))
    y1 = min(image_h, y + int(radius_px) + 1)
    if x0 >= x1 or y0 >= y1:
        return None
    roi = depth_m[y0:y1, x0:x1]
    valid = roi[np.isfinite(roi) & (roi >= min_depth) & (roi <= max_depth)]
    if valid.size < 8:
        return None
    return float(np.median(valid))

def estimate_depth_scale_offset_from_marker_poses(depth_m, detections, min_depth=0.15, max_depth=6.0):
    measured = []
    expected = []
    details = []
    for key, detection in sorted(detections.items()):
        center = detection.get("center_px")
        measured_depth = robust_depth_at_pixel(depth_m, center, radius_px=12, min_depth=min_depth, max_depth=max_depth)
        if measured_depth is None:
            continue
        transform = np.asarray(detection["transform"], dtype=np.float64)
        expected_depth = float(transform[2, 3])
        if not np.isfinite(expected_depth) or expected_depth <= 0.0:
            continue
        measured.append(measured_depth)
        expected.append(expected_depth)
        details.append(
            {
                "dictionary": str(key[0]),
                "marker_id": int(key[1]),
                "measured_depth_m": float(measured_depth),
                "pose_depth_m": float(expected_depth),
                "center_px": [float(center[0]), float(center[1])] if center is not None else None,
            }
        )
    if not measured:
        return 1.0, 0.0, details, "depth correction skipped: no marker depth samples"

    measured_arr = np.asarray(measured, dtype=np.float64)
    expected_arr = np.asarray(expected, dtype=np.float64)
    if measured_arr.size >= 2 and float(np.ptp(measured_arr)) > 0.02:
        a = np.stack([measured_arr, np.ones_like(measured_arr)], axis=1)
        scale, offset = np.linalg.lstsq(a, expected_arr, rcond=None)[0]
    else:
        scale = float(np.median(expected_arr / np.maximum(measured_arr, 1e-6)))
        offset = 0.0
    scale = float(np.clip(scale, 0.70, 1.30))
    offset = float(np.clip(offset, -0.30, 0.30))
    corrected = measured_arr * scale + offset
    residual = corrected - expected_arr
    status = (
        f"depth correction scale={scale:.5f} offset={offset:.4f}m "
        f"samples={len(measured)} median_abs_err={float(np.median(np.abs(residual))):.4f}m"
    )
    return scale, offset, details, status

def median_marker_depth_error(details, scale, offset, quadratic=0.0):
    errors = []
    for item in details or []:
        measured = item.get("measured_depth_m")
        expected = item.get("pose_depth_m")
        if measured is None or expected is None:
            continue
        corrected = (float(measured) * float(measured) * float(quadratic)) + (float(measured) * float(scale)) + float(offset)
        if np.isfinite(corrected) and np.isfinite(float(expected)):
            errors.append(abs(corrected - float(expected)))
    if not errors:
        return None
    return float(np.median(np.asarray(errors, dtype=np.float64)))

def estimate_depth_scale_offset_from_cross_depth(
    oak_depth,
    rs_depth,
    oak_intrinsics,
    rs_intrinsics,
    oakd_to_realsense,
    min_depth=0.15,
    max_depth=6.0,
    stride=8,
    max_samples=12000,
):
    if oak_depth is None or rs_depth is None or oak_intrinsics is None or rs_intrinsics is None:
        return None, None, {}, "scene depth correction skipped: missing depth or intrinsics"
    if oak_depth.size <= 0 or rs_depth.size <= 0:
        return None, None, {}, "scene depth correction skipped: empty depth image"

    stride = max(2, int(stride))
    rows = np.arange(0, oak_depth.shape[0], stride, dtype=np.int32)
    cols = np.arange(0, oak_depth.shape[1], stride, dtype=np.int32)
    sampled_depth = oak_depth[np.ix_(rows, cols)].astype(np.float64, copy=False)
    valid = np.isfinite(sampled_depth) & (sampled_depth >= float(min_depth)) & (sampled_depth <= float(max_depth))
    if int(valid.sum()) < 200:
        return None, None, {"sample_count": int(valid.sum())}, "scene depth correction skipped: too few OAK-D samples"

    grid_x = cols[np.newaxis, :].astype(np.float64)
    grid_y = rows[:, np.newaxis].astype(np.float64)
    ray_x = (grid_x - float(oak_intrinsics.ppx)) / max(1e-6, float(oak_intrinsics.fx))
    ray_y = -(grid_y - float(oak_intrinsics.ppy)) / max(1e-6, float(oak_intrinsics.fy))
    ray_z = -np.ones_like(sampled_depth, dtype=np.float64)

    raw_depth = sampled_depth[valid]
    rays = np.stack([ray_x + np.zeros_like(sampled_depth), ray_y + np.zeros_like(sampled_depth), ray_z], axis=2)[valid]
    if raw_depth.shape[0] > max_samples:
        keep = np.linspace(0, raw_depth.shape[0] - 1, int(max_samples), dtype=np.int64)
        raw_depth = raw_depth[keep]
        rays = rays[keep]

    transform = np.asarray(oakd_to_realsense, dtype=np.float64)
    rotation = transform[:3, :3]
    translation = transform[:3, 3]

    raw_points = rays * raw_depth[:, np.newaxis]
    raw_rs_points = (rotation @ raw_points.T).T + translation[np.newaxis, :]
    raw_rs_z = -raw_rs_points[:, 2]
    projected_valid = np.isfinite(raw_rs_z) & (raw_rs_z >= float(min_depth)) & (raw_rs_z <= float(max_depth))
    if int(projected_valid.sum()) < 200:
        return None, None, {"sample_count": int(projected_valid.sum())}, "scene depth correction skipped: too few projected samples"

    raw_depth = raw_depth[projected_valid]
    rays = rays[projected_valid]
    raw_rs_points = raw_rs_points[projected_valid]
    raw_rs_z = raw_rs_z[projected_valid]

    rs_u = raw_rs_points[:, 0] * float(rs_intrinsics.fx) / np.maximum(raw_rs_z, 1e-6) + float(rs_intrinsics.ppx)
    rs_v = -raw_rs_points[:, 1] * float(rs_intrinsics.fy) / np.maximum(raw_rs_z, 1e-6) + float(rs_intrinsics.ppy)
    rs_x = np.rint(rs_u).astype(np.int32)
    rs_y = np.rint(rs_v).astype(np.int32)
    in_bounds = (rs_x >= 0) & (rs_x < rs_depth.shape[1]) & (rs_y >= 0) & (rs_y < rs_depth.shape[0])
    if int(in_bounds.sum()) < 200:
        return None, None, {"sample_count": int(in_bounds.sum())}, "scene depth correction skipped: too little overlap"

    raw_depth = raw_depth[in_bounds]
    rays = rays[in_bounds]
    rs_x = rs_x[in_bounds]
    rs_y = rs_y[in_bounds]
    observed_rs_depth = rs_depth[rs_y, rs_x].astype(np.float64, copy=False)
    finite = np.isfinite(observed_rs_depth) & (observed_rs_depth >= float(min_depth)) & (observed_rs_depth <= float(max_depth))
    if int(finite.sum()) < 200:
        return None, None, {"sample_count": int(finite.sum())}, "scene depth correction skipped: too few matching RealSense samples"

    raw_depth = raw_depth[finite]
    rays = rays[finite]
    observed_rs_depth = observed_rs_depth[finite]

    rz = (rotation[2, :] @ rays.T)
    denom = np.asarray(rz, dtype=np.float64)
    usable = np.isfinite(denom) & (np.abs(denom) > 1e-4)
    expected_oak_depth = (-observed_rs_depth - float(translation[2])) / denom
    usable &= np.isfinite(expected_oak_depth) & (expected_oak_depth >= float(min_depth)) & (expected_oak_depth <= float(max_depth))
    if int(usable.sum()) < 200:
        return None, None, {"sample_count": int(usable.sum())}, "scene depth correction skipped: too few usable correspondences"

    raw_depth = raw_depth[usable]
    expected_oak_depth = expected_oak_depth[usable]
    residual = expected_oak_depth - raw_depth
    abs_residual = np.abs(residual)
    keep = abs_residual <= max(0.08, float(np.percentile(abs_residual, 75)) * 2.5)
    if int(keep.sum()) >= 200:
        raw_depth = raw_depth[keep]
        expected_oak_depth = expected_oak_depth[keep]

    if raw_depth.size < 200 or float(np.ptp(raw_depth)) < 0.08:
        return None, None, {
            "sample_count": int(raw_depth.size),
            "depth_span_m": float(np.ptp(raw_depth)) if raw_depth.size else 0.0,
        }, "scene depth correction skipped: not enough depth range"

    quadratic = 0.0
    if raw_depth.size >= 800 and float(np.ptp(raw_depth)) >= 0.35:
        qa = np.stack([raw_depth * raw_depth, raw_depth, np.ones_like(raw_depth)], axis=1)
        q_candidate, scale_candidate, offset_candidate = np.linalg.lstsq(qa, expected_oak_depth, rcond=None)[0]
        q_candidate = float(np.clip(q_candidate, -0.15, 0.15))
        scale_candidate = float(np.clip(scale_candidate, 0.55, 1.45))
        offset_candidate = float(np.clip(offset_candidate, -0.40, 0.40))
        near_slope = (2.0 * q_candidate * float(np.min(raw_depth))) + scale_candidate
        far_slope = (2.0 * q_candidate * float(np.max(raw_depth))) + scale_candidate
        if 0.25 <= near_slope <= 2.0 and 0.25 <= far_slope <= 2.0:
            quadratic = q_candidate
            scale = scale_candidate
            offset = offset_candidate
        else:
            a = np.stack([raw_depth, np.ones_like(raw_depth)], axis=1)
            scale, offset = np.linalg.lstsq(a, expected_oak_depth, rcond=None)[0]
    else:
        a = np.stack([raw_depth, np.ones_like(raw_depth)], axis=1)
        scale, offset = np.linalg.lstsq(a, expected_oak_depth, rcond=None)[0]
    scale = float(np.clip(scale, 0.70, 1.30))
    offset = float(np.clip(offset, -0.30, 0.30))
    corrected = (raw_depth * raw_depth * quadratic) + (raw_depth * scale) + offset
    error = corrected - expected_oak_depth
    details = {
        "sample_count": int(raw_depth.size),
        "depth_span_m": float(np.ptp(raw_depth)),
        "raw_depth_median_m": float(np.median(raw_depth)),
        "expected_depth_median_m": float(np.median(expected_oak_depth)),
        "quadratic_coeff": float(quadratic),
        "median_abs_err_m": float(np.median(np.abs(error))),
        "p90_abs_err_m": float(np.percentile(np.abs(error), 90)),
    }
    status = (
        f"scene depth correction q={quadratic:.5f} scale={scale:.5f} offset={offset:.4f}m "
        f"samples={raw_depth.size} span={details['depth_span_m']:.3f}m "
        f"median_abs_err={details['median_abs_err_m']:.4f}m"
    )
    return scale, offset, details, status

def blend_transform(previous_transform, observed_transform, alpha):
    if previous_transform is None:
        return observed_transform.astype(np.float32)
    alpha = float(np.clip(alpha, 0.0, 1.0))
    blended = np.eye(4, dtype=np.float32)
    blended[:3, 3] = (
        alpha * observed_transform[:3, 3]
        + (1.0 - alpha) * previous_transform[:3, 3]
    )
    r_blend = (
        alpha * observed_transform[:3, :3]
        + (1.0 - alpha) * previous_transform[:3, :3]
    )
    u, _, vt = np.linalg.svd(r_blend)
    blended[:3, :3] = u @ vt
    return blended

def canonicalize_y_up_transform(transform):
    return (Y_UP_FRAME_FLIP_4 @ transform.astype(np.float32) @ Y_UP_FRAME_FLIP_4).astype(np.float32)

def decanonicalize_y_up_transform(transform):
    # The Y-up conversion is self-inverse.
    return canonicalize_y_up_transform(transform)

def canonicalize_y_up_position(position):
    return (Y_UP_FRAME_FLIP_3 @ np.asarray(position, dtype=np.float32)).astype(np.float32)

def transform_from_payload(payload):
    if not isinstance(payload, dict):
        return None
    r_rows = payload.get("R")
    t_vals = payload.get("T")
    if not (isinstance(r_rows, list) and isinstance(t_vals, list) and len(r_rows) == 3 and len(t_vals) == 3):
        return None
    try:
        transform = np.eye(4, dtype=np.float32)
        transform[:3, :3] = np.array(r_rows, dtype=np.float32)
        transform[:3, 3] = np.array(t_vals, dtype=np.float32)
        if bool(payload.get("canonical_y_up", False)):
            transform = decanonicalize_y_up_transform(transform)
        return transform
    except Exception:
        return None

def normalize_screen_id(value):
    if value is None:
        return ""
    if isinstance(value, int):
        return str(int(value))
    if isinstance(value, float):
        rounded = round(float(value))
        if abs(float(value) - rounded) <= 1e-6:
            return str(int(rounded))
        return str(float(value))
    text = str(value).strip()
    if text == "":
        return ""
    try:
        parsed = float(text)
        rounded = round(parsed)
        if abs(parsed - rounded) <= 1e-6:
            return str(int(rounded))
    except ValueError:
        pass
    return text

def tracking_alignment_rotation(raw_rotation):
    yaw_flip = np.array(
        [
            [-1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, -1.0],
        ],
        dtype=np.float32,
    )
    corrected = raw_rotation.astype(np.float32) @ yaw_flip
    u, _, vt = np.linalg.svd(corrected)
    return (u @ vt).astype(np.float32)

def tracking_position_alignment_rotation(raw_rotation):
    x_flip = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, -1.0, 0.0],
            [0.0, 0.0, -1.0],
        ],
        dtype=np.float32,
    )
    corrected = tracking_alignment_rotation(raw_rotation) @ x_flip
    u, _, vt = np.linalg.svd(corrected)
    return (u @ vt).astype(np.float32)

def opentrack_rotation_matrix(yaw_deg, pitch_deg, roll_deg):
    yaw = np.radians(float(yaw_deg))
    pitch = np.radians(float(pitch_deg))
    roll_sign = -1.0 if TRACKING_INVERT_ROLL else 1.0
    roll = np.radians(float(roll_deg) * roll_sign)
    ry = np.array(
        [
            [np.cos(yaw), 0.0, np.sin(yaw)],
            [0.0, 1.0, 0.0],
            [-np.sin(yaw), 0.0, np.cos(yaw)],
        ],
        dtype=np.float32,
    )
    rx = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, np.cos(pitch), -np.sin(pitch)],
            [0.0, np.sin(pitch), np.cos(pitch)],
        ],
        dtype=np.float32,
    )
    rz = np.array(
        [
            [np.cos(roll), -np.sin(roll), 0.0],
            [np.sin(roll), np.cos(roll), 0.0],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float32,
    )
    return ry @ rx @ rz

def load_screen_configs():
    if os.path.exists("monitor_configs.json"):
        try:
            with open("monitor_configs.json", "r") as f:
                return json.load(f)
        except:
            pass
    return {}

def save_screen_config(screen_id, width_inches, height_inches, source="manual"):
    configs = load_screen_configs()
    configs[str(screen_id)] = {
        "width": float(width_inches),
        "height": float(height_inches),
        "source": source,
    }
    with open("monitor_configs.json", "w") as f:
        json.dump(configs, f, indent=4)

def build_status_frame(title, lines, width=1280, height=720):
    frame = np.full((height, width, 3), 20, dtype=np.uint8)
    cv2.putText(frame, title, (40, 80), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 3, cv2.LINE_AA)

    y = 145
    for line in lines:
        cv2.putText(frame, line, (40, y), cv2.FONT_HERSHEY_SIMPLEX, 0.78, (210, 210, 210), 2, cv2.LINE_AA)
        y += 42

    return frame

def draw_outlined_text(frame, text, origin, scale=0.62, color=(255, 255, 255), thickness=1):
    cv2.putText(
        frame,
        text,
        origin,
        cv2.FONT_HERSHEY_SIMPLEX,
        scale,
        (0, 0, 0),
        thickness + 3,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        text,
        origin,
        cv2.FONT_HERSHEY_SIMPLEX,
        scale,
        color,
        thickness,
        cv2.LINE_AA,
    )

def get_capture_dimensions(capture):
    width = int(round(capture.get(cv2.CAP_PROP_FRAME_WIDTH)))
    height = int(round(capture.get(cv2.CAP_PROP_FRAME_HEIGHT)))
    return width, height

def camera_mode_score(width, height):
    return width * height

def get_camera_backends():
    backends = []
    if os.name == "nt" and hasattr(cv2, "CAP_DSHOW"):
        backends.append(cv2.CAP_DSHOW)
    backends.append(cv2.CAP_ANY)
    return backends

def open_capture_for_index(index, backends):
    for backend in backends:
        capture = cv2.VideoCapture(index, backend)
        if capture.isOpened():
            return capture
        capture.release()
    return None

def probe_camera_candidates(backends, active_index=None, active_mode=None):
    candidates = []
    for index in range(CAMERA_INDEX_AUTO_MAX):
        if active_index is not None and index == active_index and active_mode is not None:
            candidates.append(
                {
                    "index": index,
                    "width": int(active_mode[0]),
                    "height": int(active_mode[1]),
                }
            )
            continue
        capture = open_capture_for_index(index, backends)
        if capture is None:
            continue
        if hasattr(cv2, "CAP_PROP_FOURCC"):
            capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        if hasattr(cv2, "CAP_PROP_FPS"):
            capture.set(cv2.CAP_PROP_FPS, PREFERRED_CAMERA_FPS)
        best_mode = get_capture_dimensions(capture)
        best_score = camera_mode_score(*best_mode)
        for width, height in PREFERRED_CAMERA_MODES:
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            actual_mode = get_capture_dimensions(capture)
            actual_score = camera_mode_score(*actual_mode)
            if actual_score > best_score:
                best_mode = actual_mode
                best_score = actual_score
        capture.release()
        candidates.append(
            {
                "index": index,
                "width": best_mode[0],
                "height": best_mode[1],
            }
        )
    return candidates

class LatestFrameTcpServer:
    def __init__(self, host="127.0.0.1", port=4246):
        self.host = host
        self.port = int(port)
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.latest_frame = None
        self.latest_frame_id = -1
        self.has_client = False
        self.thread = threading.Thread(target=self._run, name="realsense-pointcloud-tcp", daemon=True)
        self.thread.start()

    def publish(self, frame_id, payload):
        with self.lock:
            self.latest_frame_id = int(frame_id)
            self.latest_frame = bytes(payload)

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=2.0)

    def _run(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            server.bind((self.host, self.port))
            server.listen(1)
            server.settimeout(0.25)
            print(f">>> RealSense point cloud TCP server listening on {self.host}:{self.port} <<<")
        except Exception as exc:
            print(f">>> RealSense point cloud TCP server unavailable: {exc} <<<")
            server.close()
            return

        try:
            while not self.stop_event.is_set():
                try:
                    client, addr = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                print(f">>> RealSense point cloud TCP client connected: {addr} <<<")
                self.has_client = True
                client.settimeout(0.25)
                sent_frame_id = -1
                try:
                    while not self.stop_event.is_set():
                        with self.lock:
                            frame_id = self.latest_frame_id
                            frame = self.latest_frame
                        if frame is None or frame_id == sent_frame_id:
                            time.sleep(0.001)
                            continue
                        packet = struct.pack("<I", len(frame)) + frame
                        client.sendall(packet)
                        sent_frame_id = frame_id
                except (ConnectionError, OSError, socket.timeout):
                    pass
                finally:
                    self.has_client = False
                    try:
                        client.close()
                    except OSError:
                        pass
                    print(">>> RealSense point cloud TCP client disconnected <<<")
        finally:
            server.close()

class LatestGridSharedMemory:
    def __init__(self, name=REALSENSE_POINT_CLOUD_SHM_NAME, size=REALSENSE_POINT_CLOUD_SHM_MAX_BYTES, label="RealSense point cloud"):
        self.name = name
        self.size = int(size)
        self.label = label
        self.sequence = 0
        self.shm = None
        try:
            self.shm = shared_memory.SharedMemory(name=self.name, create=True, size=self.size)
            self.shm.buf[:REALSENSE_POINT_CLOUD_SHM_HEADER_SIZE] = b"\x00" * REALSENSE_POINT_CLOUD_SHM_HEADER_SIZE
            print(f">>> {self.label} shared memory created: name={self.name} bytes={self.size} <<<")
        except FileExistsError:
            self.shm = shared_memory.SharedMemory(name=self.name, create=False)
            self.size = self.shm.size
            print(f">>> {self.label} shared memory attached: name={self.name} bytes={self.size} <<<")
        except Exception as exc:
            print(f">>> {self.label} shared memory unavailable: {exc} <<<")
            self.shm = None

    def publish_grid(self, frame_id, grid_depth, grid_color, stride, intrinsics, color_format="rgba"):
        if self.shm is None:
            return False
        color_format = str(color_format or "rgba").strip().lower()
        color_format_code = 1
        if color_format == "rgb":
            color_format_code = 2
        elif color_format == "bgr":
            color_format_code = 3
        elif color_format != "rgba":
            color_format = "rgba"
            color_format_code = 1
        grid_h, grid_w = grid_depth.shape
        cell_count = int(grid_w * grid_h)
        grid_depth = np.ascontiguousarray(grid_depth, dtype="<f4")
        grid_color = np.ascontiguousarray(grid_color, dtype=np.uint8)
        expected_channels = 4 if color_format_code == 1 else 3
        if grid_color.shape[:2] != (grid_h, grid_w) or len(grid_color.shape) != 3 or grid_color.shape[2] != expected_channels:
            print(
                f">>> {self.label} shared memory bad color grid: "
                f"shape={grid_color.shape} expected={grid_h}x{grid_w}x{expected_channels} format={color_format} <<<"
            )
            return False
        depth_bytes = grid_depth.nbytes
        color_bytes = grid_color.nbytes
        payload_bytes = depth_bytes + color_bytes
        total_bytes = REALSENSE_POINT_CLOUD_SHM_HEADER_SIZE + payload_bytes
        if total_bytes > self.size:
            print(f">>> {self.label} shared memory frame too large: need={total_bytes} bytes have={self.size} bytes <<<")
            return False
        self.sequence += 2
        write_sequence = self.sequence | 1
        ready_sequence = self.sequence + 2
        header = struct.pack(
            "<8sQQIIIIffffII",
            REALSENSE_POINT_CLOUD_SHM_MAGIC,
            int(write_sequence),
            int(frame_id),
            int(grid_w),
            int(grid_h),
            int(stride),
            int(color_format_code),
            float(intrinsics.fx),
            float(intrinsics.fy),
            float(intrinsics.ppx),
            float(intrinsics.ppy),
            int(depth_bytes),
            int(color_bytes),
        )
        view = self.shm.buf
        view[:len(header)] = header
        offset = REALSENSE_POINT_CLOUD_SHM_HEADER_SIZE
        view[offset:offset + depth_bytes] = grid_depth.reshape(-1).view(np.uint8)
        offset += depth_bytes
        view[offset:offset + color_bytes] = grid_color.reshape(-1).view(np.uint8)
        struct.pack_into("<Q", view, 8, int(ready_sequence))
        return True

    def close(self):
        if self.shm is None:
            return
        try:
            self.shm.close()
        except Exception:
            pass
        self.shm = None

class CameraIntrinsics:
    def __init__(self, fx, fy, ppx, ppy):
        self.fx = float(fx)
        self.fy = float(fy)
        self.ppx = float(ppx)
        self.ppy = float(ppy)

class FastFoundationDepthWorker:
    def __init__(
        self,
        width,
        height,
        intrinsics,
        baseline_m,
        scale=1.0,
        iters=8,
        torch_compile=False,
        backend="pytorch",
        model_profile=None,
    ):
        self.width = int(width)
        self.height = int(height)
        self.intrinsics = intrinsics
        self.baseline_m = float(baseline_m)
        self.scale = max(0.25, min(1.0, float(scale)))
        self.iters = max(1, min(32, int(iters)))
        self.torch_compile = bool(torch_compile)
        self.backend = str(backend or "pytorch").strip().lower()
        if self.backend not in ("pytorch", "onnx_trt", "onnx_cuda", "trt_engine"):
            self.backend = "pytorch"
        self.model_profile = str(
            model_profile or os.environ.get("FAST_FOUNDATIONSTEREO_PROFILE", "full_320x736_i4")
        ).strip().lower()
        if self.model_profile not in FAST_FOUNDATION_MODEL_PROFILES:
            self.model_profile = "full_320x736_i4"
        profile = FAST_FOUNDATION_MODEL_PROFILES[self.model_profile]
        self.model_path = os.environ.get("FAST_FOUNDATIONSTEREO_MODEL", DEFAULT_FAST_FOUNDATION_MODEL)
        self.onnx_path = os.environ.get("FAST_FOUNDATIONSTEREO_ONNX", profile["onnx"])
        self.trt_engine_path = os.environ.get("FAST_FOUNDATIONSTEREO_TRT_ENGINE", profile["engine"])
        self.profile_label = str(profile["label"])
        self.repo_dir = os.environ.get("FAST_FOUNDATIONSTEREO_DIR", DEFAULT_FAST_FOUNDATION_DIR)
        self.onnx_provider = "not loaded"
        self._cond = threading.Condition()
        self._pending = None
        self._stopped = False
        self._loaded = False
        self._torch = None
        self._amp_dtype = None
        self._padder_cls = None
        self._model = None
        self._ort = None
        self._ort_session = None
        self._ort_input_names = None
        self._ort_output_name = None
        self._onnx_hw = None
        self._trt = None
        self._trt_engine = None
        self._trt_context = None
        self._trt_input_names = None
        self._trt_output_names = None
        self._trt_hw = None
        self._trt_stream = None
        self._ff_left_input = None
        self._ff_right_input = None
        self._ff_prep_tmp = None
        self._latest = None
        self._latest_seq = 0
        self._fps_count = 0
        self._fps_last_time = time.perf_counter()
        self.fps = 0.0
        self.status = "not loaded"
        self.timing_ms = {}
        self._thread = threading.Thread(target=self._loop, name="oakd-fast-foundation-depth", daemon=True)
        self._thread.start()

    def _init_fast_input_buffers(self, target_h, target_w):
        self._ff_left_input = np.empty((1, 3, int(target_h), int(target_w)), dtype=np.float32)
        self._ff_right_input = np.empty((1, 3, int(target_h), int(target_w)), dtype=np.float32)
        self._ff_prep_tmp = np.empty((int(target_h), int(target_w)), dtype=np.float32)

    def _fill_normalized_gray_input(self, gray_u8, out_nchw):
        tmp = self._ff_prep_tmp
        np.multiply(gray_u8, 1.0 / 255.0, out=tmp, casting="unsafe")
        out = out_nchw[0]
        np.subtract(tmp, 0.485, out=out[0])
        np.multiply(out[0], 1.0 / 0.229, out=out[0])
        np.subtract(tmp, 0.456, out=out[1])
        np.multiply(out[1], 1.0 / 0.224, out=out[1])
        np.subtract(tmp, 0.406, out=out[2])
        np.multiply(out[2], 1.0 / 0.225, out=out[2])

    def submit(self, left_img, right_img, color_img=None, left_timestamp=None, right_timestamp=None, left_received_perf=0.0, right_received_perf=0.0):
        if left_img is None or right_img is None:
            return
        with self._cond:
            self._pending = (
                left_img.copy(),
                right_img.copy(),
                None if color_img is None else color_img.copy(),
                left_timestamp,
                right_timestamp,
                float(left_received_perf),
                float(right_received_perf),
            )
            self._cond.notify()

    def get_latest(self):
        with self._cond:
            if self._latest is None:
                return None
            seq, color, depth, left_timestamp, right_timestamp, left_received_perf, right_received_perf = self._latest
            return int(seq), color.copy(), depth.copy(), left_timestamp, right_timestamp, float(left_received_perf), float(right_received_perf)

    def stop(self):
        with self._cond:
            self._stopped = True
            self._cond.notify()
        self._thread.join(timeout=2.0)

    def _load_model(self):
        if self.backend == "trt_engine":
            self._load_trt_engine_model()
            return
        if self.backend in ("onnx_trt", "onnx_cuda"):
            self._load_onnx_model()
            return
        if not os.path.isdir(self.repo_dir):
            raise FileNotFoundError(f"Fast-FoundationStereo repo missing: {self.repo_dir}")
        if not os.path.isfile(self.model_path):
            raise FileNotFoundError(f"Fast-FoundationStereo model missing: {self.model_path}")
        if self.repo_dir not in sys.path:
            sys.path.insert(0, self.repo_dir)
        os.environ["FOUNDATIONSTEREO_HEADLESS"] = "1"
        if self.torch_compile:
            os.environ.pop("FOUNDATIONSTEREO_DISABLE_TORCH_COMPILE", None)
        else:
            os.environ["FOUNDATIONSTEREO_DISABLE_TORCH_COMPILE"] = "1"

        import torch
        import torch._dynamo
        from core.utils.utils import InputPadder
        from Utils import AMP_DTYPE, set_logging_format, set_seed

        set_logging_format()
        set_seed(0)
        torch.autograd.set_grad_enabled(False)
        torch._dynamo.config.suppress_errors = True
        model = torch.load(self.model_path, map_location="cpu", weights_only=False)
        model.args.valid_iters = self.iters
        model.args.max_disp = int(getattr(model.args, "max_disp", 192))
        model.cuda().eval()
        self._torch = torch
        self._amp_dtype = AMP_DTYPE
        self._padder_cls = InputPadder
        self._model = model
        self._loaded = True
        self.status = "loaded"
        print(
            f">>> OAK-D FastFoundation GPU model loaded: iters={self.iters} scale={self.scale:.2f} "
            f"backend=pytorch profile={self.model_profile} ({self.profile_label}) "
            f"torch_compile={'on' if self.torch_compile else 'off'} <<<",
            flush=True,
        )

    def _trt_dtype_to_torch_dtype(self, trt_dtype):
        torch = self._torch
        trt = self._trt
        mapping = {
            trt.DataType.FLOAT: torch.float32,
            trt.DataType.HALF: torch.float16,
            trt.DataType.BF16: torch.bfloat16,
            trt.DataType.INT32: torch.int32,
            trt.DataType.INT8: torch.int8,
            trt.DataType.BOOL: torch.bool,
        }
        if trt_dtype not in mapping:
            raise RuntimeError(f"Unsupported TensorRT dtype: {trt_dtype}")
        return mapping[trt_dtype]

    def _load_trt_engine_model(self):
        if not os.path.isfile(self.trt_engine_path):
            raise FileNotFoundError(
                "Fast-FoundationStereo TensorRT engine missing: "
                f"{self.trt_engine_path}. Build it with "
                "experiments/oakd_head_tracker_demo/build_fast_foundation_trt_engine.py"
            )
        import torch
        dll_dirs = ensure_fast_foundation_onnx_dll_paths()
        import tensorrt as trt

        torch.autograd.set_grad_enabled(False)
        logger = trt.Logger(trt.Logger.WARNING)
        with open(self.trt_engine_path, "rb") as engine_file:
            engine = trt.Runtime(logger).deserialize_cuda_engine(engine_file.read())
        if engine is None:
            raise RuntimeError(
                f"Failed to load TensorRT engine: {self.trt_engine_path}. "
                "Rebuild it with the same TensorRT/CUDA/driver stack on this machine."
            )
        context = engine.create_execution_context()
        input_names = []
        output_names = []
        for i in range(engine.num_io_tensors):
            name = engine.get_tensor_name(i)
            if engine.get_tensor_mode(name) == trt.TensorIOMode.INPUT:
                input_names.append(name)
            else:
                output_names.append(name)
        if len(input_names) < 2 or not output_names:
            raise RuntimeError(
                f"Unexpected TensorRT engine I/O: inputs={input_names}, outputs={output_names}"
            )
        input_shape = tuple(engine.get_tensor_shape(input_names[0]))
        self._trt_hw = (int(input_shape[2]), int(input_shape[3]))
        self._init_fast_input_buffers(self._trt_hw[0], self._trt_hw[1])
        self._torch = torch
        self._trt = trt
        self._trt_engine = engine
        self._trt_context = context
        self._trt_input_names = input_names[:2]
        self._trt_output_names = output_names
        self._trt_stream = torch.cuda.Stream()
        self._loaded = True
        self.status = "loaded"
        print(
            f">>> OAK-D FastFoundation native TensorRT engine loaded: "
            f"profile={self.model_profile} ({self.profile_label}) input={self._trt_hw[0]}x{self._trt_hw[1]} "
            f"engine={self.trt_engine_path} dll_dirs={len(dll_dirs)} <<<",
            flush=True,
        )

    def _load_onnx_model(self):
        if not os.path.isfile(self.onnx_path):
            raise FileNotFoundError(f"Fast-FoundationStereo ONNX model missing: {self.onnx_path}")
        import torch
        dll_dirs = ensure_fast_foundation_onnx_dll_paths()
        import onnxruntime as ort

        torch.autograd.set_grad_enabled(False)
        available = ort.get_available_providers()
        providers = []
        if self.backend == "onnx_trt" and "TensorrtExecutionProvider" in available:
            cache_dir = os.environ.get(
                "FAST_FOUNDATIONSTEREO_TRT_CACHE",
                os.path.join(os.path.dirname(self.onnx_path), "trt_cache"),
            )
            os.makedirs(cache_dir, exist_ok=True)
            providers.append((
                "TensorrtExecutionProvider",
                {
                    "trt_fp16_enable": True,
                    "trt_engine_cache_enable": True,
                    "trt_engine_cache_path": cache_dir,
                    "trt_min_subgraph_size": int(os.environ.get("FAST_FOUNDATIONSTEREO_TRT_MIN_SUBGRAPH_SIZE", "5")),
                },
            ))
        if "CUDAExecutionProvider" in available:
            providers.append("CUDAExecutionProvider")
        providers.append("CPUExecutionProvider")

        sess_options = ort.SessionOptions()
        sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess_options.log_severity_level = int(os.environ.get("FAST_FOUNDATIONSTEREO_ORT_LOG_SEVERITY", "3"))
        self._ort_session = ort.InferenceSession(self.onnx_path, sess_options=sess_options, providers=providers)
        self._ort = ort
        self._ort_input_names = [inp.name for inp in self._ort_session.get_inputs()]
        self._ort_output_name = self._ort_session.get_outputs()[0].name
        input_shape = self._ort_session.get_inputs()[0].shape
        self._onnx_hw = (int(input_shape[2]), int(input_shape[3]))
        self._init_fast_input_buffers(self._onnx_hw[0], self._onnx_hw[1])
        self.onnx_provider = ",".join(self._ort_session.get_providers())
        if self.backend == "onnx_trt" and "TensorrtExecutionProvider" not in self._ort_session.get_providers():
            print(
                f">>> OAK-D FastFoundation TensorRT requested but not active; "
                f"providers={self.onnx_provider}. Falling back inside ONNX Runtime. <<<",
                flush=True,
            )
        self._loaded = True
        self.status = "loaded"
        print(
            f">>> OAK-D FastFoundation ONNX model loaded: backend={self.backend} "
            f"profile={self.model_profile} ({self.profile_label}) "
            f"providers={self.onnx_provider} input={self._onnx_hw[0]}x{self._onnx_hw[1]} "
            f"dll_dirs={len(dll_dirs)} path={self.onnx_path} <<<",
            flush=True,
        )

    def _infer_depth_onnx(self, left_gray, right_gray, color_img):
        target_h, target_w = self._onnx_hw
        t0 = time.perf_counter()
        left_small = cv2.resize(left_gray, (target_w, target_h), interpolation=cv2.INTER_LINEAR)
        right_small = cv2.resize(right_gray, (target_w, target_h), interpolation=cv2.INTER_LINEAR)

        self._fill_normalized_gray_input(left_small, self._ff_left_input)
        self._fill_normalized_gray_input(right_small, self._ff_right_input)
        feed = {
            self._ort_input_names[0]: self._ff_left_input,
            self._ort_input_names[1]: self._ff_right_input,
        }
        t_pre = time.perf_counter()
        output = self._ort_session.run([self._ort_output_name], feed)[0]
        t_model = time.perf_counter()
        disp = np.asarray(output, dtype=np.float32).reshape(target_h, target_w).clip(0, None)
        fx = target_w / float(max(1, self.width))
        disp = cv2.resize(disp, (self.width, self.height), interpolation=cv2.INTER_LINEAR) / max(1e-6, fx)
        t_download = time.perf_counter()

        valid = np.isfinite(disp) & (disp > 0.75)
        depth_m = np.zeros((self.height, self.width), dtype=np.float32)
        depth_m[valid] = (float(self.intrinsics.fx) * self.baseline_m) / np.maximum(disp[valid], 0.75)
        depth_m[(depth_m < 0.05) | (depth_m > 10.0)] = 0.0
        if color_img is not None:
            color = cv2.resize(color_img, (self.width, self.height), interpolation=cv2.INTER_LINEAR)
        else:
            color = cv2.cvtColor(left_gray, cv2.COLOR_GRAY2BGR)
        t_cloud = time.perf_counter()
        self.timing_ms = {
            "pre": (t_pre - t0) * 1000.0,
            "upload": 0.0,
            "model": (t_model - t_pre) * 1000.0,
            "download": (t_download - t_model) * 1000.0,
            "depth": (t_cloud - t_download) * 1000.0,
        }
        return color, depth_m

    def _infer_depth_trt_engine(self, left_gray, right_gray, color_img):
        target_h, target_w = self._trt_hw
        t0 = time.perf_counter()
        left_small = cv2.resize(left_gray, (target_w, target_h), interpolation=cv2.INTER_LINEAR)
        right_small = cv2.resize(right_gray, (target_w, target_h), interpolation=cv2.INTER_LINEAR)

        self._fill_normalized_gray_input(left_small, self._ff_left_input)
        self._fill_normalized_gray_input(right_small, self._ff_right_input)
        t_pre = time.perf_counter()

        torch = self._torch
        engine = self._trt_engine
        context = self._trt_context
        stream = self._trt_stream or torch.cuda.current_stream()
        with torch.cuda.stream(stream):
            input_tensors = {}
            for name, array in zip(self._trt_input_names, (self._ff_left_input, self._ff_right_input)):
                tensor = torch.as_tensor(array, device="cuda")
                expected_dtype = self._trt_dtype_to_torch_dtype(engine.get_tensor_dtype(name))
                if tensor.dtype != expected_dtype:
                    tensor = tensor.to(expected_dtype)
                if not tensor.is_contiguous():
                    tensor = tensor.contiguous()
                context.set_input_shape(name, tuple(tensor.shape))
                input_tensors[name] = tensor
            t_upload = time.perf_counter()

            output_tensors = {}
            for name in self._trt_output_names:
                shape = tuple(context.get_tensor_shape(name))
                dtype = self._trt_dtype_to_torch_dtype(engine.get_tensor_dtype(name))
                output_tensors[name] = torch.empty(shape, device="cuda", dtype=dtype)

            for name, tensor in input_tensors.items():
                context.set_tensor_address(name, int(tensor.data_ptr()))
            for name, tensor in output_tensors.items():
                context.set_tensor_address(name, int(tensor.data_ptr()))

            if not context.execute_async_v3(stream.cuda_stream):
                raise RuntimeError("TensorRT execute_async_v3 failed")
            output_cpu = output_tensors[self._trt_output_names[0]].float().cpu()
        stream.synchronize()
        t_model = time.perf_counter()

        disp = np.asarray(output_cpu.numpy(), dtype=np.float32).reshape(target_h, target_w).clip(0, None)
        fx = target_w / float(max(1, self.width))
        disp = cv2.resize(disp, (self.width, self.height), interpolation=cv2.INTER_LINEAR) / max(1e-6, fx)
        t_download = time.perf_counter()

        valid = np.isfinite(disp) & (disp > 0.75)
        depth_m = np.zeros((self.height, self.width), dtype=np.float32)
        depth_m[valid] = (float(self.intrinsics.fx) * self.baseline_m) / np.maximum(disp[valid], 0.75)
        depth_m[(depth_m < 0.05) | (depth_m > 10.0)] = 0.0
        if color_img is not None:
            color = cv2.resize(color_img, (self.width, self.height), interpolation=cv2.INTER_LINEAR)
        else:
            color = cv2.cvtColor(left_gray, cv2.COLOR_GRAY2BGR)
        t_cloud = time.perf_counter()
        self.timing_ms = {
            "pre": (t_pre - t0) * 1000.0,
            "upload": (t_upload - t_pre) * 1000.0,
            "model": (t_model - t_upload) * 1000.0,
            "download": (t_download - t_model) * 1000.0,
            "depth": (t_cloud - t_download) * 1000.0,
        }
        return color, depth_m

    def _infer_depth(self, left_img, right_img, color_img):
        if not self._loaded:
            self.status = "loading"
            self._load_model()

        t0 = time.perf_counter()
        if left_img.ndim == 3:
            left_gray = cv2.cvtColor(left_img, cv2.COLOR_BGR2GRAY)
        else:
            left_gray = left_img
        if right_img.ndim == 3:
            right_gray = cv2.cvtColor(right_img, cv2.COLOR_BGR2GRAY)
        else:
            right_gray = right_img
        if left_gray.shape[:2] != (self.height, self.width):
            left_gray = cv2.resize(left_gray, (self.width, self.height), interpolation=cv2.INTER_AREA)
        if right_gray.shape[:2] != (self.height, self.width):
            right_gray = cv2.resize(right_gray, (self.width, self.height), interpolation=cv2.INTER_AREA)

        if self.backend == "trt_engine":
            return self._infer_depth_trt_engine(left_gray, right_gray, color_img)
        if self.backend in ("onnx_trt", "onnx_cuda"):
            return self._infer_depth_onnx(left_gray, right_gray, color_img)

        if self.scale < 0.999:
            left_small = cv2.resize(left_gray, dsize=None, fx=self.scale, fy=self.scale, interpolation=cv2.INTER_LINEAR)
            right_small = cv2.resize(right_gray, (left_small.shape[1], left_small.shape[0]), interpolation=cv2.INTER_LINEAR)
        else:
            left_small = left_gray
            right_small = right_gray
        t_pre = time.perf_counter()

        torch = self._torch
        img0 = torch.as_tensor(left_small).cuda().float()[None, None].expand(-1, 3, -1, -1)
        img1 = torch.as_tensor(right_small).cuda().float()[None, None].expand(-1, 3, -1, -1)
        padder = self._padder_cls(img0.shape, divis_by=32, force_square=False)
        img0, img1 = padder.pad(img0, img1)
        t_upload = time.perf_counter()
        with torch.amp.autocast("cuda", enabled=True, dtype=self._amp_dtype):
            disp = self._model.forward(
                img0,
                img1,
                iters=self.iters,
                test_mode=True,
                optimize_build_volume="pytorch1",
            )
        torch.cuda.synchronize()
        t_model = time.perf_counter()
        disp = padder.unpad(disp.float()).data.cpu().numpy().reshape(left_small.shape[:2]).clip(0, None)
        t_download = time.perf_counter()
        if self.scale < 0.999:
            disp = cv2.resize(disp, (self.width, self.height), interpolation=cv2.INTER_LINEAR) / self.scale

        valid = np.isfinite(disp) & (disp > 0.75)
        depth_m = np.zeros((self.height, self.width), dtype=np.float32)
        depth_m[valid] = (float(self.intrinsics.fx) * self.baseline_m) / np.maximum(disp[valid], 0.75)
        depth_m[(depth_m < 0.05) | (depth_m > 10.0)] = 0.0
        if color_img is not None:
            color = cv2.resize(color_img, (self.width, self.height), interpolation=cv2.INTER_LINEAR)
        else:
            color = cv2.cvtColor(left_gray, cv2.COLOR_GRAY2BGR)
        t_cloud = time.perf_counter()
        self.timing_ms = {
            "pre": (t_pre - t0) * 1000.0,
            "upload": (t_upload - t_pre) * 1000.0,
            "model": (t_model - t_upload) * 1000.0,
            "download": (t_download - t_model) * 1000.0,
            "depth": (t_cloud - t_download) * 1000.0,
        }
        return color, depth_m

    def _loop(self):
        while True:
            with self._cond:
                while self._pending is None and not self._stopped:
                    self._cond.wait()
                if self._stopped:
                    return
                item = self._pending
                self._pending = None
            left_img, right_img, color_img, left_timestamp, right_timestamp, left_received_perf, right_received_perf = item
            try:
                color, depth = self._infer_depth(left_img, right_img, color_img)
                now = time.perf_counter()
                self._fps_count += 1
                if now - self._fps_last_time >= 0.5:
                    self.fps = self._fps_count / (now - self._fps_last_time)
                    self._fps_count = 0
                    self._fps_last_time = now
                with self._cond:
                    self._latest_seq += 1
                    self._latest = (self._latest_seq, color, depth, left_timestamp, right_timestamp, left_received_perf, right_received_perf)
                self.status = "running"
            except Exception as exc:
                self.status = f"error: {exc}"
                print(f">>> OAK-D FastFoundation GPU worker error: {exc} <<<", flush=True)
                time.sleep(0.2)

class OakDCapture:
    COLOR_RESOLUTIONS = None
    MONO_RESOLUTIONS = None
    PRESETS = None

    def __init__(
        self,
        width=OAKD_WIDTH,
        height=OAKD_HEIGHT,
        fps=OAKD_FPS,
        rgb_res=None,
        mono_res=None,
        preset=None,
        lr_check=None,
        subpixel=None,
        subpixel_bits=None,
        confidence_threshold=None,
        median_filter=None,
        speckle_filter=None,
        speckle_range=None,
        depth_source=None,
        fast_stereo_iters=None,
        fast_stereo_scale=None,
        fast_stereo_torch_compile=None,
        fast_stereo_backend=None,
        fast_stereo_model_profile=None,
        use_rgb_color_for_host_depth=None,
        host_depth_color_mode=None,
    ):
        ensure_depthai()
        self.width = int(width)
        self.height = int(height)
        self.fps = float(fps)
        self.rgb_res = (rgb_res or os.environ.get("OAKD_RGB_RES", "1080p")).strip().lower()
        self.mono_res = (mono_res or os.environ.get("OAKD_MONO_RES", "800p")).strip().lower()
        self.preset = (preset or os.environ.get("OAKD_STEREO_PRESET", "fast_density")).strip().lower()
        self.lr_check = OAKD_LR_CHECK if lr_check is None else bool(lr_check)
        self.subpixel = OAKD_SUBPIXEL if subpixel is None else bool(subpixel)
        self.subpixel_bits = OAKD_SUBPIXEL_BITS if subpixel_bits is None else int(subpixel_bits)
        self.confidence_threshold = OAKD_CONFIDENCE_THRESHOLD if confidence_threshold is None else int(confidence_threshold)
        self.median_filter = (median_filter or OAKD_MEDIAN_FILTER).strip().lower()
        self.speckle_filter = OAKD_SPECKLE_FILTER if speckle_filter is None else bool(speckle_filter)
        self.speckle_range = OAKD_SPECKLE_RANGE if speckle_range is None else int(speckle_range)
        self.depth_source = (depth_source or os.environ.get("OAKD_DEPTH_SOURCE", "depthai")).strip().lower()
        if self.depth_source not in ("depthai", "fast_foundation", "host_sgbm"):
            self.depth_source = "depthai"
        self.fast_foundation_enabled = self.depth_source == "fast_foundation"
        self.host_sgbm_enabled = self.depth_source == "host_sgbm"
        self.host_stereo_enabled = self.fast_foundation_enabled or self.host_sgbm_enabled
        self.fast_stereo_iters = 4 if fast_stereo_iters is None else int(fast_stereo_iters)
        self.fast_stereo_scale = 1.0 if fast_stereo_scale is None else float(fast_stereo_scale)
        self.fast_stereo_torch_compile = False if fast_stereo_torch_compile is None else bool(fast_stereo_torch_compile)
        self.fast_stereo_backend = str(fast_stereo_backend or os.environ.get("OAKD_FAST_STEREO_BACKEND", "pytorch")).strip().lower()
        if self.fast_stereo_backend not in ("pytorch", "onnx_trt", "onnx_cuda", "trt_engine"):
            self.fast_stereo_backend = "pytorch"
        self.fast_stereo_model_profile = str(
            fast_stereo_model_profile or os.environ.get("OAKD_FAST_STEREO_MODEL_PROFILE", "full_320x736_i4")
        ).strip().lower()
        if self.fast_stereo_model_profile not in FAST_FOUNDATION_MODEL_PROFILES:
            self.fast_stereo_model_profile = "full_320x736_i4"
        self.use_rgb_color_for_host_depth = (
            os.environ.get("OAKD_USE_RGB_COLOR_FOR_HOST_DEPTH", "1").strip().lower() in ("1", "true", "yes", "on")
            if use_rgb_color_for_host_depth is None
            else bool(use_rgb_color_for_host_depth)
        )
        self.host_depth_color_mode = str(
            host_depth_color_mode or os.environ.get("OAKD_HOST_DEPTH_COLOR_MODE", "rgb_projected_stable")
        ).strip().lower()
        if self.host_depth_color_mode not in ("gray", "rgb_preview", "rgb_projected", "rgb_projected_stable"):
            self.host_depth_color_mode = "rgb_projected_stable"
        if not self.use_rgb_color_for_host_depth:
            self.host_depth_color_mode = "gray"
        self._stable_projected_color_bgr = None
        self._stable_projected_color_alpha = float(np.clip(float(os.environ.get("OAKD_PROJECTED_COLOR_SMOOTHING", "0.55")), 0.0, 0.95))
        self.pipeline = None
        self.rgb_queue = None
        self.depth_queue = None
        self.left_queue = None
        self.right_queue = None
        self.config_queue = None
        self.host_stereo_matcher = None
        self.host_stereo_matcher_scale = None
        self.fast_foundation_worker = None
        self.host_stereo_fx = 790.0
        self.host_stereo_baseline_m = float(os.environ.get("OAKD_HOST_STEREO_BASELINE_M", "0.075"))
        self.calibration = None
        self.rgb_intrinsics = None
        self.mono_intrinsics = None
        self.left_to_rgb_extrinsics_m = None
        self.left_rectification_rotation = None
        self._host_rgb_projection_cache = None
        self.latest_color_bgr = None
        self.latest_depth_m = None
        self.latest_frame_serial = 0
        self.latest_frame_time = 0.0
        self.latest_sensor_age_ms = 0.0
        self.latest_color_age_ms = 0.0
        self.latest_sensor_host_age_ms = 0.0
        self.latest_color_host_age_ms = 0.0
        self.depth_correction_quadratic = float(os.environ.get("OAKD_DEPTH_CORRECTION_QUADRATIC", "0.0"))
        self.depth_correction_scale = float(os.environ.get("OAKD_DEPTH_CORRECTION_SCALE", "1.0"))
        self.depth_correction_offset_m = float(os.environ.get("OAKD_DEPTH_CORRECTION_OFFSET_M", "0.0"))
        self.capture_fps = 0.0
        self._capture_count = 0
        self._last_capture_fps_time = time.perf_counter()
        self._frame_lock = threading.Lock()
        self._config_lock = threading.Lock()
        self._stop_event = threading.Event()
        self._frame_event = threading.Event()
        self.device_error = False
        self.device_error_message = ""
        self._device_error_reported = False
        self.intrinsics = CameraIntrinsics(
            0.5 * self.width / np.tan(np.deg2rad(69.0) * 0.5),
            0.5 * self.width / np.tan(np.deg2rad(69.0) * 0.5),
            self.width * 0.5,
            self.height * 0.5,
        )
        self._start_pipeline()
        self._capture_thread = threading.Thread(target=self._capture_loop, name="oakd-capture", daemon=True)
        self._capture_thread.start()

    @classmethod
    def _init_depthai_constants(cls):
        if cls.COLOR_RESOLUTIONS is not None:
            return
        cls.COLOR_RESOLUTIONS = {
            "720p": dai.ColorCameraProperties.SensorResolution.THE_720_P,
            "800p": dai.ColorCameraProperties.SensorResolution.THE_800_P,
            "1080p": dai.ColorCameraProperties.SensorResolution.THE_1080_P,
        }
        cls.MONO_RESOLUTIONS = {
            "400p": dai.MonoCameraProperties.SensorResolution.THE_400_P,
            "480p": dai.MonoCameraProperties.SensorResolution.THE_480_P,
            "720p": dai.MonoCameraProperties.SensorResolution.THE_720_P,
            "800p": dai.MonoCameraProperties.SensorResolution.THE_800_P,
        }
        cls.PRESETS = {
            "default": dai.node.StereoDepth.PresetMode.DEFAULT,
            "density": dai.node.StereoDepth.PresetMode.DENSITY,
            "fast_density": dai.node.StereoDepth.PresetMode.FAST_DENSITY,
            "fast_accuracy": dai.node.StereoDepth.PresetMode.FAST_ACCURACY,
        }

    def _median_filter_mode(self):
        return self._median_filter_mode_for(self.median_filter)

    @staticmethod
    def _median_filter_mode_for(value):
        text = str(value).strip().lower()
        modes = {
            "off": dai.MedianFilter.MEDIAN_OFF,
            "0": dai.MedianFilter.MEDIAN_OFF,
            "3": dai.MedianFilter.KERNEL_3x3,
            "3x3": dai.MedianFilter.KERNEL_3x3,
            "5": dai.MedianFilter.KERNEL_5x5,
            "5x5": dai.MedianFilter.KERNEL_5x5,
            "7": dai.MedianFilter.KERNEL_7x7,
            "7x7": dai.MedianFilter.KERNEL_7x7,
        }
        return modes.get(text, dai.MedianFilter.KERNEL_7x7)

    def _make_stereo_config(self):
        config = dai.StereoDepthConfig()
        config.setConfidenceThreshold(max(0, min(255, int(self.confidence_threshold))))
        config.setMedianFilter(self._median_filter_mode())
        config.postProcessing.speckleFilter.enable = bool(self.speckle_filter)
        config.postProcessing.speckleFilter.speckleRange = max(0, int(self.speckle_range))
        return config

    def apply_runtime_settings(self, settings):
        with self._config_lock:
            self.confidence_threshold = int(settings.get("confidence_threshold", self.confidence_threshold))
            self.median_filter = str(settings.get("median_filter", self.median_filter)).strip().lower()
            self.speckle_filter = bool(settings.get("speckle_filter", self.speckle_filter))
            self.speckle_range = int(settings.get("speckle_range", self.speckle_range))
            self.use_rgb_color_for_host_depth = bool(settings.get("use_rgb_color_for_host_depth", self.use_rgb_color_for_host_depth))
            self.host_depth_color_mode = str(settings.get("host_depth_color_mode", self.host_depth_color_mode)).strip().lower()
            if self.host_depth_color_mode not in ("gray", "rgb_preview", "rgb_projected", "rgb_projected_stable"):
                self.host_depth_color_mode = "rgb_projected_stable"
            if not self.use_rgb_color_for_host_depth:
                self.host_depth_color_mode = "gray"
            if self.host_depth_color_mode != "rgb_projected_stable":
                self._stable_projected_color_bgr = None
            print(
                ">>> OAK-D runtime stereo config queued locally only; "
                "DepthAI inputConfig is disabled while RGB depthAlign is active to avoid native crashes. "
                f"confidence={max(0, min(255, self.confidence_threshold))} "
                f"median={self.median_filter} "
                f"speckle={'on' if self.speckle_filter else 'off'}:{max(0, self.speckle_range)} "
                f"host_color={self.host_depth_color_mode} <<<"
            )
            return False

    def _start_pipeline(self):
        self._init_depthai_constants()
        rgb_res = self.rgb_res
        mono_res = self.mono_res
        preset = self.preset
        rgb_res = rgb_res if rgb_res in self.COLOR_RESOLUTIONS else "1080p"
        mono_res = mono_res if mono_res in self.MONO_RESOLUTIONS else "400p"
        preset = preset if preset in self.PRESETS else "fast_density"

        pipeline = dai.Pipeline()
        color = pipeline.create(dai.node.ColorCamera)
        color.setBoardSocket(dai.CameraBoardSocket.CAM_A)
        color.setResolution(self.COLOR_RESOLUTIONS[rgb_res])
        color.setPreviewSize(self.width, self.height)
        color.setInterleaved(False)
        color.setColorOrder(dai.ColorCameraProperties.ColorOrder.BGR)
        color.setFps(self.fps)

        mono_left = pipeline.create(dai.node.MonoCamera)
        mono_right = pipeline.create(dai.node.MonoCamera)
        mono_left.setBoardSocket(dai.CameraBoardSocket.CAM_B)
        mono_right.setBoardSocket(dai.CameraBoardSocket.CAM_C)
        mono_left.setResolution(self.MONO_RESOLUTIONS[mono_res])
        mono_right.setResolution(self.MONO_RESOLUTIONS[mono_res])
        mono_left.setFps(self.fps)
        mono_right.setFps(self.fps)

        stereo = pipeline.create(dai.node.StereoDepth)
        stereo.setDefaultProfilePreset(self.PRESETS[preset])
        if not self.lr_check:
            print(
                ">>> OAK-D forcing lr_check=on because DepthAI RGB/CENTER depth alignment rejects lr_check=off. "
                "Host stereo source switches still work, but the on-device DepthAI queue needs LR check. <<<"
            )
            self.lr_check = True
        if self.host_stereo_enabled:
            print(
                ">>> OAK-D host stereo low-latency path: RGB depthAlign disabled; "
                "host color projection handles RGB/mono alignment. <<<"
            )
        else:
            stereo.setDepthAlign(dai.CameraBoardSocket.CAM_A)
            stereo.setOutputSize(self.width, self.height)
        stereo.setLeftRightCheck(self.lr_check)
        stereo.setSubpixel(self.subpixel)
        if self.subpixel and hasattr(stereo.initialConfig, "setSubpixelFractionalBits"):
            stereo.initialConfig.setSubpixelFractionalBits(max(3, min(5, self.subpixel_bits)))
        stereo.initialConfig.setConfidenceThreshold(max(0, min(255, self.confidence_threshold)))
        stereo.initialConfig.setMedianFilter(self._median_filter_mode())
        stereo.initialConfig.postProcessing.speckleFilter.enable = bool(self.speckle_filter)
        stereo.initialConfig.postProcessing.speckleFilter.speckleRange = max(0, self.speckle_range)
        mono_left.out.link(stereo.left)
        mono_right.out.link(stereo.right)

        self.config_queue = stereo.inputConfig.createInputQueue(maxSize=1, blocking=False)
        self.rgb_queue = color.preview.createOutputQueue(maxSize=1, blocking=False)
        self.left_queue = stereo.rectifiedLeft.createOutputQueue(maxSize=1, blocking=False)
        self.right_queue = stereo.rectifiedRight.createOutputQueue(maxSize=1, blocking=False)
        if self.host_stereo_enabled:
            self.depth_queue = None
        else:
            self.depth_queue = stereo.depth.createOutputQueue(maxSize=1, blocking=False)
        self.pipeline = pipeline
        self.pipeline.start()
        self._try_load_intrinsics()
        if self.host_sgbm_enabled:
            self._init_host_stereo_matcher()
        if self.fast_foundation_enabled:
            self.fast_foundation_worker = FastFoundationDepthWorker(
                self.width,
                self.height,
                self.intrinsics,
                self.host_stereo_baseline_m,
                scale=self.fast_stereo_scale,
                iters=self.fast_stereo_iters,
                torch_compile=self.fast_stereo_torch_compile,
                backend=self.fast_stereo_backend,
                model_profile=self.fast_stereo_model_profile,
            )
        color_label = rgb_res
        print(
            f">>> OAK-D RGB+depth source active at {self.width}x{self.height} "
            f"{self.fps:.0f}fps rgb={color_label} mono={mono_res} preset={preset} "
            f"lr={'on' if self.lr_check else 'off'} subpixel={'on' if self.subpixel else 'off'} "
            f"subpixel_bits={max(3, min(5, self.subpixel_bits)) if self.subpixel else 0} "
            f"confidence={max(0, min(255, self.confidence_threshold))} "
            f"median={self.median_filter} speckle={'on' if self.speckle_filter else 'off'}:{max(0, self.speckle_range)} "
            f"depth_source={'fast_foundation_gpu' if self.fast_foundation_enabled else ('host_sgbm_local' if self.host_sgbm_enabled else 'depthai_on_device')} <<<"
        )

    def _try_load_intrinsics(self):
        try:
            device = self.pipeline.getDefaultDevice()
            calibration = device.readCalibration()
            self.calibration = calibration
            rgb_matrix = calibration.getCameraIntrinsics(dai.CameraBoardSocket.CAM_A, self.width, self.height)
            mono_matrix = calibration.getCameraIntrinsics(dai.CameraBoardSocket.CAM_B, self.width, self.height)
            self.rgb_intrinsics = CameraIntrinsics(rgb_matrix[0][0], rgb_matrix[1][1], rgb_matrix[0][2], rgb_matrix[1][2])
            self.mono_intrinsics = CameraIntrinsics(mono_matrix[0][0], mono_matrix[1][1], mono_matrix[0][2], mono_matrix[1][2])
            try:
                self.left_to_rgb_extrinsics_m = np.array(
                    calibration.getCameraExtrinsics(
                        dai.CameraBoardSocket.CAM_B,
                        dai.CameraBoardSocket.CAM_A,
                        False,
                        dai.LengthUnit.METER,
                    ),
                    dtype=np.float32,
                )
            except Exception as exc:
                self.left_to_rgb_extrinsics_m = None
                print(f">>> OAK-D left->RGB extrinsics unavailable; projected host color disabled: {exc} <<<")
            try:
                self.left_rectification_rotation = np.array(calibration.getStereoLeftRectificationRotation(), dtype=np.float32)
                if self.left_rectification_rotation.shape != (3, 3):
                    self.left_rectification_rotation = None
            except Exception:
                self.left_rectification_rotation = None
            try:
                self.host_stereo_baseline_m = float(calibration.getBaselineDistance(dai.CameraBoardSocket.CAM_B, dai.CameraBoardSocket.CAM_C)) / 100.0
            except Exception:
                pass
            self._select_active_intrinsics()
            print(
                f">>> OAK-D intrinsics fx={self.intrinsics.fx:.1f} fy={self.intrinsics.fy:.1f} "
                f"pp=({self.intrinsics.ppx:.1f},{self.intrinsics.ppy:.1f}) baseline={self.host_stereo_baseline_m:.3f}m <<<"
            )
        except Exception as exc:
            print(f">>> OAK-D calibration intrinsics unavailable; using approximate FOV intrinsics: {exc} <<<")

    def _select_active_intrinsics(self):
        if self.host_stereo_enabled and self.mono_intrinsics is not None:
            self.intrinsics = self.mono_intrinsics
        elif not self.host_stereo_enabled and self.rgb_intrinsics is not None:
            self.intrinsics = self.rgb_intrinsics
        self.host_stereo_fx = float(self.intrinsics.fx)

    def set_depth_source(
        self,
        depth_source,
        fast_stereo_iters=None,
        fast_stereo_scale=None,
        fast_stereo_torch_compile=None,
        fast_stereo_backend=None,
        fast_stereo_model_profile=None,
    ):
        requested = str(depth_source or "depthai").strip().lower()
        if requested not in ("depthai", "fast_foundation", "host_sgbm"):
            requested = "depthai"
        with self._config_lock:
            previous_source = self.depth_source
            if fast_stereo_iters is not None:
                self.fast_stereo_iters = int(fast_stereo_iters)
            if fast_stereo_scale is not None:
                self.fast_stereo_scale = float(fast_stereo_scale)
            if fast_stereo_torch_compile is not None:
                self.fast_stereo_torch_compile = bool(fast_stereo_torch_compile)
            if fast_stereo_backend is not None:
                self.fast_stereo_backend = str(fast_stereo_backend or "pytorch").strip().lower()
                if self.fast_stereo_backend not in ("pytorch", "onnx_trt", "onnx_cuda", "trt_engine"):
                    self.fast_stereo_backend = "pytorch"
            if fast_stereo_model_profile is not None:
                self.fast_stereo_model_profile = str(fast_stereo_model_profile or "full_320x736_i4").strip().lower()
                if self.fast_stereo_model_profile not in FAST_FOUNDATION_MODEL_PROFILES:
                    self.fast_stereo_model_profile = "full_320x736_i4"

            needs_host_streams = requested in ("fast_foundation", "host_sgbm")
            if needs_host_streams and (self.left_queue is None or self.right_queue is None):
                return False, "rectified mono queues are not available in this OAK-D pipeline"
            if requested == "depthai" and (self.depth_queue is None or self.rgb_queue is None):
                return False, "DepthAI RGB/depth queues are not available in this host-only OAK-D pipeline"

            worker_needs_rebuild = (
                self.fast_foundation_worker is not None
                and (
                    requested != "fast_foundation"
                    or self.fast_foundation_worker.iters != self.fast_stereo_iters
                    or abs(float(self.fast_foundation_worker.scale) - float(self.fast_stereo_scale)) > 1e-6
                    or bool(self.fast_foundation_worker.torch_compile) != bool(self.fast_stereo_torch_compile)
                    or str(getattr(self.fast_foundation_worker, "backend", "pytorch")) != self.fast_stereo_backend
                    or str(getattr(self.fast_foundation_worker, "model_profile", "full_320x736_i4")) != self.fast_stereo_model_profile
                )
            )
            if worker_needs_rebuild:
                self.fast_foundation_worker.stop()
                self.fast_foundation_worker = None

            self.depth_source = requested
            self.fast_foundation_enabled = requested == "fast_foundation"
            self.host_sgbm_enabled = requested == "host_sgbm"
            self.host_stereo_enabled = self.fast_foundation_enabled or self.host_sgbm_enabled
            self._select_active_intrinsics()

            host_matcher_needs_rebuild = (
                self.host_sgbm_enabled
                and (
                    self.host_stereo_matcher is None
                    or self.host_stereo_matcher_scale is None
                    or abs(float(self.host_stereo_matcher_scale) - float(self.fast_stereo_scale)) > 1e-6
                )
            )
            if host_matcher_needs_rebuild:
                self.host_stereo_matcher = None
                self._init_host_stereo_matcher()
            if self.fast_foundation_enabled and self.fast_foundation_worker is None:
                self.fast_foundation_worker = FastFoundationDepthWorker(
                    self.width,
                    self.height,
                    self.intrinsics,
                    self.host_stereo_baseline_m,
                    scale=self.fast_stereo_scale,
                    iters=self.fast_stereo_iters,
                    torch_compile=self.fast_stereo_torch_compile,
                    backend=self.fast_stereo_backend,
                    model_profile=self.fast_stereo_model_profile,
                )
            if previous_source != requested or worker_needs_rebuild:
                print(
                    ">>> OAK-D live depth source switched to "
                    f"{'fast_foundation_gpu' if self.fast_foundation_enabled else ('host_sgbm_local' if self.host_sgbm_enabled else 'depthai_on_device')} "
                    f"without restarting the stack. <<<"
                )
            return True, "ok"

    def _init_host_stereo_matcher(self):
        scale = max(0.25, min(1.0, float(self.fast_stereo_scale)))
        match_width = max(160, int(round(self.width * scale)))
        max_disp = max(64, min(256, int(round(match_width / 4.0))))
        num_disparities = max(16, int(np.ceil(max_disp / 16.0)) * 16)
        block_size = 5
        self.host_stereo_matcher = cv2.StereoSGBM_create(
            minDisparity=0,
            numDisparities=num_disparities,
            blockSize=block_size,
            P1=8 * block_size * block_size,
            P2=32 * block_size * block_size,
            disp12MaxDiff=2,
            uniquenessRatio=4,
            speckleWindowSize=0,
            speckleRange=0,
            preFilterCap=31,
            mode=cv2.STEREO_SGBM_MODE_SGBM_3WAY,
        )
        self.host_stereo_matcher_scale = scale
        print(
            f">>> OAK-D host/local stereo active: OpenCV SGBM scale={scale:.2f} "
            f"num_disparities={num_disparities} baseline={self.host_stereo_baseline_m:.3f}m. "
            "DepthAI on-device stereo remains available by turning off OAK-D Fast Stereo. <<<"
        )

    def _project_rgb_color_to_host_depth(self, depth_m, rgb_img, fallback_gray=None, visibility_tolerance_m=0.035):
        if (
            depth_m is None
            or rgb_img is None
            or self.rgb_intrinsics is None
            or self.mono_intrinsics is None
            or self.left_to_rgb_extrinsics_m is None
        ):
            return None
        h, w = depth_m.shape[:2]
        rgb_h, rgb_w = rgb_img.shape[:2]
        cache_key = (
            h,
            w,
            float(self.mono_intrinsics.fx),
            float(self.mono_intrinsics.fy),
            float(self.mono_intrinsics.ppx),
            float(self.mono_intrinsics.ppy),
        )
        if self._host_rgb_projection_cache is None or self._host_rgb_projection_cache.get("key") != cache_key:
            ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
            self._host_rgb_projection_cache = {
                "key": cache_key,
                "x_norm": (xs - float(self.mono_intrinsics.ppx)) / max(1e-6, float(self.mono_intrinsics.fx)),
                "y_norm": (ys - float(self.mono_intrinsics.ppy)) / max(1e-6, float(self.mono_intrinsics.fy)),
            }
        x_norm = self._host_rgb_projection_cache["x_norm"]
        y_norm = self._host_rgb_projection_cache["y_norm"]
        z = depth_m.astype(np.float32, copy=False)
        valid = np.isfinite(z) & (z > 0.05) & (z < 10.0)
        if int(valid.sum()) <= 0:
            return None

        left_x = x_norm[valid] * z[valid]
        left_y = y_norm[valid] * z[valid]
        left_z = z[valid]
        if self.left_rectification_rotation is not None:
            rect_points = np.stack([left_x, left_y, left_z], axis=0)
            raw_points = self.left_rectification_rotation.T @ rect_points
            left_x, left_y, left_z = raw_points[0], raw_points[1], raw_points[2]

        left_points = np.stack([left_x, left_y, left_z, np.ones_like(left_z, dtype=np.float32)], axis=0)
        rgb_points = self.left_to_rgb_extrinsics_m @ left_points
        rgb_z = rgb_points[2]
        valid_z = np.isfinite(rgb_z) & (rgb_z > 1e-4)
        if int(valid_z.sum()) <= 0:
            return None

        u = np.rint((rgb_points[0] * float(self.rgb_intrinsics.fx) / np.maximum(rgb_z, 1e-6)) + float(self.rgb_intrinsics.ppx)).astype(np.int32)
        v = np.rint((rgb_points[1] * float(self.rgb_intrinsics.fy) / np.maximum(rgb_z, 1e-6)) + float(self.rgb_intrinsics.ppy)).astype(np.int32)
        inside = valid_z & (u >= 0) & (u < rgb_w) & (v >= 0) & (v < rgb_h)
        if int(inside.sum()) <= 0:
            return None

        if fallback_gray is None:
            fallback_gray = np.zeros((h, w, 3), dtype=np.uint8)
        projected = fallback_gray.copy()
        flat_indices = np.flatnonzero(valid)
        inside_flat = flat_indices[inside]
        rgb_linear = v[inside].astype(np.int64) * int(rgb_w) + u[inside].astype(np.int64)
        nearest = np.full(int(rgb_h) * int(rgb_w), np.inf, dtype=np.float32)
        np.minimum.at(nearest, rgb_linear, rgb_z[inside].astype(np.float32))
        nearest_z = nearest[rgb_linear]
        visible = np.abs(rgb_z[inside].astype(np.float32) - nearest_z) <= float(visibility_tolerance_m)
        if int(visible.sum()) <= 0:
            return projected
        projected.reshape(-1, 3)[inside_flat[visible]] = rgb_img[v[inside][visible], u[inside][visible]]
        return projected

    def _color_for_host_depth(self, left_gray, depth_m, color_img=None):
        gray_color = cv2.cvtColor(left_gray, cv2.COLOR_GRAY2BGR)
        if color_img is None or self.host_depth_color_mode == "gray":
            self._stable_projected_color_bgr = None
            return gray_color
        if self.host_depth_color_mode == "rgb_preview":
            self._stable_projected_color_bgr = None
            return cv2.resize(color_img, (self.width, self.height), interpolation=cv2.INTER_LINEAR)
        stable_mode = self.host_depth_color_mode == "rgb_projected_stable"
        fallback = gray_color
        if stable_mode and self._stable_projected_color_bgr is not None and self._stable_projected_color_bgr.shape == gray_color.shape:
            fallback = self._stable_projected_color_bgr
        tolerance = 0.16 if stable_mode else 0.035
        projected = self._project_rgb_color_to_host_depth(depth_m, color_img, fallback, tolerance)
        if projected is not None:
            if stable_mode:
                if self._stable_projected_color_bgr is None or self._stable_projected_color_bgr.shape != projected.shape:
                    self._stable_projected_color_bgr = projected.copy()
                    return projected
                alpha = float(self._stable_projected_color_alpha)
                stable = cv2.addWeighted(self._stable_projected_color_bgr, alpha, projected, 1.0 - alpha, 0.0)
                self._stable_projected_color_bgr = stable
                return stable
            self._stable_projected_color_bgr = None
            return projected
        self._stable_projected_color_bgr = None
        return cv2.resize(color_img, (self.width, self.height), interpolation=cv2.INTER_LINEAR)

    def _compute_host_stereo_depth(self, left_gray, right_gray, color_img=None):
        if left_gray is None or right_gray is None:
            return None, None
        if left_gray.ndim == 3:
            left_gray = cv2.cvtColor(left_gray, cv2.COLOR_BGR2GRAY)
        if right_gray.ndim == 3:
            right_gray = cv2.cvtColor(right_gray, cv2.COLOR_BGR2GRAY)
        if self.host_stereo_matcher is None:
            self._init_host_stereo_matcher()
        if left_gray.shape[:2] != (self.height, self.width):
            left_gray = cv2.resize(left_gray, (self.width, self.height), interpolation=cv2.INTER_AREA)
        if right_gray.shape[:2] != (self.height, self.width):
            right_gray = cv2.resize(right_gray, (self.width, self.height), interpolation=cv2.INTER_AREA)

        scale = max(0.25, min(1.0, float(self.fast_stereo_scale)))
        if scale < 0.999:
            small_size = (max(160, int(round(self.width * scale))), max(90, int(round(self.height * scale))))
            left_match = cv2.resize(left_gray, small_size, interpolation=cv2.INTER_AREA)
            right_match = cv2.resize(right_gray, small_size, interpolation=cv2.INTER_AREA)
            disp_small = self.host_stereo_matcher.compute(left_match, right_match).astype(np.float32) / 16.0
            disparity = cv2.resize(disp_small, (self.width, self.height), interpolation=cv2.INTER_LINEAR) / scale
        else:
            disparity = self.host_stereo_matcher.compute(left_gray, right_gray).astype(np.float32) / 16.0

        valid = disparity > 0.75
        depth_m = np.zeros((self.height, self.width), dtype=np.float32)
        depth_m[valid] = (float(self.host_stereo_fx) * float(self.host_stereo_baseline_m)) / np.maximum(disparity[valid], 0.75)
        depth_m[(depth_m < 0.05) | (depth_m > 10.0)] = 0.0
        color = self._color_for_host_depth(left_gray, depth_m, color_img)
        return color, depth_m

    def _drain_latest(self, queue):
        latest = None
        while queue is not None:
            try:
                msg = queue.tryGet()
            except Exception as exc:
                self.device_error = True
                self.device_error_message = str(exc)
                self._stop_event.set()
                self._frame_event.set()
                if not self._device_error_reported:
                    self._device_error_reported = True
                    print(
                        f">>> OAK-D stream queue closed; marking capture for restart. "
                        f"This usually follows a USB/device X_LINK drop: {exc} <<<",
                        flush=True,
                    )
                return latest
            if msg is None:
                break
            latest = msg
        return latest

    def _message_timestamp(self, msg):
        if msg is None:
            return None
        try:
            return msg.getTimestamp()
        except Exception:
            return None

    def _timestamp_age_ms(self, timestamp, received_perf=0.0):
        if timestamp is not None:
            try:
                age = dai.Clock.now() - timestamp
                return max(0.0, float(age.total_seconds()) * 1000.0)
            except Exception:
                pass
        if received_perf:
            return max(0.0, (time.perf_counter() - float(received_perf)) * 1000.0)
        return 0.0

    def _host_received_age_ms(self, received_perf=0.0):
        if received_perf:
            return max(0.0, (time.perf_counter() - float(received_perf)) * 1000.0)
        return 0.0

    def _capture_loop(self):
        pending_color = None
        pending_depth_m = None
        pending_left = None
        pending_right = None
        pending_color_timestamp = None
        pending_depth_timestamp = None
        pending_left_timestamp = None
        pending_right_timestamp = None
        pending_color_received_perf = 0.0
        pending_depth_received_perf = 0.0
        pending_left_received_perf = 0.0
        pending_right_received_perf = 0.0
        pending_color_serial = 0
        pending_left_serial = 0
        pending_right_serial = 0
        pending_depth_serial = 0
        pending_stereo_serial = 0
        published_fast_seq = -1
        published_depth_serial = -1
        published_color_serial = -1
        submitted_fast_pair = (-1, -1)
        computed_host_pair = (-1, -1)
        while not self._stop_event.is_set():
            rgb_msg = self._drain_latest(self.rgb_queue) if self.rgb_queue is not None else None
            depth_msg = self._drain_latest(self.depth_queue) if not self.host_stereo_enabled else None
            left_msg = self._drain_latest(self.left_queue)
            right_msg = self._drain_latest(self.right_queue)
            got_message = rgb_msg is not None or depth_msg is not None or left_msg is not None or right_msg is not None
            if rgb_msg is not None:
                pending_color = rgb_msg.getCvFrame()
                pending_color_timestamp = self._message_timestamp(rgb_msg)
                pending_color_received_perf = time.perf_counter()
                pending_color_serial += 1
            if self.host_stereo_enabled:
                if left_msg is not None:
                    pending_left = left_msg.getCvFrame()
                    pending_left_timestamp = self._message_timestamp(left_msg)
                    pending_left_received_perf = time.perf_counter()
                    pending_left_serial += 1
                if right_msg is not None:
                    pending_right = right_msg.getCvFrame()
                    pending_right_timestamp = self._message_timestamp(right_msg)
                    pending_right_received_perf = time.perf_counter()
                    pending_right_serial += 1
                current_pair = (pending_left_serial, pending_right_serial)
                if self.fast_foundation_enabled:
                    if pending_left is not None and pending_right is not None and current_pair != submitted_fast_pair:
                        worker = self.fast_foundation_worker
                        if worker is not None:
                            color_for_depth = pending_color if self.host_depth_color_mode == "rgb_preview" else None
                            worker.submit(
                                pending_left,
                                pending_right,
                                color_for_depth,
                                pending_left_timestamp,
                                pending_right_timestamp,
                                pending_left_received_perf,
                                pending_right_received_perf,
                            )
                            submitted_fast_pair = current_pair
                    worker = self.fast_foundation_worker
                    result = worker.get_latest() if worker is not None else None
                    if result is not None:
                        seq, result_color, result_depth, result_left_timestamp, result_right_timestamp, result_left_received_perf, result_right_received_perf = result
                        if seq != published_fast_seq:
                            if self.host_depth_color_mode == "rgb_preview":
                                pending_color = result_color
                            else:
                                color_for_depth = pending_color if self.host_depth_color_mode in ("rgb_projected", "rgb_projected_stable") else None
                                pending_color = self._color_for_host_depth(
                                    pending_left if pending_left is not None else result_color,
                                    result_depth,
                                    color_for_depth,
                                )
                            pending_depth_m = result_depth
                            pending_left_timestamp = result_left_timestamp
                            pending_right_timestamp = result_right_timestamp
                            pending_left_received_perf = result_left_received_perf
                            pending_right_received_perf = result_right_received_perf
                            pending_stereo_serial = seq
                            published_fast_seq = seq
                elif pending_left is not None and pending_right is not None and current_pair != computed_host_pair:
                    color_for_depth = pending_color if self.host_depth_color_mode in ("rgb_preview", "rgb_projected", "rgb_projected_stable") else None
                    pending_color, pending_depth_m = self._compute_host_stereo_depth(pending_left, pending_right, color_for_depth)
                    pending_stereo_serial += 1
                    computed_host_pair = current_pair
            elif depth_msg is not None:
                pending_depth_m = depth_msg.getFrame().astype(np.float32) * 0.001
                pending_depth_timestamp = self._message_timestamp(depth_msg)
                pending_depth_received_perf = time.perf_counter()
                pending_depth_serial += 1
            latest_depth_serial = pending_stereo_serial if self.host_stereo_enabled else pending_depth_serial
            color_is_fresh = self.host_stereo_enabled or pending_color_serial != published_color_serial
            if (
                pending_color is not None
                and pending_depth_m is not None
                and latest_depth_serial != published_depth_serial
                and color_is_fresh
            ):
                with self._frame_lock:
                    self.latest_color_bgr = pending_color.copy()
                    self.latest_depth_m = pending_depth_m
                    self.latest_frame_serial += 1
                    self.latest_frame_time = time.perf_counter()
                    if self.host_stereo_enabled:
                        self.latest_sensor_age_ms = max(
                            self._timestamp_age_ms(pending_left_timestamp, pending_left_received_perf),
                            self._timestamp_age_ms(pending_right_timestamp, pending_right_received_perf),
                        )
                        self.latest_sensor_host_age_ms = max(
                            self._host_received_age_ms(pending_left_received_perf),
                            self._host_received_age_ms(pending_right_received_perf),
                        )
                    else:
                        self.latest_sensor_age_ms = self._timestamp_age_ms(pending_depth_timestamp, pending_depth_received_perf)
                        self.latest_sensor_host_age_ms = self._host_received_age_ms(pending_depth_received_perf)
                    self.latest_color_age_ms = self._timestamp_age_ms(pending_color_timestamp, pending_color_received_perf)
                    self.latest_color_host_age_ms = self._host_received_age_ms(pending_color_received_perf)
                    self._capture_count += 1
                    now = time.perf_counter()
                    if now - self._last_capture_fps_time >= 0.5:
                        self.capture_fps = self._capture_count / (now - self._last_capture_fps_time)
                        if self.fast_foundation_worker is not None:
                            self.capture_fps = float(self.fast_foundation_worker.fps)
                        self._capture_count = 0
                        self._last_capture_fps_time = now
                    published_depth_serial = latest_depth_serial
                    published_color_serial = pending_color_serial
                self._frame_event.set()
            elif not got_message:
                time.sleep(0.001)

    def set_depth_correction(self, scale=1.0, offset_m=0.0, quadratic=0.0):
        with self._frame_lock:
            self.depth_correction_quadratic = float(np.clip(float(quadratic), -0.15, 0.15))
            self.depth_correction_scale = float(np.clip(float(scale), 0.70, 1.30))
            self.depth_correction_offset_m = float(np.clip(float(offset_m), -0.30, 0.30))
        print(
            f">>> OAK-D depth correction active: "
            f"depth = depth^2 * {self.depth_correction_quadratic:.5f} "
            f"+ depth * {self.depth_correction_scale:.5f} + {self.depth_correction_offset_m:.4f}m <<<"
        )

    def _correct_depth(self, depth_m):
        if depth_m is None:
            return None
        raw = depth_m.astype(np.float32, copy=True)
        corrected = (
            raw * raw * float(self.depth_correction_quadratic)
            + raw * float(self.depth_correction_scale)
            + float(self.depth_correction_offset_m)
        )
        corrected[~np.isfinite(corrected)] = 0.0
        corrected[corrected < 0.0] = 0.0
        return corrected

    def read_latest(self, apply_depth_correction=True):
        with self._frame_lock:
            if self.latest_color_bgr is None or self.latest_depth_m is None:
                return None, None
            depth = self.latest_depth_m.copy()
            if apply_depth_correction:
                depth = self._correct_depth(depth)
            return self.latest_color_bgr.copy(), depth

    def read_latest_with_serial(self, apply_depth_correction=True):
        with self._frame_lock:
            if self.latest_color_bgr is None or self.latest_depth_m is None:
                return None, None, 0, 0.0, 0.0, 0.0, 0.0, 0.0
            depth = self.latest_depth_m.copy()
            if apply_depth_correction:
                if abs(self.depth_correction_quadratic) > 1e-9:
                    valid = np.isfinite(depth) & (depth > 0)
                    corrected = depth.copy()
                    corrected[valid] = (
                        self.depth_correction_quadratic * depth[valid] * depth[valid]
                        + self.depth_correction_scale * depth[valid]
                        + self.depth_correction_offset_m
                    )
                    corrected[~valid] = depth[~valid]
                    depth = corrected
                elif abs(self.depth_correction_scale - 1.0) > 1e-9 or abs(self.depth_correction_offset_m) > 1e-9:
                    depth = depth * self.depth_correction_scale + self.depth_correction_offset_m
            return (
                self.latest_color_bgr.copy(),
                depth,
                int(self.latest_frame_serial),
                float(self.latest_frame_time),
                float(self.latest_sensor_age_ms),
                float(self.latest_color_age_ms),
                float(self.latest_sensor_host_age_ms),
                float(self.latest_color_host_age_ms),
            )

    def release(self):
        self._stop_event.set()
        self._frame_event.set()
        if getattr(self, "_capture_thread", None) is not None:
            self._capture_thread.join(timeout=2.0)
        if self.fast_foundation_worker is not None:
            self.fast_foundation_worker.stop()
            self.fast_foundation_worker = None
        try:
            if hasattr(self.pipeline, "close"):
                self.pipeline.close()
            elif hasattr(self.pipeline, "stop"):
                self.pipeline.stop()
        except Exception:
            pass

def robust_depth_in_roi(depth_m, center_x, center_y, radius_px, min_depth=0.25, max_depth=7.0):
    image_h, image_w = depth_m.shape
    x0 = max(0, int(center_x) - int(radius_px))
    x1 = min(image_w, int(center_x) + int(radius_px) + 1)
    y0 = max(0, int(center_y) - int(radius_px))
    y1 = min(image_h, int(center_y) + int(radius_px) + 1)
    roi = depth_m[y0:y1, x0:x1]
    valid = roi[np.isfinite(roi) & (roi >= min_depth) & (roi <= max_depth)]
    if valid.size < 12:
        return None
    return float(np.median(valid))

def pixel_width_to_meters(width_px, depth_m, intrinsics):
    return float(width_px) * float(depth_m) / max(1e-6, float(intrinsics.fx))

def pixel_height_to_meters(height_px, depth_m, intrinsics):
    return float(height_px) * float(depth_m) / max(1e-6, float(intrinsics.fy))

def estimate_realsense_headlock_pixel(mask, depth_m, min_depth, max_depth, intrinsics, last_pixel=None):
    valid = (mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
    if int(valid.sum()) < 80:
        return None

    head_mask = valid.astype(np.uint8) * 255
    kernel = np.ones((3, 3), dtype=np.uint8)
    head_mask = cv2.morphologyEx(head_mask, cv2.MORPH_OPEN, kernel)
    component_count, labels, stats, centroids = cv2.connectedComponentsWithStats(head_mask, 8)
    best = None
    image_h, image_w = depth_m.shape

    for label_id in range(1, component_count):
        area = int(stats[label_id, cv2.CC_STAT_AREA])
        if area < 55 or area > 24000:
            continue
        x = int(stats[label_id, cv2.CC_STAT_LEFT])
        y = int(stats[label_id, cv2.CC_STAT_TOP])
        w = int(stats[label_id, cv2.CC_STAT_WIDTH])
        h = int(stats[label_id, cv2.CC_STAT_HEIGHT])
        if w < 12 or h < 12:
            continue

        component_valid = labels[y:y + h, x:x + w] == label_id
        candidate_depths = depth_m[y:y + h, x:x + w][component_valid]
        if candidate_depths.size < 55:
            continue
        candidate_depth = float(np.median(candidate_depths))
        depth_std = float(np.std(candidate_depths))
        width_m = pixel_width_to_meters(w, candidate_depth, intrinsics)
        height_m = pixel_height_to_meters(h, candidate_depth, intrinsics)
        aspect = width_m / max(0.001, height_m)
        density = float(area) / float(max(1, w * h))
        center_x = float(centroids[label_id][0])
        center_y = float(centroids[label_id][1])

        score = 0.0
        score += 5.0 if 0.11 <= width_m <= 0.36 else -5.0
        score += 5.0 if 0.11 <= height_m <= 0.46 else -5.0
        score += 2.0 if 0.42 <= aspect <= 1.85 else -2.5
        score += 1.5 if 0.18 <= density <= 0.92 else -2.5
        score += min(area / 800.0, 2.0)
        score -= max(0.0, depth_std - 0.055) * 8.0
        score -= max(0.0, candidate_depth - min_depth) * 0.15
        if center_x < 12 or center_x > image_w - 12 or center_y < 12 or center_y > image_h - 12:
            score -= 1.5

        if last_pixel is not None:
            distance = np.hypot(center_x - float(last_pixel[0]), center_y - float(last_pixel[1]))
            score += max(0.0, 7.0 - distance / 22.0)
            if distance > 190.0:
                score -= 8.0
        else:
            score += 1.0 if y < image_h * 0.72 else -2.5

        if best is None or score > best[0]:
            debug_mask = np.zeros(depth_m.shape, dtype=np.uint8)
            debug_mask[y:y + h, x:x + w][component_valid] = 255
            debug_rect = (x, y, w, h)
            best = (score, int(center_x), int(center_y), candidate_depth, debug_rect, debug_mask, debug_rect)

    if best is None or best[0] < 2.0:
        return None
    return best[1:]

class AsyncRealSenseHeadTracker:
    def __init__(
        self,
        intrinsics,
        model_path=None,
        yolo_imgsz=416,
        yolo_conf=0.35,
        smoothing=0.72,
        min_depth=0.25,
        max_depth=7.0,
        foreground_band=0.75,
    ):
        self.intrinsics = intrinsics
        self.model_path = model_path or os.environ.get(REALSENSE_HEAD_MODEL_ENV, REALSENSE_HEAD_MODEL_DEFAULT)
        self.yolo = None
        self.yolo_imgsz = int(os.environ.get("REALSENSE_YOLO_IMGSZ", yolo_imgsz))
        self.yolo_conf = float(yolo_conf)
        self.smoothing = float(np.clip(smoothing, 0.0, 0.98))
        self.min_depth = float(min_depth)
        self.max_depth = float(max_depth)
        self.foreground_band = float(foreground_band)
        self.lock = threading.Lock()
        self.new_frame_event = threading.Event()
        self.stop_event = threading.Event()
        self.pending_color = None
        self.pending_depth = None
        self.latest_point_m = None
        self.latest_pixel = None
        self.latest_raw_pixel = None
        self.latest_rect = None
        self.latest_debug_rect = None
        self.latest_mask = None
        self.latest_mode = "none"
        self.latest_label = ""
        self.latest_conf = 0.0
        self.inference_fps = 0.0
        self._smoothed_point = None
        self._smoothed_pixel = None
        self._frame_id = 0
        self._inference_count = 0
        self._last_fps_time = time.perf_counter()

        if YOLO is not None and self.model_path and os.path.exists(self.model_path):
            self.yolo = YOLO(self.model_path)
            print(f">>> RealSense YOLO head model active: {self.model_path} <<<")
            print(f">>> RealSense YOLO classes: {getattr(self.yolo, 'names', {})} <<<")
        elif YOLO is None:
            print(">>> ultralytics is not installed; RealSense uses depth-only head fallback. <<<")
        else:
            print(f">>> RealSense head model not found ({self.model_path}); using depth-only fallback. <<<")

        self.thread = threading.Thread(target=self._run, name="realsense-yolo-head", daemon=True)
        self.thread.start()

    def close(self):
        self.stop_event.set()
        self.new_frame_event.set()
        self.thread.join(timeout=2.0)

    def submit_frame(self, color, depth_m):
        if self.yolo is None:
            return
        with self.lock:
            self.pending_color = color.copy()
            self.pending_depth = depth_m.copy()
            self._frame_id += 1
        self.new_frame_event.set()

    def get_latest(self):
        with self.lock:
            if self.latest_point_m is None or self.latest_pixel is None:
                return None, None
            return self.latest_point_m.copy(), self.latest_pixel.copy()

    def get_debug(self):
        with self.lock:
            return {
                "pixel": None if self.latest_pixel is None else self.latest_pixel.copy(),
                "raw_pixel": None if self.latest_raw_pixel is None else self.latest_raw_pixel.copy(),
                "rect": self.latest_rect,
                "debug_rect": self.latest_debug_rect,
                "mask": None if self.latest_mask is None else self.latest_mask.copy(),
                "fps": float(self.inference_fps),
                "active": self.yolo is not None,
                "mode": self.latest_mode,
                "label": self.latest_label,
                "conf": float(self.latest_conf),
            }

    def _take_frame(self):
        with self.lock:
            color = self.pending_color
            depth_m = self.pending_depth
            self.pending_color = None
            self.pending_depth = None
        return color, depth_m

    def _run(self):
        while not self.stop_event.is_set():
            self.new_frame_event.wait(0.05)
            self.new_frame_event.clear()
            color, depth_m = self._take_frame()
            if color is None or depth_m is None:
                continue
            self._process_frame(color, depth_m)

    def _process_frame(self, color, depth_m):
        last_pixel = None
        with self.lock:
            if self._smoothed_pixel is not None:
                last_pixel = self._smoothed_pixel.copy()

        head_result = self._estimate_yolo(color, depth_m, last_pixel)
        mode = "yolo"
        label = ""
        conf = 0.0
        if head_result is None:
            head_result = self._estimate_headlock_fallback(depth_m, last_pixel)
            mode = "headlock"
        if head_result is None:
            with self.lock:
                self.latest_point_m = None
                self.latest_pixel = None
                self.latest_raw_pixel = None
                self.latest_rect = None
                self.latest_debug_rect = None
                self.latest_mask = None
                self.latest_mode = "none"
                self.latest_label = ""
                self.latest_conf = 0.0
                self._smoothed_point = None
                self._smoothed_pixel = None
            self._update_fps_counter()
            return

        px, py, depth, rect, mask, debug_rect = head_result[:6]
        if len(head_result) >= 8:
            label = str(head_result[6])
            conf = float(head_result[7])
        point = np.array(
            rs.rs2_deproject_pixel_to_point(self.intrinsics, [float(px), float(py)], float(depth)),
            dtype=np.float32,
        )
        with self.lock:
            if self._smoothed_point is None:
                self._smoothed_point = point
                self._smoothed_pixel = np.array([px, py], dtype=np.float32)
            else:
                self._smoothed_point = (self._smoothed_point * self.smoothing) + (point * (1.0 - self.smoothing))
                self._smoothed_pixel = (
                    self._smoothed_pixel * self.smoothing
                    + (np.array([px, py], dtype=np.float32) * (1.0 - self.smoothing))
                )
            self.latest_point_m = self._smoothed_point.copy()
            self.latest_pixel = self._smoothed_pixel.copy()
            self.latest_raw_pixel = np.array([px, py], dtype=np.float32)
            self.latest_rect = rect
            self.latest_debug_rect = debug_rect
            self.latest_mask = mask
            self.latest_mode = mode
            self.latest_label = label
            self.latest_conf = conf

        self._update_fps_counter()

    def _estimate_yolo(self, color, depth_m, last_pixel):
        if self.yolo is None:
            return None
        results = self.yolo.predict(color, imgsz=self.yolo_imgsz, conf=self.yolo_conf, verbose=False)
        if not results:
            return None
        names = getattr(results[0], "names", {}) or {}
        boxes = getattr(results[0], "boxes", None)
        if boxes is None or len(boxes) == 0:
            return None

        best = None
        for box in boxes:
            xyxy = box.xyxy[0].detach().cpu().numpy()
            x0, y0, x1, y1 = [int(round(v)) for v in xyxy]
            w = max(1, x1 - x0)
            h = max(1, y1 - y0)
            conf = float(box.conf[0].detach().cpu().numpy()) if box.conf is not None else 0.0
            cls = int(box.cls[0].detach().cpu().numpy()) if box.cls is not None else -1
            label = str(names.get(cls, "")).lower()
            if "person" in label:
                px = x0 + w * 0.5
                py = y0 + h * 0.16
                radius = max(10, int(min(w, h) * 0.055))
            elif "head" in label or label == "":
                px = x0 + w * 0.5
                py = y0 + h * 0.5
                radius = max(10, int(min(w, h) * 0.20))
            else:
                continue
            depth = robust_depth_in_roi(depth_m, px, py, radius, self.min_depth, self.max_depth)
            if depth is None:
                continue

            score = conf * 10.0
            if "head" in label:
                score += 6.0
            elif "person" in label:
                score += 2.0
            if last_pixel is not None:
                score += max(0.0, 5.0 - np.hypot(px - last_pixel[0], py - last_pixel[1]) / 45.0)
            if best is None or score > best[0]:
                rect = (x0, y0, w, h)
                mask = np.zeros(depth_m.shape, dtype=np.uint8)
                x0c = max(0, x0)
                y0c = max(0, y0)
                x1c = min(depth_m.shape[1], x0 + w)
                y1c = min(depth_m.shape[0], y0 + h)
                mask[y0c:y1c, x0c:x1c] = 255
                best = (score, int(px), int(py), depth, rect, mask, rect, label or "head", conf)

        if best is None:
            return None
        return best[1:]

    def _estimate_headlock_fallback(self, depth_m, last_pixel):
        valid_depth = depth_m[(depth_m > self.min_depth) & (depth_m < self.max_depth)]
        if valid_depth.size <= 100:
            return None
        near_depth = float(np.percentile(valid_depth, 8.0))
        foreground_max = min(self.max_depth, near_depth + self.foreground_band)
        mask = ((depth_m >= self.min_depth) & (depth_m <= foreground_max)).astype(np.uint8) * 255
        kernel = np.ones((5, 5), dtype=np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
        result = estimate_realsense_headlock_pixel(
            mask,
            depth_m,
            self.min_depth,
            self.max_depth,
            self.intrinsics,
            last_pixel,
        )
        if result is None:
            return None
        px, py, depth, rect, blob_mask, debug_rect = result
        return (px, py, depth, rect, blob_mask, debug_rect, "headlock", 0.0)

    def _update_fps_counter(self):
        now = time.perf_counter()
        with self.lock:
            self._inference_count += 1
            if now - self._last_fps_time >= 0.5:
                self.inference_fps = self._inference_count / (now - self._last_fps_time)
                self._inference_count = 0
                self._last_fps_time = now

class DemoRealSenseHeadTrackerAdapter:
    def __init__(self, intrinsics, head_model=""):
        if DemoRealSenseTrackerWorker is None:
            raise RuntimeError("Demo RealSense tracker worker is unavailable")
        args = type("Args", (), {})()
        args.mode = "ml"
        args.max_distance = float(os.environ.get("REALSENSE_MAX_DISTANCE", "7.0"))
        args.foreground_band = float(os.environ.get("REALSENSE_FOREGROUND_BAND", "0.75"))
        args.min_distance = float(os.environ.get("REALSENSE_MIN_DISTANCE", "0.25"))
        args.near_percentile = float(os.environ.get("REALSENSE_NEAR_PERCENTILE", "8.0"))
        args.smoothing = float(os.environ.get("REALSENSE_SMOOTHING", "0.72"))
        # Match the demo default: MediaPipe/pose first, then depth/headlock.
        args.head_model = head_model
        args.yolo_conf = float(os.environ.get("REALSENSE_YOLO_CONF", "0.35"))
        args.yolo_imgsz = int(os.environ.get("REALSENSE_YOLO_IMGSZ", "416"))
        args.pose_model = os.environ.get("REALSENSE_POSE_MODEL", REALSENSE_POSE_MODEL_DEFAULT)
        print(
            ">>> RealSense demo-style ML tracker active: "
            f"mode={args.mode} head_model={'none' if not args.head_model else args.head_model} "
            f"pose_model={args.pose_model} <<<"
        )
        self.worker = DemoRealSenseTrackerWorker(args, intrinsics)

    def close(self):
        self.worker.close()

    def submit_frame(self, color, depth_m):
        self.worker.submit_frame(color, depth_m)

    def get_latest(self):
        latest = self.worker.get_latest()
        if latest is None or not latest.get("has_head"):
            return None, None
        return latest["point"].copy(), latest["pixel"].copy()

    def get_debug(self):
        latest = self.worker.get_latest()
        if latest is None:
            return {
                "pixel": None,
                "raw_pixel": None,
                "rect": None,
                "debug_rect": None,
                "mask": None,
                "fps": 0.0,
                "active": True,
                "mode": "demo-ml",
                "label": "",
                "conf": 0.0,
            }
        return {
            "pixel": None if latest.get("pixel") is None else latest["pixel"].copy(),
            "raw_pixel": None if latest.get("raw_pixel") is None else latest["raw_pixel"].copy(),
            "rect": latest.get("rect"),
            "debug_rect": latest.get("debug_rect"),
            "mask": None if latest.get("blob_mask") is None else latest["blob_mask"].copy(),
            "fps": float(latest.get("inference_fps", 0.0)),
            "active": bool(latest.get("has_head")),
            "mode": str(latest.get("mode", "demo-ml")),
            "label": "demo",
            "conf": 0.0,
        }

class RealSenseCapture:
    def __init__(self, width=640, height=480, fps=30, tracking_mode=None, tracking_enabled=True, color_width=None, color_height=None, color_fps=None):
        if rs is None:
            raise RuntimeError("pyrealsense2 is not installed")
        self.depth_width = int(width)
        self.depth_height = int(height)
        self.width = int(color_width or width)
        self.height = int(color_height or height)
        self.fps = int(fps)
        self.color_fps = int(color_fps or fps)
        self.pipeline = rs.pipeline()
        self.config = rs.config()
        self.config.enable_stream(rs.stream.depth, self.depth_width, self.depth_height, rs.format.z16, self.fps)
        self.config.enable_stream(rs.stream.color, self.width, self.height, rs.format.bgr8, self.color_fps)
        self.profile = self.pipeline.start(self.config)
        self.device = self.profile.get_device()
        if REALSENSE_APPLY_DEFAULT_SETTINGS:
            self._apply_advanced_settings_json(REALSENSE_DEFAULT_SETTINGS_JSON)
        self.align_to_depth = rs.align(rs.stream.depth)
        self.depth_filters_enabled = bool(REALSENSE_DEPTH_FILTERS_ENABLED)
        self.disparity_filters_enabled = bool(REALSENSE_DEPTH_DISPARITY_FILTERS)
        self.depth_to_disparity_filter = None
        self.disparity_to_depth_filter = None
        self.spatial_filter = None
        self.temporal_filter = None
        self.hole_filling_filter = None
        self.depth_spatial_alpha = float(REALSENSE_DEPTH_SPATIAL_ALPHA)
        self.depth_spatial_delta = float(REALSENSE_DEPTH_SPATIAL_DELTA)
        self.depth_temporal_alpha = float(REALSENSE_DEPTH_TEMPORAL_ALPHA)
        self.depth_temporal_delta = float(REALSENSE_DEPTH_TEMPORAL_DELTA)
        self.depth_hole_filling = int(REALSENSE_DEPTH_HOLE_FILLING)
        self.filters_for_point_cloud_geometry = bool(REALSENSE_FILTERS_FOR_POINT_CLOUD_GEOMETRY)
        self.filter_geometry_edge_guard_m = float(REALSENSE_FILTER_GEOMETRY_EDGE_GUARD_M)
        self._configure_depth_filters()
        self.depth_sensor = self.device.first_depth_sensor()
        self.color_sensor = None
        for sensor in self.device.query_sensors():
            try:
                if sensor.supports(rs.option.enable_auto_exposure) and sensor.supports(rs.option.white_balance):
                    self.color_sensor = sensor
                    break
            except Exception:
                continue
        self._apply_initial_sensor_options()
        self.depth_scale = float(self.depth_sensor.get_depth_scale())
        color_profile = self.profile.get_stream(rs.stream.color).as_video_stream_profile()
        depth_profile = self.profile.get_stream(rs.stream.depth).as_video_stream_profile()
        self.charuco_intrinsics = color_profile.get_intrinsics()
        self.point_cloud_intrinsics = depth_profile.get_intrinsics()
        self.intrinsics = self.point_cloud_intrinsics
        self.latest_depth_m = None
        self.latest_tracking_depth_m = None
        self.latest_color_bgr = None
        self.latest_head_point_m = None
        self.latest_head_pixel = None
        self.latest_head_raw_pixel = None
        self.latest_head_rect = None
        self.latest_head_debug_rect = None
        self.latest_head_mask = None
        self.capture_fps = 0.0
        self._capture_count = 0
        self._last_capture_fps_time = time.perf_counter()
        self._latest_frame_id = 0
        self._last_read_frame_id = -1
        self._latest_color_bgr = None
        self._latest_charuco_color_bgr = None
        self._latest_depth_m = None
        self._latest_tracking_depth_m = None
        self._latest_head_point_m = None
        self._latest_head_pixel = None
        self._latest_head_raw_pixel = None
        self._latest_head_rect = None
        self._latest_head_debug_rect = None
        self._latest_head_mask = None
        self._frame_lock = threading.Lock()
        self._tracker_lock = threading.Lock()
        self._stop_event = threading.Event()
        self._frame_event = threading.Event()
        requested_mode = (tracking_mode or os.environ.get(REALSENSE_TRACKING_MODE_ENV, "ml")).lower()
        self.tracking_mode = requested_mode if requested_mode in REALSENSE_TRACKING_MODES else "ml"
        self.tracking_enabled = bool(tracking_enabled)
        self.head_tracker = None
        self._create_head_tracker()
        self._capture_thread = threading.Thread(target=self._capture_loop, name="realsense-capture", daemon=True)
        self._capture_thread.start()

    def _set_sensor_option(self, sensor, option, value, label):
        if sensor is None or value is None:
            return False
        try:
            numeric_value = float(value)
        except Exception:
            return False
        if numeric_value < 0:
            return False
        try:
            if not sensor.supports(option):
                return False
            option_range = sensor.get_option_range(option)
            numeric_value = float(np.clip(numeric_value, option_range.min, option_range.max))
            sensor.set_option(option, numeric_value)
            print(f">>> RealSense option {label}={numeric_value:g} <<<")
            return True
        except Exception as exc:
            print(f">>> RealSense option {label} failed: {exc} <<<")
            return False

    def _apply_advanced_settings_json(self, path):
        if not path:
            return False
        resolved_path = os.path.abspath(path)
        if not os.path.exists(resolved_path):
            print(f">>> RealSense default settings JSON not found: {resolved_path} <<<")
            return False
        try:
            if not hasattr(rs, "rs400_advanced_mode"):
                print(">>> RealSense advanced mode API unavailable in pyrealsense2; skipped default_settings.json <<<")
                return False
            advanced_mode = rs.rs400_advanced_mode(self.device)
            if not advanced_mode.is_enabled():
                advanced_mode.toggle_advanced_mode(True)
                time.sleep(0.5)
            with open(resolved_path, "r", encoding="utf-8") as handle:
                settings_json = handle.read()
            advanced_mode.load_json(settings_json)
            print(f">>> Applied RealSense advanced default settings: {resolved_path} <<<")
            return True
        except Exception as exc:
            print(f">>> Failed to apply RealSense advanced default settings {resolved_path}: {exc} <<<")
            return False

    def _configure_depth_filters(self):
        if not self.depth_filters_enabled:
            self.depth_to_disparity_filter = None
            self.disparity_to_depth_filter = None
            self.spatial_filter = None
            self.temporal_filter = None
            self.hole_filling_filter = None
            print(">>> RealSense depth filters disabled <<<")
            return
        self.depth_to_disparity_filter = rs.disparity_transform(True) if self.disparity_filters_enabled else None
        self.disparity_to_depth_filter = rs.disparity_transform(False) if self.disparity_filters_enabled else None
        self.spatial_filter = rs.spatial_filter()
        self.spatial_filter.set_option(rs.option.filter_smooth_alpha, float(np.clip(self.depth_spatial_alpha, 0.25, 1.0)))
        self.spatial_filter.set_option(rs.option.filter_smooth_delta, float(np.clip(self.depth_spatial_delta, 1.0, 50.0)))
        self.temporal_filter = rs.temporal_filter()
        self.temporal_filter.set_option(rs.option.filter_smooth_alpha, float(np.clip(self.depth_temporal_alpha, 0.05, 1.0)))
        self.temporal_filter.set_option(rs.option.filter_smooth_delta, float(np.clip(self.depth_temporal_delta, 1.0, 100.0)))
        self.hole_filling_filter = rs.hole_filling_filter()
        if hasattr(rs.option, "holes_fill"):
            self.hole_filling_filter.set_option(rs.option.holes_fill, float(np.clip(self.depth_hole_filling, 0, 2)))
        print(
            ">>> RealSense depth filters: "
            f"disparity={'on' if self.disparity_filters_enabled else 'off'}, "
            f"spatial alpha={self.depth_spatial_alpha:.2f} delta={self.depth_spatial_delta:.1f}, "
            f"temporal alpha={self.depth_temporal_alpha:.2f} delta={self.depth_temporal_delta:.1f}, "
            f"hole_fill={self.depth_hole_filling if self.depth_hole_filling >= 0 else 'off'} <<<"
        )

    def _apply_initial_sensor_options(self):
        self._set_sensor_option(self.depth_sensor, rs.option.visual_preset, REALSENSE_VISUAL_PRESET, "visual_preset")
        self._set_sensor_option(self.depth_sensor, rs.option.emitter_enabled, REALSENSE_EMITTER_ENABLED, "emitter_enabled")
        self._set_sensor_option(self.depth_sensor, rs.option.laser_power, REALSENSE_LASER_POWER, "laser_power")
        self._set_sensor_option(self.color_sensor, rs.option.enable_auto_exposure, REALSENSE_COLOR_AUTO_EXPOSURE, "color_auto_exposure")
        self._set_sensor_option(self.color_sensor, rs.option.exposure, REALSENSE_COLOR_EXPOSURE, "color_exposure")
        self._set_sensor_option(self.color_sensor, rs.option.gain, REALSENSE_COLOR_GAIN, "color_gain")
        self._set_sensor_option(self.color_sensor, rs.option.enable_auto_white_balance, REALSENSE_COLOR_AUTO_WHITE_BALANCE, "color_auto_white_balance")
        self._set_sensor_option(self.color_sensor, rs.option.white_balance, REALSENSE_COLOR_WHITE_BALANCE, "color_white_balance")

    def apply_runtime_settings(self, settings):
        changed_filters = False
        if "depth_filters_enabled" in settings:
            next_value = bool(settings["depth_filters_enabled"])
            changed_filters = changed_filters or next_value != self.depth_filters_enabled
            self.depth_filters_enabled = next_value
        if "disparity_filters_enabled" in settings:
            next_value = bool(settings["disparity_filters_enabled"])
            changed_filters = changed_filters or next_value != self.disparity_filters_enabled
            self.disparity_filters_enabled = next_value
        for key, attr, caster in (
            ("spatial_alpha", "depth_spatial_alpha", float),
            ("spatial_delta", "depth_spatial_delta", float),
            ("temporal_alpha", "depth_temporal_alpha", float),
            ("temporal_delta", "depth_temporal_delta", float),
            ("hole_filling", "depth_hole_filling", int),
        ):
            if key in settings:
                next_value = caster(settings[key])
                changed_filters = changed_filters or next_value != getattr(self, attr)
                setattr(self, attr, next_value)
        if changed_filters:
            self._configure_depth_filters()
        if "filters_for_point_cloud_geometry" in settings:
            self.filters_for_point_cloud_geometry = bool(settings["filters_for_point_cloud_geometry"])
            print(f">>> RealSense point cloud geometry depth: {'filtered' if self.filters_for_point_cloud_geometry else 'raw aligned'} <<<")
        if "filter_geometry_edge_guard_m" in settings:
            self.filter_geometry_edge_guard_m = max(0.0, float(settings["filter_geometry_edge_guard_m"]))
            print(f">>> RealSense filtered geometry edge guard: {self.filter_geometry_edge_guard_m:.3f}m <<<")

        self._set_sensor_option(self.depth_sensor, rs.option.visual_preset, settings.get("visual_preset", -1), "visual_preset")
        self._set_sensor_option(self.depth_sensor, rs.option.emitter_enabled, settings.get("emitter_enabled", -1), "emitter_enabled")
        self._set_sensor_option(self.depth_sensor, rs.option.laser_power, settings.get("laser_power", -1), "laser_power")
        self._set_sensor_option(self.color_sensor, rs.option.enable_auto_exposure, settings.get("color_auto_exposure", -1), "color_auto_exposure")
        self._set_sensor_option(self.color_sensor, rs.option.exposure, settings.get("color_exposure", -1), "color_exposure")
        self._set_sensor_option(self.color_sensor, rs.option.gain, settings.get("color_gain", -1), "color_gain")
        self._set_sensor_option(self.color_sensor, rs.option.enable_auto_white_balance, settings.get("color_auto_white_balance", -1), "color_auto_white_balance")
        self._set_sensor_option(self.color_sensor, rs.option.white_balance, settings.get("color_white_balance", -1), "color_white_balance")

    def _create_head_tracker(self):
        with self._tracker_lock:
            if self.head_tracker is not None:
                self.head_tracker.close()
                self.head_tracker = None
            self.latest_head_point_m = None
            self.latest_head_pixel = None
            self.latest_head_raw_pixel = None
            self.latest_head_rect = None
            self.latest_head_debug_rect = None
            self.latest_head_mask = None
            with self._frame_lock:
                self._latest_head_point_m = None
                self._latest_head_pixel = None
                self._latest_head_raw_pixel = None
                self._latest_head_rect = None
                self._latest_head_debug_rect = None
                self._latest_head_mask = None

            if not self.tracking_enabled:
                print(">>> RealSense head tracking disabled; depth/color capture remains active. <<<")
                return

            if self.tracking_mode == "yolo":
                self.head_tracker = AsyncRealSenseHeadTracker(self.intrinsics)
                print(">>> RealSense tracking mode: YOLO head model <<<")
                return

            if DemoRealSenseTrackerWorker is not None:
                self.head_tracker = DemoRealSenseHeadTrackerAdapter(self.intrinsics, head_model="")
                print(">>> RealSense tracking mode: ML demo worker <<<")
            else:
                self.head_tracker = AsyncRealSenseHeadTracker(self.intrinsics)
                self.tracking_mode = "yolo"
                print(">>> RealSense ML worker unavailable; falling back to YOLO mode. <<<")

    def set_tracking_enabled(self, enabled):
        enabled = bool(enabled)
        if self.tracking_enabled == enabled:
            return self.tracking_enabled
        self.tracking_enabled = enabled
        self._create_head_tracker()
        print(f">>> RealSense head tracking {'enabled' if self.tracking_enabled else 'disabled'} <<<")
        return self.tracking_enabled

    def toggle_tracking_enabled(self):
        return self.set_tracking_enabled(not self.tracking_enabled)

    def cycle_tracking_mode(self):
        if not self.tracking_enabled:
            print(">>> RealSense tracking mode toggle ignored: head tracking is disabled. Press 'n' to enable it. <<<")
            return self.tracking_mode
        mode_index = REALSENSE_TRACKING_MODES.index(self.tracking_mode) if self.tracking_mode in REALSENSE_TRACKING_MODES else 0
        self.tracking_mode = REALSENSE_TRACKING_MODES[(mode_index + 1) % len(REALSENSE_TRACKING_MODES)]
        self._create_head_tracker()
        print(f">>> RealSense tracking mode switched to: {self.tracking_mode.upper()} <<<")
        return self.tracking_mode

    def release(self):
        self._stop_event.set()
        self._frame_event.set()
        if getattr(self, "_capture_thread", None) is not None:
            self._capture_thread.join(timeout=2.0)
        with self._tracker_lock:
            if self.head_tracker is not None:
                self.head_tracker.close()
                self.head_tracker = None
        self.pipeline.stop()

    def get_camera_matrix(self):
        return np.array(
            [
                [float(self.intrinsics.fx), 0.0, float(self.intrinsics.ppx)],
                [0.0, float(self.intrinsics.fy), float(self.intrinsics.ppy)],
                [0.0, 0.0, 1.0],
            ],
            dtype=np.float32,
        )

    def get_dist_coeffs(self):
        coeffs = np.array(getattr(self.intrinsics, "coeffs", [0.0, 0.0, 0.0, 0.0, 0.0]), dtype=np.float32).reshape(-1, 1)
        if coeffs.size < 5:
            padded = np.zeros((5, 1), dtype=np.float32)
            padded[: coeffs.size, 0] = coeffs.flatten()
            return padded
        return coeffs[:5].astype(np.float32)

    def get_head_debug(self):
        with self._tracker_lock:
            if self.head_tracker is None:
                return {"active": False, "fps": 0.0, "mode": "none", "label": "", "conf": 0.0}
            return self.head_tracker.get_debug()

    def _deproject_depth_pixel(self, pixel, radius_px=8):
        depth_m = self.latest_tracking_depth_m if self.latest_tracking_depth_m is not None else self.latest_depth_m
        if depth_m is None:
            return None
        depth = robust_depth_in_roi(
            depth_m,
            float(pixel[0]),
            float(pixel[1]),
            radius_px,
            min_depth=0.20,
            max_depth=7.0,
        )
        if depth is None:
            return None
        point = rs.rs2_deproject_pixel_to_point(self.intrinsics, [float(pixel[0]), float(pixel[1])], float(depth))
        return np.array(point, dtype=np.float32)

    def _deproject_marker_corners(self, marker_corners):
        points = []
        for corner in marker_corners:
            point = self._deproject_depth_pixel(corner)
            if point is None:
                return None
            points.append(point)
        return np.array(points, dtype=np.float32)

    def measure_screen_size_from_markers(self, tl_marker, tr_marker, bl_marker, br_marker):
        marker_sets = [
            self._deproject_marker_corners(tl_marker),
            self._deproject_marker_corners(tr_marker),
            self._deproject_marker_corners(bl_marker),
            self._deproject_marker_corners(br_marker),
        ]
        if any(marker_points is None for marker_points in marker_sets):
            return None

        side_lengths = []
        for marker_points in marker_sets:
            side_lengths.extend(
                [
                    float(np.linalg.norm(marker_points[1] - marker_points[0])),
                    float(np.linalg.norm(marker_points[2] - marker_points[1])),
                    float(np.linalg.norm(marker_points[3] - marker_points[2])),
                    float(np.linalg.norm(marker_points[0] - marker_points[3])),
                ]
            )
        marker_size_m = float(np.median(side_lengths))
        if not np.isfinite(marker_size_m) or marker_size_m <= 0.01:
            return None

        # Godot lays out calibration markers as squares sized to 40% of the
        # shorter screen dimension, padded inward by 15% of that marker size.
        pad_m = marker_size_m * 0.15
        tl_points, tr_points, bl_points, br_points = marker_sets
        width_m = (
            float(np.linalg.norm(tr_points[1] - tl_points[0]))
            + float(np.linalg.norm(br_points[2] - bl_points[3]))
        ) * 0.5 + (2.0 * pad_m)
        height_m = (
            float(np.linalg.norm(bl_points[3] - tl_points[0]))
            + float(np.linalg.norm(br_points[2] - tr_points[1]))
        ) * 0.5 + (2.0 * pad_m)

        width_inches = width_m / 0.0254
        height_inches = height_m / 0.0254
        if not (4.0 <= width_inches <= 120.0 and 3.0 <= height_inches <= 80.0):
            return None
        return float(width_inches), float(height_inches)

    def _guard_filtered_geometry_depth(self, raw_depth_m, filtered_depth_m):
        guard_m = float(self.filter_geometry_edge_guard_m)
        if guard_m <= 0.0:
            return filtered_depth_m

        raw_valid = np.isfinite(raw_depth_m) & (raw_depth_m > 0.0)
        filtered_valid = np.isfinite(filtered_depth_m) & (filtered_depth_m > 0.0)
        guarded = filtered_depth_m.copy()

        # Keep filtered smoothness on broad surfaces, but don't let the filter
        # move a real raw depth sample far enough to smear foreground edges.
        disagreement = raw_valid & filtered_valid & (np.abs(filtered_depth_m - raw_depth_m) > guard_m)
        guarded[disagreement] = raw_depth_m[disagreement]

        # If a filter invents depth in a raw hole on a strong raw discontinuity,
        # drop it instead of letting the mesh create a halo or skinny bridge.
        raw_min_src = np.where(raw_valid, raw_depth_m, 9999.0).astype(np.float32)
        raw_max_src = np.where(raw_valid, raw_depth_m, 0.0).astype(np.float32)
        kernel = np.ones((3, 3), dtype=np.uint8)
        local_min = cv2.erode(raw_min_src, kernel)
        local_max = cv2.dilate(raw_max_src, kernel)
        raw_edge = (local_max > 0.0) & (local_min < 9998.0) & ((local_max - local_min) > guard_m)
        guarded[(~raw_valid) & filtered_valid & raw_edge] = 0.0
        return guarded

    def _capture_loop(self):
        while not self._stop_event.is_set():
            try:
                frames = self.pipeline.wait_for_frames()
                color_frame_for_charuco = frames.get_color_frame()
                frames = self.align_to_depth.process(frames)
            except Exception as exc:
                if not self._stop_event.is_set():
                    print(f">>> RealSense capture thread stopped: {exc} <<<")
                break

            depth_frame = frames.get_depth_frame()
            color_frame = frames.get_color_frame()
            if not depth_frame or not color_frame or not color_frame_for_charuco:
                continue
            raw_depth_m = np.asanyarray(depth_frame.get_data()).astype(np.float32) * self.depth_scale
            filtered_depth_frame = depth_frame
            if self.depth_filters_enabled:
                try:
                    if self.depth_to_disparity_filter is not None:
                        filtered_depth_frame = self.depth_to_disparity_filter.process(filtered_depth_frame)
                    if self.spatial_filter is not None:
                        filtered_depth_frame = self.spatial_filter.process(filtered_depth_frame)
                    if self.temporal_filter is not None:
                        filtered_depth_frame = self.temporal_filter.process(filtered_depth_frame)
                    if self.disparity_to_depth_filter is not None:
                        filtered_depth_frame = self.disparity_to_depth_filter.process(filtered_depth_frame)
                    if self.hole_filling_filter is not None:
                        filtered_depth_frame = self.hole_filling_filter.process(filtered_depth_frame)
                except Exception as exc:
                    print(f">>> RealSense depth filter failed; using raw depth this frame: {exc} <<<")
                    filtered_depth_frame = depth_frame

            color = np.asanyarray(color_frame.get_data()).copy()
            charuco_color = np.asanyarray(color_frame_for_charuco.get_data()).copy()
            filtered_depth_m = np.asanyarray(filtered_depth_frame.get_data()).astype(np.float32) * self.depth_scale
            if self.filters_for_point_cloud_geometry:
                point_cloud_depth_m = self._guard_filtered_geometry_depth(raw_depth_m, filtered_depth_m)
            else:
                point_cloud_depth_m = raw_depth_m
            head_point = None
            head_pixel = None
            head_raw_pixel = None
            head_rect = None
            head_debug_rect = None
            head_mask = None

            if self.tracking_enabled:
                with self._tracker_lock:
                    tracker = self.head_tracker
                    if tracker is not None:
                        tracker.submit_frame(color, filtered_depth_m)
                        head_point, head_pixel = tracker.get_latest()
                        debug = tracker.get_debug()
                        head_raw_pixel = debug.get("raw_pixel")
                        head_rect = debug.get("rect")
                        head_debug_rect = debug.get("debug_rect")
                        head_mask = debug.get("mask")

            now = time.perf_counter()
            self._capture_count += 1
            if now - self._last_capture_fps_time >= 0.5:
                self.capture_fps = self._capture_count / (now - self._last_capture_fps_time)
                self._capture_count = 0
                self._last_capture_fps_time = now

            with self._frame_lock:
                self._latest_color_bgr = color
                self._latest_charuco_color_bgr = charuco_color
                self._latest_depth_m = point_cloud_depth_m
                self._latest_tracking_depth_m = filtered_depth_m
                self._latest_head_point_m = None if head_point is None else head_point.copy()
                self._latest_head_pixel = None if head_pixel is None else head_pixel.copy()
                self._latest_head_raw_pixel = None if head_raw_pixel is None else head_raw_pixel.copy()
                self._latest_head_rect = head_rect
                self._latest_head_debug_rect = head_debug_rect
                self._latest_head_mask = None if head_mask is None else head_mask.copy()
                self._latest_frame_id += 1
            self._frame_event.set()

    def read(self):
        if self._latest_color_bgr is None and self._latest_charuco_color_bgr is None:
            self._frame_event.wait(0.5)
        with self._frame_lock:
            if self._latest_color_bgr is None and self._latest_charuco_color_bgr is None:
                return False, None
            aligned_color = None if self._latest_color_bgr is None else self._latest_color_bgr.copy()
            preview_color = self._latest_charuco_color_bgr.copy() if self._latest_charuco_color_bgr is not None else aligned_color.copy()
            self.latest_color_bgr = aligned_color
            self.latest_depth_m = None if self._latest_depth_m is None else self._latest_depth_m.copy()
            self.latest_tracking_depth_m = None if self._latest_tracking_depth_m is None else self._latest_tracking_depth_m.copy()
            self.latest_head_point_m = None if self._latest_head_point_m is None else self._latest_head_point_m.copy()
            self.latest_head_pixel = None if self._latest_head_pixel is None else self._latest_head_pixel.copy()
            self.latest_head_raw_pixel = None if self._latest_head_raw_pixel is None else self._latest_head_raw_pixel.copy()
            self.latest_head_rect = self._latest_head_rect
            self.latest_head_debug_rect = self._latest_head_debug_rect
            self.latest_head_mask = None if self._latest_head_mask is None else self._latest_head_mask.copy()
            self._last_read_frame_id = self._latest_frame_id

        if self.tracking_enabled and self.latest_head_point_m is None:
            self.latest_head_point_m, self.latest_head_pixel = self.estimate_head()
            self.latest_head_raw_pixel = self.latest_head_pixel
            self.latest_head_rect = None
            self.latest_head_debug_rect = None
            self.latest_head_mask = None
        if not self.tracking_enabled:
            self.latest_head_point_m = None
            self.latest_head_pixel = None
            self.latest_head_raw_pixel = None
            self.latest_head_rect = None
            self.latest_head_debug_rect = None
            self.latest_head_mask = None
        return True, preview_color

    def read_latest_color_for_alignment(self, last_frame_id=-1, timeout=0.35):
        deadline = time.perf_counter() + max(0.0, float(timeout))
        while time.perf_counter() < deadline:
            with self._frame_lock:
                if self._latest_charuco_color_bgr is not None and self._latest_frame_id != last_frame_id:
                    return self._latest_charuco_color_bgr.copy(), int(self._latest_frame_id)
            self._frame_event.wait(0.01)
            self._frame_event.clear()
        with self._frame_lock:
            if self._latest_charuco_color_bgr is None:
                return None, last_frame_id
            return self._latest_charuco_color_bgr.copy(), int(self._latest_frame_id)

    def estimate_head(self, min_distance=0.25, max_distance=7.0, foreground_band=0.75, near_percentile=8.0):
        depth_m = self.latest_tracking_depth_m if self.latest_tracking_depth_m is not None else self.latest_depth_m
        if depth_m is None:
            return None, None
        valid_depth = depth_m[(depth_m > min_distance) & (depth_m < max_distance)]
        if valid_depth.size <= 100:
            return None, None
        near_depth = float(np.percentile(valid_depth, near_percentile))
        foreground_max = min(max_distance, near_depth + foreground_band)
        mask = ((depth_m >= min_distance) & (depth_m <= foreground_max)).astype(np.uint8) * 255
        kernel = np.ones((5, 5), dtype=np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return None, None

        best = None
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < 700:
                continue
            x, y, w, h = cv2.boundingRect(contour)
            if w < 25 or h < 45:
                continue
            score = area
            if self.latest_head_pixel is not None:
                cx = x + w * 0.5
                cy = y + h * 0.5
                score -= np.hypot(cx - self.latest_head_pixel[0], cy - self.latest_head_pixel[1]) * 6.0
            if best is None or score > best[0]:
                best = (score, contour)
        if best is None:
            return None, None

        contour = best[1]
        x, y, w, h = cv2.boundingRect(contour)
        blob_mask = np.zeros(depth_m.shape, dtype=np.uint8)
        cv2.drawContours(blob_mask, [contour], -1, 255, thickness=cv2.FILLED)
        y0 = min(depth_m.shape[0] - 1, y + max(8, int(h * 0.04)))
        y1 = min(depth_m.shape[0], y + max(35, int(h * 0.28)))
        top_mask = np.zeros_like(blob_mask)
        top_mask[y0:y1, x:x + w] = blob_mask[y0:y1, x:x + w]
        valid = (top_mask > 0) & np.isfinite(depth_m) & (depth_m >= min_distance) & (depth_m <= max_distance)
        ys, xs = np.nonzero(valid)
        if len(xs) < 40:
            return None, None
        depth = float(np.median(depth_m[ys, xs]))
        px = int(np.median(xs))
        py = int(np.median(ys))
        point = rs.rs2_deproject_pixel_to_point(self.intrinsics, [float(px), float(py)], depth)
        # Keep RealSense/OpenCV camera coordinates here: X right, Y down, Z forward.
        # T_origin_to_cam is solved from OpenCV PnP and maps this same camera frame
        # into the calibrated room.
        return np.array([float(point[0]), float(point[1]), float(point[2])], dtype=np.float32), np.array([px, py], dtype=np.float32)

    def draw_head_debug(self, frame):
        if not self.tracking_enabled:
            return
        if self.latest_head_pixel is None:
            return
        px, py = int(self.latest_head_pixel[0]), int(self.latest_head_pixel[1])
        if getattr(self, "latest_head_mask", None) is not None:
            overlay = np.full_like(frame, (0, 90, 120))
            mask = self.latest_head_mask > 0
            frame[mask] = cv2.addWeighted(frame, 0.45, overlay, 0.55, 0)[mask]
        if self.latest_head_rect is not None:
            x, y, w, h = self.latest_head_rect
            cv2.rectangle(frame, (int(x), int(y)), (int(x + w), int(y + h)), (0, 200, 255), 2)
        if getattr(self, "latest_head_debug_rect", None) is not None:
            x, y, w, h = self.latest_head_debug_rect
            cv2.rectangle(frame, (int(x), int(y)), (int(x + w), int(y + h)), (255, 80, 0), 2)
        if self.latest_head_raw_pixel is not None:
            raw_x, raw_y = int(self.latest_head_raw_pixel[0]), int(self.latest_head_raw_pixel[1])
            cv2.circle(frame, (raw_x, raw_y), 5, (0, 255, 255), -1)
        cv2.circle(frame, (px, py), 9, (0, 0, 255), -1)
        debug = self.get_head_debug()
        mode = debug.get("mode", "none")
        label_name = debug.get("label", "")
        label = f"RealSense {mode}"
        if label_name and label_name != mode:
            label += f" {label_name}"
        if debug.get("conf", 0.0) > 0.0:
            label += f" {debug.get('conf', 0.0):.2f}"
        label += f" {debug.get('fps', 0.0):.1f}fps"
        cv2.putText(frame, label, (px + 12, py + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 255), 2, cv2.LINE_AA)

def pick_camera_index_in_terminal(candidates, active_camera_index):
    if not sys.stdin.isatty() or os.name != "nt":
        print(">>> Interactive camera picker requires a Windows terminal with stdin attached. <<<")
        return None
    if not candidates:
        print(">>> No camera candidates were detected. <<<")
        return None

    selected = 0
    for idx, candidate in enumerate(candidates):
        if candidate["index"] == active_camera_index:
            selected = idx
            break

    def render():
        os.system("cls")
        print("=== Camera Picker ===")
        print("Use terminal Up/Down to choose, Enter to confirm, Esc to cancel.\n")
        for idx, candidate in enumerate(candidates):
            prefix = ">" if idx == selected else " "
            current = " (current)" if candidate["index"] == active_camera_index else ""
            print(
                f"{prefix} Camera {candidate['index']}: "
                f"{candidate['width']}x{candidate['height']}{current}"
            )

    render()
    while True:
        key = msvcrt.getwch()
        if key in ("\x00", "\xe0"):
            special = msvcrt.getwch()
            if special == "H":  # up
                selected = (selected - 1) % len(candidates)
                render()
                continue
            if special == "P":  # down
                selected = (selected + 1) % len(candidates)
                render()
                continue
            if special in ("K", "M"):  # left/right
                render()
                continue
        if key == "\r":
            chosen = candidates[selected]["index"]
            print(f"\n>>> Selected camera {chosen}. <<<")
            return chosen
        if key == "\x1b":
            print("\n>>> Camera picker canceled. <<<")
            return None

def select_best_camera_index(backends):
    best_index = None
    best_score = -1
    best_mode = None

    for index in range(CAMERA_INDEX_AUTO_MAX):
        cap = open_capture_for_index(index, backends)
        if cap is None:
            continue

        if hasattr(cv2, "CAP_PROP_FOURCC"):
            cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        if hasattr(cv2, "CAP_PROP_FPS"):
            cap.set(cv2.CAP_PROP_FPS, PREFERRED_CAMERA_FPS)

        current_mode = get_capture_dimensions(cap)
        current_score = camera_mode_score(*current_mode)
        for width, height in PREFERRED_CAMERA_MODES:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            actual_mode = get_capture_dimensions(cap)
            actual_score = camera_mode_score(*actual_mode)
            if actual_score > current_score:
                current_score = actual_score
                current_mode = actual_mode

        if current_score > best_score:
            best_score = current_score
            best_index = index
            best_mode = current_mode

        cap.release()

    return best_index, best_mode

def infer_calibration_size(camera_matrix):
    if camera_matrix is None:
        return None
    cx = float(camera_matrix[0, 2])
    cy = float(camera_matrix[1, 2])
    inferred_width = int(round(cx * 2.0))
    inferred_height = int(round(cy * 2.0))
    if inferred_width <= 0 or inferred_height <= 0:
        return None
    return inferred_width, inferred_height

def main():
    print("Starting ArUco Constellation Tracker...")
    print("Fusion ChArUco detector: ArUco scales=1,1.5,2,3,4 plus checkerboard fallback=7x5.")
    print("Press 'v' in the camera window to release/reacquire the webcam without stopping the tracker.")
    print("Press 'y' in the camera window to choose a webcam from the terminal picker.")
    print("Press 's' in the camera window to toggle webcam vs RealSense RGB+depth source.")
    print("Press 'r' in the camera window to reset the solved room/screen map.")
    print("Press 'q' in the camera window to quit.\n")
    os.environ.pop(CAMERA_INDEX_ENV, None)

    # Load the 4x4_50 dictionary we used in Godot
    aruco_dict = aruco.getPredefinedDictionary(aruco.DICT_4X4_50)
    parameters = make_detector_params() # Use the robust parameters!
    detector = aruco.ArucoDetector(aruco_dict, parameters)
    
    # --- CHARUCO CALIBRATION SETUP ---
    charuco_dict = aruco.getPredefinedDictionary(aruco.DICT_6X6_250)
    charuco_board = aruco.CharucoBoard(
        (CHARUCO_SQUARES_X, CHARUCO_SQUARES_Y),
        CHARUCO_SQUARE_M,
        CHARUCO_MARKER_M,
        charuco_dict,
    )
    charuco_detector = aruco.ArucoDetector(charuco_dict, parameters)
    
    camera_matrix = None
    dist_coeffs = None
    stored_camera_matrix = None
    stored_dist_coeffs = None
    stored_calibration_size = None
    if os.path.exists("camera_calibration.json"):
        try:
            with open("camera_calibration.json", "r") as f:
                calib = json.load(f)
                stored_camera_matrix = np.array(calib["camera_matrix"], dtype=np.float32)
                stored_dist_coeffs = np.array(calib["dist_coeffs"], dtype=np.float32)
                if "image_width" in calib and "image_height" in calib:
                    stored_calibration_size = (int(calib["image_width"]), int(calib["image_height"]))
            print(">>> Successfully loaded camera_calibration.json! Intrinsics are available pending capture-mode validation. <<<")
        except Exception as e:
            print("Failed to load calibration:", e)
    elif not CAMERA_AUTO_CALIBRATE_INTRINSICS:
        print(">>> camera_calibration.json not found; using approximate webcam intrinsics. Set CAMERA_AUTO_CALIBRATE_INTRINSICS=1 to run ChArUco calibration. <<<")
            
    all_charuco_corners = []
    all_charuco_ids = []
    accepted_sigs = []
    last_calib_time = time.time()
    
    # Constellation Definitions
    # TL: 40, TR: 41, BL: 42, BR: 43
    # Center Device IDs: 0-5
    
    # --- SLAM SPATIAL GRAPH MEMORY ---
    global_origin_id = None
    # Dictionary mapping screen_id (int) -> {"transform": 4x4 ndarray, "width": float, "height": float}
    global_transforms = {}
    global_anchor_transforms = {} # anchor_id -> {"transform": 4x4 ndarray, "size": float}
    screen_trackers = {} # c_id -> {"rvec": rvec, "tvec": tvec}
    anchor_trackers = {} # anchor_id -> {"rvec": rvec, "tvec": tvec}
    
    # Temporal Smoothing
    smoothed_T_cam = None

    view_pitch = 45.0
    view_yaw = -45.0
    view_dist = ROOM_MAP_DEFAULT_VIEW_DIST
    view_pan_x = 0.0
    view_pan_y = 0.0
    mouse_is_down = False
    pan_is_down = False
    last_mouse_x = 0
    last_mouse_y = 0
    last_pan_x = 0
    last_pan_y = 0
    rendered_screen_centers = []
    bridge_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    point_cloud_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    point_cloud_tcp_server = None
    point_cloud_shared_memory = None
    oakd_point_cloud_shared_memory = None
    command_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    command_sock.bind(("127.0.0.1", TRACKER_CONTROL_PORT))
    command_sock.setblocking(False)
    last_status_blob = ""
    last_status_time = 0.0
    last_layout_send_time = 0.0
    last_tracker_pose_send_time = 0.0
    last_resolved_head_pose_send_time = 0.0
    last_realsense_tracking_send_time = 0.0
    last_realsense_point_cloud_send_time = 0.0
    realsense_point_cloud_enabled = False
    realsense_point_cloud_stride = max(1, REALSENSE_POINT_CLOUD_DEFAULT_STRIDE)
    realsense_point_cloud_min_depth = REALSENSE_POINT_CLOUD_MIN_DEPTH_M
    realsense_point_cloud_max_depth = REALSENSE_POINT_CLOUD_MAX_DEPTH_M
    realsense_point_cloud_max_points = max(0, REALSENSE_POINT_CLOUD_MAX_POINTS)
    realsense_point_cloud_mesh_enabled = False
    realsense_point_cloud_mesh_mode = "gpu_grid"
    realsense_point_cloud_mesh_max_edge = REALSENSE_POINT_CLOUD_MESH_MAX_EDGE_M
    realsense_point_cloud_packet_points = max(1, REALSENSE_POINT_CLOUD_DEFAULT_PACKET_POINTS)
    realsense_point_cloud_transport = "udp"
    realsense_point_cloud_shm_color_format = "rgba"
    realsense_point_cloud_frame_id = 0
    realsense_point_cloud_waiting_warned = False
    realsense_point_cloud_send_counter = 0
    realsense_point_cloud_last_fps_print_time = time.time()
    oakd_capture = None
    oakd_point_cloud_enabled = False
    oakd_point_cloud_stride = max(1, OAKD_POINT_CLOUD_DEFAULT_STRIDE)
    oakd_point_cloud_min_depth = OAKD_POINT_CLOUD_MIN_DEPTH_M
    oakd_point_cloud_max_depth = OAKD_POINT_CLOUD_MAX_DEPTH_M
    oakd_point_cloud_frame_id = 0
    oakd_point_cloud_send_counter = 0
    oakd_point_cloud_last_fps_print_time = time.time()
    oakd_point_cloud_shm_color_format = "rgba"
    last_oakd_point_cloud_send_time = 0.0
    last_oakd_point_cloud_frame_serial = 0
    oakd_point_cloud_settings = {
        "width": OAKD_WIDTH,
        "height": OAKD_HEIGHT,
        "fps": OAKD_FPS,
        "rgb_res": os.environ.get("OAKD_RGB_RES", "1080p"),
        "mono_res": os.environ.get("OAKD_MONO_RES", "800p"),
        "preset": os.environ.get("OAKD_STEREO_PRESET", "fast_density"),
        "lr_check": OAKD_LR_CHECK,
        "subpixel": OAKD_SUBPIXEL,
        "subpixel_bits": OAKD_SUBPIXEL_BITS,
        "confidence_threshold": OAKD_CONFIDENCE_THRESHOLD,
        "median_filter": OAKD_MEDIAN_FILTER,
        "speckle_filter": OAKD_SPECKLE_FILTER,
        "speckle_range": OAKD_SPECKLE_RANGE,
        "depth_source": os.environ.get("OAKD_DEPTH_SOURCE", "depthai"),
        "fast_stereo_enabled": os.environ.get("OAKD_FAST_STEREO_ENABLED", "0").strip().lower() in ("1", "true", "yes", "on"),
        "fast_stereo_iters": int(os.environ.get("OAKD_FAST_STEREO_ITERS", "4")),
        "fast_stereo_scale": float(os.environ.get("OAKD_FAST_STEREO_SCALE", "1.0")),
        "fast_stereo_torch_compile": os.environ.get("OAKD_FAST_STEREO_TORCH_COMPILE", "0").strip().lower() in ("1", "true", "yes", "on"),
        "fast_stereo_backend": os.environ.get("OAKD_FAST_STEREO_BACKEND", "pytorch").strip().lower(),
        "fast_stereo_model_profile": os.environ.get("OAKD_FAST_STEREO_MODEL_PROFILE", "full_320x736_i4").strip().lower(),
        "use_rgb_color_for_host_depth": os.environ.get("OAKD_USE_RGB_COLOR_FOR_HOST_DEPTH", "1").strip().lower() in ("1", "true", "yes", "on"),
        "host_depth_color_mode": os.environ.get("OAKD_HOST_DEPTH_COLOR_MODE", "rgb_projected_stable").strip().lower(),
    }
    if oakd_point_cloud_settings["fast_stereo_model_profile"] not in FAST_FOUNDATION_MODEL_PROFILES:
        oakd_point_cloud_settings["fast_stereo_model_profile"] = "full_320x736_i4"
    oakd_publisher_thread = None
    oakd_start_thread = None
    oakd_starting = False
    oakd_next_start_time = 0.0
    oakd_publisher_stop_event = threading.Event()
    oakd_publish_lock = threading.Lock()
    oakd_realsense_align_lock = threading.Lock()
    oakd_realsense_align_thread = None
    point_cloud_stats_path = ""
    point_cloud_console_stats = os.environ.get("POINT_CLOUD_CONSOLE_STATS", "0").strip().lower() in ("1", "true", "yes", "on")
    point_cloud_sync_to_slowest = os.environ.get("POINT_CLOUD_SYNC_TO_SLOWEST", "0").strip().lower() in ("1", "true", "yes", "on")
    point_cloud_stats = {
        "realsense": {"enabled": False, "publish_fps": 0.0, "capture_fps": 0.0, "points": 0, "valid_pct": 0.0, "width": 0, "height": 0, "frame_age_ms": 0.0, "sensor_age_ms": 0.0, "color_age_ms": 0.0, "sensor_host_age_ms": 0.0, "color_host_age_ms": 0.0},
        "oakd": {"enabled": False, "publish_fps": 0.0, "capture_fps": 0.0, "points": 0, "valid_pct": 0.0, "width": 0, "height": 0, "source": "depthai", "frame_age_ms": 0.0, "sensor_age_ms": 0.0, "color_age_ms": 0.0, "sensor_host_age_ms": 0.0, "color_host_age_ms": 0.0},
        "sync_to_slowest": bool(point_cloud_sync_to_slowest),
        "timestamp": time.time(),
    }
    point_cloud_stats_last_write_time = 0.0
    capture_loop_frame_count = 0
    capture_loop_fps = 0.0
    capture_loop_last_fps_time = time.perf_counter()
    cap = None
    camera_paused = False
    active_capture_width = 0
    active_capture_height = 0
    active_camera_index = None
    active_camera_source = os.environ.get(CAMERA_SOURCE_ENV, CAMERA_SOURCE_WEBCAM).strip().lower()
    if active_camera_source not in (CAMERA_SOURCE_WEBCAM, CAMERA_SOURCE_REALSENSE):
        active_camera_source = CAMERA_SOURCE_WEBCAM
    active_realsense_tracking_mode = os.environ.get(REALSENSE_TRACKING_MODE_ENV, "ml").strip().lower()
    if active_realsense_tracking_mode not in REALSENSE_TRACKING_MODES:
        active_realsense_tracking_mode = "ml"
    active_realsense_tracking_enabled = os.environ.get(REALSENSE_TRACKING_ENABLED_ENV, "0").strip().lower() not in ("0", "false", "no", "off")
    stereo_screen_size_auto = os.environ.get(STEREO_SCREEN_SIZE_AUTO_ENV, "0").strip().lower() in ("1", "true", "yes", "on")
    scan_locked_state = False
    layout_calibration_active = False
    locked_tracking_reference = None
    locked_tracking_reference_origin = ""
    latest_live_tracking_pose = None
    latest_live_tracking_time = 0.0
    latest_depth_head_position = None
    latest_depth_head_time = 0.0
    show_head_to_camera_debug = False
    anchor_pose_mode_index = 0
    tracker_anchor_button_rect = None
    measured_screen_sizes = {}
    measured_screen_size_last_write = {}

    def send_udp_json(payload):
        bridge_sock.sendto(json.dumps(payload).encode('utf-8'), ("127.0.0.1", 4243))

    def update_point_cloud_stats(camera_name, **values):
        nonlocal point_cloud_stats_last_write_time
        now = time.time()
        if camera_name not in point_cloud_stats:
            point_cloud_stats[camera_name] = {}
        point_cloud_stats[camera_name].update(values)
        point_cloud_stats[camera_name]["last_update"] = now
        point_cloud_stats["sync_to_slowest"] = bool(point_cloud_sync_to_slowest)
        point_cloud_stats["timestamp"] = now
        if not point_cloud_stats_path:
            return
        if now - point_cloud_stats_last_write_time < 0.25:
            return
        try:
            resolved = os.path.abspath(point_cloud_stats_path)
            os.makedirs(os.path.dirname(resolved), exist_ok=True)
            tmp_path = resolved + ".tmp"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(point_cloud_stats, f)
            os.replace(tmp_path, resolved)
            point_cloud_stats_last_write_time = now
        except Exception:
            pass

    def point_cloud_effective_send_interval(camera_name):
        if camera_name == "oakd":
            interval = float(OAKD_POINT_CLOUD_SEND_INTERVAL_SEC)
        else:
            interval = float(REALSENSE_POINT_CLOUD_SEND_INTERVAL_SEC)
        if not (
            point_cloud_sync_to_slowest
            and realsense_point_cloud_enabled
            and oakd_point_cloud_enabled
        ):
            return interval

        interval = max(interval, float(REALSENSE_POINT_CLOUD_SEND_INTERVAL_SEC), float(OAKD_POINT_CLOUD_SEND_INTERVAL_SEC))
        now = time.time()
        for stats_name in ("realsense", "oakd"):
            stats = point_cloud_stats.get(stats_name, {})
            if not bool(stats.get("enabled", False)):
                continue
            last_update = float(stats.get("last_update", 0.0) or 0.0)
            if last_update > 0.0 and now - last_update > 2.0:
                continue
            try:
                fps = float(stats.get("capture_fps", 0.0) or 0.0)
            except Exception:
                fps = 0.0
            if 0.1 <= fps <= 240.0:
                interval = max(interval, 1.0 / max(0.1, fps))
        return min(5.0, max(0.001, interval))

    def broadcast_measured_screen_size(screen_id, width_inches, height_inches):
        send_udp_json(
            {
                "type": "measured_screen_size",
                "screen_id": int(screen_id),
                "width": float(width_inches),
                "height": float(height_inches),
                "source": "realsense_stereo",
            }
        )

    def send_scan_status(state, message, **extra):
        nonlocal last_status_blob, last_status_time
        payload = {
            "type": "scan_status",
            "state": state,
            "message": message,
        }
        payload.update(extra)
        blob = json.dumps(payload, sort_keys=True)
        now = time.time()
        if blob != last_status_blob or now - last_status_time > 1.0:
            send_udp_json(payload)
            last_status_blob = blob
            last_status_time = now

    def broadcast_layout():
        nonlocal last_layout_send_time
        origin_screen = int(global_origin_id) if global_origin_id is not None else None
        if origin_screen is None and global_transforms:
            sorted_ids = sorted(int(sid) for sid in global_transforms.keys())
            origin_screen = sorted_ids[0]
            print(f">>> WARNING: layout broadcast had no origin; falling back to screen {origin_screen}. <<<")
        layout_payload = {
            "type": "layout_map",
            "origin_screen": origin_screen,
            "screens": {}
        }
        for sid, sdata in global_transforms.items():
            T = sdata["transform"]
            layout_payload["screens"][str(sid)] = {
                "R": T[:3, :3].tolist(),
                "T": T[:3, 3].tolist(),
                "width": sdata["width"],
                "height": sdata["height"]
            }

        send_udp_json(layout_payload)
        last_layout_send_time = time.time()

    def broadcast_tracker_camera_pose(T_origin_to_cam):
        nonlocal last_tracker_pose_send_time
        if global_origin_id is None or T_origin_to_cam is None:
            return
        payload_transform = canonicalize_y_up_transform(T_origin_to_cam) if CANONICAL_Y_UP_PAYLOADS else T_origin_to_cam
        payload = {
            "type": "tracker_camera_pose",
            "origin_screen": int(global_origin_id),
            "R": payload_transform[:3, :3].tolist(),
            "T": payload_transform[:3, 3].tolist(),
        }
        if CANONICAL_Y_UP_PAYLOADS:
            payload["canonical_y_up"] = True
        send_udp_json(payload)
        last_tracker_pose_send_time = time.time()

    def broadcast_resolved_head_pose(camera_transform, head_position):
        nonlocal last_resolved_head_pose_send_time
        if global_origin_id is None or camera_transform is None or head_position is None:
            return
        payload_camera_transform = canonicalize_y_up_transform(camera_transform) if CANONICAL_Y_UP_PAYLOADS else camera_transform
        payload_head_position = canonicalize_y_up_position(head_position) if CANONICAL_Y_UP_PAYLOADS else np.asarray(head_position, dtype=np.float32)
        payload = {
            "type": "resolved_head_pose",
            "origin_screen": int(global_origin_id),
            "camera_R": payload_camera_transform[:3, :3].tolist(),
            "camera_T": payload_camera_transform[:3, 3].tolist(),
            "head_T": [float(payload_head_position[0]), float(payload_head_position[1]), float(payload_head_position[2])],
        }
        if CANONICAL_Y_UP_PAYLOADS:
            payload["canonical_y_up"] = True
        send_udp_json(payload)
        last_resolved_head_pose_send_time = time.time()

    def broadcast_realsense_tracking_pose(head_position_m):
        nonlocal last_realsense_tracking_send_time
        if head_position_m is None:
            return
        now = time.time()
        if now - last_realsense_tracking_send_time <= REALSENSE_TRACKING_SEND_INTERVAL_SEC:
            return
        head_position_m = np.asarray(head_position_m, dtype=np.float32)
        payload = {
            "type": "tracking",
            "source": "realsense_depth",
            "active": True,
            # Match the existing WebSocket tracking packet convention: raw
            # position values are centimeters, then Godot applies its normal
            # screen/reference transform path.
            "x": float(head_position_m[0] * 100.0),
            "y": float(head_position_m[1] * 100.0),
            "z": float(head_position_m[2] * 100.0),
        }
        send_udp_json(payload)
        last_realsense_tracking_send_time = now

    def broadcast_realsense_point_cloud(capture):
        nonlocal point_cloud_tcp_server, point_cloud_shared_memory
        nonlocal last_realsense_point_cloud_send_time, realsense_point_cloud_frame_id, realsense_point_cloud_waiting_warned
        nonlocal realsense_point_cloud_send_counter, realsense_point_cloud_last_fps_print_time
        if not realsense_point_cloud_enabled or not isinstance(capture, RealSenseCapture):
            return
        if realsense_point_cloud_transport == "shm" and point_cloud_shared_memory is None:
            point_cloud_shared_memory = LatestGridSharedMemory(REALSENSE_POINT_CLOUD_SHM_NAME, label="RealSense point cloud")
        if realsense_point_cloud_transport == "tcp" and point_cloud_tcp_server is None:
            point_cloud_tcp_server = LatestFrameTcpServer(port=REALSENSE_POINT_CLOUD_TCP_PORT)
        realsense_point_cloud_waiting_warned = False
        depth_m = capture.latest_depth_m
        if depth_m is None:
            return
        now = time.time()
        if now - last_realsense_point_cloud_send_time <= point_cloud_effective_send_interval("realsense"):
            return

        stride = max(1, int(realsense_point_cloud_stride))
        min_depth = float(realsense_point_cloud_min_depth)
        max_depth = float(realsense_point_cloud_max_depth)
        color = None
        try:
            color = capture.latest_color_bgr
        except AttributeError:
            color = None
        if color is None:
            return
        point_cloud_intrinsics = getattr(capture, "point_cloud_intrinsics", capture.intrinsics)

        rows = np.arange(0, depth_m.shape[0], stride, dtype=np.int32)
        cols = np.arange(0, depth_m.shape[1], stride, dtype=np.int32)
        sampled_depth = depth_m[np.ix_(rows, cols)]
        valid = np.isfinite(sampled_depth) & (sampled_depth >= min_depth) & (sampled_depth <= max_depth)
        valid_count = int(valid.sum())
        if valid_count <= 0:
            return

        uses_grid_transport = (
            realsense_point_cloud_transport == "shm"
            or (
                realsense_point_cloud_transport == "tcp"
                and realsense_point_cloud_mesh_enabled
                and realsense_point_cloud_mesh_mode in ("gpu_grid", "gpu_points", "stereo_gpu")
            )
        )
        if uses_grid_transport:
            grid_depth = sampled_depth.astype("<f4", copy=True)
            grid_depth[~valid] = 0.0
            sampled_color_grid = color[np.ix_(rows, cols)]
            grid_h, grid_w = grid_depth.shape
            tri_mask = None
            needs_triangle_mask = (
                realsense_point_cloud_transport == "tcp"
                and realsense_point_cloud_mesh_mode in ("gpu_grid", "stereo_gpu")
            )
            if needs_triangle_mask and grid_h > 1 and grid_w > 1:
                tri_mask = np.empty((max(1, grid_h - 1), max(1, grid_w - 1), 4), dtype=np.uint8)
                tri_mask[:, :, :] = 255
                grid_x = cols[np.newaxis, :].astype(np.float32)
                grid_y = rows[:, np.newaxis].astype(np.float32)
                z = grid_depth.astype(np.float32)
                x = (grid_x - float(point_cloud_intrinsics.ppx)) * z / max(1e-6, float(point_cloud_intrinsics.fx))
                y = (grid_y - float(point_cloud_intrinsics.ppy)) * z / max(1e-6, float(point_cloud_intrinsics.fy))
                grid_positions = np.stack([x, -y, -z], axis=2)
                pa = grid_positions[:-1, :-1]
                pb = grid_positions[:-1, 1:]
                pc = grid_positions[1:, :-1]
                pd = grid_positions[1:, 1:]
                va = valid[:-1, :-1]
                vb = valid[:-1, 1:]
                vc = valid[1:, :-1]
                vd = valid[1:, 1:]
                edge_sq = float(realsense_point_cloud_mesh_max_edge) ** 2
                tri1 = (
                    va & vb & vc
                    & (np.sum((pa - pb) * (pa - pb), axis=2) <= edge_sq)
                    & (np.sum((pb - pc) * (pb - pc), axis=2) <= edge_sq)
                    & (np.sum((pc - pa) * (pc - pa), axis=2) <= edge_sq)
                )
                tri2 = (
                    vb & vc & vd
                    & (np.sum((pb - pc) * (pb - pc), axis=2) <= edge_sq)
                    & (np.sum((pc - pd) * (pc - pd), axis=2) <= edge_sq)
                    & (np.sum((pd - pb) * (pd - pb), axis=2) <= edge_sq)
                )
                tri_mask[:, :, 0] = np.where(tri1, 255, 0).astype(np.uint8)
                tri_mask[:, :, 1] = np.where(tri2, 255, 0).astype(np.uint8)
            realsense_point_cloud_frame_id = (realsense_point_cloud_frame_id + 1) & 0xFFFFFFFF
            if realsense_point_cloud_transport == "shm":
                if realsense_point_cloud_shm_color_format == "bgr":
                    shm_color = sampled_color_grid
                    shm_color_format = "bgr"
                else:
                    grid_rgba = np.empty((sampled_color_grid.shape[0], sampled_color_grid.shape[1], 4), dtype=np.uint8)
                    grid_rgba[:, :, 0] = sampled_color_grid[:, :, 2]
                    grid_rgba[:, :, 1] = sampled_color_grid[:, :, 1]
                    grid_rgba[:, :, 2] = sampled_color_grid[:, :, 0]
                    grid_rgba[:, :, 3] = np.where(valid, 255, 0).astype(np.uint8)
                    shm_color = grid_rgba
                    shm_color_format = "rgba"
                point_cloud_shared_memory.publish_grid(
                    realsense_point_cloud_frame_id,
                    grid_depth,
                    shm_color,
                    stride,
                    point_cloud_intrinsics,
                    shm_color_format,
                )
                publish_fps = 1.0 / max(0.001, now - last_realsense_point_cloud_send_time)
                last_realsense_point_cloud_send_time = now
                realsense_point_cloud_send_counter += 1
                valid_pct = 100.0 * float(valid_count) / max(1.0, float(valid.size))
                update_point_cloud_stats(
                    "realsense",
                    enabled=True,
                    publish_fps=float(publish_fps),
                    capture_fps=float(getattr(capture, "capture_fps", 0.0)),
                    points=int(valid_count),
                    valid_pct=float(valid_pct),
                    width=int(grid_w),
                    height=int(grid_h),
                    stride=int(stride),
                )
                if point_cloud_console_stats and now - realsense_point_cloud_last_fps_print_time >= 2.0:
                    elapsed = now - realsense_point_cloud_last_fps_print_time
                    print(
                        f">>> RealSense point cloud shm publish: "
                        f"{realsense_point_cloud_send_counter / max(0.001, elapsed):.1f}fps, "
                        f"{grid_w}x{grid_h} cells, points={valid_count}, valid={valid_pct:.0f}%, "
                        f"name={REALSENSE_POINT_CLOUD_SHM_NAME} <<<"
                    )
                    realsense_point_cloud_send_counter = 0
                    realsense_point_cloud_last_fps_print_time = now
                return
            grid_rgba = np.empty((sampled_color_grid.shape[0], sampled_color_grid.shape[1], 4), dtype=np.uint8)
            grid_rgba[:, :, 0] = sampled_color_grid[:, :, 2]
            grid_rgba[:, :, 1] = sampled_color_grid[:, :, 1]
            grid_rgba[:, :, 2] = sampled_color_grid[:, :, 0]
            grid_rgba[:, :, 3] = np.where(valid, 255, 0).astype(np.uint8)
            frame_payload = bytearray()
            frame_payload.extend(REALSENSE_POINT_CLOUD_FRAME_MAGIC)
            frame_payload.extend(struct.pack("<IIIHH", realsense_point_cloud_frame_id, int(grid_w * grid_h), 0, stride, 1))
            frame_payload.extend(
                struct.pack(
                    "<HHffff",
                    int(grid_w),
                    int(grid_h),
                    float(point_cloud_intrinsics.fx),
                    float(point_cloud_intrinsics.fy),
                    float(point_cloud_intrinsics.ppx),
                    float(point_cloud_intrinsics.ppy),
                )
            )
            frame_payload.extend(grid_depth.tobytes())
            frame_payload.extend(grid_rgba.tobytes())
            if tri_mask is not None:
                frame_payload.extend(tri_mask.tobytes())
            if point_cloud_tcp_server is not None:
                point_cloud_tcp_server.publish(realsense_point_cloud_frame_id, frame_payload)
            publish_fps = 1.0 / max(0.001, now - last_realsense_point_cloud_send_time)
            last_realsense_point_cloud_send_time = now
            realsense_point_cloud_send_counter += 1
            valid_pct = 100.0 * float(valid_count) / max(1.0, float(valid.size))
            update_point_cloud_stats(
                "realsense",
                enabled=True,
                publish_fps=float(publish_fps),
                capture_fps=float(getattr(capture, "capture_fps", 0.0)),
                points=int(valid_count),
                valid_pct=float(valid_pct),
                width=int(grid_w),
                height=int(grid_h),
                stride=int(stride),
            )
            if point_cloud_console_stats and now - realsense_point_cloud_last_fps_print_time >= 2.0:
                elapsed = now - realsense_point_cloud_last_fps_print_time
                print(
                    f">>> RealSense point cloud tcp grid publish: "
                    f"{realsense_point_cloud_send_counter / max(0.001, elapsed):.1f}fps, "
                    f"{grid_w}x{grid_h} cells, points={valid_count}, valid={valid_pct:.0f}% <<<"
                )
                realsense_point_cloud_send_counter = 0
                realsense_point_cloud_last_fps_print_time = now
            return

        grid_x = cols[np.newaxis, :].astype(np.float32)
        grid_y = rows[:, np.newaxis].astype(np.float32)
        z = sampled_depth.astype(np.float32)
        x = (grid_x - float(point_cloud_intrinsics.ppx)) * z / max(1e-6, float(point_cloud_intrinsics.fx))
        y = (grid_y - float(point_cloud_intrinsics.ppy)) * z / max(1e-6, float(point_cloud_intrinsics.fy))
        # RealSense/OpenCV is X right, Y down, Z forward. Godot view space here is
        # X right, Y up, -Z forward so the live cloud appears in front of the window.
        positions = np.stack([x[valid], -y[valid], -z[valid]], axis=1).astype("<f4", copy=False)
        sampled_color = color[np.ix_(rows, cols)][valid]
        rgba = np.empty((sampled_color.shape[0], 4), dtype=np.uint8)
        rgba[:, 0] = sampled_color[:, 2]
        rgba[:, 1] = sampled_color[:, 1]
        rgba[:, 2] = sampled_color[:, 0]
        rgba[:, 3] = 255

        mesh_build_start = time.perf_counter()
        mesh_build_msec = 0.0
        max_points = max(0, int(realsense_point_cloud_max_points))
        if max_points > 0 and positions.shape[0] > max_points:
            decimation = int(np.ceil(positions.shape[0] / float(max_points)))
            positions = positions[::decimation][:max_points]
            rgba = rgba[::decimation][:max_points]
            mesh_indices = np.empty(0, dtype="<u4")
        elif realsense_point_cloud_mesh_enabled:
            compact_index = np.full(sampled_depth.shape, -1, dtype=np.int32)
            compact_index[valid] = np.arange(int(valid.sum()), dtype=np.int32)
            a = compact_index[:-1, :-1]
            b = compact_index[:-1, 1:]
            c = compact_index[1:, :-1]
            d = compact_index[1:, 1:]
            mesh_max_edge_sq = float(realsense_point_cloud_mesh_max_edge) ** 2

            tri1_valid = (a >= 0) & (b >= 0) & (c >= 0)
            if tri1_valid.any():
                tri1_a = a[tri1_valid]
                tri1_b = b[tri1_valid]
                tri1_c = c[tri1_valid]
                pa = positions[tri1_a]
                pb = positions[tri1_b]
                pc = positions[tri1_c]
                tri1_keep = (
                    np.sum((pa - pb) * (pa - pb), axis=1) <= mesh_max_edge_sq
                ) & (
                    np.sum((pb - pc) * (pb - pc), axis=1) <= mesh_max_edge_sq
                ) & (
                    np.sum((pc - pa) * (pc - pa), axis=1) <= mesh_max_edge_sq
                )
                tri1 = np.stack(
                    [tri1_a[tri1_keep], tri1_c[tri1_keep], tri1_b[tri1_keep]],
                    axis=1,
                )
            else:
                tri1 = np.empty((0, 3), dtype=np.int32)

            tri2_valid = (b >= 0) & (c >= 0) & (d >= 0)
            if tri2_valid.any():
                tri2_b = b[tri2_valid]
                tri2_c = c[tri2_valid]
                tri2_d = d[tri2_valid]
                pb = positions[tri2_b]
                pc = positions[tri2_c]
                pd = positions[tri2_d]
                tri2_keep = (
                    np.sum((pb - pc) * (pb - pc), axis=1) <= mesh_max_edge_sq
                ) & (
                    np.sum((pc - pd) * (pc - pd), axis=1) <= mesh_max_edge_sq
                ) & (
                    np.sum((pd - pb) * (pd - pb), axis=1) <= mesh_max_edge_sq
                )
                tri2 = np.stack(
                    [tri2_b[tri2_keep], tri2_c[tri2_keep], tri2_d[tri2_keep]],
                    axis=1,
                )
            else:
                tri2 = np.empty((0, 3), dtype=np.int32)

            mesh_indices = np.concatenate([tri1, tri2], axis=0).astype("<u4", copy=False).reshape(-1)
            mesh_build_msec = (time.perf_counter() - mesh_build_start) * 1000.0
        else:
            mesh_indices = np.empty(0, dtype="<u4")

        point_count = int(positions.shape[0])
        point_records = np.empty(
            point_count,
            dtype=np.dtype(
                [
                    ("x", "<f4"),
                    ("y", "<f4"),
                    ("z", "<f4"),
                    ("r", "u1"),
                    ("g", "u1"),
                    ("b", "u1"),
                    ("a", "u1"),
                ]
            ),
        )
        point_records["x"] = positions[:, 0]
        point_records["y"] = positions[:, 1]
        point_records["z"] = positions[:, 2]
        point_records["r"] = rgba[:, 0]
        point_records["g"] = rgba[:, 1]
        point_records["b"] = rgba[:, 2]
        point_records["a"] = rgba[:, 3]
        realsense_point_cloud_frame_id = (realsense_point_cloud_frame_id + 1) & 0xFFFFFFFF

        if realsense_point_cloud_transport == "tcp":
            frame_payload = bytearray()
            frame_payload.extend(REALSENSE_POINT_CLOUD_FRAME_MAGIC)
            frame_payload.extend(struct.pack("<IIIHH", realsense_point_cloud_frame_id, point_count, int(mesh_indices.size), stride, 0))
            frame_payload.extend(point_records.tobytes())
            if mesh_indices.size:
                frame_payload.extend(mesh_indices.tobytes())
            if point_cloud_tcp_server is not None:
                point_cloud_tcp_server.publish(realsense_point_cloud_frame_id, frame_payload)
            last_realsense_point_cloud_send_time = now
            realsense_point_cloud_send_counter += 1
            if point_cloud_console_stats and now - realsense_point_cloud_last_fps_print_time >= 2.0:
                elapsed = now - realsense_point_cloud_last_fps_print_time
                print(f">>> RealSense point cloud tcp publish: {realsense_point_cloud_send_counter / max(0.001, elapsed):.1f}fps, {point_count} points, {int(mesh_indices.size / 3)} tris, mesh {mesh_build_msec:.1f}ms <<<")
                realsense_point_cloud_send_counter = 0
                realsense_point_cloud_last_fps_print_time = now
            return

        packet_points = max(1, int(realsense_point_cloud_packet_points))
        chunk_count = int(np.ceil(point_count / float(packet_points)))
        for chunk_index in range(chunk_count):
            start = chunk_index * packet_points
            end = min(point_count, start + packet_points)
            payload = bytearray()
            payload.extend(REALSENSE_POINT_CLOUD_MAGIC)
            payload.extend(
                struct.pack(
                    "<IHHHHII",
                    realsense_point_cloud_frame_id,
                    chunk_index,
                    chunk_count,
                    int(end - start),
                    stride,
                    point_count,
                    0,
                )
            )
            payload.extend(point_records[start:end].tobytes())
            point_cloud_sock.sendto(payload, ("127.0.0.1", REALSENSE_POINT_CLOUD_PORT))
        last_realsense_point_cloud_send_time = now
        realsense_point_cloud_send_counter += 1
        if point_cloud_console_stats and now - realsense_point_cloud_last_fps_print_time >= 2.0:
            elapsed = now - realsense_point_cloud_last_fps_print_time
            print(f">>> RealSense point cloud send: {realsense_point_cloud_send_counter / max(0.001, elapsed):.1f}fps, {point_count} points <<<")
            realsense_point_cloud_send_counter = 0
            realsense_point_cloud_last_fps_print_time = now

    def _oakd_settings_signature():
        # Only include settings that require rebuilding the live DepthAI pipeline.
        # Depth-source switches are handled inside OakDCapture when the running
        # pipeline has the needed queues, so they should not force a full stack
        # restart by themselves.
        return (
            int(oakd_point_cloud_settings["width"]),
            int(oakd_point_cloud_settings["height"]),
            float(oakd_point_cloud_settings["fps"]),
            str(oakd_point_cloud_settings["rgb_res"]).strip().lower(),
            str(oakd_point_cloud_settings["mono_res"]).strip().lower(),
            str(oakd_point_cloud_settings["preset"]).strip().lower(),
            bool(oakd_point_cloud_settings["lr_check"]),
            bool(oakd_point_cloud_settings["subpixel"]),
            int(oakd_point_cloud_settings["subpixel_bits"]),
        )

    def _oakd_publisher_loop():
        while not oakd_publisher_stop_event.is_set():
            broadcast_oakd_point_cloud()
            time.sleep(0.001)

    def _start_oakd_publisher_if_needed():
        nonlocal oakd_publisher_thread
        if oakd_publisher_thread is None or not oakd_publisher_thread.is_alive():
            oakd_publisher_stop_event.clear()
            oakd_publisher_thread = threading.Thread(target=_oakd_publisher_loop, name="oakd-point-cloud-publisher", daemon=True)
            oakd_publisher_thread.start()

    def _stop_oakd_publisher():
        nonlocal oakd_publisher_thread
        oakd_publisher_stop_event.set()
        if oakd_publisher_thread is not None:
            oakd_publisher_thread.join(timeout=1.0)
            oakd_publisher_thread = None

    def _run_charuco_alignment_worker(result_path, oak_capture, rs_capture, oak_color, rs_color, rs_intrinsics):
        try:
            oak_pose, oak_status = detect_fusion_charuco_pose(oak_color, oak_capture.intrinsics, "OAK-D")
            rs_pose, rs_status = detect_fusion_charuco_pose(rs_color, rs_intrinsics, "RealSense")
            if oak_pose is None or rs_pose is None:
                status = f"ChArUco failed | {oak_status} | {rs_status}"
                write_oakd_alignment_result(result_path, "charuco", False, status)
                print(f">>> OAK-D/RealSense {status} <<<")
                return

            cv_to_view = np.diag([1.0, -1.0, -1.0, 1.0]).astype(np.float64)
            rs_to_oak = cv_to_view @ oak_pose @ np.linalg.inv(rs_pose) @ cv_to_view
            oakd_to_realsense = np.linalg.inv(rs_to_oak)
            write_oakd_alignment_result(
                result_path,
                "charuco",
                True,
                f"ChArUco applied | OAK->RS view transform | {oak_status} | {rs_status}",
                oakd_to_realsense,
            )
            print(
                f">>> OAK-D/RealSense ChArUco alignment solved and wrote {result_path or '<no result path>'}: "
                f"OAK->RS view transform | {oak_status} | {rs_status} <<<"
            )
        except Exception as exc:
            status = f"ChArUco failed: {exc}"
            write_oakd_alignment_result(result_path, "charuco", False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
        finally:
            oakd_realsense_align_lock.release()

    def refine_oakd_to_realsense_with_depth(init_transform, oak_depth, rs_depth, oak_intrinsics, rs_intrinsics, min_depth, max_depth, stride):
        try:
            import open3d as o3d
        except Exception as exc:
            return np.asarray(init_transform, dtype=np.float64), f"depth refine skipped: open3d import failed ({exc})", {}

        align_stride = max(1, int(stride))
        if align_stride == 1:
            align_stride = 2
        oak_points = depth_to_view_points(oak_depth, oak_intrinsics, min_depth, max_depth, align_stride, max_points=90000)
        rs_points = depth_to_view_points(rs_depth, rs_intrinsics, min_depth, max_depth, align_stride, max_points=90000)
        if oak_points is None or rs_points is None or oak_points.shape[0] < 800 or rs_points.shape[0] < 800:
            status = (
                "depth refine skipped: not enough points "
                f"OAK={0 if oak_points is None else oak_points.shape[0]} RS={0 if rs_points is None else rs_points.shape[0]}"
            )
            return np.asarray(init_transform, dtype=np.float64), status, {}

        source = o3d.geometry.PointCloud()
        target = o3d.geometry.PointCloud()
        source.points = o3d.utility.Vector3dVector(oak_points)
        target.points = o3d.utility.Vector3dVector(rs_points)

        voxel = float(os.environ.get("OAKD_REALSENSE_ARUCO_REFINE_VOXEL_M", "0.025"))
        max_corr = float(os.environ.get("OAKD_REALSENSE_ARUCO_REFINE_MAX_CORR_M", str(voxel * 3.0)))
        source_down = source.voxel_down_sample(voxel)
        target_down = target.voxel_down_sample(voxel)
        if len(source_down.points) < 200 or len(target_down.points) < 200:
            source_down = source
            target_down = target
        if len(source_down.points) < 200 or len(target_down.points) < 200:
            status = f"depth refine skipped: downsample too sparse OAK={len(source_down.points)} RS={len(target_down.points)}"
            return np.asarray(init_transform, dtype=np.float64), status, {}

        target_down.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 3.0, max_nn=40))
        init = np.asarray(init_transform, dtype=np.float64)
        try:
            icp = o3d.pipelines.registration.registration_icp(
                source_down,
                target_down,
                max_corr,
                init,
                o3d.pipelines.registration.TransformationEstimationPointToPlane(),
                o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=60),
            )
        except Exception:
            icp = o3d.pipelines.registration.registration_icp(
                source_down,
                target_down,
                max_corr,
                init,
                o3d.pipelines.registration.TransformationEstimationPointToPoint(),
                o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=60),
            )
        refined = np.asarray(icp.transformation, dtype=np.float64)
        details = {
            "depth_refine_fitness": float(icp.fitness),
            "depth_refine_rmse": float(icp.inlier_rmse),
            "depth_refine_oak_points": int(oak_points.shape[0]),
            "depth_refine_rs_points": int(rs_points.shape[0]),
            "depth_refine_oak_down": int(len(source_down.points)),
            "depth_refine_rs_down": int(len(target_down.points)),
            "depth_refine_voxel_m": float(voxel),
            "depth_refine_max_corr_m": float(max_corr),
        }
        status = (
            "depth refined "
            f"fitness={float(icp.fitness):.3f} rmse={float(icp.inlier_rmse):.4f} "
            f"pts OAK={oak_points.shape[0]} RS={rs_points.shape[0]} down OAK={len(source_down.points)} RS={len(target_down.points)}"
        )
        return refined, status, details

    def _run_single_aruco_alignment_worker(
        result_path,
        oak_capture,
        oak_color,
        rs_color,
        rs_intrinsics,
        marker_size_m,
        dictionary_name,
        marker_id,
        marker_ids=None,
        auto_depth_refine=True,
        oak_depth=None,
        rs_depth=None,
        oak_depth_intrinsics=None,
        rs_depth_intrinsics=None,
        min_depth=OAKD_POINT_CLOUD_MIN_DEPTH_M,
        max_depth=OAKD_POINT_CLOUD_MAX_DEPTH_M,
        stride=2,
        requested_method="single_aruco",
    ):
        alignment_label = "big ArUco" if str(requested_method).strip().lower() == "big_aruco" else "single ArUco"
        try:
            oak_poses, oak_status = detect_big_aruco_poses(
                oak_color,
                oak_capture.intrinsics,
                "OAK-D",
                marker_size_m,
                dictionary_name,
                marker_id,
                marker_ids,
            )
            rs_poses, rs_status = detect_big_aruco_poses(
                rs_color,
                rs_intrinsics,
                "RealSense",
                marker_size_m,
                dictionary_name,
                marker_id,
                marker_ids,
            )
            shared_keys = sorted(set(oak_poses.keys()) & set(rs_poses.keys()))
            if not oak_poses or not rs_poses or not shared_keys:
                status = f"{alignment_label} failed | {oak_status} | {rs_status}"
                write_oakd_alignment_result(result_path, requested_method, False, status)
                print(f">>> OAK-D/RealSense {status} <<<")
                return

            cv_to_view = np.diag([1.0, -1.0, -1.0, 1.0]).astype(np.float64)
            marker_transforms = []
            marker_details = []
            for key in shared_keys:
                oak_pose = oak_poses[key]["transform"]
                rs_pose = rs_poses[key]["transform"]
                rs_to_oak = cv_to_view @ oak_pose @ np.linalg.inv(rs_pose) @ cv_to_view
                marker_oakd_to_realsense = np.linalg.inv(rs_to_oak)
                marker_transforms.append(marker_oakd_to_realsense)
                marker_details.append(
                    {
                        "dictionary": str(key[0]),
                        "marker_id": int(key[1]),
                        "oak_area_px": float(oak_poses[key]["area_px"]),
                        "rs_area_px": float(rs_poses[key]["area_px"]),
                    }
                )
            oakd_to_realsense = average_rigid_transforms(marker_transforms)
            if oakd_to_realsense is None:
                status = f"{alignment_label} failed: no usable shared marker transforms | {oak_status} | {rs_status}"
                write_oakd_alignment_result(result_path, requested_method, False, status)
                print(f">>> OAK-D/RealSense {status} <<<")
                return
            shared_text = ",".join(f"{key[0]}:{key[1]}" for key in shared_keys)
            depth_correction_status = "depth correction skipped"
            depth_correction_details = []
            depth_correction_scale = 1.0
            depth_correction_offset_m = 0.0
            depth_correction_quadratic = 0.0
            scene_depth_correction_status = "scene depth correction skipped"
            scene_depth_correction_details = {}
            if oak_depth is not None:
                shared_oak_poses = {key: oak_poses[key] for key in shared_keys}
                (
                    depth_correction_scale,
                    depth_correction_offset_m,
                    depth_correction_details,
                    depth_correction_status,
                ) = estimate_depth_scale_offset_from_marker_poses(
                    oak_depth,
                    shared_oak_poses,
                    min_depth,
                    max_depth,
                )
                marker_depth_error = median_marker_depth_error(
                    depth_correction_details,
                    depth_correction_scale,
                    depth_correction_offset_m,
                    0.0,
                )
                if rs_depth is not None:
                    (
                        scene_scale,
                        scene_offset_m,
                        scene_depth_correction_details,
                        scene_depth_correction_status,
                    ) = estimate_depth_scale_offset_from_cross_depth(
                        oak_depth,
                        rs_depth,
                        oak_depth_intrinsics if oak_depth_intrinsics is not None else oak_capture.intrinsics,
                        rs_depth_intrinsics if rs_depth_intrinsics is not None else rs_intrinsics,
                        oakd_to_realsense,
                        min_depth,
                        max_depth,
                        stride=max(6, int(stride) * 3),
                    )
                    if scene_scale is not None and scene_offset_m is not None:
                        scene_quadratic = float(scene_depth_correction_details.get("quadratic_coeff", 0.0))
                        scene_marker_error = median_marker_depth_error(
                            depth_correction_details,
                            scene_scale,
                            scene_offset_m,
                            scene_quadratic,
                        )
                        marker_limit = max(0.018, (marker_depth_error or 0.0) + 0.012)
                        if scene_marker_error is None or scene_marker_error <= marker_limit:
                            depth_correction_scale = scene_scale
                            depth_correction_offset_m = scene_offset_m
                            depth_correction_quadratic = scene_quadratic
                            depth_correction_status = scene_depth_correction_status
                        else:
                            scene_depth_correction_status = (
                                f"{scene_depth_correction_status}; rejected because marker plane error "
                                f"{scene_marker_error:.4f}m exceeded {marker_limit:.4f}m"
                            )
                if hasattr(oak_capture, "set_depth_correction"):
                    oak_capture.set_depth_correction(
                        depth_correction_scale,
                        depth_correction_offset_m,
                        depth_correction_quadratic,
                    )
                raw_oak_depth = oak_depth.astype(np.float32, copy=True)
                oak_depth = (
                    raw_oak_depth * raw_oak_depth * float(depth_correction_quadratic)
                    + raw_oak_depth * float(depth_correction_scale)
                    + float(depth_correction_offset_m)
                )
                oak_depth[~np.isfinite(oak_depth)] = 0.0
                oak_depth[oak_depth < 0.0] = 0.0
            refine_status = "depth refine disabled"
            refine_details = {}
            if auto_depth_refine:
                if oak_depth is not None and rs_depth is not None:
                    oakd_to_realsense, refine_status, refine_details = refine_oakd_to_realsense_with_depth(
                        oakd_to_realsense,
                        oak_depth,
                        rs_depth,
                        oak_depth_intrinsics if oak_depth_intrinsics is not None else oak_capture.intrinsics,
                        rs_depth_intrinsics if rs_depth_intrinsics is not None else rs_intrinsics,
                        min_depth,
                        max_depth,
                        stride,
                    )
                else:
                    refine_status = "depth refine skipped: missing latest OAK-D or RealSense depth"
            result_details = {
                "marker_size_m": float(marker_size_m),
                "dictionary": str(dictionary_name),
                "marker_id": int(marker_id),
                "marker_ids": sorted(parse_marker_id_filter(marker_id, marker_ids) or []),
                "shared_marker_count": int(len(shared_keys)),
                "shared_markers": marker_details,
                "oak_depth_correction_scale": float(depth_correction_scale),
                "oak_depth_correction_offset_m": float(depth_correction_offset_m),
                "oak_depth_correction_quadratic": float(depth_correction_quadratic),
                "oak_depth_correction_status": depth_correction_status,
                "oak_depth_correction_markers": depth_correction_details,
                "oak_scene_depth_correction_status": scene_depth_correction_status,
                "oak_scene_depth_correction": scene_depth_correction_details,
                "auto_depth_refine": bool(auto_depth_refine),
                "depth_refine_status": refine_status,
            }
            result_details.update(refine_details)
            write_oakd_alignment_result(
                result_path,
                requested_method,
                True,
                f"big ArUco applied | shared={len(shared_keys)} [{shared_text}] | {depth_correction_status} | {refine_status} | OAK->RS view transform | {oak_status} | {rs_status}",
                oakd_to_realsense,
                result_details,
            )
            print(
                f">>> OAK-D/RealSense big ArUco alignment solved from {len(shared_keys)} shared marker(s) "
                f"and wrote {result_path or '<no result path>'}: {depth_correction_status} | {refine_status} | OAK->RS view transform | {oak_status} | {rs_status} <<<"
            )
        except Exception as exc:
            status = f"{alignment_label} failed: {exc}"
            write_oakd_alignment_result(result_path, requested_method, False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
        finally:
            oakd_realsense_align_lock.release()

    def _run_open3d_alignment_worker(result_path, oak_capture, rs_capture, oak_depth, rs_depth, oak_intrinsics, rs_intrinsics, min_depth, max_depth, stride):
        try:
            try:
                import open3d as o3d
            except Exception as exc:
                status = f"Open3D alignment failed: open3d import failed ({exc})"
                write_oakd_alignment_result(result_path, "open3d", False, status)
                print(f">>> OAK-D/RealSense {status} <<<")
                return

            align_stride = max(1, int(stride))
            if align_stride == 1:
                align_stride = 2
            oak_points = depth_to_view_points(oak_depth, oak_intrinsics, min_depth, max_depth, align_stride, max_points=70000)
            rs_points = depth_to_view_points(rs_depth, rs_intrinsics, min_depth, max_depth, align_stride, max_points=70000)
            if oak_points is None or rs_points is None or oak_points.shape[0] < 500 or rs_points.shape[0] < 500:
                status = (
                    "Open3D alignment failed: not enough points "
                    f"OAK={0 if oak_points is None else oak_points.shape[0]} RS={0 if rs_points is None else rs_points.shape[0]}"
                )
                write_oakd_alignment_result(result_path, "open3d", False, status)
                print(f">>> OAK-D/RealSense {status} <<<")
                return

            source = o3d.geometry.PointCloud()
            target = o3d.geometry.PointCloud()
            source.points = o3d.utility.Vector3dVector(oak_points)
            target.points = o3d.utility.Vector3dVector(rs_points)

            voxel = float(os.environ.get("OAKD_REALSENSE_OPEN3D_VOXEL_M", "0.045"))
            max_corr = float(os.environ.get("OAKD_REALSENSE_OPEN3D_MAX_CORR_M", str(voxel * 2.5)))

            def preprocess(pcd):
                down = pcd.voxel_down_sample(voxel)
                if len(down.points) < 100:
                    down = pcd
                down.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 2.5, max_nn=30))
                fpfh = o3d.pipelines.registration.compute_fpfh_feature(
                    down,
                    o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 5.0, max_nn=100),
                )
                return down, fpfh

            source_down, source_fpfh = preprocess(source)
            target_down, target_fpfh = preprocess(target)
            if len(source_down.points) < 100 or len(target_down.points) < 100:
                status = f"Open3D alignment failed: downsample too sparse OAK={len(source_down.points)} RS={len(target_down.points)}"
                write_oakd_alignment_result(result_path, "open3d", False, status)
                print(f">>> OAK-D/RealSense {status} <<<")
                return

            global_result = o3d.pipelines.registration.registration_ransac_based_on_feature_matching(
                source_down,
                target_down,
                source_fpfh,
                target_fpfh,
                True,
                max_corr,
                o3d.pipelines.registration.TransformationEstimationPointToPoint(False),
                4,
                [
                    o3d.pipelines.registration.CorrespondenceCheckerBasedOnEdgeLength(0.9),
                    o3d.pipelines.registration.CorrespondenceCheckerBasedOnDistance(max_corr),
                ],
                o3d.pipelines.registration.RANSACConvergenceCriteria(40000, 0.999),
            )
            init = np.asarray(global_result.transformation, dtype=np.float64)
            target_down.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 2.5, max_nn=30))
            try:
                icp = o3d.pipelines.registration.registration_icp(
                    source_down,
                    target_down,
                    max_corr,
                    init,
                    o3d.pipelines.registration.TransformationEstimationPointToPlane(),
                    o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=80),
                )
            except Exception:
                icp = o3d.pipelines.registration.registration_icp(
                    source_down,
                    target_down,
                    max_corr,
                    init,
                    o3d.pipelines.registration.TransformationEstimationPointToPoint(),
                    o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=80),
                )
            transform = np.asarray(icp.transformation, dtype=np.float64)
            status = (
                "Open3D applied | source=OAK target=RealSense "
                f"global_fitness={float(global_result.fitness):.3f} "
                f"ICP_fitness={float(icp.fitness):.3f} rmse={float(icp.inlier_rmse):.3f} "
                f"pts OAK={oak_points.shape[0]} RS={rs_points.shape[0]} down OAK={len(source_down.points)} RS={len(target_down.points)}"
            )
            write_oakd_alignment_result(
                result_path,
                "open3d",
                True,
                status,
                transform,
                {
                    "global_fitness": float(global_result.fitness),
                    "icp_fitness": float(icp.fitness),
                    "icp_rmse": float(icp.inlier_rmse),
                    "oak_points": int(oak_points.shape[0]),
                    "rs_points": int(rs_points.shape[0]),
                    "voxel_m": float(voxel),
                },
            )
            print(f">>> OAK-D/RealSense Open3D alignment solved and wrote {result_path or '<no result path>'}: {status} <<<")
        except Exception as exc:
            status = f"Open3D alignment failed: {exc}"
            write_oakd_alignment_result(result_path, "open3d", False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
        finally:
            oakd_realsense_align_lock.release()

    def start_charuco_alignment(result_path):
        nonlocal oakd_realsense_align_thread
        if not oakd_realsense_align_lock.acquire(False):
            status = "ChArUco alignment already running"
            write_oakd_alignment_result(result_path, "charuco", False, status)
            print(f">>> OAK-D/RealSense {status}; ignoring duplicate request. <<<")
            return
        if oakd_capture is None:
            oakd_realsense_align_lock.release()
            status = "ChArUco failed: OAK-D stream is not active"
            print(f">>> OAK-D/RealSense {status} <<<")
            write_oakd_alignment_result(result_path, "charuco", False, status)
            return
        if not isinstance(cap, RealSenseCapture):
            oakd_realsense_align_lock.release()
            status = "ChArUco failed: RealSense stream is not active"
            print(f">>> OAK-D/RealSense {status} <<<")
            write_oakd_alignment_result(result_path, "charuco", False, status)
            return

        oak_color, _oak_depth = oakd_capture.read_latest()
        rs_color, _rs_frame_id = cap.read_latest_color_for_alignment(timeout=0.02)
        if oak_color is None:
            oakd_realsense_align_lock.release()
            status = "ChArUco failed: no latest OAK-D frame"
            print(f">>> OAK-D/RealSense {status} <<<")
            write_oakd_alignment_result(result_path, "charuco", False, status)
            return
        if rs_color is None:
            oakd_realsense_align_lock.release()
            status = "ChArUco failed: no latest RealSense RGB frame"
            print(f">>> OAK-D/RealSense {status} <<<")
            write_oakd_alignment_result(result_path, "charuco", False, status)
            return

        rs_intrinsics = getattr(cap, "charuco_intrinsics", cap.intrinsics)
        oakd_realsense_align_thread = threading.Thread(
            target=_run_charuco_alignment_worker,
            args=(result_path, oakd_capture, cap, oak_color.copy(), rs_color.copy(), rs_intrinsics),
            name="oakd-realsense-charuco-align",
            daemon=True,
        )
        oakd_realsense_align_thread.start()
        print(">>> OAK-D/RealSense ChArUco alignment started in background; live preview/cloud publishing remains active. <<<")

    def start_single_aruco_alignment(result_path, marker_size_m, dictionary_name, marker_id, marker_ids=None, auto_depth_refine=True, min_depth=OAKD_POINT_CLOUD_MIN_DEPTH_M, max_depth=OAKD_POINT_CLOUD_MAX_DEPTH_M, stride=2, requested_method="single_aruco"):
        nonlocal oakd_realsense_align_thread
        requested_method = str(requested_method).strip().lower()
        if requested_method not in ("single_aruco", "big_aruco"):
            requested_method = "single_aruco"
        alignment_label = "big ArUco" if requested_method == "big_aruco" else "single ArUco"
        if not oakd_realsense_align_lock.acquire(False):
            status = f"{alignment_label} alignment already running"
            write_oakd_alignment_result(result_path, requested_method, False, status)
            print(f">>> OAK-D/RealSense {status}; ignoring duplicate request. <<<")
            return
        if marker_size_m <= 0.0:
            marker_size_m = BIG_ARUCO_MARKER_SIZE_M
            print(f">>> OAK-D/RealSense big ArUco marker_size_m was 0; using default {marker_size_m:.4f}m <<<")
        if oakd_capture is None:
            oakd_realsense_align_lock.release()
            status = f"{alignment_label} failed: OAK-D stream is not active"
            write_oakd_alignment_result(result_path, requested_method, False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
            return
        if not isinstance(cap, RealSenseCapture):
            oakd_realsense_align_lock.release()
            status = f"{alignment_label} failed: RealSense stream is not active"
            write_oakd_alignment_result(result_path, requested_method, False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
            return

        oak_color, oak_depth = oakd_capture.read_latest(apply_depth_correction=False)
        rs_color, _rs_frame_id = cap.read_latest_color_for_alignment(timeout=0.02)
        _rs_pc_color, rs_depth, rs_depth_intrinsics = read_realsense_point_cloud_snapshot(cap)
        if oak_color is None or rs_color is None:
            oakd_realsense_align_lock.release()
            status = f"{alignment_label} failed: missing latest OAK-D or RealSense RGB frame"
            write_oakd_alignment_result(result_path, requested_method, False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
            return
        rs_intrinsics = getattr(cap, "charuco_intrinsics", cap.intrinsics)
        oakd_realsense_align_thread = threading.Thread(
            target=_run_single_aruco_alignment_worker,
            args=(
                result_path,
                oakd_capture,
                oak_color.copy(),
                rs_color.copy(),
                rs_intrinsics,
                float(marker_size_m),
                dictionary_name,
                int(marker_id),
                marker_ids,
                bool(auto_depth_refine),
                None if oak_depth is None else oak_depth.copy(),
                None if rs_depth is None else rs_depth.copy(),
                oakd_capture.intrinsics,
                rs_depth_intrinsics,
                float(min_depth),
                float(max_depth),
                max(1, int(stride)),
                requested_method,
            ),
            name=f"oakd-realsense-{requested_method.replace('_', '-')}-align",
            daemon=True,
        )
        oakd_realsense_align_thread.start()
        print(f">>> OAK-D/RealSense {alignment_label} alignment started in background; live preview/cloud publishing remains active. <<<")

    def start_open3d_alignment(result_path, min_depth, max_depth, stride):
        nonlocal oakd_realsense_align_thread
        if not oakd_realsense_align_lock.acquire(False):
            status = "Open3D alignment already running"
            write_oakd_alignment_result(result_path, "open3d", False, status)
            print(f">>> OAK-D/RealSense {status}; ignoring duplicate request. <<<")
            return
        if oakd_capture is None:
            oakd_realsense_align_lock.release()
            status = "Open3D failed: OAK-D stream is not active"
            write_oakd_alignment_result(result_path, "open3d", False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
            return
        if not isinstance(cap, RealSenseCapture):
            oakd_realsense_align_lock.release()
            status = "Open3D failed: RealSense stream is not active"
            write_oakd_alignment_result(result_path, "open3d", False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
            return

        _oak_color, oak_depth = oakd_capture.read_latest()
        _rs_color, rs_depth, rs_intrinsics = read_realsense_point_cloud_snapshot(cap)
        if oak_depth is None or rs_depth is None:
            oakd_realsense_align_lock.release()
            status = "Open3D failed: missing latest OAK-D or RealSense depth frame"
            write_oakd_alignment_result(result_path, "open3d", False, status)
            print(f">>> OAK-D/RealSense {status} <<<")
            return
        oakd_realsense_align_thread = threading.Thread(
            target=_run_open3d_alignment_worker,
            args=(
                result_path,
                oakd_capture,
                cap,
                oak_depth.copy(),
                rs_depth.copy(),
                oakd_capture.intrinsics,
                rs_intrinsics,
                float(min_depth),
                float(max_depth),
                max(1, int(stride)),
            ),
            name="oakd-realsense-open3d-align",
            daemon=True,
        )
        oakd_realsense_align_thread.start()
        print(">>> OAK-D/RealSense Open3D point-cloud alignment started in background; live preview/cloud publishing remains active. <<<")

    def _start_oakd_capture_worker(signature, settings):
        nonlocal oakd_capture, oakd_starting, oakd_next_start_time
        try:
            capture = OakDCapture(
                width=settings["width"],
                height=settings["height"],
                fps=settings["fps"],
                rgb_res=settings["rgb_res"],
                mono_res=settings["mono_res"],
                preset=settings["preset"],
                lr_check=settings["lr_check"],
                subpixel=settings["subpixel"],
                subpixel_bits=settings["subpixel_bits"],
                confidence_threshold=settings["confidence_threshold"],
                median_filter=settings["median_filter"],
                speckle_filter=settings["speckle_filter"],
                speckle_range=settings["speckle_range"],
                depth_source=settings.get("depth_source", "depthai"),
                fast_stereo_iters=settings.get("fast_stereo_iters", 4),
                fast_stereo_scale=settings.get("fast_stereo_scale", 1.0),
                fast_stereo_torch_compile=settings.get("fast_stereo_torch_compile", False),
                fast_stereo_backend=settings.get("fast_stereo_backend", "pytorch"),
                fast_stereo_model_profile=settings.get("fast_stereo_model_profile", "full_320x736_i4"),
                use_rgb_color_for_host_depth=settings.get("use_rgb_color_for_host_depth", True),
                host_depth_color_mode=settings.get("host_depth_color_mode", "rgb_projected_stable"),
            )
            capture.settings_signature = signature
            oakd_capture = capture
            oakd_next_start_time = 0.0
            _start_oakd_publisher_if_needed()
        except Exception as exc:
            oakd_capture = None
            oakd_next_start_time = time.time() + 5.0
            print(f">>> OAK-D unavailable: {exc} <<<")
        finally:
            oakd_starting = False

    def ensure_oakd_capture(enabled):
        nonlocal oakd_capture, oakd_point_cloud_shared_memory
        nonlocal oakd_publisher_thread, oakd_publisher_stop_event
        nonlocal oakd_start_thread, oakd_starting, oakd_next_start_time
        nonlocal last_oakd_point_cloud_frame_serial
        if not enabled:
            _stop_oakd_publisher()
            if oakd_capture is not None:
                print(
                    ">>> OAK-D point cloud publishing paused; keeping DepthAI device open "
                    "to avoid the Windows native close crash. Restart the stack to fully release/rebuild OAK-D. <<<"
                )
            if oakd_point_cloud_shared_memory is not None:
                oakd_point_cloud_shared_memory.close()
                oakd_point_cloud_shared_memory = None
            oakd_starting = False
            return
        if oakd_point_cloud_shared_memory is None:
            oakd_point_cloud_shared_memory = LatestGridSharedMemory(OAKD_POINT_CLOUD_SHM_NAME, label="OAK-D point cloud")
        signature = _oakd_settings_signature()
        if oakd_capture is not None and bool(getattr(oakd_capture, "device_error", False)):
            reason = str(getattr(oakd_capture, "device_error_message", "stream queue closed"))
            print(
                f">>> OAK-D capture marked unhealthy after DepthAI stream error: {reason}. "
                "Dropping the stale capture object and retrying after a short backoff. <<<"
            )
            oakd_capture = None
            last_oakd_point_cloud_frame_serial = 0
            oakd_next_start_time = max(oakd_next_start_time, time.time() + 2.0)
        if oakd_capture is not None and getattr(oakd_capture, "settings_signature", None) == signature:
            ok, reason = oakd_capture.set_depth_source(
                oakd_point_cloud_settings.get("depth_source", "depthai"),
                fast_stereo_iters=oakd_point_cloud_settings.get("fast_stereo_iters", 4),
                fast_stereo_scale=oakd_point_cloud_settings.get("fast_stereo_scale", 1.0),
                fast_stereo_torch_compile=oakd_point_cloud_settings.get("fast_stereo_torch_compile", False),
                fast_stereo_backend=oakd_point_cloud_settings.get("fast_stereo_backend", "pytorch"),
                fast_stereo_model_profile=oakd_point_cloud_settings.get("fast_stereo_model_profile", "full_320x736_i4"),
            )
            if not ok:
                print(f">>> OAK-D live depth-source switch unavailable: {reason}. Restart the stack only if you need this source from a host-only pipeline. <<<")
            oakd_capture.apply_runtime_settings(oakd_point_cloud_settings)
            _start_oakd_publisher_if_needed()
            return
        if oakd_starting:
            return
        if oakd_capture is not None:
            ok, reason = oakd_capture.set_depth_source(
                oakd_point_cloud_settings.get("depth_source", "depthai"),
                fast_stereo_iters=oakd_point_cloud_settings.get("fast_stereo_iters", 4),
                fast_stereo_scale=oakd_point_cloud_settings.get("fast_stereo_scale", 1.0),
                fast_stereo_torch_compile=oakd_point_cloud_settings.get("fast_stereo_torch_compile", False),
                fast_stereo_backend=oakd_point_cloud_settings.get("fast_stereo_backend", "pytorch"),
                fast_stereo_model_profile=oakd_point_cloud_settings.get("fast_stereo_model_profile", "full_320x736_i4"),
            )
            if not ok:
                print(f">>> OAK-D live depth-source switch unavailable while rebuild is deferred: {reason}. <<<")
            oakd_capture.apply_runtime_settings(oakd_point_cloud_settings)
            previous_deferred = getattr(oakd_capture, "restart_deferred_signature", None)
            if previous_deferred != signature:
                oakd_capture.restart_deferred_signature = signature
                active_source = getattr(oakd_capture, "depth_source", "depthai")
                requested_source = str(oakd_point_cloud_settings.get("depth_source", "depthai")).strip().lower()
                source_note = ""
                if active_source != requested_source:
                    source_note = f" active_source={active_source}, requested_source={requested_source}."
                print(
                    ">>> OAK-D setting change received while capture is live; "
                    "restart deferred to avoid DepthAI native close crash. "
                    "Live-safe depth source/iters/scale/compile were still applied when possible. "
                    "Restart the stack only to apply OAK-D width/fps/mono/preset/lr/subpixel changes."
                    f"{source_note} <<<"
                )
            _start_oakd_publisher_if_needed()
            return
        settings = dict(oakd_point_cloud_settings)
        settings["fps"] = min(60.0, max(1.0, float(settings["fps"])))
        if time.time() < oakd_next_start_time:
            return
        oakd_next_start_time = time.time() + 5.0
        print(
            f">>> Starting OAK-D point cloud capture in background: "
            f"{settings['width']}x{settings['height']} {settings['fps']:.0f}fps mono={settings['mono_res']} "
            f"subpixel={'on' if settings['subpixel'] else 'off'} "
            f"depth_source={settings.get('depth_source', 'depthai')} <<<"
        )
        oakd_starting = True
        oakd_start_thread = threading.Thread(target=_start_oakd_capture_worker, args=(signature, settings), name="oakd-start", daemon=True)
        oakd_start_thread.start()

    def broadcast_oakd_point_cloud():
        nonlocal last_oakd_point_cloud_send_time, oakd_point_cloud_frame_id
        nonlocal oakd_point_cloud_send_counter, oakd_point_cloud_last_fps_print_time, last_oakd_point_cloud_frame_serial
        if not oakd_publish_lock.acquire(False):
            return
        try:
            if not oakd_point_cloud_enabled:
                return
            if oakd_capture is None or oakd_point_cloud_shared_memory is None:
                return
            now = time.time()
            if now - last_oakd_point_cloud_send_time <= point_cloud_effective_send_interval("oakd"):
                return
            sensor_age_ms = 0.0
            color_age_ms = 0.0
            sensor_host_age_ms = 0.0
            color_host_age_ms = 0.0
            if hasattr(oakd_capture, "read_latest_with_serial"):
                result = oakd_capture.read_latest_with_serial()
                if len(result) >= 8:
                    color, depth_m, frame_serial, frame_time, sensor_age_ms, color_age_ms, sensor_host_age_ms, color_host_age_ms = result
                elif len(result) >= 6:
                    color, depth_m, frame_serial, frame_time, sensor_age_ms, color_age_ms = result
                else:
                    color, depth_m, frame_serial, frame_time = result
            else:
                color, depth_m = oakd_capture.read_latest()
                frame_serial = 0
                frame_time = 0.0
            if color is None or depth_m is None:
                return
            if frame_serial > 0 and frame_serial == last_oakd_point_cloud_frame_serial:
                return

            stride = max(1, int(oakd_point_cloud_stride))
            min_depth = float(oakd_point_cloud_min_depth)
            max_depth = float(oakd_point_cloud_max_depth)
            rows = np.arange(0, depth_m.shape[0], stride, dtype=np.int32)
            cols = np.arange(0, depth_m.shape[1], stride, dtype=np.int32)
            sampled_depth = depth_m[np.ix_(rows, cols)]
            valid = np.isfinite(sampled_depth) & (sampled_depth >= min_depth) & (sampled_depth <= max_depth)
            valid_count = int(valid.sum())
            if valid_count <= 0:
                return

            grid_depth = sampled_depth.astype("<f4", copy=True)
            grid_depth[~valid] = 0.0
            if color.shape[:2] != depth_m.shape[:2]:
                color = cv2.resize(color, (depth_m.shape[1], depth_m.shape[0]), interpolation=cv2.INTER_LINEAR)
            sampled_color_grid = color[np.ix_(rows, cols)]
            if oakd_point_cloud_shm_color_format == "bgr":
                shm_color = sampled_color_grid
                shm_color_format = "bgr"
            else:
                grid_rgba = np.empty((sampled_color_grid.shape[0], sampled_color_grid.shape[1], 4), dtype=np.uint8)
                grid_rgba[:, :, 0] = sampled_color_grid[:, :, 2]
                grid_rgba[:, :, 1] = sampled_color_grid[:, :, 1]
                grid_rgba[:, :, 2] = sampled_color_grid[:, :, 0]
                grid_rgba[:, :, 3] = np.where(valid, 255, 0).astype(np.uint8)
                shm_color = grid_rgba
                shm_color_format = "rgba"
            grid_h, grid_w = grid_depth.shape
            oakd_point_cloud_frame_id = (oakd_point_cloud_frame_id + 1) & 0xFFFFFFFF
            if oakd_point_cloud_shared_memory.publish_grid(
                oakd_point_cloud_frame_id,
                grid_depth,
                shm_color,
                stride,
                oakd_capture.intrinsics,
                shm_color_format,
            ):
                publish_fps = 1.0 / max(0.001, now - last_oakd_point_cloud_send_time)
                last_oakd_point_cloud_send_time = now
                last_oakd_point_cloud_frame_serial = int(frame_serial)
                oakd_point_cloud_send_counter += 1
                valid_pct = 100.0 * float(valid_count) / max(1.0, float(valid.size))
                update_point_cloud_stats(
                    "oakd",
                    enabled=True,
                    publish_fps=float(publish_fps),
                    capture_fps=float(getattr(oakd_capture, "capture_fps", 0.0)),
                    points=int(valid_count),
                    valid_pct=float(valid_pct),
                    width=int(grid_w),
                    height=int(grid_h),
                    stride=int(stride),
                    source=str(getattr(oakd_capture, "depth_source", oakd_point_cloud_settings.get("depth_source", "depthai"))),
                    frame_age_ms=float((time.perf_counter() - frame_time) * 1000.0) if frame_time else 0.0,
                    sensor_age_ms=float(sensor_age_ms),
                    color_age_ms=float(color_age_ms),
                    sensor_host_age_ms=float(sensor_host_age_ms),
                    color_host_age_ms=float(color_host_age_ms),
                    fast_backend=str(getattr(oakd_capture, "fast_stereo_backend", oakd_point_cloud_settings.get("fast_stereo_backend", ""))),
                    fast_profile=str(getattr(oakd_capture, "fast_stereo_model_profile", oakd_point_cloud_settings.get("fast_stereo_model_profile", ""))),
                    fast_timing_ms=dict(getattr(getattr(oakd_capture, "fast_foundation_worker", None), "timing_ms", {}) or {}),
                )
                if point_cloud_console_stats and now - oakd_point_cloud_last_fps_print_time >= 2.0:
                    elapsed = now - oakd_point_cloud_last_fps_print_time
                    print(
                        f">>> OAK-D point cloud shm publish: "
                        f"{oakd_point_cloud_send_counter / max(0.001, elapsed):.1f}fps, "
                        f"{grid_w}x{grid_h} cells, points={valid_count}, valid={valid_pct:.0f}%, capture={oakd_capture.capture_fps:.1f}fps, "
                        f"name={OAKD_POINT_CLOUD_SHM_NAME} <<<"
                    )
                    oakd_point_cloud_send_counter = 0
                    oakd_point_cloud_last_fps_print_time = now
        finally:
            oakd_publish_lock.release()

    def reset_spatial_map():
        nonlocal global_origin_id, smoothed_T_cam
        print(">>> WIPING SPATIAL MAP RE-INITIALIZING <<<")
        global_transforms.clear()
        global_anchor_transforms.clear()
        global_origin_id = None
        rendered_screen_centers.clear()
        screen_trackers.clear()
        anchor_trackers.clear()
        smoothed_T_cam = None

    def active_anchor_pose_mode():
        return ANCHOR_POSE_MODES[anchor_pose_mode_index]

    def cycle_anchor_pose_mode():
        nonlocal anchor_pose_mode_index
        anchor_pose_mode_index = (anchor_pose_mode_index + 1) % len(ANCHOR_POSE_MODES)
        mode = active_anchor_pose_mode()
        print(f">>> Anchor landmark mode: {ANCHOR_POSE_MODE_LABELS.get(mode, mode)} <<<")

    def draw_anchor_pose_mode_button(frame):
        nonlocal tracker_anchor_button_rect
        mode = active_anchor_pose_mode()
        label = f"{ANCHOR_POSE_MODE_BUTTON_LABEL}: {ANCHOR_POSE_MODE_LABELS.get(mode, mode)}"
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.62
        thickness = 2
        text_size, _ = cv2.getTextSize(label, font, font_scale, thickness)
        pad_x = 12
        pad_y = 9
        x2 = frame.shape[1] - 18
        y1 = 18
        x1 = max(10, x2 - text_size[0] - pad_x * 2)
        y2 = y1 + text_size[1] + pad_y * 2
        tracker_anchor_button_rect = (x1, y1, x2, y2)
        color = (45, 45, 45)
        if mode == "stable":
            color = (30, 95, 70)
        elif mode == "raw":
            color = (50, 75, 120)
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, -1)
        cv2.rectangle(frame, (x1, y1), (x2, y2), (235, 235, 235), 1)
        cv2.putText(
            frame,
            label,
            (x1 + pad_x, y2 - pad_y - 1),
            font,
            font_scale,
            (255, 255, 255),
            thickness,
            cv2.LINE_AA,
        )

    def tracker_mouse_callback(event, x, y, flags, param):
        if event != cv2.EVENT_LBUTTONDOWN or tracker_anchor_button_rect is None:
            return
        x1, y1, x2, y2 = tracker_anchor_button_rect
        if x1 <= x <= x2 and y1 <= y <= y2:
            cycle_anchor_pose_mode()

    def configure_active_calibration():
        nonlocal camera_matrix, dist_coeffs, stored_calibration_size
        camera_matrix = None
        dist_coeffs = None

        if stored_camera_matrix is None or stored_dist_coeffs is None:
            return

        if active_capture_width <= 0 or active_capture_height <= 0:
            return

        calib_size = stored_calibration_size
        inferred_size = False
        if calib_size is None:
            calib_size = infer_calibration_size(stored_camera_matrix)
            inferred_size = True

        if calib_size is None:
            print(">>> Stored camera calibration has no usable image size. Recalibrate at the active capture mode. <<<")
            return

        calib_width, calib_height = calib_size
        current_aspect = active_capture_width / float(active_capture_height)
        calib_aspect = calib_width / float(calib_height)
        aspect_delta = abs(current_aspect - calib_aspect)

        if aspect_delta > 0.02:
            print(
                f">>> Stored calibration {calib_width}x{calib_height} is incompatible with active capture "
                f"{active_capture_width}x{active_capture_height} (aspect mismatch). Recalibrate this camera mode. <<<"
            )
            return

        scale_x = active_capture_width / float(calib_width)
        scale_y = active_capture_height / float(calib_height)
        scaled_camera_matrix = stored_camera_matrix.copy().astype(np.float32)
        scaled_camera_matrix[0, 0] *= scale_x
        scaled_camera_matrix[0, 2] *= scale_x
        scaled_camera_matrix[1, 1] *= scale_y
        scaled_camera_matrix[1, 2] *= scale_y
        camera_matrix = scaled_camera_matrix
        dist_coeffs = stored_dist_coeffs.copy().astype(np.float32)

        qualifier = "inferred-size " if inferred_size else ""
        print(
            f">>> Applied {qualifier}camera calibration from {calib_width}x{calib_height} "
            f"to active capture {active_capture_width}x{active_capture_height}. <<<"
        )

    def use_approximate_active_intrinsics():
        nonlocal camera_matrix, dist_coeffs
        if active_capture_width <= 0 or active_capture_height <= 0:
            return
        focal = float(max(active_capture_width, active_capture_height))
        camera_matrix = np.array(
            [
                [focal, 0.0, active_capture_width * 0.5],
                [0.0, focal, active_capture_height * 0.5],
                [0.0, 0.0, 1.0],
            ],
            dtype=np.float32,
        )
        dist_coeffs = np.zeros((5, 1), dtype=np.float32)
        print(
            f">>> Using approximate webcam intrinsics for {active_capture_width}x{active_capture_height}; "
            "layout scanning remains available. <<<"
        )

    def open_camera():
        nonlocal active_capture_width, active_capture_height, active_camera_index, camera_matrix, dist_coeffs

        backends = get_camera_backends()

        if active_camera_source == CAMERA_SOURCE_REALSENSE:
            if rs is None:
                print(">>> RealSense selected but pyrealsense2 is not installed. <<<")
                return None
            capture = None
            last_exc = None
            candidates = [
                (
                    REALSENSE_DEPTH_WIDTH,
                    REALSENSE_DEPTH_HEIGHT,
                    REALSENSE_CAMERA_FPS,
                    REALSENSE_COLOR_WIDTH,
                    REALSENSE_COLOR_HEIGHT,
                    REALSENSE_COLOR_FPS,
                    "requested",
                ),
                (
                    REALSENSE_DEPTH_WIDTH,
                    REALSENSE_DEPTH_HEIGHT,
                    REALSENSE_CAMERA_FPS,
                    REALSENSE_DEPTH_WIDTH,
                    REALSENSE_DEPTH_HEIGHT,
                    REALSENSE_CAMERA_FPS,
                    "same-res 60fps fallback",
                ),
                (
                    REALSENSE_DEPTH_WIDTH,
                    REALSENSE_DEPTH_HEIGHT,
                    30,
                    REALSENSE_COLOR_WIDTH,
                    REALSENSE_COLOR_HEIGHT,
                    min(REALSENSE_COLOR_FPS, 30),
                    "30fps high-color fallback",
                ),
                (
                    REALSENSE_DEPTH_WIDTH,
                    REALSENSE_DEPTH_HEIGHT,
                    30,
                    REALSENSE_DEPTH_WIDTH,
                    REALSENSE_DEPTH_HEIGHT,
                    30,
                    "30fps same-res fallback",
                ),
            ]
            seen_profiles = set()
            for depth_w, depth_h, depth_fps, color_w, color_h, color_fps, label in candidates:
                profile_key = (depth_w, depth_h, depth_fps, color_w, color_h, color_fps)
                if profile_key in seen_profiles:
                    continue
                seen_profiles.add(profile_key)
                try:
                    capture = RealSenseCapture(
                        width=depth_w,
                        height=depth_h,
                        fps=depth_fps,
                        tracking_mode=active_realsense_tracking_mode,
                        tracking_enabled=active_realsense_tracking_enabled,
                        color_width=color_w,
                        color_height=color_h,
                        color_fps=color_fps,
                    )
                    if label != "requested":
                        print(
                            f">>> RealSense using {label}: color {color_w}x{color_h}@{color_fps}, "
                            f"depth {depth_w}x{depth_h}@{depth_fps}. <<<"
                        )
                    break
                except Exception as exc:
                    last_exc = exc
                    print(
                        f">>> RealSense profile rejected ({label}): color {color_w}x{color_h}@{color_fps}, "
                        f"depth {depth_w}x{depth_h}@{depth_fps}: {exc} <<<"
                    )
            if capture is None:
                print(f">>> RealSense unavailable: {last_exc} <<<")
                return None
            active_camera_index = None
            active_capture_width = capture.width
            active_capture_height = capture.height
            camera_matrix = capture.get_camera_matrix()
            dist_coeffs = capture.get_dist_coeffs()
            print(
                f">>> RealSense RGB+depth source active at {active_capture_width}x{active_capture_height}"
                f" color, depth {capture.depth_width}x{capture.depth_height}"
                f" @ depth {capture.fps}fps color {capture.color_fps}fps. Head tracking: {'ON' if capture.tracking_enabled else 'OFF'}. <<<"
            )
            return capture

        forced_index = os.environ.get(CAMERA_INDEX_ENV, "").strip()
        if forced_index != "":
            try:
                active_camera_index = int(forced_index)
            except ValueError:
                active_camera_index = None
        if active_camera_index is None:
            active_camera_index = CAMERA_INDEX_DEFAULT

        capture = None
        if active_camera_index is not None:
            capture = open_capture_for_index(active_camera_index, backends)
        if capture is None:
            best_index, _ = select_best_camera_index(backends)
            active_camera_index = best_index
            if active_camera_index is not None:
                capture = open_capture_for_index(active_camera_index, backends)
        if capture is None:
            active_camera_index = None

        if capture is None:
            print(">>> Webcam unavailable. Tracker will keep running without it. Press 'v' to retry. <<<")
            return None

        if hasattr(cv2, "CAP_PROP_FOURCC"):
            capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        if hasattr(cv2, "CAP_PROP_FPS"):
            capture.set(cv2.CAP_PROP_FPS, PREFERRED_CAMERA_FPS)
        if hasattr(cv2, "CAP_PROP_BUFFERSIZE"):
            capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        best_mode = get_capture_dimensions(capture)
        best_score = camera_mode_score(*best_mode)

        for width, height in PREFERRED_CAMERA_MODES:
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            actual_mode = get_capture_dimensions(capture)
            actual_score = camera_mode_score(*actual_mode)
            if actual_score > best_score:
                best_mode = actual_mode
                best_score = actual_score

        if best_mode[0] > 0 and best_mode[1] > 0:
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, best_mode[0])
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, best_mode[1])

        active_capture_width, active_capture_height = get_capture_dimensions(capture)
        configure_active_calibration()
        if camera_matrix is None and not CAMERA_AUTO_CALIBRATE_INTRINSICS:
            use_approximate_active_intrinsics()
        idx_label = active_camera_index if active_camera_index is not None else "unknown"
        print(
            f">>> Webcam[{idx_label}] capture active at {active_capture_width}x{active_capture_height}"
            f" @ target {PREFERRED_CAMERA_FPS}fps. <<<"
        )
        return capture

    def switch_camera_index(delta):
        nonlocal active_camera_index, camera_paused, cap
        prev_index = active_camera_index
        prev_cap = cap

        if active_camera_index is None:
            active_camera_index = 0
        else:
            active_camera_index = (active_camera_index + delta) % CAMERA_INDEX_AUTO_MAX

        release_camera()
        os.environ[CAMERA_INDEX_ENV] = str(active_camera_index)
        cap_local = open_camera()
        if cap_local is None:
            # restore previous camera if the new one fails
            active_camera_index = prev_index
            if active_camera_index is not None:
                os.environ[CAMERA_INDEX_ENV] = str(active_camera_index)
            cap_local = prev_cap
            if cap_local is None and active_camera_index is not None:
                cap_local = open_camera()
            if cap_local is None:
                camera_paused = True
                print(">>> Camera switch failed; staying paused. <<<")
                return None

        camera_paused = False
        return cap_local

    def switch_camera_to_index(target_index):
        nonlocal active_camera_index, camera_paused, cap
        prev_index = active_camera_index
        prev_cap = cap

        if target_index is None:
            return prev_cap

        release_camera()
        active_camera_index = int(target_index)
        os.environ[CAMERA_INDEX_ENV] = str(active_camera_index)
        cap_local = open_camera()
        if cap_local is None:
            active_camera_index = prev_index
            if active_camera_index is not None:
                os.environ[CAMERA_INDEX_ENV] = str(active_camera_index)
            cap_local = prev_cap
            if cap_local is None and active_camera_index is not None:
                cap_local = open_camera()
            if cap_local is None:
                camera_paused = True
                print(">>> Camera switch failed; staying paused. <<<")
                return None

        camera_paused = False
        return cap_local

    def open_camera_picker():
        nonlocal cap, active_camera_source
        backends = get_camera_backends()
        print(">>> Probing available cameras for selection... <<<")
        active_mode = None
        if active_capture_width > 0 and active_capture_height > 0:
            active_mode = (active_capture_width, active_capture_height)
        candidates = probe_camera_candidates(backends, active_camera_index, active_mode)
        chosen_index = pick_camera_index_in_terminal(candidates, active_camera_index)
        if chosen_index is None:
            return
        active_camera_source = CAMERA_SOURCE_WEBCAM
        os.environ[CAMERA_SOURCE_ENV] = active_camera_source
        cap = switch_camera_to_index(chosen_index)

    def release_camera():
        nonlocal cap, active_capture_width, active_capture_height, active_camera_index
        if cap is not None:
            cap.release()
            cap = None
        active_capture_width = 0
        active_capture_height = 0
        active_camera_index = None

    def set_camera_paused(paused):
        nonlocal cap, camera_paused
        if paused:
            release_camera()
            camera_paused = True
            print(">>> Webcam capture released. Tracker and bridge remain active. Press 'v' to reacquire. <<<")
            return

        cap = open_camera()
        camera_paused = cap is None
        if not camera_paused:
            print(">>> Webcam capture reacquired. <<<")

    def toggle_camera_source():
        nonlocal active_camera_source, cap, camera_paused
        release_camera()
        active_camera_source = CAMERA_SOURCE_REALSENSE if active_camera_source == CAMERA_SOURCE_WEBCAM else CAMERA_SOURCE_WEBCAM
        os.environ[CAMERA_SOURCE_ENV] = active_camera_source
        print(f">>> Camera source switched to {active_camera_source}. <<<")
        cap = open_camera()
        camera_paused = cap is None

    def mouse_callback(event, x, y, flags, param):
        nonlocal view_pitch, view_yaw, view_dist, view_pan_x, view_pan_y, mouse_is_down, pan_is_down, last_mouse_x, last_mouse_y, last_pan_x, last_pan_y, global_origin_id
        global global_transforms
        if event == cv2.EVENT_LBUTTONDOWN:
            mouse_is_down = True
            last_mouse_x = x
            last_mouse_y = y
        elif event == cv2.EVENT_LBUTTONUP:
            mouse_is_down = False
        elif event == cv2.EVENT_MBUTTONDOWN:
            pan_is_down = True
            last_pan_x = x
            last_pan_y = y
        elif event == cv2.EVENT_MBUTTONUP:
            pan_is_down = False
        elif event == cv2.EVENT_MOUSEWHEEL:
            if flags > 0:
                view_dist -= 15.0 # Zoom in
            else:
                view_dist += 15.0 # Zoom out
            view_dist = max(5.0, view_dist)
        elif event == cv2.EVENT_RBUTTONDOWN or event == cv2.EVENT_LBUTTONDBLCLK:
            for s_id, pt in rendered_screen_centers:
                if (x - pt[0])**2 + (y - pt[1])**2 < 40**2:
                    if s_id in global_transforms:
                        print(f"[*] USER DELETED Screen {s_id} from Spatial Map!")
                        del global_transforms[s_id]
                        if s_id == global_origin_id:
                            print("[!] Global Origin Deleted! Wiping entire Spatial Map!")
                            global_origin_id = None
                            global_transforms = {}
                        break
        elif event == cv2.EVENT_MOUSEMOVE:
            if mouse_is_down:
                dx = x - last_mouse_x
                dy = y - last_mouse_y
                view_yaw -= dx * 0.5
                view_pitch += dy * 0.5
                view_pitch = max(-89.0, min(89.0, view_pitch))
                last_mouse_x = x
                last_mouse_y = y
            elif pan_is_down:
                dx = x - last_pan_x
                dy = y - last_pan_y
                pan_scale = view_dist / 600.0 # Scale pan speed relative to zoom level
                view_pan_x -= dx * pan_scale * 5.0
                view_pan_y -= dy * pan_scale * 5.0
                last_pan_x = x
                last_pan_y = y

    cv2.namedWindow(TRACKER_WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.namedWindow(ROOM_MAP_WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(TRACKER_WINDOW_NAME, TRACKER_WINDOW_DEFAULT_WIDTH, TRACKER_WINDOW_DEFAULT_HEIGHT)
    cv2.resizeWindow(ROOM_MAP_WINDOW_NAME, ROOM_MAP_WINDOW_DEFAULT_WIDTH, ROOM_MAP_WINDOW_DEFAULT_HEIGHT)
    cv2.moveWindow(ROOM_MAP_WINDOW_NAME, WINDOW_DEFAULT_X, WINDOW_DEFAULT_Y)
    cv2.moveWindow(
        TRACKER_WINDOW_NAME,
        WINDOW_DEFAULT_X + ROOM_MAP_WINDOW_DEFAULT_WIDTH + WINDOW_DEFAULT_GAP,
        WINDOW_DEFAULT_Y,
    )
    cv2.setMouseCallback(TRACKER_WINDOW_NAME, tracker_mouse_callback)
    cv2.setMouseCallback(ROOM_MAP_WINDOW_NAME, mouse_callback)
    cap = open_camera()
    camera_paused = cap is None

    while True:
        capture_loop_frame_count += 1
        now_for_capture_fps = time.perf_counter()
        if now_for_capture_fps - capture_loop_last_fps_time >= 0.5:
            capture_loop_fps = capture_loop_frame_count / (now_for_capture_fps - capture_loop_last_fps_time)
            capture_loop_frame_count = 0
            capture_loop_last_fps_time = now_for_capture_fps

        try:
            while True:
                cmd_data, _ = command_sock.recvfrom(65535)
                cmd_json = json.loads(cmd_data.decode("utf-8"))
                cmd_type = cmd_json.get("type")
                if cmd_type == "reset_spatial_map":
                    reset_spatial_map()
                    scan_locked_state = False
                    layout_calibration_active = True
                    locked_tracking_reference = None
                    locked_tracking_reference_origin = ""
                    latest_live_tracking_pose = None
                    latest_live_tracking_time = 0.0
                elif cmd_type == "pause_camera_capture":
                    set_camera_paused(True)
                elif cmd_type == "resume_camera_capture":
                    set_camera_paused(False)
                elif cmd_type == "toggle_camera_capture":
                    set_camera_paused(not camera_paused)
                elif cmd_type == "scan_lock_state":
                    scan_locked_state = bool(cmd_json.get("locked", False))
                    reason = str(cmd_json.get("reason", ""))
                    if scan_locked_state:
                        layout_calibration_active = False
                    elif reason in ("register_screen", "rescan_layout"):
                        layout_calibration_active = True
                    locked_tracking_reference = transform_from_payload(cmd_json.get("tracking_reference"))
                    locked_tracking_reference_origin = normalize_screen_id(
                        (cmd_json.get("tracking_reference") or {}).get("origin_screen", "")
                    )
                    if not scan_locked_state:
                        locked_tracking_reference = None
                        locked_tracking_reference_origin = ""
                elif cmd_type == "calibration_mode_state":
                    layout_calibration_active = bool(cmd_json.get("active", False))
                    if layout_calibration_active:
                        scan_locked_state = False
                elif cmd_type == "live_tracking_pose":
                    if bool(cmd_json.get("active", True)):
                        latest_live_tracking_pose = {
                            "x": float(cmd_json.get("x", 0.0)),
                            "y": float(cmd_json.get("y", 0.0)),
                            "z": float(cmd_json.get("z", 0.0)),
                            "yaw": float(cmd_json.get("yaw", 0.0)),
                            "pitch": float(cmd_json.get("pitch", 0.0)),
                            "roll": float(cmd_json.get("roll", 0.0)),
                        }
                        latest_live_tracking_time = time.time()
                    else:
                        latest_live_tracking_pose = None
                        latest_live_tracking_time = 0.0
                elif cmd_type == "realsense_point_cloud":
                    point_cloud_stats_path = str(cmd_json.get("stats_path", point_cloud_stats_path)).strip()
                    point_cloud_console_stats = bool(cmd_json.get("console_stats", point_cloud_console_stats))
                    point_cloud_sync_to_slowest = bool(cmd_json.get("sync_to_slowest", point_cloud_sync_to_slowest))
                    realsense_point_cloud_enabled = bool(cmd_json.get("enabled", False))
                    realsense_point_cloud_stride = max(1, int(cmd_json.get("stride", realsense_point_cloud_stride)))
                    realsense_point_cloud_min_depth = float(cmd_json.get("min_depth", realsense_point_cloud_min_depth))
                    realsense_point_cloud_max_depth = float(cmd_json.get("max_depth", realsense_point_cloud_max_depth))
                    realsense_point_cloud_max_points = max(0, int(cmd_json.get("max_points", realsense_point_cloud_max_points)))
                    realsense_point_cloud_mesh_enabled = bool(cmd_json.get("mesh_enabled", realsense_point_cloud_mesh_enabled))
                    realsense_point_cloud_mesh_mode = str(cmd_json.get("mesh_mode", realsense_point_cloud_mesh_mode)).strip().lower()
                    if realsense_point_cloud_mesh_mode not in ("gpu_grid", "gpu_points", "stereo_cpu", "stereo_gpu"):
                        realsense_point_cloud_mesh_mode = "gpu_grid"
                    realsense_point_cloud_mesh_max_edge = float(cmd_json.get("mesh_max_edge", realsense_point_cloud_mesh_max_edge))
                    realsense_point_cloud_packet_points = max(1, int(cmd_json.get("packet_points", realsense_point_cloud_packet_points)))
                    realsense_point_cloud_transport = str(cmd_json.get("transport", realsense_point_cloud_transport)).strip().lower()
                    if realsense_point_cloud_transport not in ("udp", "tcp", "shm"):
                        realsense_point_cloud_transport = "udp"
                    realsense_point_cloud_shm_color_format = str(cmd_json.get("shm_color_format", realsense_point_cloud_shm_color_format)).strip().lower()
                    if realsense_point_cloud_shm_color_format not in ("rgba", "rgb", "bgr"):
                        realsense_point_cloud_shm_color_format = "rgba"
                    if isinstance(cap, RealSenseCapture):
                        cap.apply_runtime_settings({
                            "depth_filters_enabled": bool(cmd_json.get("rs_depth_filters_enabled", cap.depth_filters_enabled)),
                            "disparity_filters_enabled": bool(cmd_json.get("rs_disparity_filters_enabled", cap.disparity_filters_enabled)),
                            "spatial_alpha": float(cmd_json.get("rs_spatial_alpha", cap.depth_spatial_alpha)),
                            "spatial_delta": float(cmd_json.get("rs_spatial_delta", cap.depth_spatial_delta)),
                            "temporal_alpha": float(cmd_json.get("rs_temporal_alpha", cap.depth_temporal_alpha)),
                            "temporal_delta": float(cmd_json.get("rs_temporal_delta", cap.depth_temporal_delta)),
                            "hole_filling": int(cmd_json.get("rs_hole_filling", cap.depth_hole_filling)),
                            "filters_for_point_cloud_geometry": bool(cmd_json.get("rs_filters_for_point_cloud_geometry", cap.filters_for_point_cloud_geometry)),
                            "filter_geometry_edge_guard_m": float(cmd_json.get("rs_filter_geometry_edge_guard_m", cap.filter_geometry_edge_guard_m)),
                            "visual_preset": int(cmd_json.get("rs_visual_preset", -1)),
                            "emitter_enabled": int(cmd_json.get("rs_emitter_enabled", -1)),
                            "laser_power": float(cmd_json.get("rs_laser_power", -1)),
                            "color_auto_exposure": int(cmd_json.get("rs_color_auto_exposure", -1)),
                            "color_exposure": float(cmd_json.get("rs_color_exposure", -1)),
                            "color_gain": float(cmd_json.get("rs_color_gain", -1)),
                            "color_auto_white_balance": int(cmd_json.get("rs_color_auto_white_balance", -1)),
                            "color_white_balance": float(cmd_json.get("rs_color_white_balance", -1)),
                        })
                    realsense_point_cloud_waiting_warned = False
                    update_point_cloud_stats("realsense", enabled=bool(realsense_point_cloud_enabled))
                    print(
                        ">>> RealSense point cloud stream "
                        f"{'enabled' if realsense_point_cloud_enabled else 'disabled'} "
                        f"stride={realsense_point_cloud_stride} "
                        f"depth={realsense_point_cloud_min_depth:.2f}-{realsense_point_cloud_max_depth:.2f}m "
                        f"max_points={realsense_point_cloud_max_points or 'unlimited'} "
                        f"mesh={'on' if realsense_point_cloud_mesh_enabled else 'off'} "
                        f"mesh_mode={realsense_point_cloud_mesh_mode} "
                        f"sync_to_slowest={'on' if point_cloud_sync_to_slowest else 'off'} "
                        f"packet_points={realsense_point_cloud_packet_points} "
                        f"transport={realsense_point_cloud_transport} "
                        f"shm_color={realsense_point_cloud_shm_color_format} <<<"
                    )
                elif cmd_type == "oakd_point_cloud":
                    point_cloud_stats_path = str(cmd_json.get("stats_path", point_cloud_stats_path)).strip()
                    point_cloud_console_stats = bool(cmd_json.get("console_stats", point_cloud_console_stats))
                    point_cloud_sync_to_slowest = bool(cmd_json.get("sync_to_slowest", point_cloud_sync_to_slowest))
                    oakd_point_cloud_enabled = bool(cmd_json.get("enabled", False))
                    oakd_point_cloud_stride = max(1, int(cmd_json.get("stride", oakd_point_cloud_stride)))
                    oakd_point_cloud_min_depth = float(cmd_json.get("min_depth", oakd_point_cloud_min_depth))
                    oakd_point_cloud_max_depth = float(cmd_json.get("max_depth", oakd_point_cloud_max_depth))
                    oakd_point_cloud_shm_color_format = str(cmd_json.get("shm_color_format", oakd_point_cloud_shm_color_format)).strip().lower()
                    if oakd_point_cloud_shm_color_format not in ("rgba", "rgb", "bgr"):
                        oakd_point_cloud_shm_color_format = "rgba"
                    oakd_point_cloud_settings.update({
                        "width": max(160, int(cmd_json.get("oakd_width", oakd_point_cloud_settings["width"]))),
                        "height": max(120, int(cmd_json.get("oakd_height", oakd_point_cloud_settings["height"]))),
                        "fps": min(60.0, max(1.0, float(cmd_json.get("oakd_fps", oakd_point_cloud_settings["fps"])))),
                        "rgb_res": str(cmd_json.get("oakd_rgb_res", oakd_point_cloud_settings["rgb_res"])).strip().lower(),
                        "use_rgb_color_for_host_depth": bool(cmd_json.get("oakd_use_rgb_color_for_host_depth", oakd_point_cloud_settings.get("use_rgb_color_for_host_depth", True))),
                        "host_depth_color_mode": str(cmd_json.get("oakd_host_depth_color_mode", oakd_point_cloud_settings.get("host_depth_color_mode", "rgb_projected_stable"))).strip().lower(),
                        "mono_res": str(cmd_json.get("oakd_mono_res", oakd_point_cloud_settings["mono_res"])).strip().lower(),
                        "preset": str(cmd_json.get("oakd_stereo_preset", oakd_point_cloud_settings["preset"])).strip().lower(),
                        "lr_check": bool(cmd_json.get("oakd_lr_check", oakd_point_cloud_settings["lr_check"])),
                        "subpixel": bool(cmd_json.get("oakd_subpixel", oakd_point_cloud_settings["subpixel"])),
                        "subpixel_bits": max(3, min(5, int(cmd_json.get("oakd_subpixel_bits", oakd_point_cloud_settings["subpixel_bits"])))),
                        "confidence_threshold": max(0, min(255, int(cmd_json.get("oakd_confidence_threshold", oakd_point_cloud_settings["confidence_threshold"])))),
                        "median_filter": str(cmd_json.get("oakd_median_filter", oakd_point_cloud_settings["median_filter"])).strip().lower(),
                        "speckle_filter": bool(cmd_json.get("oakd_speckle_filter", oakd_point_cloud_settings["speckle_filter"])),
                        "speckle_range": max(0, int(cmd_json.get("oakd_speckle_range", oakd_point_cloud_settings["speckle_range"]))),
                        "depth_source": str(cmd_json.get("oakd_depth_source", oakd_point_cloud_settings.get("depth_source", "depthai"))).strip().lower(),
                        "fast_stereo_enabled": bool(cmd_json.get("oakd_fast_stereo_enabled", oakd_point_cloud_settings.get("fast_stereo_enabled", False))),
                        "fast_stereo_iters": max(1, min(32, int(cmd_json.get("oakd_fast_stereo_iters", oakd_point_cloud_settings.get("fast_stereo_iters", 4))))),
                        "fast_stereo_scale": max(0.25, min(1.0, float(cmd_json.get("oakd_fast_stereo_scale", oakd_point_cloud_settings.get("fast_stereo_scale", 1.0))))),
                        "fast_stereo_torch_compile": bool(cmd_json.get("oakd_fast_stereo_torch_compile", oakd_point_cloud_settings.get("fast_stereo_torch_compile", False))),
                        "fast_stereo_backend": str(cmd_json.get("oakd_fast_stereo_backend", oakd_point_cloud_settings.get("fast_stereo_backend", "pytorch"))).strip().lower(),
                        "fast_stereo_model_profile": str(cmd_json.get("oakd_fast_stereo_model_profile", oakd_point_cloud_settings.get("fast_stereo_model_profile", "full_320x736_i4"))).strip().lower(),
                    })
                    if oakd_point_cloud_settings["depth_source"] not in ("depthai", "fast_foundation", "host_sgbm"):
                        oakd_point_cloud_settings["depth_source"] = "depthai"
                    if oakd_point_cloud_settings["fast_stereo_backend"] not in ("pytorch", "onnx_trt", "onnx_cuda", "trt_engine"):
                        oakd_point_cloud_settings["fast_stereo_backend"] = "pytorch"
                    if oakd_point_cloud_settings["fast_stereo_model_profile"] not in FAST_FOUNDATION_MODEL_PROFILES:
                        oakd_point_cloud_settings["fast_stereo_model_profile"] = "full_320x736_i4"
                    if oakd_point_cloud_settings["host_depth_color_mode"] not in ("gray", "rgb_preview", "rgb_projected", "rgb_projected_stable"):
                        oakd_point_cloud_settings["host_depth_color_mode"] = "rgb_projected_stable"
                    if not oakd_point_cloud_settings.get("use_rgb_color_for_host_depth", True):
                        oakd_point_cloud_settings["host_depth_color_mode"] = "gray"
                    if oakd_point_cloud_settings["depth_source"] == "depthai" and not oakd_point_cloud_settings["lr_check"]:
                        oakd_point_cloud_settings["lr_check"] = True
                        print(
                            ">>> OAK-D forcing lr_check=on for DepthAI RGB/CENTER depth alignment. "
                            "DepthAI rejects depthAlign with lr_check=off. <<<"
                        )
                    if oakd_point_cloud_settings["depth_source"] == "fast_foundation":
                        print(
                            ">>> OAK-D FastFoundation source requested from Godot. "
                            "Using NVIDIA FastFoundationStereo GPU depth; live switch is attempted when the running OAK-D pipeline has rectified mono queues. <<<"
                        )
                    ensure_oakd_capture(oakd_point_cloud_enabled)
                    update_point_cloud_stats("oakd", enabled=bool(oakd_point_cloud_enabled), source=str(oakd_point_cloud_settings["depth_source"]))
                    if oakd_capture is not None and getattr(oakd_capture, "settings_signature", None) == _oakd_settings_signature():
                        oakd_capture.apply_runtime_settings(oakd_point_cloud_settings)
                    source_label = "depthai_on_device"
                    active_oakd_source = getattr(oakd_capture, "depth_source", oakd_point_cloud_settings["depth_source"]) if oakd_capture is not None else oakd_point_cloud_settings["depth_source"]
                    if active_oakd_source == "fast_foundation":
                        source_label = "fast_foundation_gpu"
                    elif active_oakd_source == "host_sgbm":
                        source_label = "host_sgbm_local"
                    print(
                        ">>> OAK-D point cloud stream "
                        f"{'enabled' if oakd_point_cloud_enabled else 'disabled'} "
                        f"stride={oakd_point_cloud_stride} "
                        f"depth={oakd_point_cloud_min_depth:.2f}-{oakd_point_cloud_max_depth:.2f}m "
                        f"{oakd_point_cloud_settings['width']}x{oakd_point_cloud_settings['height']} "
                        f"{oakd_point_cloud_settings['fps']:.0f}fps "
                        f"mono={oakd_point_cloud_settings['mono_res']} "
                        f"subpixel={'on' if oakd_point_cloud_settings['subpixel'] else 'off'} "
                        f"conf={oakd_point_cloud_settings['confidence_threshold']} "
                        f"speckle={'on' if oakd_point_cloud_settings['speckle_filter'] else 'off'}:{oakd_point_cloud_settings['speckle_range']} "
                        f"source={source_label} "
                        f"fast_backend={oakd_point_cloud_settings['fast_stereo_backend']} "
                        f"fast_profile={oakd_point_cloud_settings['fast_stereo_model_profile']} "
                        f"fast_iters={oakd_point_cloud_settings['fast_stereo_iters']} "
                        f"fast_compile={'on' if oakd_point_cloud_settings['fast_stereo_torch_compile'] else 'off'} "
                        f"host_color={oakd_point_cloud_settings.get('host_depth_color_mode', 'rgb_projected_stable')} "
                        f"sync_to_slowest={'on' if point_cloud_sync_to_slowest else 'off'} "
                        f"shm_color={oakd_point_cloud_shm_color_format} "
                        f"shm={OAKD_POINT_CLOUD_SHM_NAME} <<<"
                    )
                elif cmd_type == "oakd_realsense_align":
                    method = str(cmd_json.get("method", "")).strip().lower()
                    result_path = str(cmd_json.get("result_path", "")).strip()
                    if method not in ("open3d", "charuco", "single_aruco", "big_aruco"):
                        print(f">>> OAK-D/RealSense alignment ignored: unknown method={method!r} <<<")
                        write_oakd_alignment_result(result_path, method, False, f"unknown method={method!r}")
                    elif method == "charuco":
                        start_charuco_alignment(result_path)
                    elif method in ("single_aruco", "big_aruco"):
                        start_single_aruco_alignment(
                            result_path,
                            float(cmd_json.get("marker_size_m", 0.0)),
                            str(cmd_json.get("aruco_dictionary", "auto")),
                            int(cmd_json.get("aruco_marker_id", -1)),
                            cmd_json.get("aruco_marker_ids", None),
                            bool(cmd_json.get("auto_depth_refine", True)),
                            float(cmd_json.get("min_depth", OAKD_POINT_CLOUD_MIN_DEPTH_M)),
                            float(cmd_json.get("max_depth", OAKD_POINT_CLOUD_MAX_DEPTH_M)),
                            max(1, int(cmd_json.get("stride", 2))),
                            method,
                        )
                    else:
                        start_open3d_alignment(
                            result_path,
                            float(cmd_json.get("min_depth", OAKD_POINT_CLOUD_MIN_DEPTH_M)),
                            float(cmd_json.get("max_depth", OAKD_POINT_CLOUD_MAX_DEPTH_M)),
                            max(1, int(cmd_json.get("stride", 1))),
                        )
                elif cmd_type == "realsense_tracking":
                    active_realsense_tracking_enabled = bool(cmd_json.get("enabled", active_realsense_tracking_enabled))
                    os.environ[REALSENSE_TRACKING_ENABLED_ENV] = "1" if active_realsense_tracking_enabled else "0"
                    if isinstance(cap, RealSenseCapture):
                        cap.set_tracking_enabled(active_realsense_tracking_enabled)
                    else:
                        print(f">>> RealSense head tracking set to {'ON' if active_realsense_tracking_enabled else 'OFF'} for the next RealSense capture. <<<")
                elif cmd_type == "realsense_apply_default_settings":
                    settings_path = str(cmd_json.get("path", REALSENSE_DEFAULT_SETTINGS_JSON))
                    if isinstance(cap, RealSenseCapture):
                        cap._apply_advanced_settings_json(settings_path)
                    else:
                        print(f">>> RealSense default settings will apply on next RealSense capture: {settings_path} <<<")
        except BlockingIOError:
            pass
        except Exception as exc:
            print(f"[tracker] Failed to process control command: {exc}")

        current_frame_screens = []
        current_frame_anchors = []
        ids = None
        frame = None
        detection_frame = None

        if camera_paused or cap is None:
            frame = build_status_frame(
                "WEBCAM RELEASED",
                [
                    "The tracker process is still running.",
                    "Bridge and websocket sync are still active.",
                    f"Last capture mode: {active_capture_width}x{active_capture_height}" if active_capture_width and active_capture_height else "Last capture mode: unknown",
                    f"Last camera index: {active_camera_index}" if active_camera_index is not None else "Last camera index: unknown",
                    "Press 'v' to reacquire the webcam when you want to scan again.",
                    "Existing mapped screens are kept in memory until you reset/rescan.",
                ],
            )
        else:
            ret, frame = cap.read()
            if not ret:
                print(">>> Camera read failed. Releasing capture but keeping tracker alive. Press 'v' to retry. <<<")
                set_camera_paused(True)
                frame = build_status_frame(
                    "CAMERA UNAVAILABLE",
                    [
                        "The tracker could not read a frame from the active camera.",
                        f"Last capture mode: {active_capture_width}x{active_capture_height}" if active_capture_width and active_capture_height else "Last capture mode: unknown",
                        f"Last camera index: {active_camera_index}" if active_camera_index is not None else "Last camera index: unknown",
                        "Press 'v' to try opening the active camera again.",
                        "Bridge and websocket sync are still active.",
                    ],
                )
            elif isinstance(cap, RealSenseCapture):
                detection_frame = frame.copy()
                latest_depth_head_position = cap.latest_head_point_m.copy() if cap.latest_head_point_m is not None else None
                latest_depth_head_time = time.time() if latest_depth_head_position is not None else 0.0
                if latest_depth_head_position is not None:
                    broadcast_realsense_tracking_pose(latest_depth_head_position)
                broadcast_realsense_point_cloud(cap)
                cap.draw_head_debug(frame)
            else:
                detection_frame = frame.copy()
            if realsense_point_cloud_enabled and not isinstance(cap, RealSenseCapture) and not realsense_point_cloud_waiting_warned:
                print(">>> RealSense point cloud requested, but active camera source is not RealSense. Press 's' in the tracker window. <<<")
                realsense_point_cloud_waiting_warned = True
        if oakd_capture is None and not oakd_starting:
            ensure_oakd_capture(oakd_point_cloud_enabled)
             
        should_scan_layout_markers = (
            layout_calibration_active
            and not scan_locked_state
            and not camera_paused
            and cap is not None
        )

        if not camera_paused and cap is not None:
            # Continuous ChArUco Auto-Calibration
            if CAMERA_AUTO_CALIBRATE_INTRINSICS and camera_matrix is None:
                # ArUco detection requires grayscale
                clean_frame = detection_frame if detection_frame is not None else frame
                gray = cv2.cvtColor(clean_frame, cv2.COLOR_BGR2GRAY)
                corners, ids, rejected = detector.detectMarkers(gray)
                
                cv2.putText(frame, f"CALIBRATING SENSOR: {len(all_charuco_corners)}/20", (30, 50), 
                            cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3, cv2.LINE_AA)
                cv2.putText(frame, "Please slowly tilt the ChArUco board!", (30, 90), 
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2, cv2.LINE_AA)
                send_scan_status(
                    "camera_calibrating",
                    "Calibrating webcam intrinsics before layout scanning can begin.",
                    accepted_frames=len(all_charuco_corners),
                    target_frames=20
                )
                
                ret, ch_corners, ch_ids = detect_charuco_corners_compat(
                    gray,
                    charuco_board,
                    charuco_detector,
                    detector,
                    charuco_dict,
                    parameters,
                )
                if ch_ids is not None:
                    if ret > 12: # Min 12 corners for a robust sample
                        aruco.drawDetectedCornersCharuco(frame, ch_corners, ch_ids, (0, 0, 255))
                        
                        sig = frame_signature(ch_corners, (frame.shape[1], frame.shape[0]))
                        if time.time() - last_calib_time > 0.5 and len(all_charuco_corners) < 20 and is_diverse(sig, accepted_sigs, 0.14):
                            all_charuco_corners.append(ch_corners)
                            all_charuco_ids.append(ch_ids)
                            accepted_sigs.append(sig)
                            last_calib_time = time.time()
                            print(f"[*] Captured ChArUco Calibration Frame {len(all_charuco_corners)}/20!")
                            
                            # Briefly flash the screen bright green to indicate a successful capture!
                            cv2.rectangle(frame, (0,0), (frame.shape[1], frame.shape[0]), (0, 255, 0), 15)
                            
                            if len(all_charuco_corners) == 20:
                                print(">>> RUNNING CHARUCO CAMERA CALIBRATION! PLEASE WAIT... <<<")
                                cv2.putText(frame, "PROCESSING CALIBRATION...", (30, 150), 
                                            cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 255), 4, cv2.LINE_AA)
                                cv2.imshow(TRACKER_WINDOW_NAME, frame)
                                cv2.waitKey(1) # Force a tiny frame update so they see the text before it hangs!
                                
                                if not hasattr(aruco, "calibrateCameraCharuco"):
                                    print(">>> ChArUco calibration is unavailable in this OpenCV build; using approximate intrinsics. <<<")
                                    use_approximate_active_intrinsics()
                                    all_charuco_corners.clear()
                                    all_charuco_ids.clear()
                                    accepted_sigs.clear()
                                    continue
                                ret_val, temp_cam, temp_dist, _, _ = aruco.calibrateCameraCharuco(all_charuco_corners, all_charuco_ids, charuco_board, gray.shape[::-1], None, None)
                                camera_matrix = temp_cam
                                dist_coeffs = temp_dist
                                stored_camera_matrix = temp_cam.copy().astype(np.float32)
                                stored_dist_coeffs = temp_dist.copy().astype(np.float32)
                                stored_calibration_size = (int(gray.shape[1]), int(gray.shape[0]))
                                
                                print(f">>> CALIBRATION COMPLETE! RMS Error: {ret_val} <<<")
                                with open("camera_calibration.json", "w") as f:
                                    json.dump({
                                        "camera_matrix": camera_matrix.tolist(),
                                        "dist_coeffs": dist_coeffs.tolist(),
                                        "image_width": int(gray.shape[1]),
                                        "image_height": int(gray.shape[0])
                                    }, f, indent=4)
                                    
                                print("Saved to camera_calibration.json! Perfect Intrinsics locked in!")
            elif should_scan_layout_markers:
                # We have perfect intrinsics! Immediately undistort the raw webcam feed
                # so the user can visually see the math flattening their curved room!
                clean_frame = detection_frame if detection_frame is not None else frame
                clean_undistorted = cv2.undistort(clean_frame, camera_matrix, dist_coeffs)
                frame = cv2.undistort(frame, camera_matrix, dist_coeffs)
                
                # Now run ArUco detection on the mathematically perfect image!
                gray = cv2.cvtColor(clean_undistorted, cv2.COLOR_BGR2GRAY)
                corners, ids, rejected = detector.detectMarkers(gray)
         
        if ids is not None:
            # 0. Black out the markers to prevent infinite loops from the webcam seeing the screen!
            for i in range(len(ids)):
                cv2.fillPoly(frame, [np.int32(corners[i])], (0, 0, 0))
                
            # 1. Outline every individual marker found
            aruco.drawDetectedMarkers(frame, corners, ids)
            
            ids_list = ids.flatten().tolist()
            anchor_ids = [i for i, id_val in enumerate(ids_list) if id_val in WORLD_ANCHOR_MARKER_IDS]
            
            # 2. Extract our defined layout markers
            center_ids = [i for i, id_val in enumerate(ids_list) if id_val in range(6)]
            
            # 3. Cluster corners to their nearest center ID
            # This allows multiple physical monitors to be tracked simultaneously!
            for c_idx in center_ids:
                c_id = ids_list[c_idx]
                
                base_id = (c_id % 6) * 4 + 10
                tl_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id]
                tr_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id + 1]
                bl_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id + 2]
                br_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id + 3]
                
                # Get the absolute pixel center of the central ArUco marker
                c_center = np.mean(corners[c_idx][0], axis=0)
                # Caluclate the pixel perimeter of the center marker
                c_perimeter = cv2.arcLength(corners[c_idx][0], True)
                
                # Helper function to select the best-matching corner marker near the center marker.
                def get_marker_corners(target_idx_list):
                    if not target_idx_list: return None
                    
                    best_idx = None
                    min_dist_to_center = float('inf')
                    
                    for idx in target_idx_list:
                        pt = np.mean(corners[idx][0], axis=0)
                        
                        pt_perimeter = cv2.arcLength(corners[idx][0], True)
                        if pt_perimeter > c_perimeter * 2.5 or pt_perimeter < c_perimeter * 0.4:
                            continue 
                            
                        dist = np.linalg.norm(c_center - pt)
                        if dist < min_dist_to_center:
                            min_dist_to_center = dist
                            best_idx = idx

                    if min_dist_to_center > c_perimeter * 10.0:
                        return None
                    
                    if best_idx is not None:
                        return corners[best_idx][0].astype(np.float32)
                        
                    return None

                def expand_marker_corner(marker_corners, corner_index):
                    best_pt = marker_corners[corner_index]
                    marker_width = np.linalg.norm(marker_corners[0] - marker_corners[1])
                    godot_pad_pixels = marker_width * 0.15
                    direction_vector = best_pt - c_center
                    norm = np.linalg.norm(direction_vector)
                    if norm <= 1e-6:
                        return best_pt
                    direction_vector = direction_vector / norm
                    return best_pt + (direction_vector * godot_pad_pixels)
                
                tl_marker = get_marker_corners(tl_ids)
                tr_marker = get_marker_corners(tr_ids)
                bl_marker = get_marker_corners(bl_ids)
                br_marker = get_marker_corners(br_ids)
                
                # If we successfully locked onto all 4 corners + center...
                if tl_marker is not None and tr_marker is not None and br_marker is not None and bl_marker is not None:
                    # ---------------------------------------------------------
                    # 3D SPATIAL PROJECTION (DEVICE-SPECIFIC SCALE!)
                    # ---------------------------------------------------------
                    configs = load_screen_configs()
                    str_id = str(c_id)
                    measured_size = None
                    if stereo_screen_size_auto and isinstance(cap, RealSenseCapture):
                        measured_size = cap.measure_screen_size_from_markers(tl_marker, tr_marker, bl_marker, br_marker)
                        if measured_size is not None:
                            previous_size = measured_screen_sizes.get(str_id)
                            if previous_size is None:
                                smooth_size = measured_size
                            else:
                                smooth_size = (
                                    (previous_size[0] * 0.85) + (measured_size[0] * 0.15),
                                    (previous_size[1] * 0.85) + (measured_size[1] * 0.15),
                                )
                            measured_screen_sizes[str_id] = smooth_size
                            configs[str_id] = {
                                "width": float(smooth_size[0]),
                                "height": float(smooth_size[1]),
                                "source": "realsense_stereo",
                            }
                            now = time.time()
                            last_write = measured_screen_size_last_write.get(str_id, 0.0)
                            if now - last_write >= 1.0:
                                save_screen_config(str_id, smooth_size[0], smooth_size[1], "realsense_stereo")
                                broadcast_measured_screen_size(c_id, smooth_size[0], smooth_size[1])
                                measured_screen_size_last_write[str_id] = now
                    
                    if str_id in configs:
                        width_inches = configs[str_id].get("width", 20.9)
                        height_inches = configs[str_id].get("height", 11.7)
                        size_source = configs[str_id].get("source", "manual")

                        shortest_dim = min(width_inches, height_inches)
                        marker_size = shortest_dim * 0.40
                        marker_pad = marker_size * 0.15

                        plane_points = np.array([
                            # Top-left marker: TL, TR, BR, BL
                            [marker_pad, marker_pad],
                            [marker_pad + marker_size, marker_pad],
                            [marker_pad + marker_size, marker_pad + marker_size],
                            [marker_pad, marker_pad + marker_size],
                            # Top-right marker
                            [width_inches - marker_pad - marker_size, marker_pad],
                            [width_inches - marker_pad, marker_pad],
                            [width_inches - marker_pad, marker_pad + marker_size],
                            [width_inches - marker_pad - marker_size, marker_pad + marker_size],
                            # Bottom-left marker
                            [marker_pad, height_inches - marker_pad - marker_size],
                            [marker_pad + marker_size, height_inches - marker_pad - marker_size],
                            [marker_pad + marker_size, height_inches - marker_pad],
                            [marker_pad, height_inches - marker_pad],
                            # Bottom-right marker
                            [width_inches - marker_pad - marker_size, height_inches - marker_pad - marker_size],
                            [width_inches - marker_pad, height_inches - marker_pad - marker_size],
                            [width_inches - marker_pad, height_inches - marker_pad],
                            [width_inches - marker_pad - marker_size, height_inches - marker_pad],
                        ], dtype=np.float32)

                        image_points_h = np.vstack([
                            tl_marker,
                            tr_marker,
                            bl_marker,
                            br_marker,
                        ]).astype(np.float32)

                        homography, _ = cv2.findHomography(plane_points, image_points_h, 0)

                        if homography is not None:
                            screen_plane_corners = np.array([
                                [0.0, 0.0],
                                [width_inches, 0.0],
                                [width_inches, height_inches],
                                [0.0, height_inches],
                            ], dtype=np.float32).reshape(1, 4, 2)
                            projected_screen_corners = cv2.perspectiveTransform(screen_plane_corners, homography).reshape(4, 2)
                            tl = projected_screen_corners[0]
                            tr = projected_screen_corners[1]
                            br = projected_screen_corners[2]
                            bl = projected_screen_corners[3]
                        else:
                            tl = expand_marker_corner(tl_marker, 0)
                            tr = expand_marker_corner(tr_marker, 1)
                            bl = expand_marker_corner(bl_marker, 3)
                            br = expand_marker_corner(br_marker, 2)

                        # Construct a polygon defining the physical screen's edge bounds!
                        pts = np.array([tl, tr, br, bl], np.int32)
                        pts = pts.reshape((-1, 1, 2))
                        
                        # Draw a thick green bounding box tracing the perimeter of the physical monitor
                        cv2.polylines(frame, [pts], isClosed=True, color=(0, 255, 0), thickness=3)
                        
                        # Inject a semi-transparent green overlay over the screen
                        overlay = frame.copy()
                        cv2.fillPoly(overlay, [pts], (0, 255, 0))
                        cv2.addWeighted(overlay, 0.2, frame, 0.8, 0, frame)
                        
                        # Render the Device ID prominently above the screen
                        cv2.putText(frame, f"Godot Screen ID: {c_id}", (int(tl[0]), int(tl[1] - 15)), 
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2, cv2.LINE_AA)
                        
                        # Dynamically declare the 3D dimensions of THIS precise screen!
                        w2 = width_inches / 2.0
                        h2 = height_inches / 2.0
                        object_points = np.array([
                            [-w2, -h2, 0],
                            [ w2, -h2, 0],
                            [ w2,  h2, 0],
                            [-w2,  h2, 0]
                        ], dtype=np.float32)
                        
                        # Check if we have real perfectly calibrated intrinsics
                        if camera_matrix is not None:
                            cam_mat_use = camera_matrix
                            dist_use = np.zeros((5, 1), dtype=np.float32) # Undistorted
                            pnp_flags = cv2.SOLVEPNP_IPPE
                        else:
                            # Fake Intrinsics Matrix
                            focal_length = frame.shape[1]
                            center_pt = (frame.shape[1] / 2.0, frame.shape[0] / 2.0)
                            cam_mat_use = np.array([
                                [focal_length, 0, center_pt[0]],
                                [0, focal_length, center_pt[1]],
                                [0, 0, 1]
                            ], dtype=np.float32)
                            dist_use = np.zeros((5, 1), dtype=np.float32)
                            pnp_flags = cv2.SOLVEPNP_ITERATIVE
                            
                        image_points = np.array([tl, tr, br, bl], dtype=np.float32)
                        
                        # TEMPORAL LOCKING: Prevent Necker Flipping by anchoring to the last known pose!
                        tracker = screen_trackers.get(c_id)
                        use_guess = False
                        r_guess, t_guess = None, None
                        if tracker is not None and camera_matrix is not None:
                            r_guess = tracker["rvec"].copy()
                            t_guess = tracker["tvec"].copy()
                            use_guess = True
                            pnp_flags = cv2.SOLVEPNP_ITERATIVE

                        # Project 2D pixels into Physical Space!
                        if use_guess:
                            success, rvec, tvec = cv2.solvePnP(object_points, image_points, cam_mat_use, dist_use, 
                                                               rvec=r_guess, tvec=t_guess,
                                                               useExtrinsicGuess=True, flags=pnp_flags)
                        else:
                            success, rvec, tvec = cv2.solvePnP(object_points, image_points, cam_mat_use, dist_use, flags=pnp_flags)
                        
                        if success:
                            screen_trackers[c_id] = {"rvec": rvec, "tvec": tvec}
                            # Draw full 3D coordinate axes relative to the unique screen size!
                            # Shrunk axis length so OpenCV stops warning about lines extending off-screen!
                            axis_length = float(width_inches * 0.2)
                            cv2.drawFrameAxes(frame, cam_mat_use, dist_use, rvec, tvec, axis_length, 2)
                            
                            dist_inches = np.linalg.norm(tvec)
                            cv2.putText(frame, f"Dist: {dist_inches:.1f}\"", (int(tl[0]), int(tl[1] - 40)), 
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2, cv2.LINE_AA)
                            cv2.putText(frame, f"Size: {width_inches}\"x{height_inches}\"", (int(tl[0]), int(tl[1] - 65)), 
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 1, cv2.LINE_AA)
                            if size_source == "realsense_stereo":
                                cv2.putText(frame, "Stereo measured size", (int(tl[0]), int(tl[1] - 90)),
                                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 255), 1, cv2.LINE_AA)
                            
                            # Save to current frame array for SLAM graph chaining
                            current_frame_screens.append({
                                "screen_id": int(c_id),
                                "width": width_inches,
                                "height": height_inches,
                                "rvec": rvec,
                                "tvec": tvec
                            })
                    else:
                        cv2.putText(frame, "[?] Uncalibrated Screen Size", (int(tl[0]), int(tl[1] - 40)), 
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2, cv2.LINE_AA)

            # 4. Detect reserved world-anchor markers without feeding them into screen stitching.
            anchor_half = WORLD_ANCHOR_MARKER_SIZE_INCHES / 2.0
            anchor_object_points = np.array([
                [-anchor_half, -anchor_half, 0.0],
                [ anchor_half, -anchor_half, 0.0],
                [ anchor_half,  anchor_half, 0.0],
                [-anchor_half,  anchor_half, 0.0],
            ], dtype=np.float32)

            for anchor_idx in anchor_ids:
                anchor_id = int(ids_list[anchor_idx])
                anchor_corners = corners[anchor_idx][0].astype(np.float32)

                if camera_matrix is not None:
                    cam_mat_use = camera_matrix
                    dist_use = np.zeros((5, 1), dtype=np.float32)
                    pnp_flags = cv2.SOLVEPNP_IPPE
                else:
                    focal_length = frame.shape[1]
                    center_pt = (frame.shape[1] / 2.0, frame.shape[0] / 2.0)
                    cam_mat_use = np.array([
                        [focal_length, 0, center_pt[0]],
                        [0, focal_length, center_pt[1]],
                        [0, 0, 1]
                    ], dtype=np.float32)
                    dist_use = np.zeros((5, 1), dtype=np.float32)
                    pnp_flags = cv2.SOLVEPNP_ITERATIVE

                tracker = anchor_trackers.get(anchor_id)
                use_guess = False
                r_guess, t_guess = None, None
                if tracker is not None and camera_matrix is not None:
                    mode = active_anchor_pose_mode()
                    guess_age = time.time() - float(tracker.get("last_seen", 0.0))
                    if mode == "smooth" or guess_age <= ANCHOR_POSE_GUESS_TIMEOUT_SEC:
                        r_guess = tracker["rvec"].copy()
                        t_guess = tracker["tvec"].copy()
                        use_guess = True
                        pnp_flags = cv2.SOLVEPNP_ITERATIVE

                if use_guess:
                    success, rvec, tvec = cv2.solvePnP(
                        anchor_object_points,
                        anchor_corners,
                        cam_mat_use,
                        dist_use,
                        rvec=r_guess,
                        tvec=t_guess,
                        useExtrinsicGuess=True,
                        flags=pnp_flags,
                    )
                else:
                    success, rvec, tvec = cv2.solvePnP(
                        anchor_object_points,
                        anchor_corners,
                        cam_mat_use,
                        dist_use,
                        flags=pnp_flags,
                    )

                if success:
                    anchor_trackers[anchor_id] = {
                        "rvec": rvec,
                        "tvec": tvec,
                        "last_seen": time.time(),
                    }
                    anchor_dist_inches = float(np.linalg.norm(tvec))
                    cv2.drawFrameAxes(frame, cam_mat_use, dist_use, rvec, tvec, WORLD_ANCHOR_MARKER_SIZE_INCHES * 0.35, 2)
                    label_pos = anchor_corners[0].astype(np.int32)
                    cv2.putText(
                        frame,
                        f"World Anchor {anchor_id}",
                        (int(label_pos[0]), int(label_pos[1] - 16)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.65,
                        (0, 215, 255),
                        2,
                        cv2.LINE_AA,
                    )
                    cv2.putText(
                        frame,
                        f'{WORLD_ANCHOR_MARKER_SIZE_INCHES:.1f}" square | {anchor_dist_inches:.1f}"',
                        (int(label_pos[0]), int(label_pos[1] - 40)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        (0, 215, 255),
                        2,
                        cv2.LINE_AA,
                    )
                    current_frame_anchors.append({
                        "anchor_id": anchor_id,
                        "size": WORLD_ANCHOR_MARKER_SIZE_INCHES,
                        "rvec": rvec,
                        "tvec": tvec,
                    })

        # ---------------------------------------------------------
        # SPATIAL GRAPH MAPPING (SLAM)
        # ---------------------------------------------------------
        T_origin_to_cam = None
        
        if current_frame_screens:
            # Case 1: The map is completely empty. We must set the first screen we see as the Origin.
            if global_origin_id is None:
                first_screen = current_frame_screens[0]
                global_origin_id = first_screen["screen_id"]
                # The "Origin" Screen defines the absolute center (0,0,0) of the virtual room.
                global_transforms[global_origin_id] = {
                    "transform": np.eye(4, dtype=np.float32),
                    "width": first_screen["width"],
                    "height": first_screen["height"]
                }
                print(f"[{global_origin_id}] locked as the Global Graph Origin.")

        # Localization: Where is the camera?
        # Prefer a known screen, otherwise fall back to a known world anchor.
        known_screen = None
        if current_frame_screens:
            # Prioritize the global origin if it's visible to eliminate chaining drift
            for s in current_frame_screens:
                if s["screen_id"] == global_origin_id:
                    known_screen = s
                    break

            # Fallback to any other known screen if the origin isn't visible
            if known_screen is None:
                for s in current_frame_screens:
                    if s["screen_id"] in global_transforms:
                        known_screen = s
                        break

        known_anchor = None
        if known_screen is None and current_frame_anchors:
            for a in current_frame_anchors:
                if a["anchor_id"] in global_anchor_transforms:
                    known_anchor = a
                    break

        if known_screen is not None or known_anchor is not None:
            # Calculate Camera Position relative to the Origin
            if known_screen is not None:
                T_cam_to_known = create_transform_matrix(known_screen["rvec"], known_screen["tvec"])
                T_origin_to_known = global_transforms[known_screen["screen_id"]]["transform"]
            else:
                T_cam_to_known = create_transform_matrix(known_anchor["rvec"], known_anchor["tvec"])
                T_origin_to_known = global_anchor_transforms[known_anchor["anchor_id"]]["transform"]

            # Equation: T_origin_to_known = T_origin_to_cam * T_cam_to_known
            # Therefore: T_origin_to_cam = T_origin_to_known * (T_cam_to_known)^(-1)
            raw_T_cam = T_origin_to_known @ np.linalg.inv(T_cam_to_known)

            # --- Exponential Moving Average (EMA) Smoothing ---
            if smoothed_T_cam is None:
                smoothed_T_cam = raw_T_cam.copy()
            else:
                alpha_t = 0.25 # Translation smoothing speed (1.0 = instant, 0.01 = glacial)
                alpha_r = 0.15 # Rotation smoothing speed

                # Smooth Translation
                smoothed_T_cam[:3, 3] = (alpha_t * raw_T_cam[:3, 3]) + ((1.0 - alpha_t) * smoothed_T_cam[:3, 3])

                # Smooth Rotation (Simple Matrix LERP with SVD Orthogonalization)
                R_blend = (alpha_r * raw_T_cam[:3, :3]) + ((1.0 - alpha_r) * smoothed_T_cam[:3, :3])
                U, _, Vt = np.linalg.svd(R_blend)
                smoothed_T_cam[:3, :3] = U @ Vt

            T_origin_to_cam = smoothed_T_cam

            # Discovery & Continuous Updating: Map newly seen screens into the Graph, and update existing ones!
            for s in current_frame_screens:
                c_id = s["screen_id"]
                # Do not re-update the position of the screen we are currently using as our anchor!
                # Doing so with a smoothed camera position creates a feedback loop that drags the screen!
                if known_screen is None or c_id != known_screen["screen_id"]:
                    T_cam_to_screen = create_transform_matrix(s["rvec"], s["tvec"])
                    T_origin_to_screen = T_origin_to_cam @ T_cam_to_screen

                    if c_id not in global_transforms:
                        print(f"[{c_id}] mathematical position locked into the Global Graph!")

                    # Continuously update the position of the screen relative to the known camera
                    global_transforms[c_id] = {
                        "transform": T_origin_to_screen,
                        "width": s["width"],
                        "height": s["height"]
                    }

            # Optional world anchors: visible, mappable into the same room space,
            # but intentionally excluded from the screen layout graph and broadcasts.
            # Only update anchor world transforms when the camera pose is backed by a
            # known screen. If we let an anchor-only solve rewrite the anchors, the
            # anchor drags around with the camera instead of staying fixed.
            if known_screen is not None:
                for a in current_frame_anchors:
                    T_cam_to_anchor = create_transform_matrix(a["rvec"], a["tvec"])
                    anchor_mode = active_anchor_pose_mode()
                    anchor_camera_transform = raw_T_cam if anchor_mode in ("stable", "raw") else T_origin_to_cam
                    observed_T_origin_to_anchor = anchor_camera_transform @ T_cam_to_anchor
                    previous_anchor_transform = global_anchor_transforms.get(a["anchor_id"], {}).get("transform")
                    T_origin_to_anchor = observed_T_origin_to_anchor
                    if anchor_mode == "stable":
                        T_origin_to_anchor = blend_transform(
                            previous_anchor_transform,
                            observed_T_origin_to_anchor,
                            ANCHOR_STABLE_BLEND_ALPHA,
                        )
                    global_anchor_transforms[a["anchor_id"]] = {
                        "transform": T_origin_to_anchor,
                        "size": a["size"],
                    }

        # ---------------------------------------------------------
        # 3D ROOM LAYOUT VISUALIZER (INTERACTIVE 3D PERSPECTIVE)
        # ---------------------------------------------------------
        visible_ids = [s["screen_id"] for s in current_frame_screens]
        visible_anchor_ids = [a["anchor_id"] for a in current_frame_anchors]

        if (
            T_origin_to_cam is not None
            and time.time() - last_tracker_pose_send_time > TRACKER_CAMERA_POSE_SEND_INTERVAL_SEC
        ):
            broadcast_tracker_camera_pose(T_origin_to_cam)

        if camera_paused or cap is None:
            send_scan_status(
                "camera_paused",
                "Webcam capture is released. Press 'v' in the tracker window to reacquire it.",
                visible_screens=[],
                mapped_screens=sorted(int(sid) for sid in global_transforms.keys())
            )
        elif camera_matrix is not None:
            if not should_scan_layout_markers:
                mapped_ids = sorted(int(sid) for sid in global_transforms.keys())
                send_scan_status(
                    "layout_ready" if mapped_ids else "idle",
                    "Layout marker scanning is off. Head tracking is live." if mapped_ids else "Layout marker scanning is off.",
                    visible_screens=[],
                    mapped_screens=mapped_ids
                )
            elif not visible_ids:
                mapped_ids = sorted(int(sid) for sid in global_transforms.keys())
                if scan_locked_state and mapped_ids:
                    send_scan_status(
                        "layout_ready",
                        "Layout is locked. Markers are not currently visible.",
                        visible_screens=[],
                        mapped_screens=mapped_ids
                    )
                else:
                    send_scan_status(
                        "waiting_for_markers",
                        "Waiting for the screen marker constellation to become visible.",
                        mapped_screens=mapped_ids
                    )
            else:
                mapped_ids = sorted(int(sid) for sid in global_transforms.keys())
                state = "layout_ready" if mapped_ids else "scanning"
                message = (
                    "Layout solved and streaming."
                    if state == "layout_ready"
                    else "Markers detected. Solving screen poses and mapping the room."
                )
                send_scan_status(
                    state,
                    message,
                    visible_screens=visible_ids,
                    mapped_screens=mapped_ids
                )

            if global_transforms and visible_ids and time.time() - last_layout_send_time > 0.75:
                broadcast_layout()

        tracker_camera_debug_transform = T_origin_to_cam
        if scan_locked_state and locked_tracking_reference is not None:
            origin_matches = (
                locked_tracking_reference_origin == ""
                or global_origin_id is None
                or locked_tracking_reference_origin == normalize_screen_id(global_origin_id)
            )
            if origin_matches:
                tracker_camera_debug_transform = locked_tracking_reference

        debug_head_position = None
        debug_head_forward = None
        if scan_locked_state and global_origin_id is not None:
            debug_head_position = np.array([0.0, 0.0, TRACKING_DEFAULT_HEAD_DISTANCE], dtype=np.float32)
            debug_head_forward = np.array([0.0, 0.0, -1.0], dtype=np.float32)
            realSense_depth_active = (
                active_camera_source == CAMERA_SOURCE_REALSENSE
                and latest_depth_head_position is not None
                and (time.time() - latest_depth_head_time) <= TRACKING_POSE_TIMEOUT_SEC
            )
            if realSense_depth_active:
                depth_offset = (latest_depth_head_position * METERS_TO_WORLD_UNITS).astype(np.float32)
                debug_head_position = depth_offset.copy()
                debug_head_forward = np.array([0.0, 0.0, -1.0], dtype=np.float32)
                origin_matches = (
                    locked_tracking_reference is not None
                    and (
                        locked_tracking_reference_origin == ""
                        or locked_tracking_reference_origin == normalize_screen_id(global_origin_id)
                    )
                )
                if origin_matches:
                    debug_head_position = locked_tracking_reference[:3, 3] + (locked_tracking_reference[:3, :3] @ depth_offset)
                    debug_head_forward = tracking_alignment_rotation(locked_tracking_reference[:3, :3]) @ debug_head_forward
            elif latest_live_tracking_pose is not None and (time.time() - latest_live_tracking_time) <= TRACKING_POSE_TIMEOUT_SEC:
                tracking_offset = np.array(
                    [
                        latest_live_tracking_pose["x"] * CM_TO_WORLD_UNITS * (-1.0 if TRACKING_INVERT_X else 1.0),
                        latest_live_tracking_pose["y"] * CM_TO_WORLD_UNITS * (-1.0 if TRACKING_INVERT_Y else 1.0),
                        latest_live_tracking_pose["z"] * CM_TO_WORLD_UNITS * (-1.0 if TRACKING_INVERT_Z else 1.0),
                    ],
                    dtype=np.float32,
                )
                debug_head_position = tracking_offset.copy()
                head_rotation = opentrack_rotation_matrix(
                    latest_live_tracking_pose["yaw"],
                    latest_live_tracking_pose["pitch"],
                    latest_live_tracking_pose["roll"],
                )
                debug_head_forward = head_rotation @ np.array([0.0, 0.0, -1.0], dtype=np.float32)
                if TRACKING_FORWARD_FLIP:
                    debug_head_forward *= -1.0

                origin_matches = (
                    locked_tracking_reference is not None
                    and (
                        locked_tracking_reference_origin == ""
                        or locked_tracking_reference_origin == normalize_screen_id(global_origin_id)
                    )
                )
                if origin_matches:
                    aligned_position_rotation = tracking_position_alignment_rotation(locked_tracking_reference[:3, :3])
                    debug_head_position = locked_tracking_reference[:3, 3] + (aligned_position_rotation @ tracking_offset)
                    aligned_visual_rotation = tracking_alignment_rotation(locked_tracking_reference[:3, :3])
                    debug_head_forward = aligned_visual_rotation @ debug_head_forward
                else:
                    # Match Godot's fallback live-tracking path: only apply the default
                    # viewer distance when we are not localizing the head through a frozen
                    # off-axis tracking reference. In off-axis mode the reference transform
                    # already defines the tracker-camera relationship to the main screen.
                    debug_head_position[2] += TRACKING_DEFAULT_HEAD_DISTANCE

            forward_norm = float(np.linalg.norm(debug_head_forward))
            if forward_norm > 1e-6:
                debug_head_forward = (debug_head_forward / forward_norm).astype(np.float32)

        if (
            tracker_camera_debug_transform is not None
            and debug_head_position is not None
            and (time.time() - last_resolved_head_pose_send_time) > RESOLVED_HEAD_POSE_SEND_INTERVAL_SEC
        ):
            broadcast_resolved_head_pose(tracker_camera_debug_transform, debug_head_position)

        room_map = np.zeros((800, 800, 3), dtype=np.uint8)
        
        cx, cy = 400, 400
        pitch_rad = np.radians(view_pitch)
        yaw_rad = np.radians(view_yaw)
        
        Rx = np.array([
            [1, 0, 0],
            [0, np.cos(pitch_rad), -np.sin(pitch_rad)],
            [0, np.sin(pitch_rad), np.cos(pitch_rad)]
        ])
        Ry = np.array([
            [np.cos(yaw_rad), 0, np.sin(yaw_rad)],
            [0, 1, 0],
            [-np.sin(yaw_rad), 0, np.cos(yaw_rad)]
        ])
        R_view = Rx @ Ry
        T_view = np.array([view_pan_x, view_pan_y, view_dist])

        def room_map_display_point(pt):
            arr = np.array(pt, dtype=np.float32).copy()
            if ROOM_MAP_FLIP_LIVE_CALIBRATION_CAMERA_Y:
                arr[1] *= -1.0
            return arr

        def room_map_display_vector(vec):
            arr = np.array(vec, dtype=np.float32).copy()
            if ROOM_MAP_FLIP_LIVE_CALIBRATION_CAMERA_Y:
                arr[1] *= -1.0
            return arr

        def room_map_display_transform(transform):
            if transform is None:
                return None
            if not ROOM_MAP_FLIP_LIVE_CALIBRATION_CAMERA_Y:
                return transform
            room_map_y_flip = np.eye(4, dtype=np.float32)
            room_map_y_flip[1, 1] = -1.0
            return room_map_y_flip @ transform

        room_map_head_position = None
        room_map_head_forward = None
        tracker_camera_room_map_transform = room_map_display_transform(tracker_camera_debug_transform)
        if debug_head_position is not None and debug_head_forward is not None:
            room_map_head_position = room_map_display_point(debug_head_position)
            room_map_head_forward = room_map_display_vector(debug_head_forward)

            if (
                latest_live_tracking_pose is not None
                and (time.time() - latest_live_tracking_time) <= TRACKING_POSE_TIMEOUT_SEC
                and tracker_camera_room_map_transform is not None
                and scan_locked_state
            ):
                origin_matches = (
                    locked_tracking_reference is not None
                    and (
                        locked_tracking_reference_origin == ""
                        or locked_tracking_reference_origin == normalize_screen_id(global_origin_id)
                    )
                )
                if origin_matches:
                    tracking_offset = np.array(
                        [
                            latest_live_tracking_pose["x"] * CM_TO_WORLD_UNITS * (-1.0 if TRACKING_INVERT_X else 1.0),
                            latest_live_tracking_pose["y"] * CM_TO_WORLD_UNITS * (-1.0 if TRACKING_INVERT_Y else 1.0),
                            latest_live_tracking_pose["z"] * CM_TO_WORLD_UNITS * (-1.0 if TRACKING_INVERT_Z else 1.0),
                        ],
                        dtype=np.float32,
                    )
                    room_map_aligned_position_rotation = tracking_position_alignment_rotation(
                        tracker_camera_room_map_transform[:3, :3]
                    )
                    room_map_head_position = tracker_camera_room_map_transform[:3, 3] + (
                        room_map_aligned_position_rotation @ tracking_offset
                    )
                    room_map_aligned_visual_rotation = tracking_alignment_rotation(
                        tracker_camera_room_map_transform[:3, :3]
                    )
                    room_map_head_forward = room_map_aligned_visual_rotation @ debug_head_forward

            forward_norm = float(np.linalg.norm(room_map_head_forward))
            if forward_norm > 1e-6:
                room_map_head_forward = (room_map_head_forward / forward_norm).astype(np.float32)
        
        def project_3d(pt3d_global):
            pt_display = room_map_display_point(pt3d_global)
            pt_rotated = R_view @ pt_display[:3]
            pt_translated = pt_rotated + T_view
            z = pt_translated[2]
            if z <= 0.1: z = 0.1
            focal = 600.0
            px = int(cx + (pt_translated[0] * focal) / z)
            py = int(cy + (pt_translated[1] * focal) / z)
            return (px, py), z > 0.1

        def draw_line_3d(img, p1_global, p2_global, color, thickness):
            pt1, ok1 = project_3d(p1_global)
            pt2, ok2 = project_3d(p2_global)
            if ok1 and ok2:
                cv2.line(img, pt1, pt2, color, thickness)
                
        # Draw a faint ground grid
        for i in range(-100, 101, 20):
            draw_line_3d(room_map, np.array([i, 20, -100, 1]), np.array([i, 20, 100, 1]), (40, 40, 40), 1)
            draw_line_3d(room_map, np.array([-100, 20, i, 1]), np.array([100, 20, i, 1]), (40, 40, 40), 1)

        rendered_screen_centers.clear()
        for s_id, s_data in global_transforms.items():
            T = s_data["transform"]
            w2 = s_data["width"] / 2.0
            h2 = s_data["height"] / 2.0
            
            # The physical screen lies on its local X/Y plane
            tl_local = np.array([-w2, -h2, 0, 1])
            tr_local = np.array([ w2, -h2, 0, 1])
            bl_local = np.array([-w2,  h2, 0, 1])
            br_local = np.array([ w2,  h2, 0, 1])
            z_up_local = np.array([0, 0, -5, 1]) # Normal extending out
            
            tl_global = T @ tl_local
            tr_global = T @ tr_local
            bl_global = T @ bl_local
            br_global = T @ br_local
            z_up_global = T @ z_up_local
            center_global = T @ np.array([0,0,0,1])
            
            is_visible = s_id in visible_ids
            color = (0, 255, 0) if is_visible else (150, 150, 150)
            
            # Box
            draw_line_3d(room_map, tl_global, tr_global, color, 2)
            draw_line_3d(room_map, tr_global, br_global, color, 2)
            draw_line_3d(room_map, br_global, bl_global, color, 2)
            draw_line_3d(room_map, bl_global, tl_global, color, 2)
            
            # Diagonal
            draw_line_3d(room_map, tl_global, br_global, color, 1)
            
            # Normal tick
            draw_line_3d(room_map, center_global, z_up_global, (255, 0, 0), 2)
            
            # Draw ID Text
            pt_center, ok = project_3d(center_global)
            if ok:
                rendered_screen_centers.append((s_id, pt_center))
                cv2.circle(room_map, pt_center, 4, color, -1)
                cv2.putText(room_map, f"Screen {s_id}", (max(0, pt_center[0]-30), max(0, pt_center[1]-10)), 
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)
                if show_head_to_camera_debug and tracker_camera_debug_transform is not None:
                    c_pos = tracker_camera_debug_transform[:3, 3]
                    screen_distance_meters = float(np.linalg.norm(center_global[:3] - c_pos)) * 0.0254
                    cv2.putText(
                        room_map,
                        f"{screen_distance_meters:.2f} m",
                        (max(0, pt_center[0] - 22), max(0, pt_center[1] - 28)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.45,
                        (0, 255, 255),
                        1,
                        cv2.LINE_AA,
                    )

        for anchor_id, anchor_data in global_anchor_transforms.items():
            T = anchor_data["transform"]
            half = anchor_data["size"] / 2.0
            tl_local = np.array([-half, -half, 0, 1])
            tr_local = np.array([ half, -half, 0, 1])
            bl_local = np.array([-half,  half, 0, 1])
            br_local = np.array([ half,  half, 0, 1])
            normal_local = np.array([0, 0, -max(half, 2.0), 1])

            tl_global = T @ tl_local
            tr_global = T @ tr_local
            bl_global = T @ bl_local
            br_global = T @ br_local
            normal_global = T @ normal_local
            center_global = T @ np.array([0, 0, 0, 1])

            is_visible = anchor_id in visible_anchor_ids
            color = (0, 215, 255) if is_visible else (90, 120, 140)

            draw_line_3d(room_map, tl_global, tr_global, color, 2)
            draw_line_3d(room_map, tr_global, br_global, color, 2)
            draw_line_3d(room_map, br_global, bl_global, color, 2)
            draw_line_3d(room_map, bl_global, tl_global, color, 2)
            draw_line_3d(room_map, center_global, normal_global, (0, 140, 255), 2)

            pt_center, ok = project_3d(center_global)
            if ok:
                cv2.circle(room_map, pt_center, 4, color, -1)
                cv2.putText(
                    room_map,
                    f"Anchor {anchor_id}",
                    (max(0, pt_center[0] - 32), max(0, pt_center[1] - 10)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    color,
                    1,
                )

        # Draw the tracker camera frustum. After scan lock, prefer the frozen
        # off-axis reference so the room view keeps showing the calibrated
        # tracker-camera pose even when no markers are visible anymore.
        if tracker_camera_room_map_transform is not None:
            c_pos = tracker_camera_room_map_transform[:3, 3]
            c_global = np.array([c_pos[0], c_pos[1], c_pos[2], 1])
            
            pt_c, ok = project_3d(c_global)
            if ok:
                cv2.circle(room_map, pt_c, 6, (255, 120, 0), -1)
                cv2.putText(room_map, "Tracker Cam", (max(0, pt_c[0]+10), max(0, pt_c[1]+10)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 120, 0), 1)
            
            z_forward = tracker_camera_room_map_transform @ np.array([0, 0, 20, 1])
            z_left = tracker_camera_room_map_transform @ np.array([-10, -10, 20, 1])
            z_right = tracker_camera_room_map_transform @ np.array([ 10, -10, 20, 1])
            z_bleft = tracker_camera_room_map_transform @ np.array([-10, 10, 20, 1])
            z_bright = tracker_camera_room_map_transform @ np.array([ 10, 10, 20, 1])
            
            c_color = (255, 120, 0)
            draw_line_3d(room_map, c_global, z_left, c_color, 1)
            draw_line_3d(room_map, c_global, z_right, c_color, 1)
            draw_line_3d(room_map, c_global, z_bleft, c_color, 1)
            draw_line_3d(room_map, c_global, z_bright, c_color, 1)
            
            draw_line_3d(room_map, z_left, z_right, c_color, 1)
            draw_line_3d(room_map, z_right, z_bright, c_color, 1)
            draw_line_3d(room_map, z_bright, z_bleft, c_color, 1)
            draw_line_3d(room_map, z_bleft, z_left, c_color, 1)

        # Draw the virtual viewer head/camera that the Godot clients will use.
        # Before live tracking arrives, keep it at the default 50 cm reference
        # position in front of the primary screen so debugging stays meaningful.
        if room_map_head_position is not None and room_map_head_forward is not None:
            head_global = np.array([room_map_head_position[0], room_map_head_position[1], room_map_head_position[2], 1.0], dtype=np.float32)
            pt_head, ok = project_3d(head_global)
            if ok:
                cv2.circle(room_map, pt_head, 6, (255, 0, 255), -1)
                cv2.putText(room_map, "Viewer", (max(0, pt_head[0] + 10), max(0, pt_head[1] + 10)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 255), 1)

            up_vector = np.array([0.0, 1.0, 0.0], dtype=np.float32)
            right_vector = np.cross(room_map_head_forward, up_vector)
            if float(np.linalg.norm(right_vector)) <= 1e-6:
                right_vector = np.array([1.0, 0.0, 0.0], dtype=np.float32)
            right_vector = right_vector / max(float(np.linalg.norm(right_vector)), 1e-6)
            head_up = np.cross(right_vector, room_map_head_forward)
            head_up = head_up / max(float(np.linalg.norm(head_up)), 1e-6)

            cone_length = 14.0
            cone_radius = 6.0
            cone_tip = room_map_head_position + (room_map_head_forward * cone_length)
            cone_left = cone_tip - (right_vector * cone_radius)
            cone_right = cone_tip + (right_vector * cone_radius)
            cone_top = cone_tip + (head_up * (cone_radius * 0.8))

            head_color = (255, 0, 255)
            draw_line_3d(room_map, head_global, np.append(cone_left, 1.0), head_color, 1)
            draw_line_3d(room_map, head_global, np.append(cone_right, 1.0), head_color, 1)
            draw_line_3d(room_map, head_global, np.append(cone_top, 1.0), head_color, 1)
            draw_line_3d(room_map, np.append(cone_left, 1.0), np.append(cone_right, 1.0), head_color, 1)
            draw_line_3d(room_map, np.append(cone_right, 1.0), np.append(cone_top, 1.0), head_color, 1)
            draw_line_3d(room_map, np.append(cone_top, 1.0), np.append(cone_left, 1.0), head_color, 1)

        if show_head_to_camera_debug and tracker_camera_room_map_transform is not None and room_map_head_position is not None:
            c_pos = tracker_camera_room_map_transform[:3, 3]
            head_global = np.array([room_map_head_position[0], room_map_head_position[1], room_map_head_position[2], 1.0], dtype=np.float32)
            cam_global = np.array([c_pos[0], c_pos[1], c_pos[2], 1.0], dtype=np.float32)
            draw_line_3d(room_map, head_global, cam_global, (0, 255, 255), 2)

            distance_world_units = float(np.linalg.norm(room_map_head_position - c_pos))
            distance_meters = distance_world_units * 0.0254
            distance_text = f"Head->Cam: {distance_meters:.3f} m"
            text_size, baseline = cv2.getTextSize(distance_text, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)
            text_x = max(10, room_map.shape[1] - text_size[0] - 18)
            text_y = max(text_size[1] + 10, room_map.shape[0] - 18)
            cv2.putText(
                room_map,
                distance_text,
                (text_x, text_y),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 255, 255),
                2,
                cv2.LINE_AA,
            )

        cam_debug_pos = None
        if tracker_camera_debug_transform is not None:
            cam_debug_pos = room_map_display_point(tracker_camera_debug_transform[:3, 3])
        coord_lines = []
        if cam_debug_pos is not None:
            coord_lines.append(
                "Cam: X %.2f  Y %.2f  Z %.2f" % (
                    float(cam_debug_pos[0]),
                    float(cam_debug_pos[1]),
                    float(cam_debug_pos[2]),
                )
            )
        else:
            coord_lines.append("Cam: n/a")
        if room_map_head_position is not None:
            coord_lines.append(
                "Head: X %.2f  Y %.2f  Z %.2f" % (
                    float(room_map_head_position[0]),
                    float(room_map_head_position[1]),
                    float(room_map_head_position[2]),
                )
            )
        else:
            coord_lines.append("Head: n/a")

        line_sizes = [cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2)[0] for line in coord_lines]
        block_width = max((size[0] for size in line_sizes), default=0)
        x = max(10, room_map.shape[1] - block_width - 18)
        y = 26
        for idx, line in enumerate(coord_lines):
            cv2.putText(
                room_map,
                line,
                (x, y + idx * 24),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (220, 220, 220),
                2,
                cv2.LINE_AA,
            )

        # Output the live webcam feeds
        if active_capture_width > 0 and active_capture_height > 0:
            source_label = active_camera_source
            index_label = f"idx {active_camera_index}" if active_camera_index is not None else "depth"
            line_y = max(28, frame.shape[0] - 20)
            line_step = 27
            draw_outlined_text(
                frame,
                f"Capture: {source_label} {active_capture_width}x{active_capture_height} ({index_label})",
                (24, line_y),
                scale=0.62,
                color=(255, 255, 255),
                thickness=1,
            )
            if isinstance(cap, RealSenseCapture):
                head_debug = cap.get_head_debug()
                yolo_fps = head_debug.get("fps", 0.0)
                tracking_label = "ON" if cap.tracking_enabled else "OFF"
                draw_outlined_text(
                    frame,
                    f"Loop: {capture_loop_fps:.1f}fps | Cam: {cap.capture_fps:.1f}fps | Head: {tracking_label} {cap.tracking_mode.upper()} {yolo_fps:.1f}fps",
                    (24, max(28, line_y - line_step)),
                    scale=0.62,
                    color=(255, 255, 255),
                    thickness=1,
                )
                draw_outlined_text(
                    frame,
                    f"Stereo Size: {'AUTO' if stereo_screen_size_auto else 'MANUAL'} | H toggles",
                    (24, max(28, line_y - line_step * 2)),
                    scale=0.62,
                    color=(255, 255, 255),
                    thickness=1,
                )
        draw_anchor_pose_mode_button(frame)
        cv2.imshow(TRACKER_WINDOW_NAME, frame)
        cv2.imshow(ROOM_MAP_WINDOW_NAME, room_map)
        
        key = cv2.waitKeyEx(1)
        if key == ord('c'):
            print(">>> COMPILING AND BROADCASTING LAYOUT MAP <<<")
            broadcast_layout()
            print("Successfully sent to WebSocket Router!")
        elif key == CAMERA_TOGGLE_KEY:
            set_camera_paused(not camera_paused)
        elif key == CAMERA_PICKER_KEY:
            open_camera_picker()
        elif key == CAMERA_SOURCE_TOGGLE_KEY:
            toggle_camera_source()
        elif key == REALSENSE_TRACKING_MODE_KEY:
            if isinstance(cap, RealSenseCapture):
                active_realsense_tracking_mode = cap.cycle_tracking_mode()
            else:
                print(">>> RealSense tracking mode toggle ignored: active camera source is not RealSense. <<<")
        elif key == REALSENSE_TRACKING_ENABLE_KEY:
            if isinstance(cap, RealSenseCapture):
                active_realsense_tracking_enabled = cap.toggle_tracking_enabled()
                os.environ[REALSENSE_TRACKING_ENABLED_ENV] = "1" if active_realsense_tracking_enabled else "0"
            else:
                active_realsense_tracking_enabled = not active_realsense_tracking_enabled
                os.environ[REALSENSE_TRACKING_ENABLED_ENV] = "1" if active_realsense_tracking_enabled else "0"
                print(f">>> RealSense head tracking default set to {'ON' if active_realsense_tracking_enabled else 'OFF'} for the next RealSense capture. <<<")
        elif key == STEREO_SCREEN_SIZE_TOGGLE_KEY:
            stereo_screen_size_auto = not stereo_screen_size_auto
            os.environ[STEREO_SCREEN_SIZE_AUTO_ENV] = "1" if stereo_screen_size_auto else "0"
            print(f">>> Stereo screen-size auto measurement {'ON' if stereo_screen_size_auto else 'OFF'} <<<")

        # Press 'q' to quit
        if key == ord('q'):
            break
        elif key == HEAD_TO_CAMERA_DEBUG_KEY:
            show_head_to_camera_debug = not show_head_to_camera_debug
            print(f">>> Head-to-camera distance overlay {'ON' if show_head_to_camera_debug else 'OFF'}. <<<")
        elif key == ord('r') or key == ord('g'):
            reset_spatial_map()
        elif key == ord('x'):
            print(">>> CLEARING SENSOR CALIBRATION <<<")
            camera_matrix = None
            dist_coeffs = None
            stored_camera_matrix = None
            stored_dist_coeffs = None
            stored_calibration_size = None
            all_charuco_corners.clear()
            all_charuco_ids.clear()
            accepted_sigs.clear()
            if os.path.exists("camera_calibration.json"):
                os.remove("camera_calibration.json")
            print("Ready to gather new ChArUco frames!")
            
    release_camera()
    bridge_sock.close()
    point_cloud_sock.close()
    if point_cloud_tcp_server is not None:
        point_cloud_tcp_server.close()
    if point_cloud_shared_memory is not None:
        point_cloud_shared_memory.close()
    oakd_publisher_stop_event.set()
    if oakd_publisher_thread is not None:
        oakd_publisher_thread.join(timeout=1.0)
    if oakd_start_thread is not None and oakd_start_thread.is_alive():
        oakd_start_thread.join(timeout=1.0)
    if oakd_point_cloud_shared_memory is not None:
        oakd_point_cloud_shared_memory.close()
    if oakd_capture is not None:
        oakd_capture.release()
    command_sock.close()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
