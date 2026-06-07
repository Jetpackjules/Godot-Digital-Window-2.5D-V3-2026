import argparse
import multiprocessing as mp
import os
import queue
import sys
import time
from pathlib import Path

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")

import cv2
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import oakd_pointcloud_tuner as oak

try:
    import pyrealsense2 as rs
except ImportError:
    rs = None


VIEW_WIN = "OAK-D + RealSense Fusion View"
CTRL_WIN = oak.CTRL_WIN
MODES = ("oak", "realsense", "combined", "raw_realsense")
CHARUCO_SQUARE_M = 0.030
CHARUCO_MARKER_M = 0.022
CHARUCO_DICTIONARIES = (
    ("6x6_250", cv2.aruco.DICT_6X6_250),
    ("4x4_50", cv2.aruco.DICT_4X4_50),
    ("4x4_100", cv2.aruco.DICT_4X4_100),
    ("5x5_100", cv2.aruco.DICT_5X5_100),
    ("5x5_250", cv2.aruco.DICT_5X5_250),
)
CHARUCO_LAYOUTS = ((8, 6), (7, 5), (9, 6), (10, 7), (11, 8), (6, 4))


def charuco_dictionary(dict_id):
    return cv2.aruco.getPredefinedDictionary(dict_id)


def make_charuco_board(squares_x, squares_y, dictionary):
    return cv2.aruco.CharucoBoard(
        (int(squares_x), int(squares_y)),
        CHARUCO_SQUARE_M,
        CHARUCO_MARKER_M,
        dictionary,
    )


def camera_matrix_from_tuple(intrinsics):
    fx, fy, cx, cy = intrinsics
    return np.array([[fx, 0.0, cx], [0.0, fy, cy], [0.0, 0.0, 1.0]], dtype=np.float64)


def camera_matrix_from_rs_intrinsics(intr):
    return np.array(
        [[float(intr.fx), 0.0, float(intr.ppx)], [0.0, float(intr.fy), float(intr.ppy)], [0.0, 0.0, 1.0]],
        dtype=np.float64,
    )


def scale_camera_matrix(camera_matrix, scale):
    scaled = np.asarray(camera_matrix, dtype=np.float64).copy()
    scaled[0, 0] *= float(scale)
    scaled[1, 1] *= float(scale)
    scaled[0, 2] *= float(scale)
    scaled[1, 2] *= float(scale)
    return scaled


def detect_charuco_pose_for_config(gray, camera_matrix, label, dict_name, dict_id, squares_x, squares_y, debug_bgr=None, image_scale=1.0):
    dictionary = charuco_dictionary(dict_id)
    board = make_charuco_board(squares_x, squares_y, dictionary)
    params = cv2.aruco.DetectorParameters()
    params.adaptiveThreshWinSizeMin = 3
    params.adaptiveThreshWinSizeMax = 53
    params.adaptiveThreshWinSizeStep = 4
    params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    if abs(float(image_scale) - 1.0) > 1e-6:
        detect_gray = cv2.resize(gray, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        detect_k = scale_camera_matrix(camera_matrix, image_scale)
        if debug_bgr is not None:
            detect_debug = cv2.resize(debug_bgr, None, fx=float(image_scale), fy=float(image_scale), interpolation=cv2.INTER_CUBIC)
        else:
            detect_debug = None
    else:
        detect_gray = gray
        detect_k = camera_matrix
        detect_debug = debug_bgr
    corners, ids, _rejected = cv2.aruco.detectMarkers(detect_gray, dictionary, parameters=params)
    marker_count = 0 if ids is None else len(ids)
    if detect_debug is not None and ids is not None:
        cv2.aruco.drawDetectedMarkers(detect_debug, corners, ids)
    if ids is None or marker_count < 4:
        return None, f"{label}: {dict_name} {squares_x}x{squares_y} scale={image_scale:g} markers={marker_count}", detect_debug
    _ret, charuco_corners, charuco_ids = cv2.aruco.interpolateCornersCharuco(corners, ids, detect_gray, board, detect_k, None)
    corner_count = 0 if charuco_ids is None else len(charuco_ids)
    if charuco_ids is None or corner_count < 6:
        return None, f"{label}: {dict_name} {squares_x}x{squares_y} scale={image_scale:g} markers={marker_count} corners={corner_count}", detect_debug
    ok, rvec, tvec = cv2.aruco.estimatePoseCharucoBoard(
        charuco_corners,
        charuco_ids,
        board,
        detect_k,
        np.zeros((5, 1), dtype=np.float64),
        None,
        None,
    )
    if not ok:
        return None, f"{label}: {dict_name} {squares_x}x{squares_y} scale={image_scale:g} pose failed corners={corner_count}", detect_debug
    rot, _ = cv2.Rodrigues(rvec)
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rot
    transform[:3, 3] = np.asarray(tvec, dtype=np.float64).reshape(3)
    status = f"{label}: {dict_name} {squares_x}x{squares_y} scale={image_scale:g} markers={marker_count} corners={corner_count}"
    return (transform, dict_name, dict_id, squares_x, squares_y, marker_count, corner_count), status, detect_debug


def detect_charuco_pose(image_bgr_or_gray, camera_matrix, label, preferred_config=None, debug_name=None):
    if image_bgr_or_gray is None:
        return None, f"{label}: no image"
    if image_bgr_or_gray.ndim == 3:
        gray = cv2.cvtColor(image_bgr_or_gray, cv2.COLOR_BGR2GRAY)
        debug_bgr = image_bgr_or_gray.copy()
    else:
        gray = image_bgr_or_gray
        debug_bgr = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    configs = []
    if preferred_config is not None:
        _dict_name, dict_id, squares_x, squares_y = preferred_config
        configs.append((_dict_name, dict_id, squares_x, squares_y))
    for dict_name, dict_id in CHARUCO_DICTIONARIES:
        for squares_x, squares_y in CHARUCO_LAYOUTS:
            cfg = (dict_name, dict_id, squares_x, squares_y)
            if cfg not in configs:
                configs.append(cfg)

    best_status = f"{label}: no configs tried"
    best_score = -1
    best_debug = None
    for dict_name, dict_id, squares_x, squares_y in configs:
        for image_scale in (1.0, 1.5, 2.0, 3.0, 4.0):
            attempt_debug = debug_bgr.copy()
            pose_info, status, status_debug = detect_charuco_pose_for_config(
                gray,
                camera_matrix,
                label,
                dict_name,
                dict_id,
                squares_x,
                squares_y,
                attempt_debug,
                image_scale=image_scale,
            )
            if status_debug is not None:
                attempt_debug = status_debug
            if pose_info is not None:
                if debug_name:
                    write_charuco_debug(debug_name, attempt_debug, status)
                return pose_info, status
            try:
                if "corners=" in status:
                    score = 1000 + int(status.rsplit("corners=", 1)[-1])
                else:
                    score = int(status.rsplit("markers=", 1)[-1])
            except Exception:
                score = 0
            if score > best_score:
                best_score = score
                best_status = status
                best_debug = attempt_debug
    if debug_name and best_debug is not None:
        write_charuco_debug(debug_name, best_debug, best_status)
    return None, best_status


def write_charuco_debug(name, image, status):
    try:
        debug_dir = Path(__file__).resolve().parent / "logs"
        debug_dir.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(debug_dir / f"charuco_{name}.png"), image)
        with open(debug_dir / "charuco_status.txt", "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {name}: {status}\n")
    except Exception:
        pass


def rgb_pose_to_rectified_left_pose(rgb_pose_cv, oak_calib):
    try:
        left_to_rgb = np.array(
            oak_calib.getCameraExtrinsics(
                oak.dai.CameraBoardSocket.CAM_B,
                oak.dai.CameraBoardSocket.CAM_A,
                False,
                oak.dai.LengthUnit.METER,
            ),
            dtype=np.float64,
        )
        rect_rot = np.array(oak_calib.getStereoLeftRectificationRotation(), dtype=np.float64)
        if left_to_rgb.shape != (4, 4) or rect_rot.shape != (3, 3):
            return None
        raw_left_pose = np.linalg.inv(left_to_rgb) @ np.asarray(rgb_pose_cv, dtype=np.float64)
        rect = np.eye(4, dtype=np.float64)
        rect[:3, :3] = rect_rot
        return rect @ raw_left_pose
    except Exception:
        return None


def charuco_rs_to_oak_transform(oak_left_img, oak_rgb_img, oak_calib, rs_capture):
    if rs_capture is None or rs_capture.latest_color is None:
        return None, "ChArUco needs RealSense color"
    rs_k = camera_matrix_from_rs_intrinsics(rs_capture.intrinsics)

    oak_pose_info = None
    oak_status = "OAK: no image"
    if oak_left_img is not None:
        h, w = oak_left_img.shape[:2]
        oak_k = camera_matrix_from_tuple(oak.get_left_intrinsics(oak_calib, w, h))
        oak_pose_info, oak_status = detect_charuco_pose(oak_left_img, oak_k, "OAK-left", debug_name="oak_left")
    if oak_pose_info is None and oak_rgb_img is not None:
        h, w = oak_rgb_img.shape[:2]
        rgb_k = camera_matrix_from_tuple(oak.get_rgb_intrinsics(oak_calib, w, h))
        rgb_pose_info, rgb_status = detect_charuco_pose(oak_rgb_img, rgb_k, "OAK-rgb", debug_name="oak_rgb")
        if rgb_pose_info is not None:
            rect_pose = rgb_pose_to_rectified_left_pose(rgb_pose_info[0], oak_calib)
            if rect_pose is not None:
                oak_pose_info = (rect_pose, *rgb_pose_info[1:])
                oak_status = rgb_status + " -> left"
            else:
                oak_status = rgb_status + " but RGB->left extrinsics failed"
        else:
            oak_status = f"{oak_status}; {rgb_status}"
    if oak_pose_info is None:
        return None, f"ChArUco failed | {oak_status}"
    oak_pose_cv, dict_name, dict_id, squares_x, squares_y, _markers, _corners = oak_pose_info
    rs_pose_info, rs_status = detect_charuco_pose(rs_capture.latest_color, rs_k, "RS", preferred_config=(dict_name, dict_id, squares_x, squares_y), debug_name="rs_color")
    if rs_pose_info is None:
        return None, f"ChArUco failed | {oak_status} | {rs_status}"
    rs_pose_cv = rs_pose_info[0]

    cv_to_view = np.diag([1.0, -1.0, -1.0, 1.0]).astype(np.float64)
    rs_to_oak = cv_to_view @ oak_pose_cv @ np.linalg.inv(rs_pose_cv) @ cv_to_view
    board_distance_m = float(np.linalg.norm(oak_pose_cv[:3, 3]))
    status = f"ChArUco applied | {oak_status} | {rs_status} | board={board_distance_m:.2f}m"
    try:
        debug_dir = Path(__file__).resolve().parent / "logs"
        debug_dir.mkdir(parents=True, exist_ok=True)
        with open(debug_dir / "charuco_status.txt", "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%H:%M:%S')} applied: {status}\n")
    except Exception:
        pass
    return rs_to_oak, status


def fusion_on_mouse(event, x, y, flags, _userdata):
    view = oak.VIEW
    if event == cv2.EVENT_LBUTTONDOWN:
        pick_target = getattr(view, "pick_target", None)
        if pick_target in ("oak", "rs"):
            pts = getattr(view, "last_oak_pts", None) if pick_target == "oak" else getattr(view, "last_rs_pts", None)
            picked, dist = pick_nearest_screen_point(pts, x, y)
            if picked is not None:
                if pick_target == "oak":
                    view.pending_oak_pick = picked
                    view.calib_status = f"picked OAK point, dist={dist:.0f}px"
                else:
                    view.pending_rs_pick = picked
                    view.calib_status = f"picked RS point, dist={dist:.0f}px"
                if getattr(view, "pending_oak_pick", None) is not None and getattr(view, "pending_rs_pick", None) is not None:
                    pairs = getattr(view, "calib_pairs", [])
                    pairs.append((view.pending_oak_pick.copy(), view.pending_rs_pick.copy()))
                    view.calib_pairs = pairs
                    view.pending_oak_pick = None
                    view.pending_rs_pick = None
                    view.calib_status = f"added pair {len(pairs)}"
            else:
                view.calib_status = f"no {pick_target} point near click"
            view.pick_target = None
            view.drag_button = None
            return
        view.drag_button = "orbit"
        view.last_x = x
        view.last_y = y
    elif event in (cv2.EVENT_RBUTTONDOWN, cv2.EVENT_MBUTTONDOWN):
        view.drag_button = "pan"
        view.last_x = x
        view.last_y = y
    elif event in (cv2.EVENT_LBUTTONUP, cv2.EVENT_RBUTTONUP, cv2.EVENT_MBUTTONUP):
        view.drag_button = None
    elif event == cv2.EVENT_MOUSEMOVE and view.drag_button is not None:
        dx = x - view.last_x
        dy = y - view.last_y
        view.last_x = x
        view.last_y = y
        if view.drag_button == "orbit":
            view.yaw += dx * 0.006
            view.pitch = float(np.clip(view.pitch + dy * 0.006, -np.pi * 0.49, np.pi * 0.49))
        elif view.drag_button == "pan":
            view.pan_x += dx
            view.pan_y += dy
    elif event == cv2.EVENT_MOUSEWHEEL:
        wheel = 1.0 if flags > 0 else -1.0
        view.zoom = float(np.clip(view.zoom * (1.15 ** wheel), 25.0, 5000.0))


class RealSenseLive:
    def __init__(self, width=640, height=480, fps=30):
        if rs is None:
            raise RuntimeError("pyrealsense2 is not installed")
        self.width = int(width)
        self.height = int(height)
        self.fps = int(fps)
        self.pipeline = rs.pipeline()
        self.config = rs.config()
        self.config.enable_stream(rs.stream.depth, self.width, self.height, rs.format.z16, self.fps)
        self.config.enable_stream(rs.stream.color, self.width, self.height, rs.format.bgr8, self.fps)
        self.profile = self.pipeline.start(self.config)
        self.align = rs.align(rs.stream.color)
        self.depth_sensor = self.profile.get_device().first_depth_sensor()
        self.depth_scale = float(self.depth_sensor.get_depth_scale())
        color_profile = self.profile.get_stream(rs.stream.color).as_video_stream_profile()
        self.intrinsics = color_profile.get_intrinsics()
        self.latest_depth_m = None
        self.latest_color = None
        self.frame_count = 0
        self.fps_est = 0.0
        self._fps_count = 0
        self._last_fps_time = time.perf_counter()

    def update(self):
        frames = self.pipeline.poll_for_frames()
        if not frames:
            return False
        frames = self.align.process(frames)
        depth_frame = frames.get_depth_frame()
        color_frame = frames.get_color_frame()
        if not depth_frame or not color_frame:
            return False
        self.latest_depth_m = np.asanyarray(depth_frame.get_data()).astype(np.float32) * self.depth_scale
        self.latest_color = np.asanyarray(color_frame.get_data()).copy()
        self.frame_count += 1
        self._fps_count += 1
        now = time.perf_counter()
        if now - self._last_fps_time >= 0.5:
            self.fps_est = self._fps_count / max(1e-6, now - self._last_fps_time)
            self._fps_count = 0
            self._last_fps_time = now
        return True

    def close(self):
        try:
            self.pipeline.stop()
        except Exception:
            pass


def parse_args():
    parser = argparse.ArgumentParser(description="Live OAK-D FastFoundationStereo + RealSense point-cloud fusion viewer.")
    parser.add_argument("--preset", choices=sorted(oak.PRESETS), default="smooth")
    parser.add_argument("--foundation-scale", type=float, default=1.0)
    parser.add_argument("--fast-foundation-iters", type=int, default=8)
    parser.add_argument("--torch-compile", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--fast-live-interval", type=float, default=0.0)
    parser.add_argument("--fast-live-color-source", choices=("left", "projected-rgb", "rgb"), default="projected-rgb")
    parser.add_argument("--z-near", type=float, default=0.20)
    parser.add_argument("--z-far", type=float, default=4.50)
    parser.add_argument("--realsense", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--rs-width", type=int, default=640)
    parser.add_argument("--rs-height", type=int, default=480)
    parser.add_argument("--rs-fps", type=int, default=30)
    parser.add_argument("--start-mode", choices=MODES, default="combined")
    parser.add_argument("--auto-align-on-start", action="store_true")
    parser.add_argument("--icp-voxel-m", type=float, default=0.045)
    parser.add_argument("--align-max-tilt-deg", type=float, default=25.0)
    parser.add_argument("--align-yaw-step-deg", type=float, default=15.0)
    parser.add_argument("--enable-open3d-align", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--debug-loop", action="store_true")
    return parser.parse_args()


def create_controls(args):
    oak.create_controls()
    cv2.setTrackbarPos("z near cm", CTRL_WIN, int(round(args.z_near * 100.0)))
    cv2.setTrackbarPos("z far cm", CTRL_WIN, int(round(args.z_far * 100.0)))
    cv2.setTrackbarPos("stride", CTRL_WIN, 1)
    cv2.setTrackbarPos("edge reject cm", CTRL_WIN, 0)
    cv2.setTrackbarPos("min island px", CTRL_WIN, 0)
    cv2.setTrackbarPos("point size", CTRL_WIN, 1)
    cv2.setTrackbarPos("render every N depth", CTRL_WIN, 1)
    cv2.createTrackbar("fast iters", CTRL_WIN, int(np.clip(args.fast_foundation_iters, 1, 32)), 32, lambda _v: None)
    cv2.createTrackbar("rs stride", CTRL_WIN, 1, 12, lambda _v: None)
    cv2.createTrackbar("rs x cm", CTRL_WIN, 300, 600, lambda _v: None)
    cv2.createTrackbar("rs y cm", CTRL_WIN, 300, 600, lambda _v: None)
    cv2.createTrackbar("rs z cm", CTRL_WIN, 300, 600, lambda _v: None)
    cv2.createTrackbar("rs yaw deg", CTRL_WIN, 180, 360, lambda _v: None)
    cv2.createTrackbar("rs pitch deg", CTRL_WIN, 180, 360, lambda _v: None)
    cv2.createTrackbar("rs roll deg", CTRL_WIN, 180, 360, lambda _v: None)


def rs_transform_controls():
    def pos(name, center=300):
        return cv2.getTrackbarPos(name, CTRL_WIN) - center

    tx = pos("rs x cm") / 100.0
    ty = pos("rs y cm") / 100.0
    tz = pos("rs z cm") / 100.0
    yaw = np.deg2rad(cv2.getTrackbarPos("rs yaw deg", CTRL_WIN) - 180)
    pitch = np.deg2rad(cv2.getTrackbarPos("rs pitch deg", CTRL_WIN) - 180)
    roll = np.deg2rad(cv2.getTrackbarPos("rs roll deg", CTRL_WIN) - 180)
    return tx, ty, tz, yaw, pitch, roll


def fast_iters_control():
    return max(1, int(cv2.getTrackbarPos("fast iters", CTRL_WIN)))


def set_rs_transform_controls(tx, ty, tz, yaw, pitch, roll):
    cv2.setTrackbarPos("rs x cm", CTRL_WIN, int(np.clip(round(tx * 100.0) + 300, 0, 600)))
    cv2.setTrackbarPos("rs y cm", CTRL_WIN, int(np.clip(round(ty * 100.0) + 300, 0, 600)))
    cv2.setTrackbarPos("rs z cm", CTRL_WIN, int(np.clip(round(tz * 100.0) + 300, 0, 600)))
    cv2.setTrackbarPos("rs yaw deg", CTRL_WIN, int(np.clip(round(np.rad2deg(yaw)) + 180, 0, 360)))
    cv2.setTrackbarPos("rs pitch deg", CTRL_WIN, int(np.clip(round(np.rad2deg(pitch)) + 180, 0, 360)))
    cv2.setTrackbarPos("rs roll deg", CTRL_WIN, int(np.clip(round(np.rad2deg(roll)) + 180, 0, 360)))


def rotation_matrix(yaw, pitch, roll):
    cy, sy = np.cos(yaw), np.sin(yaw)
    cp, sp = np.cos(pitch), np.sin(pitch)
    cr, sr = np.cos(roll), np.sin(roll)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]], dtype=np.float32)
    rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]], dtype=np.float32)
    rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]], dtype=np.float32)
    return (rz @ ry @ rx).astype(np.float32)


def current_rs_transform_matrix():
    tx, ty, tz, yaw, pitch, roll = rs_transform_controls()
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rotation_matrix(yaw, pitch, roll).astype(np.float64)
    transform[:3, 3] = np.array([tx, ty, tz], dtype=np.float64)
    return transform


def set_rs_transform_matrix(transform):
    transform = np.asarray(transform, dtype=np.float64)
    yaw, pitch, roll = ypr_from_rotation_matrix(transform[:3, :3])
    tx, ty, tz = transform[:3, 3]
    set_rs_transform_controls(float(tx), float(ty), float(tz), float(yaw), float(pitch), float(roll))


def apply_transform_points(pts, transform):
    if pts is None or pts.size <= 0:
        return pts
    rot = transform[:3, :3].astype(np.float32)
    trans = transform[:3, 3].astype(np.float32)
    out = np.empty_like(pts, dtype=np.float32)
    out[:, 0] = pts[:, 0] * rot[0, 0] + pts[:, 1] * rot[0, 1] + pts[:, 2] * rot[0, 2] + trans[0]
    out[:, 1] = pts[:, 0] * rot[1, 0] + pts[:, 1] * rot[1, 1] + pts[:, 2] * rot[1, 2] + trans[1]
    out[:, 2] = pts[:, 0] * rot[2, 0] + pts[:, 1] * rot[2, 1] + pts[:, 2] * rot[2, 2] + trans[2]
    return out


def realsense_cloud(capture, znear, zfar, apply_transform=True):
    if capture is None or capture.latest_depth_m is None or capture.latest_color is None:
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)
    stride = max(1, int(cv2.getTrackbarPos("rs stride", CTRL_WIN)))
    depth = capture.latest_depth_m
    color = capture.latest_color
    rows = np.arange(0, depth.shape[0], stride, dtype=np.int32)
    cols = np.arange(0, depth.shape[1], stride, dtype=np.int32)
    z = depth[np.ix_(rows, cols)]
    valid = np.isfinite(z) & (z >= float(znear)) & (z <= float(zfar))
    if not np.any(valid):
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)

    yy, xx = np.meshgrid(rows.astype(np.float32), cols.astype(np.float32), indexing="ij")
    intr = capture.intrinsics
    zz = z[valid].astype(np.float32)
    x = (xx[valid] - float(intr.ppx)) * zz / max(1e-6, float(intr.fx))
    y = (yy[valid] - float(intr.ppy)) * zz / max(1e-6, float(intr.fy))
    pts = np.stack([x, -y, -zz], axis=1).astype(np.float32)

    if apply_transform:
        pts = apply_transform_points(pts, current_rs_transform_matrix())
    colors = color[np.ix_(rows, cols)][valid].astype(np.uint8)
    return pts, colors


def realsense_grid_cloud(capture, znear, zfar, apply_transform=True):
    if capture is None or capture.latest_depth_m is None or capture.latest_color is None:
        return None, None, None
    stride = max(1, int(cv2.getTrackbarPos("rs stride", CTRL_WIN)))
    depth = capture.latest_depth_m
    color = capture.latest_color
    rows = np.arange(0, depth.shape[0], stride, dtype=np.int32)
    cols = np.arange(0, depth.shape[1], stride, dtype=np.int32)
    z = depth[np.ix_(rows, cols)].astype(np.float32)
    valid = np.isfinite(z) & (z >= float(znear)) & (z <= float(zfar))
    yy, xx = np.meshgrid(rows.astype(np.float32), cols.astype(np.float32), indexing="ij")
    intr = capture.intrinsics
    x = (xx - float(intr.ppx)) * z / max(1e-6, float(intr.fx))
    y = (yy - float(intr.ppy)) * z / max(1e-6, float(intr.fy))
    grid_pts = np.stack([x, -y, -z], axis=2).astype(np.float32)
    grid_pts[~valid] = 0.0
    if apply_transform:
        flat = grid_pts.reshape(-1, 3)
        flat = apply_transform_points(flat, current_rs_transform_matrix())
        grid_pts = flat.reshape(grid_pts.shape)
    grid_colors = color[np.ix_(rows, cols)].astype(np.uint8)
    return grid_pts, grid_colors, valid


def draw_lines(canvas, lines):
    y = 28
    for line in lines:
        cv2.putText(canvas, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(canvas, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (120, 255, 120), 1, cv2.LINE_AA)
        y += 28


def current_cloud_center(pts):
    if pts is None or pts.size <= 0:
        return np.zeros(3, dtype=np.float32)
    old = getattr(oak.VIEW, "orbit_center", None)
    if old is None or not np.isfinite(old).all():
        oak.VIEW.orbit_center = robust_center(sample_points(pts, max_points=30000)).astype(np.float32)
    return oak.VIEW.orbit_center


def rotate_for_view(pts):
    centered = pts - current_cloud_center(pts)
    cy, sy = np.cos(oak.VIEW.yaw), np.sin(oak.VIEW.yaw)
    cp, sp = np.cos(oak.VIEW.pitch), np.sin(oak.VIEW.pitch)
    x0 = centered[:, 0]
    y0 = centered[:, 1]
    z0 = centered[:, 2]
    # Pitch first, then yaw around the model Y axis. This makes horizontal
    # mouse drag feel like a true left/right orbit instead of an apparent roll.
    x1 = x0
    y1 = y0 * cp - z0 * sp
    z1 = y0 * sp + z0 * cp
    x2 = x1 * cy + z1 * sy
    y2 = y1
    z2 = -x1 * sy + z1 * cy
    return x2, y2, z2


def project_fusion_point_arrays(pts, colors, point_size):
    canvas = np.zeros((900, 1200, 3), dtype=np.uint8)
    if pts is None or colors is None or pts.size <= 0:
        return canvas
    x, y, z = rotate_for_view(pts.astype(np.float32, copy=False))
    u = (x * oak.VIEW.zoom + canvas.shape[1] * 0.5 + oak.VIEW.pan_x).astype(np.int32)
    v = (-y * oak.VIEW.zoom + canvas.shape[0] * 0.5 + oak.VIEW.pan_y).astype(np.int32)
    inside = (u >= 0) & (u < canvas.shape[1]) & (v >= 0) & (v < canvas.shape[0])
    if not np.any(inside):
        return canvas
    u, v, colors, depth = u[inside], v[inside], colors[inside], z[inside]
    order = np.argsort(depth)
    for offset_y in range(point_size):
        for offset_x in range(point_size):
            uu = np.clip(u[order] + offset_x, 0, canvas.shape[1] - 1)
            vv = np.clip(v[order] + offset_y, 0, canvas.shape[0] - 1)
            canvas[vv, uu] = colors[order]
    return canvas


def project_to_canvas(pts):
    if pts is None or pts.size <= 0:
        return None
    x, y, z = rotate_for_view(pts.astype(np.float32, copy=False))
    u = (x * oak.VIEW.zoom + 600.0 + oak.VIEW.pan_x).astype(np.int32)
    v = (-y * oak.VIEW.zoom + 450.0 + oak.VIEW.pan_y).astype(np.int32)
    inside = (u >= 0) & (u < 1200) & (v >= 0) & (v < 900)
    return u, v, z, inside


def pick_nearest_screen_point(pts, x, y, max_px=26):
    if pts is None or pts.size <= 0:
        return None, 0.0
    sampled = sample_points(pts, max_points=90000).astype(np.float32)
    projected = project_to_canvas(sampled)
    if projected is None:
        return None, 0.0
    u, v, depth, inside = projected
    if not np.any(inside):
        return None, 0.0
    idxs = np.flatnonzero(inside)
    du = u[idxs].astype(np.float32) - float(x)
    dv = v[idxs].astype(np.float32) - float(y)
    dist2 = du * du + dv * dv
    best_local = int(np.argmin(dist2))
    best_idx = int(idxs[best_local])
    dist = float(np.sqrt(dist2[best_local]))
    if dist > float(max_px):
        return None, dist
    return sampled[best_idx].astype(np.float32), dist


def solve_rigid_transform(source_pts, target_pts):
    src = np.asarray(source_pts, dtype=np.float64)
    dst = np.asarray(target_pts, dtype=np.float64)
    if src.shape[0] < 3 or dst.shape[0] < 3:
        return None, "need at least 3 point pairs"
    src_center = np.mean(src, axis=0)
    dst_center = np.mean(dst, axis=0)
    src0 = src - src_center
    dst0 = dst - dst_center
    cov = src0.T @ dst0
    try:
        u, _s, vt = np.linalg.svd(cov)
    except Exception as exc:
        return None, f"SVD failed: {exc}"
    rot = vt.T @ u.T
    if np.linalg.det(rot) < 0:
        vt[-1, :] *= -1.0
        rot = vt.T @ u.T
    trans = dst_center - rot @ src_center
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rot
    transform[:3, 3] = trans
    fitted = (src @ rot.T) + trans
    err = np.linalg.norm(fitted - dst, axis=1)
    return transform, f"pairs={src.shape[0]} rms={float(np.sqrt(np.mean(err * err))):.3f}m max={float(np.max(err)):.3f}m"


def apply_correspondence_calibration():
    pairs = getattr(oak.VIEW, "calib_pairs", [])
    if len(pairs) < 3:
        return f"need 3+ pairs, have {len(pairs)}"
    oak_pts = np.asarray([p[0] for p in pairs], dtype=np.float64)
    rs_pts_world = np.asarray([p[1] for p in pairs], dtype=np.float64)
    current = current_rs_transform_matrix()
    inv_current = np.linalg.inv(current)
    ones = np.ones((rs_pts_world.shape[0], 1), dtype=np.float64)
    rs_raw = (inv_current @ np.concatenate([rs_pts_world, ones], axis=1).T).T[:, :3]
    transform, status = solve_rigid_transform(rs_raw, oak_pts)
    if transform is None:
        return status
    set_rs_transform_matrix(transform)
    return f"correspondence calibrated {status}"


def texture_plane_map(points, colors, origin, axis_a, axis_b, normal, image_size=720, meters_per_px=0.01, plane_band_m=0.18):
    if points is None or colors is None or points.size <= 0:
        return None, None, None
    pts = np.asarray(points, dtype=np.float64)
    cols = np.asarray(colors, dtype=np.uint8)
    valid_pts = np.isfinite(pts).all(axis=1)
    pts = pts[valid_pts]
    cols = cols[valid_pts]
    if pts.shape[0] > 130000:
        indices = np.random.default_rng(17).choice(pts.shape[0], 130000, replace=False)
        pts = pts[indices]
        cols = cols[indices]
    points = pts.astype(np.float32)
    colors_use = cols.astype(np.uint8)
    if points.shape[0] <= 0 or colors_use.shape[0] != points.shape[0]:
        return None, None, None
    rel = points.astype(np.float64) - np.asarray(origin, dtype=np.float64)
    dist = rel[:, 0] * normal[0] + rel[:, 1] * normal[1] + rel[:, 2] * normal[2]
    keep = np.abs(dist) <= float(plane_band_m)
    if np.count_nonzero(keep) < 800:
        keep = np.ones(points.shape[0], dtype=bool)
    rel = rel[keep]
    colors_use = colors_use[keep]
    u_m = rel[:, 0] * axis_a[0] + rel[:, 1] * axis_a[1] + rel[:, 2] * axis_a[2]
    v_m = rel[:, 0] * axis_b[0] + rel[:, 1] * axis_b[1] + rel[:, 2] * axis_b[2]
    center_u = float(np.median(u_m))
    center_v = float(np.median(v_m))
    px = np.rint((u_m - center_u) / float(meters_per_px) + image_size * 0.5).astype(np.int32)
    py = np.rint((v_m - center_v) / float(meters_per_px) + image_size * 0.5).astype(np.int32)
    inside = (px >= 0) & (px < image_size) & (py >= 0) & (py < image_size)
    if np.count_nonzero(inside) < 500:
        return None, None, None
    img = np.zeros((image_size, image_size, 3), dtype=np.uint8)
    mask = np.zeros((image_size, image_size), dtype=np.uint8)
    img[py[inside], px[inside]] = colors_use[inside].astype(np.uint8)
    mask[py[inside], px[inside]] = 255
    kernel = np.ones((3, 3), np.uint8)
    img = cv2.dilate(img, kernel, iterations=1)
    mask = cv2.dilate(mask, kernel, iterations=1)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)
    gray[mask == 0] = 0
    return gray, mask, (center_u, center_v)


def rotate_image_center(img, angle_deg):
    center = (img.shape[1] * 0.5, img.shape[0] * 0.5)
    mat = cv2.getRotationMatrix2D(center, float(angle_deg), 1.0)
    warped = cv2.warpAffine(img, mat, (img.shape[1], img.shape[0]), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    return warped, mat


def coarse_texture_warp(target_img, source_img):
    target = target_img.astype(np.float32)
    source = source_img.astype(np.float32)
    target = cv2.GaussianBlur(target, (5, 5), 0)
    source = cv2.GaussianBlur(source, (5, 5), 0)
    best = None
    for angle in np.arange(-35.0, 35.1, 2.5):
        rotated, rot_mat = rotate_image_center(source, angle)
        shift, response = cv2.phaseCorrelate(target, rotated)
        warp = rot_mat.copy().astype(np.float32)
        warp[0, 2] += float(shift[0])
        warp[1, 2] += float(shift[1])
        if best is None or response > best[0]:
            best = (float(response), warp, float(angle), shift)
    return best


def refine_alignment_by_texture(oak_pts, oak_colors, rs_pts, rs_colors, initial_transform=None, apply_result=True):
    def done(transform, status):
        if apply_result and transform is not None:
            set_rs_transform_matrix(transform)
        return transform, status

    if oak_pts is None or rs_pts is None or oak_colors is None or rs_colors is None:
        return done(None, "texture refine needs both clouds")
    target_sample = sample_points(oak_pts, max_points=60000)
    target_plane = fit_plane_ransac_points(target_sample, threshold=0.045, iterations=300)
    if target_plane is None:
        return done(None, "texture refine failed: OAK plane not found")
    normal, origin, _count = target_plane
    axis_a, axis_b = plane_basis(normal)
    oak_img, oak_mask, oak_center = texture_plane_map(oak_pts, oak_colors, origin, axis_a, axis_b, normal)
    rs_img, rs_mask, rs_center = texture_plane_map(rs_pts, rs_colors, origin, axis_a, axis_b, normal)
    if oak_img is None or rs_img is None:
        return done(None, "texture refine failed: not enough textured plane points")
    valid_mask = cv2.bitwise_and(oak_mask, rs_mask)
    if int(np.count_nonzero(valid_mask)) < 1000:
        valid_mask = None

    coarse = coarse_texture_warp(oak_img, rs_img)
    if coarse is None:
        return done(None, "texture refine failed: phase correlation failed")
    coarse_response, warp, coarse_angle, coarse_shift = coarse
    refine_mode = "coarse"
    try:
        cc, warp = cv2.findTransformECC(
            oak_img.astype(np.float32) / 255.0,
            rs_img.astype(np.float32) / 255.0,
            warp,
            cv2.MOTION_EUCLIDEAN,
            (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 80, 1e-5),
            valid_mask,
            5,
        )
        refine_mode = "ecc"
    except Exception as exc:
        cc = coarse_response
        # Keep coarse phase-correlation warp if ECC cannot improve from it.

    debug_dir = Path(__file__).resolve().parent / "logs"
    try:
        debug_dir.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(debug_dir / "texture_refine_oak.png"), oak_img)
        cv2.imwrite(str(debug_dir / "texture_refine_rs.png"), rs_img)
        cv2.imwrite(str(debug_dir / "texture_refine_rs_warped.png"), cv2.warpAffine(rs_img, warp, (rs_img.shape[1], rs_img.shape[0]), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP))
    except Exception:
        pass

    # Invert the image warp so it maps current RS plane coordinates toward OAK plane coordinates.
    m = np.vstack([warp, [0.0, 0.0, 1.0]]).astype(np.float64)
    try:
        inv = np.linalg.inv(m)
    except Exception:
        return done(None, "texture refine failed: singular warp")
    angle = float(np.arctan2(inv[1, 0], inv[0, 0]))
    trans_px = inv[:2, 2]
    meters_per_px = 0.01
    delta_m = axis_a * (trans_px[0] * meters_per_px) + axis_b * (trans_px[1] * meters_per_px)

    current = np.asarray(initial_transform, dtype=np.float64) if initial_transform is not None else current_rs_transform_matrix()
    oak_center_world = np.asarray(origin, dtype=np.float64) + axis_a * oak_center[0] + axis_b * oak_center[1]
    rs_center_world = np.asarray(origin, dtype=np.float64) + axis_a * rs_center[0] + axis_b * rs_center[1]
    corrected = transform_about_axis(current, normal, rs_center_world, angle)
    corrected[:3, 3] += (oak_center_world - rs_center_world) + delta_m
    total_shift = np.linalg.norm((oak_center_world - rs_center_world) + delta_m)
    return done(corrected, f"texture refine {refine_mode} score={cc:.3f} coarse_yaw={coarse_angle:.1f} yaw={np.rad2deg(angle):.2f}deg shift={total_shift:.3f}m")


def tinted_color(color, tint_bgr, mix=0.48):
    color = np.asarray(color, dtype=np.float32)
    tint = np.asarray(tint_bgr, dtype=np.float32)
    return np.clip(color * (1.0 - mix) + tint * mix, 0, 255).astype(np.uint8)


def build_godot_grid_triangles(grid_pts, grid_colors, valid, max_edge_m=0.10, max_depth_delta_m=0.10):
    if grid_pts is None or grid_colors is None or valid is None:
        return None, None, []
    h, w = valid.shape
    if h < 2 or w < 2:
        return None, None, []
    compact = np.full((h, w), -1, dtype=np.int32)
    compact[valid] = np.arange(int(np.count_nonzero(valid)), dtype=np.int32)
    verts = grid_pts[valid].astype(np.float32)
    colors = grid_colors[valid].astype(np.uint8)
    a = compact[:-1, :-1]
    b = compact[:-1, 1:]
    c = compact[1:, :-1]
    d = compact[1:, 1:]
    max_edge_sq = float(max_edge_m) ** 2
    tris = []
    tri1_valid = (a >= 0) & (b >= 0) & (c >= 0)
    if np.any(tri1_valid):
        ia = a[tri1_valid]
        ib = b[tri1_valid]
        ic = c[tri1_valid]
        pa, pb, pc = verts[ia], verts[ib], verts[ic]
        keep = (
            np.sum((pa - pb) * (pa - pb), axis=1) <= max_edge_sq
        ) & (
            np.sum((pb - pc) * (pb - pc), axis=1) <= max_edge_sq
        ) & (
            np.sum((pc - pa) * (pc - pa), axis=1) <= max_edge_sq
        ) & (
            (np.max(np.stack([pa[:, 2], pb[:, 2], pc[:, 2]], axis=1), axis=1) - np.min(np.stack([pa[:, 2], pb[:, 2], pc[:, 2]], axis=1), axis=1)) <= max_depth_delta_m
        )
        tris.extend(np.stack([ia[keep], ic[keep], ib[keep]], axis=1).tolist())
    tri2_valid = (b >= 0) & (c >= 0) & (d >= 0)
    if np.any(tri2_valid):
        ib = b[tri2_valid]
        ic = c[tri2_valid]
        id_ = d[tri2_valid]
        pb, pc, pd = verts[ib], verts[ic], verts[id_]
        keep = (
            np.sum((pb - pc) * (pb - pc), axis=1) <= max_edge_sq
        ) & (
            np.sum((pc - pd) * (pc - pd), axis=1) <= max_edge_sq
        ) & (
            np.sum((pd - pb) * (pd - pb), axis=1) <= max_edge_sq
        ) & (
            (np.max(np.stack([pb[:, 2], pc[:, 2], pd[:, 2]], axis=1), axis=1) - np.min(np.stack([pb[:, 2], pc[:, 2], pd[:, 2]], axis=1), axis=1)) <= max_depth_delta_m
        )
        tris.extend(np.stack([ib[keep], ic[keep], id_[keep]], axis=1).tolist())
    return verts, colors, tris


def draw_grid_connected_mesh(canvas, grid_pts, grid_colors, valid, tint_bgr, max_edge_m=0.10, max_depth_delta_m=0.10):
    verts, vert_colors, triangles = build_godot_grid_triangles(grid_pts, grid_colors, valid, max_edge_m, max_depth_delta_m)
    if verts is None or not triangles:
        return 0
    projected = project_to_canvas(verts)
    if projected is None:
        return 0
    u, v, depth, inside = projected
    visible = [tuple(tri) for tri in triangles if inside[list(tri)].all()]
    order = sorted(visible, key=lambda tri: float(np.mean(depth[list(tri)])))
    for tri in order[:9000]:
        pts2 = np.array([[int(u[i]), int(v[i])] for i in tri], dtype=np.int32)
        color = tinted_color(np.mean(vert_colors[list(tri)], axis=0), tint_bgr)
        cv2.fillConvexPoly(canvas, pts2, tuple(int(c) for c in color.tolist()), cv2.LINE_AA)
        cv2.polylines(canvas, [pts2], True, tint_bgr, 1, cv2.LINE_AA)
    return len(order)


def project_alignment_debug(oak_pts, oak_colors, oak_grid, rs_pts, rs_colors, rs_grid, point_size):
    pts, colors = combine_clouds(oak_pts, oak_colors, rs_pts, rs_colors)
    if colors is not None and colors.size > 0:
        colors = (colors.astype(np.float32) * 0.12).astype(np.uint8)
    canvas = project_fusion_point_arrays(pts, colors, 1)
    oak_tris = draw_grid_connected_mesh(canvas, oak_grid[0], oak_grid[1], oak_grid[2], (0, 255, 255), max_edge_m=0.12, max_depth_delta_m=0.14) if oak_grid[0] is not None else 0
    rs_tris = draw_grid_connected_mesh(canvas, rs_grid[0], rs_grid[1], rs_grid[2], (255, 0, 255), max_edge_m=0.12, max_depth_delta_m=0.14) if rs_grid[0] is not None else 0
    cv2.rectangle(canvas, (0, canvas.shape[0] - 42), (canvas.shape[1], canvas.shape[0]), (35, 35, 35), -1)
    cv2.putText(
        canvas,
        f"ALIGNMENT COLORED MESH - OAK cyan tris={oak_tris} | RealSense magenta tris={rs_tris} | v toggle",
        (18, canvas.shape[0] - 14),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.72,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )
    return canvas


def combine_clouds(oak_pts, oak_colors, rs_pts, rs_colors):
    if oak_pts is None or oak_pts.size <= 0:
        return rs_pts, rs_colors
    if rs_pts is None or rs_pts.size <= 0:
        return oak_pts, oak_colors
    return np.concatenate([oak_pts, rs_pts], axis=0), np.concatenate([oak_colors, rs_colors], axis=0)


def sample_points(pts, max_points=120000):
    pts = np.asarray(pts, dtype=np.float64)
    valid = np.isfinite(pts).all(axis=1)
    pts = pts[valid]
    if pts.shape[0] > max_points:
        indices = np.random.default_rng(7).choice(pts.shape[0], max_points, replace=False)
        pts = pts[indices]
    return pts


def get_o3d():
    import open3d as o3d

    return o3d


def make_o3d_cloud(pts, voxel_m):
    o3d = get_o3d()
    cloud = o3d.geometry.PointCloud()
    cloud.points = o3d.utility.Vector3dVector(sample_points(pts))
    if voxel_m > 0:
        cloud = cloud.voxel_down_sample(float(voxel_m))
    return cloud


def ensure_normals(cloud, voxel_m):
    o3d = get_o3d()
    radius_normal = max(0.08, voxel_m * 2.5)
    cloud.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=radius_normal, max_nn=40))
    return cloud


def estimate_features(cloud, voxel_m):
    o3d = get_o3d()
    radius_feature = max(0.18, voxel_m * 5.0)
    ensure_normals(cloud, voxel_m)
    feature = o3d.pipelines.registration.compute_fpfh_feature(
        cloud,
        o3d.geometry.KDTreeSearchParamHybrid(radius=radius_feature, max_nn=100),
    )
    return feature


def coarse_global_alignment(source, target, voxel_m):
    o3d = get_o3d()
    source_feature = estimate_features(source, voxel_m)
    target_feature = estimate_features(target, voxel_m)
    distance = max(0.12, voxel_m * 4.0)
    try:
        return o3d.pipelines.registration.registration_ransac_based_on_feature_matching(
            source,
            target,
            source_feature,
            target_feature,
            True,
            distance,
            o3d.pipelines.registration.TransformationEstimationPointToPoint(False),
            4,
            [
                o3d.pipelines.registration.CorrespondenceCheckerBasedOnEdgeLength(0.9),
                o3d.pipelines.registration.CorrespondenceCheckerBasedOnDistance(distance),
            ],
            o3d.pipelines.registration.RANSACConvergenceCriteria(60000, 0.999),
        )
    except Exception as exc:
        print(f"Global registration failed, using current transform as ICP init: {exc}", flush=True)
        return None


def transform_from_ypr_translation(yaw, pitch, roll, translation):
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rotation_matrix(yaw, pitch, roll).astype(np.float64)
    transform[:3, 3] = np.asarray(translation, dtype=np.float64)
    return transform


def robust_center(points):
    points = np.asarray(points, dtype=np.float64)
    if points.size <= 0:
        return np.zeros(3, dtype=np.float64)
    return np.median(points, axis=0)


def normalize_vec(vec):
    vec = np.asarray(vec, dtype=np.float64)
    norm = float(np.linalg.norm(vec))
    if norm < 1e-9:
        return vec
    return vec / norm


def axis_angle_rotation(axis, angle):
    axis = normalize_vec(axis)
    x, y, z = axis
    c = float(np.cos(angle))
    s = float(np.sin(angle))
    one_c = 1.0 - c
    return np.array(
        [
            [c + x * x * one_c, x * y * one_c - z * s, x * z * one_c + y * s],
            [y * x * one_c + z * s, c + y * y * one_c, y * z * one_c - x * s],
            [z * x * one_c - y * s, z * y * one_c + x * s, c + z * z * one_c],
        ],
        dtype=np.float64,
    )


def ypr_from_rotation_matrix(rot):
    rot = np.asarray(rot, dtype=np.float64)
    yaw = float(np.arcsin(np.clip(-rot[2, 0], -1.0, 1.0)))
    if abs(np.cos(yaw)) > 1e-6:
        pitch = float(np.arctan2(rot[2, 1], rot[2, 2]))
        roll = float(np.arctan2(rot[1, 0], rot[0, 0]))
    else:
        pitch = 0.0
        roll = float(np.arctan2(-rot[0, 1], rot[1, 1]))
    return yaw, pitch, roll


def rotation_between_vectors(src, dst):
    src = normalize_vec(src)
    dst = normalize_vec(dst)
    cross = np.cross(src, dst)
    dot = float(np.clip(np.dot(src, dst), -1.0, 1.0))
    if np.linalg.norm(cross) < 1e-8:
        if dot > 0:
            return np.eye(3, dtype=np.float64)
        axis = normalize_vec(np.cross(src, np.array([1.0, 0.0, 0.0])))
        if np.linalg.norm(axis) < 1e-8:
            axis = normalize_vec(np.cross(src, np.array([0.0, 1.0, 0.0])))
        return axis_angle_rotation(axis, np.pi)
    return axis_angle_rotation(cross, np.arccos(dot))


def dominant_plane(cloud, distance_threshold):
    if len(cloud.points) < 500:
        return None
    try:
        model, inliers = cloud.segment_plane(
            distance_threshold=float(distance_threshold),
            ransac_n=3,
            num_iterations=1200,
        )
    except Exception:
        return None
    if len(inliers) < 250:
        return None
    pts = np.asarray(cloud.points)[np.asarray(inliers, dtype=np.int32)]
    normal = normalize_vec(np.asarray(model[:3], dtype=np.float64))
    centroid = robust_center(pts)
    return normal, centroid, len(inliers)


def transform_about_axis(transform, axis, center, angle):
    axis = normalize_vec(axis)
    rot = axis_angle_rotation(axis, float(angle))
    wrapped = np.eye(4, dtype=np.float64)
    wrapped[:3, :3] = rot
    wrapped[:3, 3] = np.asarray(center, dtype=np.float64) - (rot @ np.asarray(center, dtype=np.float64))
    return wrapped @ transform


def fit_plane_ransac_points(points, threshold=0.04, iterations=360, max_points=35000):
    points = sample_points(points, max_points=max_points)
    if points.shape[0] < 500:
        return None
    rng = np.random.default_rng(11)
    best_normal = None
    best_centroid = None
    best_count = 0
    for _ in range(int(iterations)):
        tri = points[rng.choice(points.shape[0], 3, replace=False)]
        normal = np.cross(tri[1] - tri[0], tri[2] - tri[0])
        normal = normalize_vec(normal)
        if not np.isfinite(normal).all() or np.dot(normal, normal) < 0.5:
            continue
        diff = points - tri[0]
        dist = np.abs(diff[:, 0] * normal[0] + diff[:, 1] * normal[1] + diff[:, 2] * normal[2])
        inliers = dist < float(threshold)
        count = int(np.count_nonzero(inliers))
        if count > best_count:
            best_count = count
            best_normal = normal
            best_centroid = robust_center(points[inliers])
    if best_normal is None or best_count < 250:
        return None
    return best_normal, best_centroid, best_count


def voxel_overlap_score(source_pts, target_voxels, voxel_m):
    if source_pts.shape[0] <= 0 or not target_voxels:
        return 0
    quantized = np.floor(source_pts / float(voxel_m)).astype(np.int32)
    step = max(1, quantized.shape[0] // 25000)
    score = 0
    for row in quantized[::step]:
        if (int(row[0]), int(row[1]), int(row[2])) in target_voxels:
            score += 1
    return score


def make_voxel_set(points, voxel_m, max_points=45000):
    points = sample_points(points, max_points=max_points)
    quantized = np.floor(points / float(voxel_m)).astype(np.int32)
    return {(int(row[0]), int(row[1]), int(row[2])) for row in quantized}


def plane_basis(normal):
    normal = normalize_vec(normal)
    axis_a = normalize_vec(np.cross(normal, np.array([0.0, 0.0, 1.0], dtype=np.float64)))
    if np.linalg.norm(axis_a) < 1e-6:
        axis_a = normalize_vec(np.cross(normal, np.array([1.0, 0.0, 0.0], dtype=np.float64)))
    axis_b = normalize_vec(np.cross(normal, axis_a))
    return axis_a, axis_b


def make_plane_voxel_set(points, origin, axis_a, axis_b, cell_m, max_points=45000):
    points = sample_points(points, max_points=max_points)
    rel = points - origin
    u = np.floor((rel[:, 0] * axis_a[0] + rel[:, 1] * axis_a[1] + rel[:, 2] * axis_a[2]) / float(cell_m)).astype(np.int32)
    v = np.floor((rel[:, 0] * axis_b[0] + rel[:, 1] * axis_b[1] + rel[:, 2] * axis_b[2]) / float(cell_m)).astype(np.int32)
    return {(int(a), int(b)) for a, b in zip(u, v)}


def plane_overlap_score(points, target_voxels, origin, axis_a, axis_b, cell_m):
    if points.shape[0] <= 0 or not target_voxels:
        return 0
    rel = points - origin
    u = np.floor((rel[:, 0] * axis_a[0] + rel[:, 1] * axis_a[1] + rel[:, 2] * axis_a[2]) / float(cell_m)).astype(np.int32)
    v = np.floor((rel[:, 0] * axis_b[0] + rel[:, 1] * axis_b[1] + rel[:, 2] * axis_b[2]) / float(cell_m)).astype(np.int32)
    step = max(1, u.shape[0] // 30000)
    score = 0
    for a, b in zip(u[::step], v[::step]):
        if (int(a), int(b)) in target_voxels:
            score += 1
    return score


def refine_plane_translation(transform, source_points, target_voxels, origin, axis_a, axis_b, normal, cell_m):
    best = np.asarray(transform, dtype=np.float64).copy()
    transformed = apply_transform_points(source_points.astype(np.float32), best).astype(np.float64)
    best_score = plane_overlap_score(transformed, target_voxels, origin, axis_a, axis_b, cell_m)
    for radius in (0.75, 0.35, 0.16, 0.07, 0.03):
        improved = True
        while improved:
            improved = False
            for da, db, dn in (
                (radius, 0.0, 0.0),
                (-radius, 0.0, 0.0),
                (0.0, radius, 0.0),
                (0.0, -radius, 0.0),
                (0.0, 0.0, radius * 0.5),
                (0.0, 0.0, -radius * 0.5),
            ):
                candidate = best.copy()
                candidate[:3, 3] += axis_a * da + axis_b * db + normal * dn
                transformed = apply_transform_points(source_points.astype(np.float32), candidate).astype(np.float64)
                score = plane_overlap_score(transformed, target_voxels, origin, axis_a, axis_b, cell_m)
                if score > best_score:
                    best = candidate
                    best_score = score
                    improved = True
                    break
    return best, best_score


def refine_translation_voxel(transform, source_points, target_voxels, target_normal, voxel_m):
    normal = normalize_vec(target_normal)
    axis_a, axis_b = plane_basis(normal)
    best = np.asarray(transform, dtype=np.float64).copy()
    transformed = apply_transform_points(source_points.astype(np.float32), best).astype(np.float64)
    best_score = voxel_overlap_score(transformed, target_voxels, voxel_m)
    for radius in (0.45, 0.22, 0.10, 0.045):
        improved = True
        while improved:
            improved = False
            for da, db, dn in (
                (radius, 0.0, 0.0),
                (-radius, 0.0, 0.0),
                (0.0, radius, 0.0),
                (0.0, -radius, 0.0),
                (0.0, 0.0, radius),
                (0.0, 0.0, -radius),
            ):
                candidate = best.copy()
                candidate[:3, 3] += axis_a * da + axis_b * db + normal * dn
                transformed = apply_transform_points(source_points.astype(np.float32), candidate).astype(np.float64)
                score = voxel_overlap_score(transformed, target_voxels, voxel_m)
                if score > best_score:
                    best = candidate
                    best_score = score
                    improved = True
                    break
    return best, best_score


def safe_plane_voxel_align(oak_pts, raw_rs_pts, voxel_m=0.07, yaw_step_deg=10.0):
    if oak_pts is None or raw_rs_pts is None or oak_pts.shape[0] < 2000 or raw_rs_pts.shape[0] < 2000:
        return None, "need more OAK/RealSense points"

    target_sample = sample_points(oak_pts, max_points=50000)
    source_sample = sample_points(raw_rs_pts, max_points=50000)
    target_plane = fit_plane_ransac_points(target_sample)
    source_plane = fit_plane_ransac_points(source_sample)
    if target_plane is None or source_plane is None:
        return None, "safe align failed: plane not found"

    target_normal, target_plane_center, target_count = target_plane
    source_normal, source_plane_center, source_count = source_plane
    target_center = robust_center(target_sample)
    target_voxels = make_voxel_set(target_sample, voxel_m)
    plane_axis_a, plane_axis_b = plane_basis(target_normal)
    target_plane_voxels = make_plane_voxel_set(
        target_sample,
        target_plane_center,
        plane_axis_a,
        plane_axis_b,
        max(0.05, voxel_m),
    )

    best_transform = None
    best_score = -1
    yaw_step = max(5.0, float(yaw_step_deg))
    for sign in (1.0, -1.0):
        base_rot = rotation_between_vectors(source_normal * sign, target_normal)
        base = np.eye(4, dtype=np.float64)
        base[:3, :3] = base_rot
        base[:3, 3] = target_plane_center - (base_rot @ source_plane_center)
        for angle in np.deg2rad(np.arange(-180.0, 180.0, yaw_step, dtype=np.float64)):
            candidate = transform_about_axis(base, target_normal, target_plane_center, float(angle))
            transformed = apply_transform_points(source_sample.astype(np.float32), candidate).astype(np.float64)
            candidate[:3, 3] += target_center - robust_center(transformed)
            transformed = apply_transform_points(source_sample.astype(np.float32), candidate).astype(np.float64)
            score = voxel_overlap_score(transformed, target_voxels, voxel_m)
            if score > best_score:
                best_score = score
                best_transform = candidate.copy()

    if best_transform is None or best_score <= 0:
        return None, "safe align failed: no voxel overlap"

    best_transform, best_score = refine_translation_voxel(
        best_transform,
        source_sample,
        target_voxels,
        target_normal,
        voxel_m,
    )
    best_transform, plane_score = refine_plane_translation(
        best_transform,
        source_sample,
        target_plane_voxels,
        target_plane_center,
        plane_axis_a,
        plane_axis_b,
        target_normal,
        max(0.05, voxel_m),
    )
    set_rs_transform_matrix(best_transform)
    return best_transform, f"safe plane+voxel+floor score={best_score}/{plane_score} plane RS={source_count} OAK={target_count}"


def plane_alignment_candidates(source, target, voxel_m, yaw_step_deg):
    source_plane = dominant_plane(source, max(0.035, voxel_m * 0.9))
    target_plane = dominant_plane(target, max(0.035, voxel_m * 0.9))
    if source_plane is None or target_plane is None:
        return [], "plane not found"

    source_normal, source_center, source_count = source_plane
    target_normal, target_center, target_count = target_plane
    source_points = np.asarray(source.points)
    candidates = []
    for sign in (1.0, -1.0):
        normal_rot = rotation_between_vectors(source_normal * sign, target_normal)
        aligned_center = normal_rot @ source_center
        base = np.eye(4, dtype=np.float64)
        base[:3, :3] = normal_rot
        base[:3, 3] = target_center - aligned_center

        source_aligned = (source_points @ normal_rot.T) + base[:3, 3]
        base[:3, 3] += robust_center(np.asarray(target.points)) - robust_center(source_aligned)
        candidates.append(base)

        yaw_step = max(10.0, float(yaw_step_deg))
        for angle in np.deg2rad(np.arange(-90.0, 91.0, yaw_step, dtype=np.float64)):
            if abs(float(angle)) < 1e-6:
                continue
            candidates.append(transform_about_axis(base, target_normal, target_center, angle))

    return candidates, f"plane RS={source_count} OAK={target_count}"


def candidate_transform(yaw, pitch, roll, source_points, target_center):
    rot = rotation_matrix(yaw, pitch, roll).astype(np.float64)
    source_center = robust_center(source_points @ rot.T)
    return transform_from_ypr_translation(yaw, pitch, roll, target_center - source_center)


def transform_tilt_penalty(transform):
    _yaw, pitch, roll = ypr_from_rotation_matrix(transform[:3, :3])
    return abs(float(np.rad2deg(pitch))) + abs(float(np.rad2deg(roll))) * 0.65


def registration_score(result, transform, constrained):
    if result is None:
        return -1e9
    score = (float(result.fitness) * 4.0) - float(result.inlier_rmse)
    if constrained:
        score -= 0.012 * transform_tilt_penalty(transform)
    return score


def refine_icp(source, target, init, voxel_m, point_to_plane=True):
    o3d = get_o3d()
    transform = np.asarray(init, dtype=np.float64)
    best = None
    estimation = (
        o3d.pipelines.registration.TransformationEstimationPointToPlane()
        if point_to_plane
        else o3d.pipelines.registration.TransformationEstimationPointToPoint()
    )
    for threshold in (max(0.45, voxel_m * 10.0), max(0.22, voxel_m * 5.0), max(0.10, voxel_m * 2.5)):
        result = o3d.pipelines.registration.registration_icp(
            source,
            target,
            threshold,
            transform,
            estimation,
            o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=35),
        )
        transform = result.transformation
        best = result
    return best


def constrained_pose_candidates(source, target, voxel_m, yaw_step_deg, max_tilt_deg, initial_transform=None):
    source_points = np.asarray(source.points)
    target_points = np.asarray(target.points)
    target_center = robust_center(target_points)
    candidates = [np.asarray(initial_transform, dtype=np.float64) if initial_transform is not None else current_rs_transform_matrix()]
    current_yaw, _current_pitch, _current_roll = ypr_from_rotation_matrix(candidates[0][:3, :3])

    yaw_step = max(5.0, float(yaw_step_deg))
    yaws = np.deg2rad(np.arange(-180.0, 180.0, yaw_step, dtype=np.float64))
    tilt = np.deg2rad(float(max_tilt_deg))
    tilt_values = [0.0, -tilt * 0.5, tilt * 0.5]
    for yaw in yaws:
        for pitch in tilt_values:
            candidates.append(candidate_transform(float(yaw), float(pitch), 0.0, source_points, target_center))
    for delta in np.deg2rad(np.array([-45, -30, -15, 0, 15, 30, 45], dtype=np.float64)):
        candidates.append(candidate_transform(float(current_yaw + delta), 0.0, 0.0, source_points, target_center))
    return candidates


def auto_align_realsense_to_oak(
    oak_pts,
    raw_rs_pts,
    voxel_m=0.045,
    constrained=True,
    yaw_step_deg=15.0,
    max_tilt_deg=25.0,
    initial_transform=None,
    apply_result=True,
):
    if oak_pts is None or raw_rs_pts is None or oak_pts.shape[0] < 2000 or raw_rs_pts.shape[0] < 2000:
        return None, "need more OAK/RealSense points"

    target = make_o3d_cloud(oak_pts, voxel_m)
    source = make_o3d_cloud(raw_rs_pts, voxel_m)
    if len(target.points) < 500 or len(source.points) < 500:
        return None, "not enough downsampled points"

    ensure_normals(target, voxel_m)
    ensure_normals(source, voxel_m)
    candidates = []
    global_result = None
    plane_text = "plane skipped"
    if constrained:
        plane_candidates, plane_text = plane_alignment_candidates(source, target, voxel_m, yaw_step_deg)
        candidates.extend(plane_candidates)
        candidates.extend(constrained_pose_candidates(source, target, voxel_m, yaw_step_deg, max_tilt_deg, initial_transform))
    else:
        candidates.append(np.asarray(initial_transform, dtype=np.float64) if initial_transform is not None else current_rs_transform_matrix())
        global_result = coarse_global_alignment(source, target, voxel_m)
        if global_result is not None and global_result.fitness > 0.05:
            candidates.append(global_result.transformation)

    best = None
    best_score = -1e9
    best_idx = -1
    for idx, init in enumerate(candidates):
        try:
            result = refine_icp(source, target, init, voxel_m, point_to_plane=True)
        except Exception:
            result = refine_icp(source, target, init, voxel_m, point_to_plane=False)
        score = registration_score(result, result.transformation if result is not None else init, constrained)
        if score > best_score:
            best = result
            best_score = score
            best_idx = idx

    if best is None:
        return None, "ICP failed"

    transform = best.transformation
    if apply_result:
        set_rs_transform_matrix(transform)
    global_text = f"plane+constrained {plane_text}" if constrained else ("global skipped" if global_result is None else f"global fitness={global_result.fitness:.3f}")
    return transform, f"{global_text} best={best_idx} score={best_score:.3f} | ICP fitness={best.fitness:.3f} rmse={best.inlier_rmse:.3f} pts RS={len(source.points)} OAK={len(target.points)}"


def auto_align_worker(out_queue, oak_pts, raw_rs_pts, voxel_m, constrained, yaw_step_deg, max_tilt_deg, initial_transform):
    try:
        transform, status = auto_align_realsense_to_oak(
            oak_pts,
            raw_rs_pts,
            voxel_m,
            constrained=constrained,
            yaw_step_deg=yaw_step_deg,
            max_tilt_deg=max_tilt_deg,
            initial_transform=initial_transform,
            apply_result=False,
        )
        out_queue.put(("ok", transform, status))
    except Exception as exc:
        out_queue.put(("error", None, f"{type(exc).__name__}: {exc}"))


def texture_refine_worker(out_queue, oak_pts, oak_colors, rs_pts, rs_colors, initial_transform):
    try:
        transform, status = refine_alignment_by_texture(
            oak_pts,
            oak_colors,
            rs_pts,
            rs_colors,
            initial_transform=initial_transform,
            apply_result=False,
        )
        out_queue.put(("ok", transform, status))
    except Exception as exc:
        out_queue.put(("error", None, f"{type(exc).__name__}: {exc}"))


def main():
    args = parse_args()
    oak_args = argparse.Namespace(
        fast_foundation_dir=oak.DEFAULT_FAST_FOUNDATION_DIR,
        fast_foundation_model=oak.DEFAULT_FAST_FOUNDATION_MODEL,
        fast_foundation_iters=args.fast_foundation_iters,
        torch_compile=args.torch_compile,
        foundation_scale=args.foundation_scale,
        fast_live_zfar=args.z_far,
    )

    oak.VIEW = oak.ViewState()
    config = oak.PRESETS[args.preset]
    pipeline, rgb_queue, depth_queue, left_queue, right_queue = oak.create_pipeline(config)
    cv2.namedWindow(VIEW_WIN, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(VIEW_WIN, 1200, 900)
    cv2.setMouseCallback(VIEW_WIN, fusion_on_mouse)
    create_controls(args)

    pipeline.start()
    device = pipeline.getDefaultDevice()
    calib = device.readCalibration()
    oak.VIEW.fast_live_enabled = True
    oak.VIEW.foundation_view_enabled = True
    oak.VIEW.fast_live_color_source = args.fast_live_color_source
    oak.VIEW.fast_live_worker = oak.FastFoundationLiveWorker(oak_args, calib)

    rs_capture = None
    rs_error = ""
    if args.realsense:
        try:
            rs_capture = RealSenseLive(args.rs_width, args.rs_height, args.rs_fps)
        except Exception as exc:
            rs_error = str(exc)
            print(f"RealSense unavailable: {rs_error}", flush=True)

    mode_index = MODES.index(args.start_mode)
    color = None
    depth_m = None
    rect_left = None
    rect_right = None
    last_submit = 0.0
    fps_oak_rgb = 0.0
    fps_oak_depth = 0.0
    fps_render = 0.0
    oak_rgb_count = 0
    oak_depth_count = 0
    render_count = 0
    last_fps = time.perf_counter()
    align_status = "not run"
    align_proc = None
    align_queue = None
    mesh_debug = False
    auto_align_pending = bool(args.auto_align_on_start)
    loop_count = 0
    exit_reason = "pipeline stopped"

    try:
        while pipeline.isRunning():
            loop_count += 1
            rgb_msg, rgb_count = oak.drain_latest(rgb_queue)
            depth_msg, depth_count = oak.drain_latest(depth_queue)
            left_msg, _left_count = oak.drain_latest(left_queue)
            right_msg, _right_count = oak.drain_latest(right_queue)
            if rgb_msg is not None:
                color = rgb_msg.getCvFrame()
            if depth_msg is not None:
                depth_m = depth_msg.getFrame().astype(np.float32) * 0.001
            if left_msg is not None:
                rect_left = left_msg.getCvFrame()
            if right_msg is not None:
                rect_right = right_msg.getCvFrame()
            oak_rgb_count += rgb_count
            oak_depth_count += depth_count
            if rs_capture is not None:
                rs_capture.update()

            now = time.perf_counter()
            if now - last_fps >= 0.5:
                elapsed = now - last_fps
                fps_oak_rgb = oak_rgb_count / max(1e-6, elapsed)
                fps_oak_depth = oak_depth_count / max(1e-6, elapsed)
                fps_render = render_count / max(1e-6, elapsed)
                oak_rgb_count = 0
                oak_depth_count = 0
                render_count = 0
                last_fps = now

            if (
                rect_left is not None
                and rect_right is not None
                and color is not None
                and (now - last_submit) >= float(args.fast_live_interval)
            ):
                oak_args.fast_foundation_iters = fast_iters_control()
                oak.VIEW.fast_live_worker.submit(rect_left, rect_right, color)
                last_submit = now

            key = cv2.waitKey(1)
            if key >= 0:
                key = key & 0xFF
                if args.debug_loop:
                    print(f"key={key} loop={loop_count}", flush=True)
                if key in (27, ord("q")):
                    exit_reason = f"quit key {key}"
                    break
                if key in (81, 84):
                    oak_args.fast_foundation_iters = max(1, int(oak_args.fast_foundation_iters) - 1)
                    align_status = f"FastFoundation iters={oak_args.fast_foundation_iters}"
                elif key in (82, 83):
                    oak_args.fast_foundation_iters = min(32, int(oak_args.fast_foundation_iters) + 1)
                    align_status = f"FastFoundation iters={oak_args.fast_foundation_iters}"
                elif key == ord("m"):
                    mode_index = (mode_index + 1) % len(MODES)
                    oak.VIEW.orbit_center = None
                elif key == ord("7"):
                    mode_index = MODES.index("raw_realsense")
                    oak.VIEW.orbit_center = None
                    align_status = "showing raw untransformed RealSense"
                elif key == ord("c"):
                    modes = ["projected-rgb", "left", "rgb"]
                    oak.VIEW.fast_live_color_source = modes[(modes.index(oak.VIEW.fast_live_color_source) + 1) % len(modes)]
                elif key == ord("r"):
                    oak.VIEW.yaw = np.deg2rad(45.0)
                    oak.VIEW.pitch = np.deg2rad(-75.0)
                    oak.VIEW.zoom = 340.0
                    oak.VIEW.pan_x = 0.0
                    oak.VIEW.pan_y = 0.0
                    oak.VIEW.orbit_center = None
                elif key == ord("x"):
                    oak.VIEW.orbit_center = None
                elif key == ord("v"):
                    mesh_debug = not mesh_debug
                elif key == ord("b"):
                    transform, status = charuco_rs_to_oak_transform(rect_left, color, calib, rs_capture)
                    if transform is not None:
                        set_rs_transform_matrix(transform)
                        oak.VIEW.orbit_center = None
                    align_status = status
                elif key == ord("1"):
                    oak.VIEW.pick_target = "oak"
                    oak.VIEW.calib_status = "click OAK feature"
                elif key == ord("2"):
                    oak.VIEW.pick_target = "rs"
                    oak.VIEW.calib_status = "click RealSense feature"
                elif key == ord("3"):
                    align_status = apply_correspondence_calibration()
                elif key == ord("t"):
                    if align_proc is not None and align_proc.is_alive():
                        align_status = "align already running"
                    elif oak.VIEW.foundation_points is None or oak.VIEW.foundation_colors is None:
                        align_status = "texture refine needs OAK points"
                    else:
                        rs_pts_current, rs_colors_current = realsense_cloud(rs_capture, *oak.get_depth_limits())
                        if rs_pts_current.shape[0] < 2000:
                            align_status = "texture refine needs RealSense points"
                        else:
                            ctx = mp.get_context("spawn")
                            align_queue = ctx.Queue()
                            align_proc = ctx.Process(
                                target=texture_refine_worker,
                                args=(
                                    align_queue,
                                    oak.VIEW.foundation_points.copy(),
                                    oak.VIEW.foundation_colors.copy(),
                                    rs_pts_current.copy(),
                                    rs_colors_current.copy(),
                                    current_rs_transform_matrix(),
                                ),
                                daemon=True,
                            )
                            align_proc.start()
                            align_status = "texture refine running"
                elif key == ord("0"):
                    oak.VIEW.calib_pairs = []
                    oak.VIEW.pending_oak_pick = None
                    oak.VIEW.pending_rs_pick = None
                    oak.VIEW.pick_target = None
                    oak.VIEW.calib_status = "cleared correspondence pairs"
                elif key == ord("9"):
                    set_rs_transform_controls(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                    align_status = "RealSense transform reset"
                    oak.VIEW.orbit_center = None
                elif key == ord("i"):
                    raw_rs_pts, _raw_rs_colors = realsense_cloud(rs_capture, *oak.get_depth_limits(), apply_transform=False)
                    _transform, align_status = safe_plane_voxel_align(
                        oak.VIEW.foundation_points,
                        raw_rs_pts,
                        voxel_m=max(0.06, args.icp_voxel_m * 1.5),
                        yaw_step_deg=max(5.0, args.align_yaw_step_deg),
                    )
                elif key == ord("I"):
                    if not args.enable_open3d_align:
                        align_status = "Open3D align disabled by --no-enable-open3d-align"
                    elif align_proc is not None and align_proc.is_alive():
                        align_status = "align already running"
                    else:
                        raw_rs_pts, _raw_rs_colors = realsense_cloud(rs_capture, *oak.get_depth_limits(), apply_transform=False)
                        if oak.VIEW.foundation_points is None or raw_rs_pts.shape[0] < 2000:
                            align_status = "need more OAK/RealSense points"
                        else:
                            ctx = mp.get_context("spawn")
                            align_queue = ctx.Queue()
                            align_proc = ctx.Process(
                                target=auto_align_worker,
                                args=(
                                    align_queue,
                                    oak.VIEW.foundation_points.copy(),
                                    raw_rs_pts.copy(),
                                    args.icp_voxel_m,
                                    False,
                                    args.align_yaw_step_deg,
                                    args.align_max_tilt_deg,
                                    current_rs_transform_matrix(),
                                ),
                                daemon=True,
                            )
                            align_proc.start()
                            align_status = "Open3D align subprocess running..."

            stride, znear, zfar, _edge, _island, point_size, _render_every = oak.get_controls()
            oak_args.fast_foundation_iters = fast_iters_control()
            oak_pts = oak.VIEW.foundation_points
            oak_colors = oak.VIEW.foundation_colors
            raw_rs_pts, rs_colors = realsense_cloud(rs_capture, znear, zfar, apply_transform=False)
            if auto_align_pending and oak_pts is not None and oak_pts.shape[0] > 5000 and raw_rs_pts.shape[0] > 5000:
                _transform, align_status = safe_plane_voxel_align(
                    oak_pts,
                    raw_rs_pts,
                    voxel_m=max(0.06, args.icp_voxel_m * 1.5),
                    yaw_step_deg=max(5.0, args.align_yaw_step_deg),
                )
                auto_align_pending = False

            if align_proc is not None:
                got_align_result = False
                if align_queue is not None:
                    try:
                        state, transform, status = align_queue.get_nowait()
                        got_align_result = True
                        if state == "ok" and transform is not None:
                            set_rs_transform_matrix(transform)
                            align_status = status
                        else:
                            align_status = f"align failed: {status}"
                    except queue.Empty:
                        pass
                if got_align_result:
                    align_proc.join(timeout=0.2)
                    align_proc = None
                    align_queue = None
                elif not align_proc.is_alive():
                    exit_code = align_proc.exitcode
                    align_proc.join(timeout=0.2)
                    align_proc = None
                    align_queue = None
                    align_status = f"align subprocess crashed exit={exit_code}"
            rs_pts, rs_colors = realsense_cloud(rs_capture, znear, zfar)
            oak.VIEW.last_oak_pts = oak_pts
            oak.VIEW.last_rs_pts = rs_pts
            oak_grid = (
                getattr(oak.VIEW, "foundation_grid_points", None),
                getattr(oak.VIEW, "foundation_grid_colors", None),
                getattr(oak.VIEW, "foundation_grid_valid", None),
            )
            rs_grid = realsense_grid_cloud(rs_capture, znear, zfar)

            mode = MODES[mode_index]
            if mode == "oak":
                pts = oak_pts if oak_pts is not None else np.empty((0, 3), dtype=np.float32)
                colors = oak_colors if oak_colors is not None else np.empty((0, 3), dtype=np.uint8)
                label = "OAK FastFoundationStereo"
            elif mode == "realsense":
                pts, colors = rs_pts, rs_colors
                label = "RealSense laser depth"
            elif mode == "raw_realsense":
                pts, colors = raw_rs_pts, rs_colors
                label = "Raw RealSense laser depth"
            else:
                pts, colors = combine_clouds(oak_pts, oak_colors, rs_pts, rs_colors)
                label = "Combined OAK + RealSense"

            if mesh_debug and mode == "combined":
                view = project_alignment_debug(oak_pts, oak_colors, oak_grid, rs_pts, rs_colors, rs_grid, point_size)
            else:
                view = project_fusion_point_arrays(pts, colors, point_size)
            render_count += 1
            tx, ty, tz, yaw, pitch, roll = rs_transform_controls()
            timing = getattr(oak.VIEW, "fast_live_timing", {}) or {}
            timing_line = (
                "fast timing ms "
                f"pre={timing.get('pre_ms', 0.0):.1f} "
                f"up={timing.get('upload_ms', 0.0):.1f} "
                f"model={timing.get('model_ms', 0.0):.1f} "
                f"down={timing.get('download_ms', 0.0):.1f} "
                f"cloud={timing.get('cloud_ms', 0.0):.1f}"
            )
            lines = [
                f"{label} | mode={mode} | m switch | 7 raw RS | b ChArUco | i safe align | I Open3D align | v mesh {'on' if mesh_debug else 'off'} | x refocus | c color | r reset | q quit",
                f"manual/texture: fast iters={oak_args.fast_foundation_iters} | 1 pick OAK | 2 pick RS | 3 solve | t texture refine | 9 reset RS | 0 clear | pairs={len(getattr(oak.VIEW, 'calib_pairs', []))} {getattr(oak.VIEW, 'calib_status', '')}",
                f"OAK rgb {fps_oak_rgb:.1f}fps depth {fps_oak_depth:.1f}fps fast {oak.VIEW.fast_live_fps:.1f}fps done={oak.VIEW.fast_live_done_count} color={oak.VIEW.fast_live_color_source} compile={'on' if oak_args.torch_compile else 'off'}",
                timing_line,
                f"RealSense {'on' if rs_capture is not None else 'off'} {0.0 if rs_capture is None else rs_capture.fps_est:.1f}fps {rs_error}",
                f"z={znear:.2f}-{zfar:.2f}m | OAK pts={0 if oak_pts is None else oak_pts.shape[0]} RS raw={raw_rs_pts.shape[0]} RS xform={rs_pts.shape[0]} shown={pts.shape[0]}",
                f"RS->OAK x={tx:.2f} y={ty:.2f} z={tz:.2f}m yaw={np.rad2deg(yaw):.0f} pitch={np.rad2deg(pitch):.0f} roll={np.rad2deg(roll):.0f}",
                f"auto align: {align_status}",
            ]
            draw_lines(view, lines)
            cv2.imshow(VIEW_WIN, view)
            if args.debug_loop and loop_count % 120 == 0:
                print(
                    "loop "
                    f"{loop_count} oak_pts={0 if oak_pts is None else oak_pts.shape[0]} "
                    f"rs_pts={rs_pts.shape[0]} fast_done={oak.VIEW.fast_live_done_count} "
                    f"mode={mode}",
                    flush=True,
                )
    finally:
        print(f"Fusion viewer exiting: {exit_reason}; loops={loop_count}", flush=True)
        cv2.destroyAllWindows()
        if oak.VIEW.fast_live_worker is not None:
            oak.VIEW.fast_live_worker.stop()
        if rs_capture is not None:
            rs_capture.close()
        if align_proc is not None and align_proc.is_alive():
            align_proc.terminate()
            align_proc.join(timeout=1.0)
        try:
            pipeline.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
