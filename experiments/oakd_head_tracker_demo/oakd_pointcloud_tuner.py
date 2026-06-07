import argparse
import glob
import os
import subprocess
import sys
import threading
import time
import traceback

import cv2
import depthai as dai
import numpy as np


PRESETS = {
    "smooth": {
        "width": 640,
        "height": 360,
        "fps": 30.0,
        "rgb_res": "1080p",
        "mono_res": "400p",
        "stereo_preset": "fast_density",
        "lr_check": True,
        "subpixel": True,
        "confidence": 80,
        "median": "3x3",
        "speckle": True,
        "speckle_range": 80,
    },
    "speed_raw": {
        "width": 640,
        "height": 360,
        "fps": 30.0,
        "rgb_res": "1080p",
        "mono_res": "400p",
        "stereo_preset": "fast_density",
        "lr_check": False,
        "subpixel": False,
        "confidence": 60,
        "median": "off",
        "speckle": False,
        "speckle_range": 0,
    },
    "balanced": {
        "width": 1024,
        "height": 576,
        "fps": 30.0,
        "rgb_res": "1080p",
        "mono_res": "800p",
        "stereo_preset": "fast_density",
        "lr_check": True,
        "subpixel": True,
        "confidence": 120,
        "median": "7x7",
        "speckle": True,
        "speckle_range": 50,
    },
    "dense": {
        "width": 1024,
        "height": 576,
        "fps": 30.0,
        "rgb_res": "1080p",
        "mono_res": "800p",
        "stereo_preset": "density",
        "lr_check": True,
        "subpixel": True,
        "confidence": 80,
        "median": "5x5",
        "speckle": True,
        "speckle_range": 80,
    },
    "clean": {
        "width": 1024,
        "height": 576,
        "fps": 30.0,
        "rgb_res": "1080p",
        "mono_res": "800p",
        "stereo_preset": "fast_accuracy",
        "lr_check": True,
        "subpixel": True,
        "confidence": 180,
        "median": "7x7",
        "speckle": True,
        "speckle_range": 40,
    },
    "fast": {
        "width": 640,
        "height": 360,
        "fps": 30.0,
        "rgb_res": "1080p",
        "mono_res": "400p",
        "stereo_preset": "fast_density",
        "lr_check": True,
        "subpixel": True,
        "confidence": 100,
        "median": "5x5",
        "speckle": True,
        "speckle_range": 60,
    },
}

COLOR_RESOLUTIONS = {
    "720p": dai.ColorCameraProperties.SensorResolution.THE_720_P,
    "800p": dai.ColorCameraProperties.SensorResolution.THE_800_P,
    "1080p": dai.ColorCameraProperties.SensorResolution.THE_1080_P,
}
MONO_RESOLUTIONS = {
    "400p": dai.MonoCameraProperties.SensorResolution.THE_400_P,
    "480p": dai.MonoCameraProperties.SensorResolution.THE_480_P,
    "720p": dai.MonoCameraProperties.SensorResolution.THE_720_P,
    "800p": dai.MonoCameraProperties.SensorResolution.THE_800_P,
}
STEREO_PRESETS = {
    "default": dai.node.StereoDepth.PresetMode.DEFAULT,
    "density": dai.node.StereoDepth.PresetMode.DENSITY,
    "fast_density": dai.node.StereoDepth.PresetMode.FAST_DENSITY,
    "fast_accuracy": dai.node.StereoDepth.PresetMode.FAST_ACCURACY,
}
MEDIAN_FILTERS = {
    "off": dai.MedianFilter.MEDIAN_OFF,
    "3x3": dai.MedianFilter.KERNEL_3x3,
    "5x5": dai.MedianFilter.KERNEL_5x5,
    "7x7": dai.MedianFilter.KERNEL_7x7,
}

VIEW_WIN = "OAK-D 3D Point Cloud Tuner"
CTRL_WIN = "OAK-D Live Cleanup Controls"
FOUNDATION_WIN = "FoundationStereo Output"
SNAPSHOT_DIR = os.path.join(os.path.dirname(__file__), "pointcloud_snapshots")
FOUNDATION_RUN_DIR = os.path.join(os.path.dirname(__file__), "foundation_stereo_runs")
EXTERNAL_DIR = os.path.join(os.path.dirname(__file__), "external")
DEFAULT_FAST_FOUNDATION_DIR = os.path.join(EXTERNAL_DIR, "Fast-FoundationStereo")
DEFAULT_FAST_FOUNDATION_MODEL = os.path.join(
    DEFAULT_FAST_FOUNDATION_DIR, "weights", "20-30-48", "model_best_bp2_serialize.pth"
)
DEFAULT_FOUNDATION_DIR = os.path.join(EXTERNAL_DIR, "FoundationStereo")
DEFAULT_FOUNDATION_MODEL = os.path.join(
    os.path.dirname(__file__), "deployable_foundationstereo_small_576x960_v2.0.onnx"
)

RUNTIME_PRESETS = {
    "dense": {"stride": 1, "min_cm": 20, "max_cm": 450, "edge_cm": 25, "island": 0, "point_size": 1, "render_every": 1},
    "balanced": {"stride": 1, "min_cm": 20, "max_cm": 450, "edge_cm": 0, "island": 0, "point_size": 1, "render_every": 1},
    "clean": {"stride": 2, "min_cm": 25, "max_cm": 350, "edge_cm": 7, "island": 350, "point_size": 2, "render_every": 1},
    "mesh_safe": {"stride": 1, "min_cm": 25, "max_cm": 300, "edge_cm": 5, "island": 800, "point_size": 2, "render_every": 2},
}
RUNTIME_PRESET_NAMES = ["dense", "balanced", "clean", "mesh_safe"]


class ViewState:
    def __init__(self):
        self.yaw = np.deg2rad(45.0)
        self.pitch = np.deg2rad(-75.0)
        self.zoom = 340.0
        self.pan_x = 0.0
        self.pan_y = 0.0
        self.drag_button = None
        self.last_x = 0
        self.last_y = 0
        self.runtime_preset_index = 1
        self.snapshots = []
        self.snapshot_index = -1
        self.compare_mode = False
        self.status = "ready"
        self.last_key = -1
        self.foundation_busy = False
        self.foundation_preview = None
        self.foundation_preview_title = ""
        self.foundation_last_output = ""
        self.foundation_points = None
        self.foundation_colors = None
        self.foundation_label = ""
        self.foundation_view_enabled = False
        self.fast_live_enabled = False
        self.last_fast_live_start = 0.0
        self.fast_live_worker = None
        self.fast_live_fps = 0.0
        self.fast_live_inflight = False
        self.fast_live_color_source = "rgb"
        self.foundation_render_cache_key = None
        self.foundation_render_cache = None
        self.foundation_frame_version = 0
        self.fast_live_submit_count = 0
        self.fast_live_done_count = 0
        self.fast_live_error_count = 0
        self.fast_live_timing = {}


VIEW = ViewState()


def parse_args():
    parser = argparse.ArgumentParser(description="Standalone OAK-D point-cloud preview/tuner. No Godot or webstack.")
    parser.add_argument("--preset", choices=sorted(PRESETS), default="smooth")
    parser.add_argument("--hard-exit", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--foundation-python", default=os.environ.get("FOUNDATIONSTEREO_PYTHON", sys.executable))
    parser.add_argument("--fast-foundation-dir", default=os.environ.get("FAST_FOUNDATIONSTEREO_DIR", DEFAULT_FAST_FOUNDATION_DIR))
    parser.add_argument("--fast-foundation-model", default=os.environ.get("FAST_FOUNDATIONSTEREO_MODEL", DEFAULT_FAST_FOUNDATION_MODEL))
    parser.add_argument("--foundation-dir", default=os.environ.get("FOUNDATIONSTEREO_DIR", DEFAULT_FOUNDATION_DIR))
    parser.add_argument("--foundation-model", default=os.environ.get("FOUNDATIONSTEREO_MODEL", DEFAULT_FOUNDATION_MODEL))
    parser.add_argument("--foundation-scale", type=float, default=0.5)
    parser.add_argument("--fast-foundation-iters", type=int, default=4)
    parser.add_argument("--foundation-iters", type=int, default=16)
    parser.add_argument("--fast-live-interval", type=float, default=0.0)
    parser.add_argument("--fast-live-zfar", type=float, default=100.0)
    parser.add_argument("--fast-live-color-source", choices=("left", "projected-rgb", "rgb"), default="rgb")
    parser.add_argument("--torch-compile", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--start-fast-live", action="store_true", help="Start the in-process Fast-FoundationStereo worker automatically.")
    return parser.parse_args()


def create_pipeline(config):
    pipeline = dai.Pipeline()

    color = pipeline.create(dai.node.ColorCamera)
    color.setBoardSocket(dai.CameraBoardSocket.CAM_A)
    color.setResolution(COLOR_RESOLUTIONS[config["rgb_res"]])
    color.setPreviewSize(config["width"], config["height"])
    if config["rgb_res"] == "1080p" and config["width"] == 640 and config["height"] == 360:
        color.setIspScale(1, 3)
    color.setInterleaved(False)
    color.setColorOrder(dai.ColorCameraProperties.ColorOrder.BGR)
    color.setFps(config["fps"])

    mono_left = pipeline.create(dai.node.MonoCamera)
    mono_right = pipeline.create(dai.node.MonoCamera)
    mono_left.setBoardSocket(dai.CameraBoardSocket.CAM_B)
    mono_right.setBoardSocket(dai.CameraBoardSocket.CAM_C)
    mono_left.setResolution(MONO_RESOLUTIONS[config["mono_res"]])
    mono_right.setResolution(MONO_RESOLUTIONS[config["mono_res"]])
    mono_left.setFps(config["fps"])
    mono_right.setFps(config["fps"])

    stereo = pipeline.create(dai.node.StereoDepth)
    stereo.setDefaultProfilePreset(STEREO_PRESETS[config["stereo_preset"]])
    stereo.setDepthAlign(dai.CameraBoardSocket.CAM_A)
    stereo.setOutputSize(config["width"], config["height"])
    stereo.setLeftRightCheck(config["lr_check"])
    stereo.setSubpixel(config["subpixel"])
    stereo.initialConfig.setConfidenceThreshold(int(config["confidence"]))
    stereo.initialConfig.setMedianFilter(MEDIAN_FILTERS[config["median"]])
    stereo.initialConfig.postProcessing.speckleFilter.enable = bool(config["speckle"])
    stereo.initialConfig.postProcessing.speckleFilter.speckleRange = int(config["speckle_range"])

    mono_left.out.link(stereo.left)
    mono_right.out.link(stereo.right)

    return (
        pipeline,
        color.isp.createOutputQueue(maxSize=2, blocking=False),
        stereo.depth.createOutputQueue(maxSize=2, blocking=False),
        stereo.rectifiedLeft.createOutputQueue(maxSize=2, blocking=False),
        stereo.rectifiedRight.createOutputQueue(maxSize=2, blocking=False),
    )


def create_controls():
    cv2.namedWindow(CTRL_WIN, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(CTRL_WIN, 520, 260)
    cv2.createTrackbar("stride", CTRL_WIN, 1, 12, lambda _v: None)
    cv2.createTrackbar("z near cm", CTRL_WIN, 20, 250, lambda _v: None)
    cv2.createTrackbar("z far cm", CTRL_WIN, 450, 2000, lambda _v: None)
    cv2.createTrackbar("edge reject cm", CTRL_WIN, 0, 100, lambda _v: None)
    cv2.createTrackbar("min island px", CTRL_WIN, 0, 4000, lambda _v: None)
    cv2.createTrackbar("point size", CTRL_WIN, 1, 8, lambda _v: None)
    cv2.createTrackbar("render every N depth", CTRL_WIN, 1, 8, lambda _v: None)
    cv2.createTrackbar("rgb u offset", CTRL_WIN, 100, 200, lambda _v: None)
    cv2.createTrackbar("rgb v offset", CTRL_WIN, 100, 200, lambda _v: None)


def apply_runtime_preset(name):
    preset = RUNTIME_PRESETS[name]
    cv2.setTrackbarPos("stride", CTRL_WIN, preset["stride"])
    cv2.setTrackbarPos("z near cm", CTRL_WIN, preset["min_cm"])
    cv2.setTrackbarPos("z far cm", CTRL_WIN, preset["max_cm"])
    cv2.setTrackbarPos("edge reject cm", CTRL_WIN, preset["edge_cm"])
    cv2.setTrackbarPos("min island px", CTRL_WIN, preset["island"])
    cv2.setTrackbarPos("point size", CTRL_WIN, preset["point_size"])
    cv2.setTrackbarPos("render every N depth", CTRL_WIN, preset["render_every"])


def get_controls():
    stride = max(1, cv2.getTrackbarPos("stride", CTRL_WIN))
    min_depth = max(1, cv2.getTrackbarPos("z near cm", CTRL_WIN)) / 100.0
    max_depth = max(min_depth + 0.05, cv2.getTrackbarPos("z far cm", CTRL_WIN) / 100.0)
    edge_reject = cv2.getTrackbarPos("edge reject cm", CTRL_WIN) / 100.0
    min_island = cv2.getTrackbarPos("min island px", CTRL_WIN)
    point_size = max(1, cv2.getTrackbarPos("point size", CTRL_WIN))
    render_every = max(1, cv2.getTrackbarPos("render every N depth", CTRL_WIN))
    return stride, min_depth, max_depth, edge_reject, min_island, point_size, render_every


def get_depth_limits(default_max=100.0):
    try:
        _stride, min_depth, max_depth, _edge_reject, _min_island, _point_size, _render_every = get_controls()
        return float(min_depth), float(max_depth)
    except Exception:
        return 0.01, float(default_max)


def get_rgb_projection_offsets():
    try:
        return (
            int(cv2.getTrackbarPos("rgb u offset", CTRL_WIN)) - 100,
            int(cv2.getTrackbarPos("rgb v offset", CTRL_WIN)) - 100,
        )
    except Exception:
        return 0, 0


def on_mouse(event, x, y, flags, _userdata):
    if event == cv2.EVENT_LBUTTONDOWN:
        VIEW.drag_button = "orbit"
        VIEW.last_x = x
        VIEW.last_y = y
    elif event == cv2.EVENT_RBUTTONDOWN:
        VIEW.drag_button = "pan"
        VIEW.last_x = x
        VIEW.last_y = y
    elif event in (cv2.EVENT_LBUTTONUP, cv2.EVENT_RBUTTONUP):
        VIEW.drag_button = None
    elif event == cv2.EVENT_MOUSEMOVE and VIEW.drag_button is not None:
        dx = x - VIEW.last_x
        dy = y - VIEW.last_y
        VIEW.last_x = x
        VIEW.last_y = y
        if VIEW.drag_button == "orbit":
            VIEW.yaw += dx * 0.008
            VIEW.pitch = float(np.clip(VIEW.pitch + dy * 0.008, -np.pi * 0.49, np.pi * 0.49))
        elif VIEW.drag_button == "pan":
            VIEW.pan_x += dx
            VIEW.pan_y += dy
    elif event == cv2.EVENT_MOUSEWHEEL:
        wheel = 1.0 if flags > 0 else -1.0
        VIEW.zoom = float(np.clip(VIEW.zoom * (1.12 ** wheel), 40.0, 3000.0))


def cleanup_depth_mask(depth_m, min_depth, max_depth, edge_reject, min_island):
    valid = np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
    if edge_reject > 0.0:
        z = np.where(valid, depth_m, 0.0).astype(np.float32)
        dilated = cv2.dilate(z, np.ones((3, 3), np.uint8))
        eroded_src = np.where(valid, depth_m, 999.0).astype(np.float32)
        eroded = cv2.erode(eroded_src, np.ones((3, 3), np.uint8))
        valid &= (dilated - eroded) <= edge_reject
    if min_island > 0:
        labels, stats = cv2.connectedComponentsWithStats(valid.astype(np.uint8), 8)[1:3]
        keep = np.zeros(valid.shape, dtype=bool)
        for label in range(1, stats.shape[0]):
            if stats[label, cv2.CC_STAT_AREA] >= min_island:
                keep |= labels == label
        valid &= keep
    return valid


def extract_points(depth_m, color, valid, intrinsics, stride):
    h, w = depth_m.shape
    rows = np.arange(0, h, stride, dtype=np.int32)
    cols = np.arange(0, w, stride, dtype=np.int32)
    mask = valid[np.ix_(rows, cols)]
    if not np.any(mask):
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)
    yy, xx = np.meshgrid(rows, cols, indexing="ij")
    z = depth_m[np.ix_(rows, cols)][mask]
    x = (xx[mask].astype(np.float32) - intrinsics[2]) * z / intrinsics[0]
    y = -(yy[mask].astype(np.float32) - intrinsics[3]) * z / intrinsics[1]
    pts = np.stack([x, y, -z], axis=1)
    colors = color[np.ix_(rows, cols)][mask]
    return pts, colors


def project_point_arrays(pts, colors, point_size):
    canvas = np.zeros((900, 1200, 3), dtype=np.uint8)
    if pts.size <= 0:
        return canvas
    cy, sy = np.cos(VIEW.yaw), np.sin(VIEW.yaw)
    cp, sp = np.cos(VIEW.pitch), np.sin(VIEW.pitch)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]], dtype=np.float32)
    rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]], dtype=np.float32)
    view = pts @ (ry @ rx).T

    u = (view[:, 0] * VIEW.zoom + canvas.shape[1] * 0.5 + VIEW.pan_x).astype(np.int32)
    v = (-view[:, 1] * VIEW.zoom + canvas.shape[0] * 0.5 + VIEW.pan_y).astype(np.int32)
    inside = (u >= 0) & (u < canvas.shape[1]) & (v >= 0) & (v < canvas.shape[0])
    if not np.any(inside):
        return canvas
    u, v, colors, depth = u[inside], v[inside], colors[inside], view[inside, 2]
    order = np.argsort(depth)
    for offset_y in range(point_size):
        for offset_x in range(point_size):
            uu = np.clip(u[order] + offset_x, 0, canvas.shape[1] - 1)
            vv = np.clip(v[order] + offset_y, 0, canvas.shape[0] - 1)
            canvas[vv, uu] = colors[order]
    return canvas


def project_points(depth_m, color, valid, intrinsics, stride, point_size):
    pts, colors = extract_points(depth_m, color, valid, intrinsics, stride)
    return project_point_arrays(pts, colors, point_size), int(pts.shape[0])


def project_foundation_points_cached(pts, colors, point_size):
    cache_key = (
        int(VIEW.foundation_frame_version),
        int(point_size),
        round(float(VIEW.yaw), 4),
        round(float(VIEW.pitch), 4),
        round(float(VIEW.zoom), 2),
        round(float(VIEW.pan_x), 1),
        round(float(VIEW.pan_y), 1),
    )
    if VIEW.foundation_render_cache_key == cache_key and VIEW.foundation_render_cache is not None:
        return VIEW.foundation_render_cache.copy()
    view = project_point_arrays(pts, colors, point_size)
    VIEW.foundation_render_cache_key = cache_key
    VIEW.foundation_render_cache = view
    return view.copy()


def drain_latest(queue):
    latest = None
    count = 0
    while True:
        msg = queue.tryGet()
        if msg is None:
            break
        latest = msg
        count += 1
    return latest, count


def save_snapshot(name, depth_m, color, intrinsics):
    preset = RUNTIME_PRESETS[name]
    valid = cleanup_depth_mask(
        depth_m,
        preset["min_cm"] / 100.0,
        preset["max_cm"] / 100.0,
        preset["edge_cm"] / 100.0,
        preset["island"],
    )
    pts, colors = extract_points(depth_m, color, valid, intrinsics, max(1, preset["stride"]))
    os.makedirs(SNAPSHOT_DIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    path = os.path.join(SNAPSHOT_DIR, f"oakd_{stamp}_{name}.npz")
    np.savez_compressed(path, points=pts, colors_bgr=colors, preset=name, valid=valid)
    return {
        "name": name,
        "path": path,
        "points": pts,
        "colors": colors,
        "point_size": max(1, preset["point_size"]),
        "valid_pct": 100.0 * float(np.count_nonzero(valid)) / float(valid.size),
    }


def capture_comparison_snapshots(depth_m, color, intrinsics):
    VIEW.snapshots = [save_snapshot(name, depth_m, color, intrinsics) for name in RUNTIME_PRESET_NAMES]
    VIEW.snapshot_index = 0
    VIEW.compare_mode = True
    print("Saved OAK-D comparison snapshots:")
    for snapshot in VIEW.snapshots:
        print(f"  {snapshot['name']}: {snapshot['points'].shape[0]} points -> {snapshot['path']}")


def get_baseline_m(calib):
    try:
        return float(calib.getBaselineDistance(dai.CameraBoardSocket.CAM_B, dai.CameraBoardSocket.CAM_C, False)) / 100.0
    except Exception:
        return 0.075


def write_intrinsics_file(path, calib, width, height, baseline_m):
    try:
        intr = calib.getCameraIntrinsics(dai.CameraBoardSocket.CAM_B, width, height)
        fx = float(intr[0][0])
        fy = float(intr[1][1])
        cx = float(intr[0][2])
        cy = float(intr[1][2])
    except Exception:
        fx = fy = float(width)
        cx = float(width) * 0.5
        cy = float(height) * 0.5
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"{fx} 0 {cx} 0 {fy} {cy} 0 0 1\n")
        f.write(f"{baseline_m}\n")


def get_left_intrinsics(calib, width, height):
    try:
        intr = calib.getCameraIntrinsics(dai.CameraBoardSocket.CAM_B, width, height)
        return (
            float(intr[0][0]),
            float(intr[1][1]),
            float(intr[0][2]),
            float(intr[1][2]),
        )
    except Exception:
        return float(width), float(width), float(width) * 0.5, float(height) * 0.5


def disparity_to_cloud(disp, color_img, intrinsics, baseline_m, znear, zfar):
    disp = np.asarray(disp, dtype=np.float32)
    finite = np.isfinite(disp) & (disp > 1e-3)
    if not np.any(finite):
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)

    fx, fy, cx, cy = intrinsics
    depth = (float(fx) * float(baseline_m)) / np.where(finite, disp, np.nan)
    valid = np.isfinite(depth) & (depth >= float(znear)) & (depth <= float(zfar))
    if not np.any(valid):
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)

    h, w = disp.shape
    yy, xx = np.meshgrid(np.arange(h, dtype=np.float32), np.arange(w, dtype=np.float32), indexing="ij")
    z = depth[valid].astype(np.float32)
    x = (xx[valid] - float(cx)) * z / float(fx)
    y = -(yy[valid] - float(cy)) * z / float(fy)
    pts = np.stack([x, y, -z], axis=1).astype(np.float32)

    if color_img is None:
        colors = np.full((pts.shape[0], 3), 220, dtype=np.uint8)
    else:
        color_resized = cv2.resize(color_img, (w, h), interpolation=cv2.INTER_LINEAR)
        colors = color_resized[valid].astype(np.uint8)
    return pts, colors


def get_rgb_intrinsics(calib, width, height):
    try:
        intr = calib.getCameraIntrinsics(dai.CameraBoardSocket.CAM_A, width, height)
        return (
            float(intr[0][0]),
            float(intr[1][1]),
            float(intr[0][2]),
            float(intr[1][2]),
        )
    except Exception:
        return float(width), float(width), float(width) * 0.5, float(height) * 0.5


def rectified_left_to_raw_left_points(left_x, left_y, left_z, calib):
    try:
        rect_rot = np.array(calib.getStereoLeftRectificationRotation(), dtype=np.float32)
        if rect_rot.shape != (3, 3):
            return left_x, left_y, left_z
        rect_pts = np.stack([left_x, left_y, left_z], axis=0)
        raw_pts = rect_rot.T @ rect_pts
        return raw_pts[0], raw_pts[1], raw_pts[2]
    except Exception as exc:
        print(f"Left unrectification failed, using rectified coords for RGB projection: {exc}", flush=True)
        return left_x, left_y, left_z


def project_rgb_colors_for_left_points(left_x, left_y, left_z, rgb_img, calib):
    if rgb_img is None or left_z.size <= 0:
        return None
    try:
        extr = np.array(
            calib.getCameraExtrinsics(
                dai.CameraBoardSocket.CAM_B,
                dai.CameraBoardSocket.CAM_A,
                False,
                dai.LengthUnit.METER,
            ),
            dtype=np.float32,
        )
        rgb_h, rgb_w = rgb_img.shape[:2]
        fx, fy, cx, cy = get_rgb_intrinsics(calib, rgb_w, rgb_h)
        raw_x, raw_y, raw_z = rectified_left_to_raw_left_points(left_x, left_y, left_z, calib)
        left_pts = np.stack([raw_x, raw_y, raw_z, np.ones_like(raw_z, dtype=np.float32)], axis=0)
        rgb_pts = extr @ left_pts
        z = rgb_pts[2]
        valid_z = np.isfinite(z) & (z > 1e-4)
        u = np.zeros(z.shape, dtype=np.int32)
        v = np.zeros(z.shape, dtype=np.int32)
        offset_u, offset_v = get_rgb_projection_offsets()
        u[valid_z] = np.rint((rgb_pts[0, valid_z] * fx / z[valid_z]) + cx + offset_u).astype(np.int32)
        v[valid_z] = np.rint((rgb_pts[1, valid_z] * fy / z[valid_z]) + cy + offset_v).astype(np.int32)
        inside = valid_z & (u >= 0) & (u < rgb_w) & (v >= 0) & (v < rgb_h)
        colors = np.full((left_z.shape[0], 3), 180, dtype=np.uint8)
        colors[inside] = rgb_img[v[inside], u[inside]]
        return colors, inside
    except Exception as exc:
        print(f"RGB projection failed, falling back to left mono color: {exc}", flush=True)
        return None


def disparity_to_projected_rgb_cloud(disp, left_color_img, rgb_img, left_intrinsics, baseline_m, znear, zfar, calib):
    disp = np.asarray(disp, dtype=np.float32)
    finite = np.isfinite(disp) & (disp > 1e-3)
    if not np.any(finite):
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)

    fx, fy, cx, cy = left_intrinsics
    depth = (float(fx) * float(baseline_m)) / np.where(finite, disp, np.nan)
    valid = np.isfinite(depth) & (depth >= float(znear)) & (depth <= float(zfar))
    if not np.any(valid):
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)

    h, w = disp.shape
    yy, xx = np.meshgrid(np.arange(h, dtype=np.float32), np.arange(w, dtype=np.float32), indexing="ij")
    z = depth[valid].astype(np.float32)
    x = (xx[valid] - float(cx)) * z / float(fx)
    y = (yy[valid] - float(cy)) * z / float(fy)
    pts = np.stack([x, -y, -z], axis=1).astype(np.float32)

    projected = project_rgb_colors_for_left_points(x, y, z, rgb_img, calib)
    if projected is not None:
        return pts, projected[0]
    return disparity_to_cloud(disp, left_color_img, left_intrinsics, baseline_m, znear, zfar)


def disparity_to_grid_cloud(disp, color_img, intrinsics, baseline_m, znear, zfar, calib=None, rgb_img=None):
    disp = np.asarray(disp, dtype=np.float32)
    h, w = disp.shape
    finite = np.isfinite(disp) & (disp > 1e-3)
    fx, fy, cx, cy = intrinsics
    depth = (float(fx) * float(baseline_m)) / np.where(finite, disp, np.nan)
    valid = np.isfinite(depth) & (depth >= float(znear)) & (depth <= float(zfar))

    yy, xx = np.meshgrid(np.arange(h, dtype=np.float32), np.arange(w, dtype=np.float32), indexing="ij")
    z = np.where(valid, depth, 0.0).astype(np.float32)
    x = (xx - float(cx)) * z / float(fx)
    y = -(yy - float(cy)) * z / float(fy)
    grid_pts = np.stack([x, y, -z], axis=2).astype(np.float32)

    if color_img is None:
        grid_colors = np.full((h, w, 3), 220, dtype=np.uint8)
    else:
        grid_colors = cv2.resize(color_img, (w, h), interpolation=cv2.INTER_LINEAR).astype(np.uint8)

    if rgb_img is not None and calib is not None:
        left_z = z[valid].astype(np.float32)
        left_x = x[valid].astype(np.float32)
        left_y = -y[valid].astype(np.float32)
        projected = project_rgb_colors_for_left_points(left_x, left_y, left_z, rgb_img, calib)
        if projected is not None:
            grid_colors = np.full((h, w, 3), 180, dtype=np.uint8)
            grid_colors[valid] = projected[0]
    return grid_pts, grid_colors, valid


def make_disparity_preview(left_img, right_img, disp):
    disp = np.asarray(disp, dtype=np.float32)
    finite = np.isfinite(disp) & (disp > 0)
    if np.any(finite):
        lo, hi = np.percentile(disp[finite], [2, 98])
        hi = max(float(hi), float(lo) + 1e-3)
        disp_u8 = np.clip((disp - lo) * 255.0 / (hi - lo), 0, 255).astype(np.uint8)
    else:
        disp_u8 = np.zeros(disp.shape, dtype=np.uint8)
    heat = cv2.applyColorMap(disp_u8, cv2.COLORMAP_TURBO)
    left_bgr = left_img if left_img.ndim == 3 else cv2.cvtColor(left_img, cv2.COLOR_GRAY2BGR)
    right_bgr = right_img if right_img.ndim == 3 else cv2.cvtColor(right_img, cv2.COLOR_GRAY2BGR)
    left_bgr = cv2.resize(left_bgr, (disp.shape[1], disp.shape[0]), interpolation=cv2.INTER_LINEAR)
    right_bgr = cv2.resize(right_bgr, (disp.shape[1], disp.shape[0]), interpolation=cv2.INTER_LINEAR)
    return np.concatenate([left_bgr, right_bgr, heat], axis=1)


def make_metric_depth_preview(left_img, right_img, depth_m, znear, zfar):
    depth = np.asarray(depth_m, dtype=np.float32)
    valid = np.isfinite(depth) & (depth >= float(znear)) & (depth <= float(zfar))
    span = max(float(zfar) - float(znear), 1e-3)
    depth_u8 = np.zeros(depth.shape, dtype=np.uint8)
    depth_u8[valid] = np.clip(255.0 * (1.0 - ((depth[valid] - float(znear)) / span)), 0, 255).astype(np.uint8)
    heat = cv2.applyColorMap(depth_u8, cv2.COLORMAP_TURBO)
    heat[~valid] = (20, 20, 20)
    left_bgr = left_img if left_img.ndim == 3 else cv2.cvtColor(left_img, cv2.COLOR_GRAY2BGR)
    right_bgr = right_img if right_img.ndim == 3 else cv2.cvtColor(right_img, cv2.COLOR_GRAY2BGR)
    left_bgr = cv2.resize(left_bgr, (depth.shape[1], depth.shape[0]), interpolation=cv2.INTER_LINEAR)
    right_bgr = cv2.resize(right_bgr, (depth.shape[1], depth.shape[0]), interpolation=cv2.INTER_LINEAR)
    cv2.putText(heat, f"metric depth {znear:.2f}-{zfar:.2f}m", (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 4, cv2.LINE_AA)
    cv2.putText(heat, f"metric depth {znear:.2f}-{zfar:.2f}m", (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 1, cv2.LINE_AA)
    return np.concatenate([left_bgr, right_bgr, heat], axis=1)


def make_metric_depth_preview_from_disparity(left_img, right_img, disp, intrinsics, baseline_m, znear, zfar):
    fx = float(intrinsics[0])
    disp = np.asarray(disp, dtype=np.float32)
    depth = (fx * float(baseline_m)) / np.where(np.isfinite(disp) & (disp > 1e-3), disp, np.nan)
    return make_metric_depth_preview(left_img, right_img, depth, znear, zfar)


class FastFoundationLiveWorker:
    def __init__(self, args, calib):
        self.args = args
        self.calib = calib
        self._cond = threading.Condition()
        self._pending = None
        self._stopped = False
        self._loaded = False
        self._thread = threading.Thread(target=self._loop, name="FastFoundationLiveWorker", daemon=True)
        self._thread.start()

    def submit(self, left_img, right_img, color_img):
        if left_img is None or right_img is None:
            return
        with self._cond:
            VIEW.fast_live_submit_count += 1
            self._pending = (
                left_img.copy(),
                right_img.copy(),
                None if color_img is None else color_img.copy(),
                time.perf_counter(),
            )
            self._cond.notify()

    def stop(self):
        with self._cond:
            self._stopped = True
            self._cond.notify()
        self._thread.join(timeout=2.0)

    def _load_model(self):
        repo_dir = self.args.fast_foundation_dir
        model_path = self.args.fast_foundation_model
        if not repo_dir or not os.path.isdir(repo_dir):
            raise FileNotFoundError(f"Fast-FoundationStereo repo missing: {repo_dir}")
        if not model_path or not os.path.isfile(model_path):
            raise FileNotFoundError(f"Fast-FoundationStereo model missing: {model_path}")

        if repo_dir not in sys.path:
            sys.path.insert(0, repo_dir)
        os.environ["FOUNDATIONSTEREO_HEADLESS"] = "1"
        if bool(getattr(self.args, "torch_compile", False)):
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
        model = torch.load(model_path, map_location="cpu", weights_only=False)
        model.args.valid_iters = int(self.args.fast_foundation_iters)
        model.args.max_disp = int(getattr(model.args, "max_disp", 192))
        model.cuda().eval()
        self._torch = torch
        self._amp_dtype = AMP_DTYPE
        self._padder_cls = InputPadder
        self._model = model
        self._loaded = True
        compile_status = "torch.compile on" if bool(getattr(self.args, "torch_compile", False)) else "torch.compile off"
        VIEW.status = f"FastFoundation live model loaded ({compile_status})"
        print(f"Fast-FoundationStereo live model loaded once ({compile_status})", flush=True)

    def _infer(self, left_img, right_img, color_img):
        if not self._loaded:
            VIEW.status = "loading FastFoundation live model..."
            self._load_model()

        t0 = time.perf_counter()
        scale = float(self.args.foundation_scale)
        if scale != 1.0:
            left_small = cv2.resize(left_img, dsize=None, fx=scale, fy=scale, interpolation=cv2.INTER_LINEAR)
            right_small = cv2.resize(right_img, (left_small.shape[1], left_small.shape[0]), interpolation=cv2.INTER_LINEAR)
        else:
            left_small = left_img
            right_small = cv2.resize(right_img, (left_small.shape[1], left_small.shape[0]), interpolation=cv2.INTER_LINEAR)
        if left_small.ndim == 2:
            left_rgb = cv2.cvtColor(left_small, cv2.COLOR_GRAY2BGR)
            right_rgb = cv2.cvtColor(right_small, cv2.COLOR_GRAY2BGR)
        else:
            left_rgb = left_small[..., :3]
            right_rgb = right_small[..., :3]
        t_pre = time.perf_counter()

        torch = self._torch
        if left_small.ndim == 2:
            img0 = torch.as_tensor(left_small).cuda().float()[None, None].expand(-1, 3, -1, -1)
            img1 = torch.as_tensor(right_small).cuda().float()[None, None].expand(-1, 3, -1, -1)
        else:
            img0 = torch.as_tensor(left_rgb).cuda().float()[None].permute(0, 3, 1, 2)
            img1 = torch.as_tensor(right_rgb).cuda().float()[None].permute(0, 3, 1, 2)
        padder = self._padder_cls(img0.shape, divis_by=32, force_square=False)
        img0, img1 = padder.pad(img0, img1)
        t_upload = time.perf_counter()
        with torch.amp.autocast("cuda", enabled=True, dtype=self._amp_dtype):
            disp = self._model.forward(
                img0,
                img1,
                iters=int(self.args.fast_foundation_iters),
                test_mode=True,
                optimize_build_volume="pytorch1",
            )
        torch.cuda.synchronize()
        t_model = time.perf_counter()
        disp = padder.unpad(disp.float()).data.cpu().numpy().reshape(left_rgb.shape[:2]).clip(0, None)
        t_download = time.perf_counter()

        intr = get_left_intrinsics(self.calib, left_img.shape[1], left_img.shape[0])
        intr = tuple(v * scale if i < 4 else v for i, v in enumerate(intr))
        intr = (intr[0], intr[1], intr[2], intr[3])
        znear, zfar = get_depth_limits(self.args.fast_live_zfar)
        color_mode = VIEW.fast_live_color_source
        grid_rgb_img = None
        if color_mode == "projected-rgb":
            grid_color_img = left_rgb
            grid_rgb_img = color_img
            pts, colors = disparity_to_projected_rgb_cloud(
                disp,
                left_rgb,
                color_img,
                intr,
                get_baseline_m(self.calib),
                znear,
                zfar,
                self.calib,
            )
        else:
            color_source = left_rgb if color_mode == "left" or color_img is None else color_img
            grid_color_img = color_source
            pts, colors = disparity_to_cloud(disp, color_source, intr, get_baseline_m(self.calib), znear, zfar)
        grid_pts, grid_colors, grid_valid = disparity_to_grid_cloud(
            disp,
            grid_color_img,
            intr,
            get_baseline_m(self.calib),
            znear,
            zfar,
            self.calib,
            grid_rgb_img,
        )
        preview = make_metric_depth_preview_from_disparity(left_rgb, right_rgb, disp, intr, get_baseline_m(self.calib), znear, zfar)
        t_cloud = time.perf_counter()
        VIEW.fast_live_timing = {
            "pre_ms": (t_pre - t0) * 1000.0,
            "upload_ms": (t_upload - t_pre) * 1000.0,
            "model_ms": (t_model - t_upload) * 1000.0,
            "download_ms": (t_download - t_model) * 1000.0,
            "cloud_ms": (t_cloud - t_download) * 1000.0,
        }
        return pts, colors, preview, znear, zfar, grid_pts, grid_colors, grid_valid

    def _loop(self):
        while True:
            with self._cond:
                while self._pending is None and not self._stopped:
                    self._cond.wait()
                if self._stopped:
                    return
                item = self._pending
                self._pending = None
            left_img, right_img, color_img, _submitted_at = item
            VIEW.fast_live_inflight = True
            start = time.perf_counter()
            try:
                pts, colors, preview, znear, zfar, grid_pts, grid_colors, grid_valid = self._infer(left_img, right_img, color_img)
                elapsed = max(1e-6, time.perf_counter() - start)
                VIEW.foundation_points = pts
                VIEW.foundation_colors = colors
                VIEW.foundation_grid_points = grid_pts
                VIEW.foundation_grid_colors = grid_colors
                VIEW.foundation_grid_valid = grid_valid
                VIEW.foundation_frame_version += 1
                VIEW.fast_live_done_count += 1
                VIEW.foundation_render_cache_key = None
                VIEW.foundation_label = (
                    f"FastFoundation live #{VIEW.fast_live_done_count} | {pts.shape[0]} pts | {elapsed:.2f}s infer | "
                    f"z={znear:.2f}-{zfar:.2f}m | color={VIEW.fast_live_color_source}"
                )
                VIEW.foundation_view_enabled = True
                VIEW.compare_mode = False
                VIEW.foundation_preview = preview
                VIEW.foundation_preview_title = "FastFoundation live in-process metric depth"
                VIEW.fast_live_fps = 1.0 / elapsed
                VIEW.status = f"FastFoundation live {VIEW.fast_live_fps:.1f}fps"
            except Exception as exc:
                VIEW.fast_live_enabled = False
                VIEW.fast_live_error_count += 1
                VIEW.status = f"FastFoundation live error: {exc}"
                print(VIEW.status, flush=True)
                traceback.print_exc()
            finally:
                VIEW.fast_live_inflight = False


def latest_foundation_preview(out_dir, znear=None, zfar=None):
    depth_candidates = glob.glob(os.path.join(out_dir, "**", "depth_meter.npy"), recursive=True)
    if depth_candidates and znear is not None and zfar is not None:
        depth_candidates.sort(key=lambda path: os.path.getmtime(path), reverse=True)
        depth_path = depth_candidates[0]
        try:
            depth = np.load(depth_path)
            root_dir = os.path.dirname(os.path.dirname(depth_path))
            left_path = os.path.join(root_dir, "input", "left.png")
            right_path = os.path.join(root_dir, "input", "right.png")
            left = cv2.imread(left_path, cv2.IMREAD_COLOR)
            right = cv2.imread(right_path, cv2.IMREAD_COLOR)
            if left is not None and right is not None:
                preview = make_metric_depth_preview(left, right, depth, znear, zfar)
                return preview, depth_path
        except Exception as exc:
            print(f"Metric depth preview failed, falling back to saved images: {exc}", flush=True)
    image_paths = []
    for pattern in ("*.png", "*.jpg", "*.jpeg"):
        image_paths.extend(glob.glob(os.path.join(out_dir, "**", pattern), recursive=True))
    if not image_paths:
        return None, ""
    image_paths.sort(key=lambda path: os.path.getmtime(path), reverse=True)
    preview = cv2.imread(image_paths[0], cv2.IMREAD_COLOR)
    return preview, image_paths[0]


def load_foundation_cloud(out_dir, color_img=None, source_shape=None, scale=1.0, calib=None):
    cloud_path = os.path.join(out_dir, "cloud.ply")
    if not os.path.isfile(cloud_path):
        ply_candidates = glob.glob(os.path.join(out_dir, "**", "*.ply"), recursive=True)
        if ply_candidates:
            ply_candidates.sort(key=lambda path: os.path.getmtime(path), reverse=True)
            cloud_path = ply_candidates[0]
    if not os.path.isfile(cloud_path):
        return None, None, ""
    with open(cloud_path, "rb") as f:
        header_bytes = b""
        while not header_bytes.endswith(b"end_header\n"):
            line = f.readline()
            if not line:
                return None, None, ""
            header_bytes += line
        header = header_bytes.decode("ascii", errors="replace")
        if "format binary_little_endian" not in header:
            return None, None, cloud_path
        vertex_count = 0
        for line in header.splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[0] == "element" and parts[1] == "vertex":
                vertex_count = int(parts[2])
                break
        if vertex_count <= 0:
            return None, None, cloud_path
        dtype = np.dtype([
            ("x", "<f8"), ("y", "<f8"), ("z", "<f8"),
            ("r", "u1"), ("g", "u1"), ("b", "u1"),
        ])
        data = np.frombuffer(f.read(vertex_count * dtype.itemsize), dtype=dtype, count=vertex_count)
    if data.size <= 0:
        return None, None, cloud_path
    raw_x = data["x"].astype(np.float32)
    raw_y = data["y"].astype(np.float32)
    raw_z = data["z"].astype(np.float32)
    pts = np.column_stack([raw_x, -raw_y, -raw_z]).astype(np.float32)
    finite = np.isfinite(pts).all(axis=1)
    colors = np.column_stack([data["b"], data["g"], data["r"]]).astype(np.uint8)
    if color_img is not None and source_shape is not None:
        src_h, src_w = source_shape[:2]
        out_w = max(1, int(round(src_w * scale)))
        out_h = max(1, int(round(src_h * scale)))
        if data.size == out_w * out_h:
            color_resized = cv2.resize(color_img, (out_w, out_h), interpolation=cv2.INTER_LINEAR)
            colors = color_resized.reshape(-1, 3)
        else:
            try:
                intr = calib.getCameraIntrinsics(dai.CameraBoardSocket.CAM_B, src_w, src_h) if calib is not None else None
                fx = float(intr[0][0]) if intr is not None else float(src_w)
                fy = float(intr[1][1]) if intr is not None else float(src_w)
                cx = float(intr[0][2]) if intr is not None else float(src_w) * 0.5
                cy = float(intr[1][2]) if intr is not None else float(src_h) * 0.5
                color_resized = cv2.resize(color_img, (src_w, src_h), interpolation=cv2.INTER_LINEAR)
                valid_z = np.abs(raw_z) > 1e-6
                u = np.zeros(raw_z.shape, dtype=np.int32)
                v = np.zeros(raw_z.shape, dtype=np.int32)
                u[valid_z] = np.rint((raw_x[valid_z] * fx / raw_z[valid_z]) + cx).astype(np.int32)
                v[valid_z] = np.rint((raw_y[valid_z] * fy / raw_z[valid_z]) + cy).astype(np.int32)
                inside = valid_z & (u >= 0) & (u < src_w) & (v >= 0) & (v < src_h)
                colors[inside] = color_resized[v[inside], u[inside]]
            except Exception:
                pass
    return pts[finite], colors[finite], cloud_path


def filter_points_by_depth(pts, colors, znear, zfar):
    if pts is None or pts.size <= 0:
        return pts, colors
    depth = -pts[:, 2]
    keep = np.isfinite(depth) & (depth >= float(znear)) & (depth <= float(zfar))
    return pts[keep], colors[keep]


def run_foundation_worker(engine, left_img, right_img, color_img, calib, args, znear, zfar):
    run_dir = ""
    log_path = ""

    def fail(message, exc=None):
        VIEW.status = message
        print(message, flush=True)
        if log_path:
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as log:
                log.write("\nFAIL:\n")
                log.write(message)
                if exc is not None:
                    log.write(f"\n{type(exc).__name__}: {exc}")
                log.write("\n")

    try:
        if engine == "fast":
            repo_dir = args.fast_foundation_dir
            model_path = args.fast_foundation_model
            iters = args.fast_foundation_iters
            model_arg = "--model_dir"
            label = "Fast-FoundationStereo"
        else:
            repo_dir = args.foundation_dir
            model_path = args.foundation_model
            iters = args.foundation_iters
            model_arg = "--ckpt_dir"
            label = "FoundationStereo"

        os.makedirs(FOUNDATION_RUN_DIR, exist_ok=True)
        stamp = time.strftime("%Y%m%d_%H%M%S")
        run_dir = os.path.join(FOUNDATION_RUN_DIR, f"{engine}_{stamp}")
        input_dir = os.path.join(run_dir, "input")
        out_dir = os.path.join(run_dir, "output")
        os.makedirs(input_dir, exist_ok=True)
        log_path = os.path.join(run_dir, "run.log")
        with open(log_path, "w", encoding="utf-8") as log:
            log.write(f"{label} run starting\n")
            log.write(f"left shape: {left_img.shape}\n")
            log.write(f"right shape: {right_img.shape}\n")
            if color_img is not None:
                log.write(f"color shape: {color_img.shape}\n")

        if not repo_dir or not os.path.isdir(repo_dir):
            fail(f"{label} repo missing; set {'FAST_FOUNDATIONSTEREO_DIR' if engine == 'fast' else 'FOUNDATIONSTEREO_DIR'}")
            return
        if not model_path:
            fail(f"{label} model missing; set {'FAST_FOUNDATIONSTEREO_MODEL' if engine == 'fast' else 'FOUNDATIONSTEREO_MODEL'}")
            return
        if not os.path.isfile(model_path):
            fail(f"{label} model file missing: {model_path}")
            return
        left_path = os.path.join(input_dir, "left.png")
        right_path = os.path.join(input_dir, "right.png")
        intr_path = os.path.join(input_dir, "K.txt")
        if not cv2.imwrite(left_path, left_img):
            fail(f"{label} failed to save left image: {left_path}")
            return
        if not cv2.imwrite(right_path, right_img):
            fail(f"{label} failed to save right image: {right_path}")
            return
        write_intrinsics_file(intr_path, calib, left_img.shape[1], left_img.shape[0], get_baseline_m(calib))
        print(f"{label} inputs saved: {left_path} | {right_path}", flush=True)

        if engine == "fast":
            run_demo = os.path.join(repo_dir, "scripts", "run_demo.py")
            if not os.path.isfile(run_demo):
                run_demo = os.path.join(repo_dir, "run_demo.py")
            if not os.path.isfile(run_demo):
                fail(f"{label} run_demo.py not found")
                return
            cmd = [
                args.foundation_python,
                run_demo,
                model_arg,
                model_path,
                "--left_file",
                left_path,
                "--right_file",
                right_path,
                "--intrinsic_file",
                intr_path,
                "--out_dir",
                out_dir,
                "--scale",
                str(args.foundation_scale),
                "--valid_iters",
                str(iters),
                "--remove_invisible",
                "0",
                "--denoise_cloud",
                "0",
                "--get_pc",
                "1",
                "--zfar",
                f"{zfar:.3f}",
            ]
        else:
            ext = os.path.splitext(model_path)[1].lower()
            if ext in (".onnx", ".engine", ".plan"):
                run_demo = os.path.join(repo_dir, "scripts", "run_demo_tensorrt.py")
                if not os.path.isfile(run_demo):
                    fail(f"{label} run_demo_tensorrt.py not found")
                    return
                cmd = [
                    args.foundation_python,
                    run_demo,
                    "--left_img",
                    left_path,
                    "--right_img",
                    right_path,
                    "--save_path",
                    out_dir,
                    "--pretrained",
                    model_path,
                    "--intrinsic_file",
                    intr_path,
                    "--height",
                    str(left_img.shape[0]),
                    "--width",
                    str(left_img.shape[1]),
                    "--pc",
                    "--z_far",
                    f"{zfar:.3f}",
                ]
            else:
                cfg_path = os.path.join(os.path.dirname(model_path), "cfg.yaml")
                if not os.path.isfile(cfg_path):
                    fail(f"{label} cfg missing; expected {cfg_path}")
                    return
                run_demo = os.path.join(repo_dir, "scripts", "run_demo.py")
                if not os.path.isfile(run_demo):
                    run_demo = os.path.join(repo_dir, "run_demo.py")
                if not os.path.isfile(run_demo):
                    fail(f"{label} run_demo.py not found")
                    return
                cmd = [
                    args.foundation_python,
                    run_demo,
                    model_arg,
                    model_path,
                    "--left_file",
                    left_path,
                    "--right_file",
                    right_path,
                    "--intrinsic_file",
                    intr_path,
                    "--out_dir",
                    out_dir,
                    "--scale",
                    str(args.foundation_scale),
                    "--valid_iters",
                    str(iters),
                    "--remove_invisible",
                    "0",
                    "--denoise_cloud",
                    "0",
                    "--get_pc",
                    "1",
                    "--z_far",
                    f"{zfar:.3f}",
                ]
        start = time.perf_counter()
        env = os.environ.copy()
        env["FOUNDATIONSTEREO_HEADLESS"] = "1"
        if bool(getattr(args, "torch_compile", False)):
            env.pop("FOUNDATIONSTEREO_DISABLE_TORCH_COMPILE", None)
        else:
            env["FOUNDATIONSTEREO_DISABLE_TORCH_COMPILE"] = "1"
        result = subprocess.run(cmd, cwd=repo_dir, text=True, capture_output=True, timeout=180, env=env)
        with open(log_path, "a", encoding="utf-8") as log:
            log.write("COMMAND:\n")
            log.write(" ".join(cmd))
            log.write("\n\nSTDOUT:\n")
            log.write(result.stdout or "")
            log.write("\n\nSTDERR:\n")
            log.write(result.stderr or "")

        VIEW.foundation_last_output = out_dir
        if result.returncode != 0:
            fail(f"{label} failed; see {log_path}")
            return
        pts, colors, cloud_path = load_foundation_cloud(out_dir, color_img, left_img.shape, args.foundation_scale, calib)
        if pts is not None:
            pts, colors = filter_points_by_depth(pts, colors, znear, zfar)
            VIEW.foundation_points = pts
            VIEW.foundation_colors = colors
            VIEW.foundation_frame_version += 1
            VIEW.foundation_render_cache_key = None
            VIEW.foundation_label = f"{label} cloud | {pts.shape[0]} pts | z={znear:.2f}-{zfar:.2f}m | {cloud_path}"
            VIEW.foundation_view_enabled = True
            VIEW.compare_mode = False
            print(f"{label} cloud loaded into main view: {pts.shape[0]} pts -> {cloud_path}", flush=True)
        else:
            fail(f"{label} did not produce a loadable cloud.ply in {out_dir}")
            return
        preview, preview_path = latest_foundation_preview(out_dir, znear, zfar)
        if preview is not None:
            VIEW.foundation_preview = preview
            VIEW.foundation_preview_title = f"{label}: {preview_path}"
            VIEW.status = f"{label} done in {time.perf_counter() - start:.1f}s"
        else:
            VIEW.status = f"{label} done; output {out_dir}"
    except subprocess.TimeoutExpired:
        fail(f"{engine} FoundationStereo timed out")
    except Exception as exc:
        fail(f"{engine} FoundationStereo error: {exc}", exc)
    finally:
        VIEW.foundation_busy = False


def start_foundation_run(engine, rect_left, rect_right, color, calib, args):
    if VIEW.foundation_busy:
        VIEW.status = "FoundationStereo run already active"
        return
    if rect_left is None or rect_right is None:
        VIEW.status = "no rectified stereo frame yet"
        return
    VIEW.foundation_busy = True
    VIEW.status = f"running {'Fast-' if engine == 'fast' else ''}FoundationStereo..."
    left_copy = rect_left.copy()
    right_copy = rect_right.copy()
    color_copy = None if color is None else color.copy()
    znear, zfar = get_depth_limits(args.fast_live_zfar)
    VIEW.last_fast_live_start = time.perf_counter()
    thread = threading.Thread(target=run_foundation_worker, args=(engine, left_copy, right_copy, color_copy, calib, args, znear, zfar), daemon=False)
    thread.start()


def handle_key(key, color, depth_m, intrinsics, rect_left=None, rect_right=None, calib=None, args=None):
    if key < 0:
        return True
    key = key & 0xFF
    VIEW.last_key = key
    if key in (27, ord("q")):
        return False
    if key == ord("p"):
        VIEW.compare_mode = False
        VIEW.runtime_preset_index = (VIEW.runtime_preset_index + 1) % len(RUNTIME_PRESET_NAMES)
        name = RUNTIME_PRESET_NAMES[VIEW.runtime_preset_index]
        apply_runtime_preset(name)
        VIEW.status = f"preset {name}"
        print(f"Runtime cleanup preset: {name}", flush=True)
    elif key == ord("a"):
        if color is not None and depth_m is not None:
            capture_comparison_snapshots(depth_m, color, intrinsics)
            VIEW.status = "captured comparison snapshots"
        else:
            VIEW.status = "no frame to capture yet"
    elif key == ord("l"):
        VIEW.compare_mode = False
        VIEW.foundation_view_enabled = False
        VIEW.fast_live_enabled = False
        VIEW.status = "live view"
    elif key in (ord("["), ord(",")):
        if VIEW.snapshots:
            VIEW.compare_mode = True
            VIEW.snapshot_index = (VIEW.snapshot_index - 1) % len(VIEW.snapshots)
            VIEW.status = f"snapshot {VIEW.snapshots[VIEW.snapshot_index]['name']}"
        else:
            VIEW.status = "no snapshots; press a first"
    elif key in (ord("]"), ord(".")):
        if VIEW.snapshots:
            VIEW.compare_mode = True
            VIEW.snapshot_index = (VIEW.snapshot_index + 1) % len(VIEW.snapshots)
            VIEW.status = f"snapshot {VIEW.snapshots[VIEW.snapshot_index]['name']}"
        else:
            VIEW.status = "no snapshots; press a first"
    elif key == ord("r"):
        VIEW.yaw = np.deg2rad(45.0)
        VIEW.pitch = np.deg2rad(-75.0)
        VIEW.zoom = 340.0
        VIEW.pan_x = 0.0
        VIEW.pan_y = 0.0
        VIEW.status = "view reset"
    elif key == ord("f"):
        start_foundation_run("fast", rect_left, rect_right, color, calib, args)
    elif key == ord("F"):
        start_foundation_run("full", rect_left, rect_right, color, calib, args)
    elif key == ord("g"):
        VIEW.fast_live_enabled = not VIEW.fast_live_enabled
        VIEW.foundation_view_enabled = VIEW.fast_live_enabled or VIEW.foundation_view_enabled
        if VIEW.fast_live_enabled and VIEW.fast_live_worker is None:
            VIEW.fast_live_worker = FastFoundationLiveWorker(args, calib)
        VIEW.status = "FastFoundation live worker on" if VIEW.fast_live_enabled else "FastFoundation live worker off"
        print(VIEW.status, flush=True)
    elif key == ord("c"):
        modes = ["rgb", "projected-rgb", "left"]
        VIEW.fast_live_color_source = modes[(modes.index(VIEW.fast_live_color_source) + 1) % len(modes)]
        VIEW.status = f"FastFoundation color {VIEW.fast_live_color_source}"
        print(VIEW.status, flush=True)
    elif key == ord("o"):
        VIEW.foundation_view_enabled = not VIEW.foundation_view_enabled
        VIEW.compare_mode = False
        VIEW.status = "FoundationStereo view on" if VIEW.foundation_view_enabled else "FoundationStereo view off"
    else:
        VIEW.status = f"key {key}"
    return True


def main():
    args = parse_args()
    config = PRESETS[args.preset]
    print("OAK-D point-cloud tuner starting")
    print("Preset:", args.preset, config)
    print("Keys: q/Esc quit. f runs Fast-FoundationStereo, Shift+F runs full FoundationStereo if env paths are configured.")
    print("Restart script with --preset smooth|speed_raw|balanced|dense|clean|fast for device-level preset changes.")

    pipeline, rgb_queue, depth_queue, left_queue, right_queue = create_pipeline(config)
    cv2.namedWindow(VIEW_WIN, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(VIEW_WIN, 1200, 900)
    cv2.setMouseCallback(VIEW_WIN, on_mouse)
    create_controls()
    apply_runtime_preset(RUNTIME_PRESET_NAMES[VIEW.runtime_preset_index])

    pipeline.start()
    device = pipeline.getDefaultDevice()
    calib = device.readCalibration()
    intr = calib.getCameraIntrinsics(dai.CameraBoardSocket.CAM_A, config["width"], config["height"])
    intrinsics = (float(intr[0][0]), float(intr[1][1]), float(intr[0][2]), float(intr[1][2]))
    if args.start_fast_live:
        VIEW.fast_live_enabled = True
        VIEW.foundation_view_enabled = True
        VIEW.fast_live_color_source = args.fast_live_color_source
        VIEW.fast_live_worker = FastFoundationLiveWorker(args, calib)
        VIEW.status = "FastFoundation live worker on"

    color = None
    depth_m = None
    rect_left = None
    rect_right = None
    rgb_frames = 0
    depth_frames = 0
    render_frames = 0
    skipped_depth_frames = 0
    fps_rgb = 0.0
    fps_depth = 0.0
    fps_render = 0.0
    last_render_ms = 0.0
    last_fps = time.perf_counter()
    depth_sequence = 0

    while pipeline.isRunning():
        rgb_msg, rgb_count = drain_latest(rgb_queue)
        depth_msg, depth_count = drain_latest(depth_queue)
        left_msg, _left_count = drain_latest(left_queue)
        right_msg, _right_count = drain_latest(right_queue)
        if rgb_msg is not None:
            color = rgb_msg.getCvFrame()
        if depth_msg is not None:
            depth_m = depth_msg.getFrame().astype(np.float32) * 0.001
            depth_sequence += depth_count
        if left_msg is not None:
            rect_left = left_msg.getCvFrame()
        if right_msg is not None:
            rect_right = right_msg.getCvFrame()
        rgb_frames += rgb_count
        depth_frames += depth_count

        now = time.perf_counter()
        if now - last_fps >= 0.5:
            elapsed = now - last_fps
            fps_rgb = rgb_frames / elapsed
            fps_depth = depth_frames / elapsed
            fps_render = render_frames / elapsed
            rgb_frames = 0
            depth_frames = 0
            render_frames = 0
            last_fps = now

        if color is not None and depth_m is not None:
            if (
                VIEW.fast_live_enabled
                and VIEW.fast_live_worker is not None
                and rect_left is not None
                and rect_right is not None
                and (time.perf_counter() - VIEW.last_fast_live_start) >= args.fast_live_interval
            ):
                VIEW.fast_live_worker.submit(rect_left, rect_right, color)
                VIEW.last_fast_live_start = time.perf_counter()
            stride, min_d, max_d, edge_reject, min_island, point_size, render_every = get_controls()
            if point_size > 1 and stride <= 2:
                point_size = 1
            if depth_msg is None:
                if not handle_key(cv2.waitKey(1), color, depth_m, intrinsics, rect_left, rect_right, calib, args):
                    break
                time.sleep(0.001)
                continue
            if (depth_sequence % render_every) != 0:
                skipped_depth_frames += 1
                if not handle_key(cv2.waitKey(1), color, depth_m, intrinsics, rect_left, rect_right, calib, args):
                    break
                time.sleep(0.001)
                continue
            render_start = time.perf_counter()
            if VIEW.foundation_view_enabled and VIEW.foundation_points is not None:
                view = project_foundation_points_cached(VIEW.foundation_points, VIEW.foundation_colors, point_size)
                point_count = int(VIEW.foundation_points.shape[0])
                valid_pct = 100.0
                compare_line = f"FOUNDATION {VIEW.foundation_label} | o toggle | l live"
            elif VIEW.compare_mode and VIEW.snapshots:
                snapshot = VIEW.snapshots[VIEW.snapshot_index]
                view = project_point_arrays(snapshot["points"], snapshot["colors"], snapshot["point_size"])
                point_count = int(snapshot["points"].shape[0])
                valid_pct = snapshot["valid_pct"]
                compare_line = f"COMPARE {VIEW.snapshot_index + 1}/{len(VIEW.snapshots)} {snapshot['name']} | {snapshot['path']}"
            else:
                valid = cleanup_depth_mask(depth_m, min_d, max_d, edge_reject, min_island)
                view, point_count = project_points(depth_m, color, valid, intrinsics, stride, point_size)
                valid_pct = 100.0 * float(np.count_nonzero(valid)) / float(valid.size)
                compare_line = f"live preset {RUNTIME_PRESET_NAMES[VIEW.runtime_preset_index]} | p cycle | a capture compare"
            render_frames += 1
            last_render_ms = (time.perf_counter() - render_start) * 1000.0
            lines = [
                f"{args.preset} | {config['width']}x{config['height']} {config['fps']:.0f}fps mono={config['mono_res']} preset={config['stereo_preset']}",
                f"camera rgb {fps_rgb:.1f}fps depth {fps_depth:.1f}fps | render {fps_render:.1f}fps {last_render_ms:.1f}ms | points {point_count}",
                f"valid {valid_pct:.1f}% | stride {stride} | render every {render_every} depth | skipped {skipped_depth_frames}",
                f"z range: near={min_d:.2f}m far={max_d:.2f}m | edge={edge_reject:.2f} island={min_island}",
                f"rgb projection offset: u={get_rgb_projection_offsets()[0]}px v={get_rgb_projection_offsets()[1]}px",
                f"Fast live: {'on' if VIEW.fast_live_enabled else 'off'} inflight={int(VIEW.fast_live_inflight)} submit={VIEW.fast_live_submit_count} done={VIEW.fast_live_done_count} err={VIEW.fast_live_error_count} frame={VIEW.foundation_frame_version}",
                compare_line,
                f"status: {VIEW.status} | last_key={VIEW.last_key}",
                "keys: p preset | a capture | f Fast snap | g Fast live | c color rgb/host-projected/left | F Foundation | o FS view | l live | r reset | q quit",
            ]
            y = 28
            for line in lines:
                cv2.putText(view, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4, cv2.LINE_AA)
                cv2.putText(view, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (120, 255, 120), 1, cv2.LINE_AA)
                y += 28
            if VIEW.foundation_view_enabled and VIEW.foundation_points is not None:
                cv2.rectangle(view, (0, view.shape[0] - 48), (view.shape[1], view.shape[0]), (0, 80, 120), -1)
                cv2.putText(view, "FOUNDATIONSTEREO CLOUD VIEW - g live refresh, l live OAK-D, o toggle",
                            (18, view.shape[0] - 16), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
            cv2.imshow(VIEW_WIN, view)
            if VIEW.foundation_preview is not None:
                preview = VIEW.foundation_preview.copy()
                title = VIEW.foundation_preview_title[-140:] if VIEW.foundation_preview_title else "FoundationStereo output"
                cv2.putText(preview, title, (14, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 4, cv2.LINE_AA)
                cv2.putText(preview, title, (14, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (120, 255, 120), 1, cv2.LINE_AA)
                cv2.imshow(FOUNDATION_WIN, preview)

        if not handle_key(cv2.waitKey(1), color, depth_m, intrinsics, rect_left, rect_right, calib, args):
            break

    cv2.destroyAllWindows()
    if VIEW.fast_live_worker is not None:
        VIEW.fast_live_worker.stop()
    if args.hard_exit:
        os._exit(0)


if __name__ == "__main__":
    main()
