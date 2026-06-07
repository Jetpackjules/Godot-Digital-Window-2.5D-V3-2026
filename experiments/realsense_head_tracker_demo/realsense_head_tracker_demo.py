import argparse
import math
import threading
import time

import cv2
import numpy as np

try:
    import mediapipe as mp
except ImportError:
    mp = None

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None

try:
    import pyrealsense2 as rs
except ImportError as exc:
    raise SystemExit(
        "pyrealsense2 is not installed. Install it with:\n"
        "  python -m pip install pyrealsense2\n"
    ) from exc


WINDOW_NAME = "RealSense Depth Head Tracker Demo"
DEFAULT_POSE_MODEL_PATH = "experiments/realsense_head_tracker_demo/models/pose_landmarker_lite.task"


def deproject(intrinsics, pixel, depth_m):
    point = rs.rs2_deproject_pixel_to_point(intrinsics, [float(pixel[0]), float(pixel[1])], float(depth_m))
    return np.array(point, dtype=np.float32)


def pixel_width_to_meters(width_px, depth_m, intrinsics):
    return float(width_px) * float(depth_m) / float(intrinsics.fx)


def pixel_height_to_meters(height_px, depth_m, intrinsics):
    return float(height_px) * float(depth_m) / float(intrinsics.fy)


def largest_foreground_blob(mask, last_pixel=None):
    contours, _hierarchy = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    candidates = []
    for contour in contours:
        area = cv2.contourArea(contour)
        if area < 600:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        if w < 20 or h < 35:
            continue
        score = area
        if last_pixel is not None:
            cx = x + w * 0.5
            cy = y + h * 0.5
            dist = math.hypot(cx - last_pixel[0], cy - last_pixel[1])
            score -= dist * 6.0
        candidates.append((score, contour))

    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def best_body_blob(mask, depth_m, intrinsics, last_pixel=None):
    contours, _hierarchy = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    scored = []
    for contour in contours:
        area = cv2.contourArea(contour)
        if area < 700:
            continue

        x, y, w, h = cv2.boundingRect(contour)
        if w < 25 or h < 45:
            continue

        contour_mask = np.zeros(depth_m.shape, dtype=np.uint8)
        cv2.drawContours(contour_mask, [contour], -1, 255, thickness=cv2.FILLED)
        valid = (contour_mask > 0) & np.isfinite(depth_m) & (depth_m > 0.0)
        if int(valid.sum()) < 500:
            continue

        median_depth = float(np.median(depth_m[valid]))
        width_m = pixel_width_to_meters(w, median_depth, intrinsics)
        height_m = pixel_height_to_meters(h, median_depth, intrinsics)
        aspect = float(h) / float(max(1, w))

        score = min(area / 12000.0, 3.0)
        score += 2.5 if 0.22 <= width_m <= 1.35 else -2.0
        score += 2.5 if 0.35 <= height_m <= 2.20 else -2.0
        score += 1.5 if 0.55 <= aspect <= 3.8 else -1.5
        score += 1.0 if y < depth_m.shape[0] * 0.78 else -1.0

        if last_pixel is not None:
            cx = x + w * 0.5
            cy = y + h * 0.5
            dist = math.hypot(cx - last_pixel[0], cy - last_pixel[1])
            score -= dist / 140.0

        scored.append((score, contour))

    if not scored:
        return None
    scored.sort(key=lambda item: item[0], reverse=True)
    return scored[0][1]


def estimate_head_pixel(contour, depth_m, min_depth, max_depth):
    x, y, w, h = cv2.boundingRect(contour)
    blob_mask = np.zeros(depth_m.shape, dtype=np.uint8)
    cv2.drawContours(blob_mask, [contour], -1, 255, thickness=cv2.FILLED)

    top_margin = max(8, int(h * 0.04))
    top_band_h = max(35, int(h * 0.28))
    y0 = min(depth_m.shape[0] - 1, y + top_margin)
    y1 = min(depth_m.shape[0], y + top_band_h)

    top_mask = np.zeros_like(blob_mask)
    top_mask[y0:y1, x:x + w] = blob_mask[y0:y1, x:x + w]
    valid = (top_mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)

    ys, xs = np.nonzero(valid)
    if len(xs) < 40:
        valid = (blob_mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
        ys, xs = np.nonzero(valid)
    if len(xs) < 40:
        return None

    depths = depth_m[ys, xs]
    median_depth = float(np.median(depths))
    median_x = int(np.median(xs))
    median_y = int(np.median(ys))
    return (median_x, median_y, median_depth, (x, y, w, h), blob_mask)


def estimate_body_head_pixel(contour, depth_m, min_depth, max_depth, intrinsics, last_pixel=None):
    x, y, w, h = cv2.boundingRect(contour)
    blob_mask = np.zeros(depth_m.shape, dtype=np.uint8)
    cv2.drawContours(blob_mask, [contour], -1, 255, thickness=cv2.FILLED)

    valid_blob = (blob_mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
    blob_ys, blob_xs = np.nonzero(valid_blob)
    if len(blob_xs) < 80:
        return estimate_head_pixel(contour, depth_m, min_depth, max_depth)

    search_y0 = max(0, y + int(h * 0.03))
    search_y1 = min(depth_m.shape[0], y + max(60, int(h * 0.48)))
    upper_valid = valid_blob[search_y0:search_y1, x:x + w]
    if int(upper_valid.sum()) < 80:
        return estimate_head_pixel(contour, depth_m, min_depth, max_depth)

    column_counts = upper_valid.sum(axis=0)
    min_column_count = max(4, int((search_y1 - search_y0) * 0.06))
    active_columns = column_counts >= min_column_count
    runs = []
    run_start = None
    for col, active in enumerate(active_columns):
        if active and run_start is None:
            run_start = col
        elif not active and run_start is not None:
            runs.append((run_start, col - 1))
            run_start = None
    if run_start is not None:
        runs.append((run_start, len(active_columns) - 1))

    candidates = []
    median_blob_depth = float(np.median(depth_m[valid_blob]))
    for start_col, end_col in runs:
        run_width = end_col - start_col + 1
        if run_width < 14:
            continue
        run_x0 = x + start_col
        run_x1 = x + end_col + 1
        run_mask = np.zeros_like(blob_mask)
        run_mask[search_y0:search_y1, run_x0:run_x1] = blob_mask[search_y0:search_y1, run_x0:run_x1]
        run_valid = (run_mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
        run_ys, run_xs = np.nonzero(run_valid)
        if len(run_xs) < 45:
            continue

        run_depth = float(np.median(depth_m[run_ys, run_xs]))
        width_m = pixel_width_to_meters(run_width, run_depth, intrinsics)
        top_y = int(run_ys.min())
        center_x = float(np.median(run_xs))
        center_y = float(np.median(run_ys[run_ys <= np.percentile(run_ys, 45.0)]))

        score = 0.0
        score += 3.0 if 0.11 <= width_m <= 0.42 else -2.0
        score += max(0.0, 3.0 - ((top_y - search_y0) / 35.0))
        score += min(len(run_xs) / 1800.0, 2.0)
        score -= abs(run_depth - median_blob_depth) * 1.2
        if last_pixel is not None:
            score -= math.hypot(center_x - last_pixel[0], center_y - last_pixel[1]) / 180.0
        candidates.append((score, int(center_x), int(center_y), run_depth, (run_x0, search_y0, run_x1 - run_x0, search_y1 - search_y0)))

    if not candidates:
        return estimate_head_pixel(contour, depth_m, min_depth, max_depth)

    candidates.sort(key=lambda item: item[0], reverse=True)
    _score, candidate_x, candidate_y, candidate_depth, debug_search_rect = candidates[0]

    search_x0, _, search_w, _ = debug_search_rect
    search_x1 = search_x0 + search_w
    search_mask = np.zeros_like(blob_mask)
    search_mask[search_y0:search_y1, search_x0:search_x1] = blob_mask[search_y0:search_y1, search_x0:search_x1]
    valid = (search_mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)

    ys, xs = np.nonzero(valid)
    if len(xs) < 40:
        return (candidate_x, candidate_y, candidate_depth, (x, y, w, h), blob_mask, debug_search_rect)

    top_cutoff = int(np.percentile(ys, 35.0))
    top = ys <= top_cutoff
    if int(top.sum()) >= 30:
        xs = xs[top]
        ys = ys[top]

    depths = depth_m[ys, xs]
    median_depth = float(np.median(depths))
    median_x = int(np.median(xs))
    median_y = int(np.median(ys))
    return (median_x, median_y, median_depth, (x, y, w, h), blob_mask, debug_search_rect)


def estimate_headlock_pixel(mask, depth_m, min_depth, max_depth, intrinsics, last_pixel=None):
    valid = (mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
    if int(valid.sum()) < 80:
        return None

    head_mask = valid.astype(np.uint8) * 255
    kernel = np.ones((3, 3), dtype=np.uint8)
    head_mask = cv2.morphologyEx(head_mask, cv2.MORPH_OPEN, kernel)
    component_count, labels, stats, centroids = cv2.connectedComponentsWithStats(head_mask, 8)
    best = None
    image_h, image_w = depth_m.shape

    for label in range(1, component_count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 55 or area > 24000:
            continue
        x = int(stats[label, cv2.CC_STAT_LEFT])
        y = int(stats[label, cv2.CC_STAT_TOP])
        w = int(stats[label, cv2.CC_STAT_WIDTH])
        h = int(stats[label, cv2.CC_STAT_HEIGHT])
        if w < 12 or h < 12:
            continue

        component_valid = labels[y:y + h, x:x + w] == label
        candidate_depths = depth_m[y:y + h, x:x + w][component_valid]
        if candidate_depths.size < 55:
            continue
        candidate_depth = float(np.median(candidate_depths))
        depth_std = float(np.std(candidate_depths))
        width_m = pixel_width_to_meters(w, candidate_depth, intrinsics)
        height_m = pixel_height_to_meters(h, candidate_depth, intrinsics)
        aspect = width_m / max(0.001, height_m)
        density = float(area) / float(max(1, w * h))
        center_x = float(centroids[label][0])
        center_y = float(centroids[label][1])

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
            distance = math.hypot(center_x - float(last_pixel[0]), center_y - float(last_pixel[1]))
            score += max(0.0, 7.0 - distance / 22.0)
            if distance > 190.0:
                score -= 8.0
        else:
            # Without a lock, prefer likely head positions over nearby bedding/table blobs.
            score += 1.0 if y < image_h * 0.72 else -2.5

        if best is None or score > best[0]:
            debug_mask = np.zeros(depth_m.shape, dtype=np.uint8)
            debug_mask[y:y + h, x:x + w][component_valid] = 255
            debug_rect = (x, y, w, h)
            best = (score, int(center_x), int(center_y), candidate_depth, debug_rect, debug_mask)

    if best is None or best[0] < 2.0:
        return None

    _score, center_x, center_y, candidate_depth, debug_rect, debug_mask = best
    return (center_x, center_y, candidate_depth, debug_rect, debug_mask, debug_rect)


def robust_depth_in_roi(depth_m, center_x, center_y, radius_px, min_depth, max_depth):
    image_h, image_w = depth_m.shape
    x0 = max(0, int(center_x) - radius_px)
    x1 = min(image_w, int(center_x) + radius_px + 1)
    y0 = max(0, int(center_y) - radius_px)
    y1 = min(image_h, int(center_y) + radius_px + 1)
    roi = depth_m[y0:y1, x0:x1]
    valid = roi[np.isfinite(roi) & (roi >= min_depth) & (roi <= max_depth)]
    if valid.size < 12:
        return None
    return float(np.median(valid))


def make_rect_mask(depth_shape, rect):
    x, y, w, h = rect
    mask = np.zeros(depth_shape, dtype=np.uint8)
    mask[max(0, y):max(0, y + h), max(0, x):max(0, x + w)] = 255
    return mask


class MlHeadDetector:
    def __init__(self, head_model_path="", yolo_conf=0.35, yolo_imgsz=416, pose_model_path=DEFAULT_POSE_MODEL_PATH):
        self.yolo = None
        self.yolo_conf = float(yolo_conf)
        self.yolo_imgsz = int(yolo_imgsz)
        self.pose = None
        if head_model_path and YOLO is not None:
            self.yolo = YOLO(head_model_path)
        elif head_model_path and YOLO is None:
            print("ultralytics is not installed, so YOLO/head-model tracking is disabled.")

        if mp is not None and hasattr(mp, "tasks") and hasattr(mp.tasks, "vision") and pose_model_path:
            try:
                base_options = mp.tasks.BaseOptions(model_asset_path=pose_model_path)
                options = mp.tasks.vision.PoseLandmarkerOptions(
                    base_options=base_options,
                    running_mode=mp.tasks.vision.RunningMode.VIDEO,
                    num_poses=1,
                    min_pose_detection_confidence=0.45,
                    min_pose_presence_confidence=0.45,
                    min_tracking_confidence=0.45,
                )
                self.pose = mp.tasks.vision.PoseLandmarker.create_from_options(options)
            except Exception as exc:
                print(f"MediaPipe Tasks pose fallback failed to initialize: {exc}")
                self.pose = None
        elif mp is not None and hasattr(mp, "solutions") and hasattr(mp.solutions, "pose"):
            # Legacy MediaPipe path for older environments.
            self.pose = mp.solutions.pose.Pose(
                static_image_mode=False,
                model_complexity=1,
                smooth_landmarks=True,
                enable_segmentation=False,
                min_detection_confidence=0.45,
                min_tracking_confidence=0.45,
            )
        elif mp is not None:
            print("Installed mediapipe package has no supported pose API; pose fallback is disabled.")
        else:
            print("mediapipe is not installed, so pose fallback is disabled.")

    def close(self):
        if self.pose is not None:
            self.pose.close()

    def estimate(self, color_bgr, depth_m, intrinsics, min_depth, max_depth, last_pixel=None):
        if self.yolo is not None:
            result = self._estimate_yolo(color_bgr, depth_m, intrinsics, min_depth, max_depth, last_pixel)
            if result is not None:
                return result
        if self.pose is not None:
            result = self._estimate_pose(color_bgr, depth_m, intrinsics, min_depth, max_depth, last_pixel)
            if result is not None:
                return result
        return None

    def _estimate_yolo(self, color_bgr, depth_m, intrinsics, min_depth, max_depth, last_pixel=None):
        results = self.yolo.predict(color_bgr, imgsz=self.yolo_imgsz, conf=self.yolo_conf, verbose=False)
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
            else:
                # A custom head model should generally land here.
                px = x0 + w * 0.5
                py = y0 + h * 0.5
                radius = max(10, int(min(w, h) * 0.20))

            depth = robust_depth_in_roi(depth_m, px, py, radius, min_depth, max_depth)
            if depth is None:
                continue

            score = conf * 10.0
            if "head" in label:
                score += 6.0
            elif "person" in label:
                score += 2.0
            if last_pixel is not None:
                score += max(0.0, 5.0 - math.hypot(px - last_pixel[0], py - last_pixel[1]) / 45.0)

            if best is None or score > best[0]:
                rect = (x0, y0, w, h)
                best = (score, int(px), int(py), depth, rect, make_rect_mask(depth_m.shape, rect), rect)

        if best is None:
            return None
        return best[1:]

    def _estimate_pose(self, color_bgr, depth_m, intrinsics, min_depth, max_depth, last_pixel=None):
        rgb = cv2.cvtColor(color_bgr, cv2.COLOR_BGR2RGB)
        if hasattr(self.pose, "detect_for_video"):
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            timestamp_ms = int(time.perf_counter() * 1000)
            result = self.pose.detect_for_video(mp_image, timestamp_ms)
            pose_landmarks = result.pose_landmarks[0] if result.pose_landmarks else None
        else:
            result = self.pose.process(rgb)
            pose_landmarks = result.pose_landmarks.landmark if result.pose_landmarks else None

        if not pose_landmarks:
            return None

        image_h, image_w = depth_m.shape
        landmarks = pose_landmarks

        # BlazePose landmark indexes: nose, eyes, ears, shoulders. Use indexes
        # directly so both legacy mp.solutions and new Tasks results work.
        candidate_landmarks = [0, 2, 5, 7, 8]
        visible = []
        for landmark_id in candidate_landmarks:
            landmark = landmarks[landmark_id]
            visibility = float(getattr(landmark, "visibility", 1.0))
            presence = float(getattr(landmark, "presence", 1.0))
            confidence = min(visibility, presence)
            if confidence >= 0.25:
                visible.append((landmark.x * image_w, landmark.y * image_h, confidence))

        if visible:
            total = sum(item[2] for item in visible)
            px = sum(item[0] * item[2] for item in visible) / max(1e-6, total)
            py = sum(item[1] * item[2] for item in visible) / max(1e-6, total)
        else:
            shoulder_ids = [11, 12]
            shoulders = []
            for landmark_id in shoulder_ids:
                landmark = landmarks[landmark_id]
                visibility = float(getattr(landmark, "visibility", 1.0))
                presence = float(getattr(landmark, "presence", 1.0))
                if min(visibility, presence) >= 0.35:
                    shoulders.append((landmark.x * image_w, landmark.y * image_h))
            if len(shoulders) < 2:
                return None
            shoulder_mid_x = (shoulders[0][0] + shoulders[1][0]) * 0.5
            shoulder_mid_y = (shoulders[0][1] + shoulders[1][1]) * 0.5
            shoulder_width = math.hypot(shoulders[0][0] - shoulders[1][0], shoulders[0][1] - shoulders[1][1])
            px = shoulder_mid_x
            py = shoulder_mid_y - shoulder_width * 0.55

        radius = 18
        depth = robust_depth_in_roi(depth_m, px, py, radius, min_depth, max_depth)
        if depth is None:
            return None

        rect = (int(px - radius), int(py - radius), radius * 2, radius * 2)
        return (int(px), int(py), depth, rect, make_rect_mask(depth_m.shape, rect), rect)


class AsyncTrackerWorker:
    def __init__(self, args, intrinsics):
        self.args = args
        self.intrinsics = intrinsics
        self.mode = args.mode
        self.max_distance = args.max_distance
        self.foreground_band = args.foreground_band
        self.min_distance = args.min_distance
        self.near_percentile = args.near_percentile
        self.temporal_alpha = float(np.clip(args.smoothing, 0.0, 0.98))
        self.detector = MlHeadDetector(args.head_model, args.yolo_conf, args.yolo_imgsz, args.pose_model)
        self.lock = threading.Lock()
        self.new_frame_event = threading.Event()
        self.stop_event = threading.Event()
        self.pending_color = None
        self.pending_depth = None
        self.pending_frame_id = 0
        self.latest = None
        self.smoothed_point = None
        self.smoothed_pixel = None
        self.inference_fps = 0.0
        self.copy_ms = 0.0
        self.process_ms = 0.0
        self._inference_count = 0
        self._last_inference_fps_time = time.perf_counter()
        self.thread = threading.Thread(target=self._run, name="realsense-ml-worker", daemon=True)
        self.thread.start()

    def close(self):
        self.stop_event.set()
        self.new_frame_event.set()
        self.thread.join(timeout=2.0)
        self.detector.close()

    def submit_frame(self, color, depth_m):
        copy_start = time.perf_counter()
        with self.lock:
            # Keep only the newest frame. This prevents inference backlog and
            # keeps display/capture at camera rate even if ML is slower.
            self.pending_color = color.copy()
            self.pending_depth = depth_m.copy()
            self.pending_frame_id += 1
            self.copy_ms = (time.perf_counter() - copy_start) * 1000.0
        self.new_frame_event.set()

    def reset(self):
        with self.lock:
            self.smoothed_point = None
            self.smoothed_pixel = None
            self.latest = None

    def set_mode(self, mode):
        with self.lock:
            self.mode = mode
        self.reset()

    def set_max_distance(self, value):
        with self.lock:
            self.max_distance = float(value)
        self.reset()

    def set_foreground_band(self, value):
        with self.lock:
            self.foreground_band = float(value)

    def get_latest(self):
        with self.lock:
            if self.latest is None:
                return None
            latest = self.latest.copy()
            latest["inference_fps"] = self.inference_fps
            latest["copy_ms"] = self.copy_ms
            latest["process_ms"] = self.process_ms
            latest["mode"] = self.mode
            latest["max_distance"] = self.max_distance
            latest["foreground_band"] = self.foreground_band
            return latest

    def _take_frame(self):
        with self.lock:
            color = self.pending_color
            depth_m = self.pending_depth
            frame_id = self.pending_frame_id
            self.pending_color = None
            self.pending_depth = None
        return frame_id, color, depth_m

    def _run(self):
        last_frame_id = -1
        while not self.stop_event.is_set():
            self.new_frame_event.wait(0.05)
            self.new_frame_event.clear()
            frame_id, color, depth_m = self._take_frame()
            if color is None or depth_m is None or frame_id == last_frame_id:
                continue
            last_frame_id = frame_id
            process_start = time.perf_counter()
            self._process_frame(frame_id, color, depth_m)
            with self.lock:
                self.process_ms = (time.perf_counter() - process_start) * 1000.0

    def _process_frame(self, frame_id, color, depth_m):
        with self.lock:
            mode = self.mode
            max_distance = self.max_distance
            foreground_band = self.foreground_band
            last_pixel = None if self.smoothed_pixel is None else self.smoothed_pixel.copy()

        valid_depth = depth_m[(depth_m > self.min_distance) & (depth_m < max_distance)]
        head_result = None
        mask = np.zeros(depth_m.shape, dtype=np.uint8)
        if valid_depth.size > 100:
            near_depth = float(np.percentile(valid_depth, self.near_percentile))
            foreground_max = min(max_distance, near_depth + foreground_band)
            mask = ((depth_m >= self.min_distance) & (depth_m <= foreground_max)).astype(np.uint8) * 255
            kernel = np.ones((5, 5), dtype=np.uint8)
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
            mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)

            contour = None
            if mode == "ml":
                head_result = self.detector.estimate(color, depth_m, self.intrinsics, self.min_distance, max_distance, last_pixel)
                if head_result is None:
                    head_result = estimate_headlock_pixel(mask, depth_m, self.min_distance, max_distance, self.intrinsics, last_pixel)
            elif mode == "headlock":
                head_result = estimate_headlock_pixel(mask, depth_m, self.min_distance, max_distance, self.intrinsics, last_pixel)
            elif mode == "body":
                contour = best_body_blob(mask, depth_m, self.intrinsics, last_pixel)
            else:
                contour = largest_foreground_blob(mask, last_pixel)

            if contour is not None and head_result is None:
                if mode == "body":
                    head_result = estimate_body_head_pixel(contour, depth_m, self.min_distance, max_distance, self.intrinsics, last_pixel)
                else:
                    head_result = estimate_head_pixel(contour, depth_m, self.min_distance, max_distance)

        latest = {
            "frame_id": frame_id,
            "has_head": False,
            "point": None,
            "pixel": None,
            "raw_pixel": None,
            "rect": None,
            "debug_rect": None,
            "blob_mask": None,
        }

        if head_result is not None:
            px, py, head_depth, rect, blob_mask = head_result[:5]
            debug_rect = head_result[5] if len(head_result) > 5 else None
            point = deproject(self.intrinsics, (px, py), head_depth)
            with self.lock:
                if self.smoothed_point is None:
                    self.smoothed_point = point
                    self.smoothed_pixel = np.array([px, py], dtype=np.float32)
                else:
                    self.smoothed_point = (self.smoothed_point * self.temporal_alpha) + (point * (1.0 - self.temporal_alpha))
                    self.smoothed_pixel = (
                        self.smoothed_pixel * self.temporal_alpha
                        + (np.array([px, py], dtype=np.float32) * (1.0 - self.temporal_alpha))
                    )
                point_out = self.smoothed_point.copy()
                pixel_out = self.smoothed_pixel.copy()
            latest.update(
                {
                    "has_head": True,
                    "point": point_out,
                    "pixel": pixel_out,
                    "raw_pixel": np.array([px, py], dtype=np.float32),
                    "rect": rect,
                    "debug_rect": debug_rect,
                    "blob_mask": blob_mask,
                }
            )
        else:
            with self.lock:
                self.smoothed_point = None
                self.smoothed_pixel = None

        now = time.perf_counter()
        with self.lock:
            self.latest = latest
            self._inference_count += 1
            if now - self._last_inference_fps_time >= 0.5:
                self.inference_fps = self._inference_count / (now - self._last_inference_fps_time)
                self._inference_count = 0
                self._last_inference_fps_time = now


def make_depth_colormap(depth_m, max_distance_m):
    clipped = np.clip(depth_m, 0.0, max_distance_m)
    normalized = np.where(clipped > 0.0, clipped / max_distance_m, 0.0)
    depth_u8 = np.uint8((1.0 - normalized) * 255.0)
    depth_u8[depth_m <= 0.0] = 0
    return cv2.applyColorMap(depth_u8, cv2.COLORMAP_TURBO)


def draw_status(frame, lines):
    y = 24
    for line in lines:
        cv2.putText(frame, line, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(frame, line, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (255, 255, 255), 1, cv2.LINE_AA)
        y += 24


class LatestFrameDisplay:
    def __init__(self, window_name, width, height):
        self.window_name = window_name
        self.width = int(width)
        self.height = int(height)
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.frame_event = threading.Event()
        self.frame = None
        self.last_key = 255
        self.display_fps = 0.0
        self.thread = threading.Thread(target=self._run, name="realsense-display", daemon=True)
        self.thread.start()

    def publish(self, frame):
        with self.lock:
            # Keep only the newest display frame. If the UI thread stalls, the
            # tracker loop should not build a backlog.
            self.frame = frame.copy()
        self.frame_event.set()

    def get_key(self):
        with self.lock:
            key = self.last_key
            self.last_key = 255
            return key

    def close(self):
        self.stop_event.set()
        self.frame_event.set()
        self.thread.join(timeout=2.0)

    def _run(self):
        cv2.namedWindow(self.window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.window_name, self.width, self.height)
        frame_count = 0
        last_fps_time = time.perf_counter()
        try:
            while not self.stop_event.is_set():
                self.frame_event.wait(0.01)
                self.frame_event.clear()
                with self.lock:
                    frame = None if self.frame is None else self.frame.copy()
                if frame is not None:
                    cv2.imshow(self.window_name, frame)
                    frame_count += 1
                key = cv2.waitKey(1) & 0xFF
                if key != 255:
                    with self.lock:
                        self.last_key = key
                now = time.perf_counter()
                if now - last_fps_time >= 0.5:
                    with self.lock:
                        self.display_fps = frame_count / (now - last_fps_time)
                    frame_count = 0
                    last_fps_time = now
        finally:
            cv2.destroyWindow(self.window_name)


def _sensor_video_modes(sensor, stream_type, stream_format):
    modes = {}
    for profile in sensor.get_stream_profiles():
        video_profile = profile.as_video_stream_profile()
        if video_profile is None:
            continue
        if profile.stream_type() != stream_type or profile.format() != stream_format:
            continue
        key = (int(video_profile.width()), int(video_profile.height()))
        modes.setdefault(key, set()).add(int(profile.fps()))
    return modes


def discover_shared_realsense_profiles(default_width, default_height, default_fps):
    context = rs.context()
    devices = context.query_devices()
    if len(devices) <= 0:
        return [(int(default_width), int(default_height), int(default_fps))]

    device = devices[0]
    depth_sensor = None
    color_sensor = None
    for sensor in device.query_sensors():
        name = sensor.get_info(rs.camera_info.name).lower()
        if "stereo" in name or "depth" in name:
            depth_sensor = sensor
        if "rgb" in name or "color" in name:
            color_sensor = sensor
    if depth_sensor is None or color_sensor is None:
        return [(int(default_width), int(default_height), int(default_fps))]

    depth_modes = _sensor_video_modes(depth_sensor, rs.stream.depth, rs.format.z16)
    color_modes = _sensor_video_modes(color_sensor, rs.stream.color, rs.format.bgr8)
    profiles = []
    for resolution in sorted(set(depth_modes.keys()) & set(color_modes.keys())):
        common_fps = depth_modes[resolution] & color_modes[resolution]
        if not common_fps:
            continue
        profiles.append((resolution[0], resolution[1], max(common_fps)))

    if not profiles:
        return [(int(default_width), int(default_height), int(default_fps))]

    # Large-to-small is easier to reason about when cycling: quality first,
    # then progressively faster/lower-resolution modes.
    profiles.sort(key=lambda item: (-item[0] * item[1], -item[2], item[0], item[1]))
    default_profile = (int(default_width), int(default_height), int(default_fps))
    if default_profile in profiles:
        profiles.remove(default_profile)
        profiles.insert(0, default_profile)
    return profiles


def run(args):
    available_profiles = discover_shared_realsense_profiles(args.width, args.height, args.fps)
    if args.list_profiles:
        print("Shared RealSense depth/color profiles using max common FPS per resolution:")
        for index, (width, height, fps) in enumerate(available_profiles):
            print(f"  {index + 1:02d}: {width}x{height} @ {fps}fps")

    current_profile_index = 0
    requested_profile = (int(args.width), int(args.height), int(args.fps))
    if requested_profile in available_profiles:
        current_profile_index = available_profiles.index(requested_profile)

    pipeline = None
    profile = None
    align = None
    depth_scale = 0.0
    intrinsics = None

    def start_pipeline_for_profile(width, height, fps):
        new_pipeline = rs.pipeline()
        config = rs.config()
        config.enable_stream(rs.stream.depth, int(width), int(height), rs.format.z16, int(fps))
        config.enable_stream(rs.stream.color, int(width), int(height), rs.format.bgr8, int(fps))
        started_profile = new_pipeline.start(config)
        depth_sensor = started_profile.get_device().first_depth_sensor()
        color_sensor = None
        for sensor in started_profile.get_device().query_sensors():
            sensor_name = sensor.get_info(rs.camera_info.name).lower()
            if "rgb" in sensor_name or "color" in sensor_name:
                color_sensor = sensor
                break
        if args.manual_exposure_ms > 0:
            for sensor in (depth_sensor, color_sensor):
                if sensor is None:
                    continue
                if sensor.supports(rs.option.enable_auto_exposure):
                    sensor.set_option(rs.option.enable_auto_exposure, 0)
                if sensor.supports(rs.option.exposure):
                    sensor.set_option(rs.option.exposure, float(args.manual_exposure_ms))
            print(f"Manual exposure requested: {args.manual_exposure_ms:.2f}")
        started_intrinsics = started_profile.get_stream(rs.stream.color).as_video_stream_profile().get_intrinsics()
        print(f"RealSense profile active: {width}x{height} @ {fps}fps")
        return new_pipeline, started_profile, rs.align(rs.stream.color), float(depth_sensor.get_depth_scale()), started_intrinsics

    width, height, fps = available_profiles[current_profile_index]
    pipeline, profile, align, depth_scale, intrinsics = start_pipeline_for_profile(width, height, fps)

    max_distance = args.max_distance
    foreground_band = args.foreground_band
    last_fps_time = time.perf_counter()
    frame_counter = 0
    fps_estimate = 0.0
    tracking_mode = args.mode
    tracker = None if args.no_tracker else AsyncTrackerWorker(args, intrinsics)
    run_start_time = time.perf_counter()
    wait_time_accum = 0.0
    align_time_accum = 0.0
    convert_time_accum = 0.0
    draw_time_accum = 0.0
    display_time_accum = 0.0
    timing_frames = 0
    display_worker = None

    if not args.no_display and args.threaded_display:
        display_worker = LatestFrameDisplay(WINDOW_NAME, width * 2, height)
    elif not args.no_display:
        cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(WINDOW_NAME, width * 2, height)

    def reset_timing_counters():
        nonlocal frame_counter, last_fps_time, fps_estimate
        nonlocal wait_time_accum, align_time_accum, convert_time_accum, draw_time_accum, display_time_accum, timing_frames
        frame_counter = 0
        fps_estimate = 0.0
        last_fps_time = time.perf_counter()
        wait_time_accum = 0.0
        align_time_accum = 0.0
        convert_time_accum = 0.0
        draw_time_accum = 0.0
        display_time_accum = 0.0
        timing_frames = 0

    def switch_profile():
        nonlocal current_profile_index, pipeline, profile, align, depth_scale, intrinsics, tracker, display_worker
        if len(available_profiles) <= 1:
            print("Only one shared RealSense profile is available.")
            return
        current_profile_index = (current_profile_index + 1) % len(available_profiles)
        next_width, next_height, next_fps = available_profiles[current_profile_index]
        if tracker is not None:
            tracker.close()
            tracker = None
        pipeline.stop()
        pipeline, profile, align, depth_scale, intrinsics = start_pipeline_for_profile(next_width, next_height, next_fps)
        if not args.no_tracker:
            tracker = AsyncTrackerWorker(args, intrinsics)
        if not args.no_display:
            if display_worker is not None:
                display_worker.close()
                display_worker = LatestFrameDisplay(WINDOW_NAME, next_width * 2, next_height)
            else:
                cv2.resizeWindow(WINDOW_NAME, next_width * 2, next_height)
        reset_timing_counters()

    try:
        while True:
            loop_start = time.perf_counter()
            frames = pipeline.wait_for_frames()
            wait_done = time.perf_counter()
            if not args.no_align:
                frames = align.process(frames)
            align_done = time.perf_counter()
            depth_frame = frames.get_depth_frame()
            color_frame = frames.get_color_frame()
            if not depth_frame or not color_frame:
                continue

            color = np.asanyarray(color_frame.get_data()).copy()
            depth_raw = np.asanyarray(depth_frame.get_data())
            depth_m = depth_raw.astype(np.float32) * depth_scale
            convert_done = time.perf_counter()
            if tracker is not None:
                tracker.submit_frame(color, depth_m)

            latest = tracker.get_latest() if tracker is not None else None
            smoothed_point = latest["point"] if latest and latest.get("has_head") else None
            smoothed_pixel = latest["pixel"] if latest and latest.get("has_head") else None
            if not args.no_draw and latest and latest.get("has_head"):
                rect = latest["rect"]
                blob_mask = latest["blob_mask"]
                debug_search_rect = latest["debug_rect"]
                raw_pixel = latest["raw_pixel"]
                x, y, w, h = rect
                cv2.rectangle(color, (x, y), (x + w, y + h), (0, 200, 255), 2)
                if debug_search_rect is not None:
                    sx, sy, sw, sh = debug_search_rect
                    cv2.rectangle(color, (sx, sy), (sx + sw, sy + sh), (255, 80, 0), 2)
                cv2.circle(color, (int(smoothed_pixel[0]), int(smoothed_pixel[1])), 9, (0, 0, 255), -1)
                cv2.circle(color, (int(raw_pixel[0]), int(raw_pixel[1])), 5, (0, 255, 255), -1)
                if blob_mask is not None:
                    color[blob_mask > 0] = cv2.addWeighted(color, 0.45, np.full_like(color, (0, 90, 120)), 0.55, 0)[blob_mask > 0]

            depth_vis = None
            if not args.no_draw:
                depth_vis = make_depth_colormap(depth_m, max_distance)
                if smoothed_pixel is not None:
                    cv2.circle(depth_vis, (int(smoothed_pixel[0]), int(smoothed_pixel[1])), 9, (0, 0, 255), -1)

            frame_counter += 1
            now = time.perf_counter()
            if now - last_fps_time >= 0.5:
                fps_estimate = frame_counter / (now - last_fps_time)
                if timing_frames > 0:
                    display_fps = display_worker.display_fps if display_worker is not None else fps_estimate
                    timing_line = (
                        "Timing ms: wait %.2f | align %.2f | convert %.2f | draw %.2f | display %.2f"
                        % (
                            wait_time_accum * 1000.0 / timing_frames,
                            align_time_accum * 1000.0 / timing_frames,
                            convert_time_accum * 1000.0 / timing_frames,
                            draw_time_accum * 1000.0 / timing_frames,
                            display_time_accum * 1000.0 / timing_frames,
                        )
                    )
                    print(
                        "Bench: cam %.1ffps | ML %.1ffps | display %.1ffps | %s"
                        % (
                            fps_estimate,
                            latest.get("inference_fps", 0.0) if latest else 0.0,
                            display_fps,
                            timing_line,
                        )
                    )
                    wait_time_accum = 0.0
                    align_time_accum = 0.0
                    convert_time_accum = 0.0
                    draw_time_accum = 0.0
                    display_time_accum = 0.0
                    timing_frames = 0
                frame_counter = 0
                last_fps_time = now

            if smoothed_point is None:
                pose_line = "Head: not found"
            else:
                pose_line = "Head XYZ m: X %.3f  Y %.3f  Z %.3f" % (
                    smoothed_point[0],
                    -smoothed_point[1],
                    smoothed_point[2],
                )

            lines = [
                pose_line,
                "Mode %s | Cam FPS %.1f | ML FPS %.1f | range %.2f-%.2fm | band %.2fm"
                % (
                    tracking_mode,
                    fps_estimate,
                    latest.get("inference_fps", 0.0) if latest else 0.0,
                    args.min_distance,
                    max_distance,
                    foreground_band,
                ),
                "Profile %dx%d@%dfps | p profile | q/Esc quit | r reset | m mode | [ ] range | - = band"
                % available_profiles[current_profile_index],
            ]
            draw_start = time.perf_counter()
            if not args.no_draw:
                draw_status(color, lines)
            draw_done = time.perf_counter()

            key = 255
            if not args.no_display:
                combined = color if args.no_draw else np.hstack([color, depth_vis])
                if display_worker is not None:
                    display_worker.publish(combined)
                    key = display_worker.get_key()
                else:
                    cv2.imshow(WINDOW_NAME, combined)
                    key = cv2.waitKey(1) & 0xFF
            display_done = time.perf_counter()

            wait_time_accum += wait_done - loop_start
            align_time_accum += align_done - wait_done
            convert_time_accum += convert_done - align_done
            draw_time_accum += draw_done - draw_start
            display_time_accum += display_done - draw_done
            timing_frames += 1

            if args.duration > 0 and time.perf_counter() - run_start_time >= args.duration:
                break
            if key in (27, ord("q")):
                break
            if key == ord("p"):
                switch_profile()
            if key == ord("r") and tracker is not None:
                tracker.reset()
            elif key == ord("m") and tracker is not None:
                modes = ["ml", "headlock", "body", "nearest"]
                tracking_mode = modes[(modes.index(tracking_mode) + 1) % len(modes)]
                tracker.set_mode(tracking_mode)
            elif key == ord("[") and tracker is not None:
                max_distance = max(args.min_distance + 0.1, max_distance - 0.1)
                tracker.set_max_distance(max_distance)
            elif key == ord("]") and tracker is not None:
                max_distance = min(7.0, max_distance + 0.1)
                tracker.set_max_distance(max_distance)
            elif key == ord("-") and tracker is not None:
                foreground_band = max(0.10, foreground_band - 0.05)
                tracker.set_foreground_band(foreground_band)
            elif key == ord("=") and tracker is not None:
                foreground_band = min(2.0, foreground_band + 0.05)
                tracker.set_foreground_band(foreground_band)
    finally:
        if tracker is not None:
            tracker.close()
        if pipeline is not None:
            pipeline.stop()
        if display_worker is not None:
            display_worker.close()
        elif not args.no_display:
            cv2.destroyWindow(WINDOW_NAME)


def parse_args():
    parser = argparse.ArgumentParser(description="Depth-first RealSense head tracker demo.")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--min-distance", type=float, default=0.25)
    parser.add_argument("--max-distance", type=float, default=7.0)
    parser.add_argument("--foreground-band", type=float, default=0.75)
    parser.add_argument("--near-percentile", type=float, default=8.0)
    parser.add_argument("--smoothing", type=float, default=0.72)
    parser.add_argument("--mode", choices=["ml", "headlock", "body", "nearest"], default="ml")
    parser.add_argument("--head-model", default="", help="Optional YOLO head/person model path. If omitted, MediaPipe Pose is used as the ML source.")
    parser.add_argument("--pose-model", default=DEFAULT_POSE_MODEL_PATH, help="MediaPipe Tasks pose landmarker .task model path.")
    parser.add_argument("--yolo-conf", type=float, default=0.35)
    parser.add_argument("--yolo-imgsz", type=int, default=416)
    parser.add_argument("--duration", type=float, default=0.0, help="Exit after this many seconds; 0 means run until closed.")
    parser.add_argument("--no-display", action="store_true", help="Do not create an OpenCV window.")
    parser.add_argument("--no-align", action="store_true", help="Skip RealSense depth-to-color alignment.")
    parser.add_argument("--no-tracker", action="store_true", help="Disable the async head tracker worker.")
    parser.add_argument("--no-draw", action="store_true", help="Skip overlays and depth colormap rendering.")
    parser.add_argument("--threaded-display", action="store_true", help="Move OpenCV imshow/waitKey to a latest-frame display thread.")
    parser.add_argument("--list-profiles", action="store_true", help="Print shared depth/color resolutions and their highest common FPS.")
    parser.add_argument("--manual-exposure-ms", type=float, default=0.0, help="Disable auto exposure and set raw RealSense exposure value when supported.")
    return parser.parse_args()


if __name__ == "__main__":
    run(parse_args())
