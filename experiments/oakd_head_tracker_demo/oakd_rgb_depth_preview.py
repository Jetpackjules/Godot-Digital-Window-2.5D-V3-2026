import argparse
import time

import cv2
import depthai as dai
import numpy as np

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None


WINDOW_NAME = "OAK-D RGB + Stereo Depth Preview"
DEFAULT_HEAD_MODEL = "experiments/realsense_head_tracker_demo/models/yolov8_head_nano.pt"
COLOR_RESOLUTIONS = {
    "240p": dai.ColorCameraProperties.SensorResolution.THE_240X180,
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
PRESETS = {
    "default": dai.node.StereoDepth.PresetMode.DEFAULT,
    "density": dai.node.StereoDepth.PresetMode.DENSITY,
    "fast_density": dai.node.StereoDepth.PresetMode.FAST_DENSITY,
    "fast_accuracy": dai.node.StereoDepth.PresetMode.FAST_ACCURACY,
}


def create_pipeline(args):
    pipeline = dai.Pipeline()

    color = pipeline.create(dai.node.ColorCamera)
    color.setBoardSocket(dai.CameraBoardSocket.CAM_A)
    color.setResolution(COLOR_RESOLUTIONS[args.rgb_res])
    color.setPreviewSize(args.preview_width, args.preview_height)
    color.setInterleaved(False)
    color.setColorOrder(dai.ColorCameraProperties.ColorOrder.BGR)
    if args.rgb_binning:
        color.initialControl.setMisc("downsampling-mode", "binning")
    color.setFps(args.fps)

    mono_left = pipeline.create(dai.node.MonoCamera)
    mono_right = pipeline.create(dai.node.MonoCamera)
    mono_left.setBoardSocket(dai.CameraBoardSocket.CAM_B)
    mono_right.setBoardSocket(dai.CameraBoardSocket.CAM_C)
    mono_left.setResolution(MONO_RESOLUTIONS[args.mono_res])
    mono_right.setResolution(MONO_RESOLUTIONS[args.mono_res])
    mono_left.setFps(args.fps)
    mono_right.setFps(args.fps)

    stereo = pipeline.create(dai.node.StereoDepth)
    stereo.setDefaultProfilePreset(PRESETS[args.preset])
    if args.align_rgb:
        stereo.setDepthAlign(dai.CameraBoardSocket.CAM_A)
    stereo.setOutputSize(args.preview_width, args.preview_height)
    stereo.setLeftRightCheck(args.lr_check)
    stereo.setSubpixel(args.subpixel)

    mono_left.out.link(stereo.left)
    mono_right.out.link(stereo.right)

    return pipeline, color.preview.createOutputQueue(maxSize=2, blocking=False), stereo.depth.createOutputQueue(maxSize=2, blocking=False)


def draw_status(frame, lines):
    y = 26
    for line in lines:
        cv2.putText(frame, line, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(frame, line, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 1, cv2.LINE_AA)
        y += 26


def depth_to_color(depth_mm, max_depth_mm=7000):
    depth = np.asarray(depth_mm, dtype=np.float32)
    clipped = np.clip(depth, 0, max_depth_mm)
    normalized = np.where(clipped > 0, clipped / float(max_depth_mm), 0.0)
    depth_u8 = np.uint8((1.0 - normalized) * 255.0)
    depth_u8[depth <= 0] = 0
    return cv2.applyColorMap(depth_u8, cv2.COLORMAP_TURBO)


def median_depth_m(depth_mm, center, radius=5):
    if depth_mm is None:
        return None
    x, y = center
    h, w = depth_mm.shape[:2]
    x0 = max(0, int(x) - radius)
    x1 = min(w, int(x) + radius + 1)
    y0 = max(0, int(y) - radius)
    y1 = min(h, int(y) + radius + 1)
    roi = depth_mm[y0:y1, x0:x1]
    valid = roi[roi > 0]
    if valid.size == 0:
        return None
    return float(np.median(valid)) / 1000.0


class LocalHeadDetector:
    def __init__(self, model_path, conf, imgsz):
        if YOLO is None:
            raise RuntimeError("ultralytics is not installed. Run: python -m pip install ultralytics")
        self.model = YOLO(model_path)
        self.conf = conf
        self.imgsz = imgsz
        self.last_result = None
        self.fps = 0.0
        self._frames = 0
        self._last_fps_time = time.perf_counter()

    def detect(self, frame):
        results = self.model.predict(frame, imgsz=self.imgsz, conf=self.conf, verbose=False)
        now = time.perf_counter()
        self._frames += 1
        if now - self._last_fps_time >= 0.5:
            self.fps = self._frames / (now - self._last_fps_time)
            self._frames = 0
            self._last_fps_time = now

        best = None
        if results:
            result = results[0]
            names = getattr(result, "names", {}) or {}
            for box in result.boxes:
                cls_id = int(box.cls[0])
                label = str(names.get(cls_id, cls_id)).lower()
                if "head" not in label and "person" not in label:
                    continue
                conf = float(box.conf[0])
                x1, y1, x2, y2 = [float(v) for v in box.xyxy[0]]
                area = max(0.0, x2 - x1) * max(0.0, y2 - y1)
                score = conf * max(1.0, area)
                if best is None or score > best["score"]:
                    if "person" in label:
                        cx = (x1 + x2) * 0.5
                        cy = y1 + (y2 - y1) * 0.18
                    else:
                        cx = (x1 + x2) * 0.5
                        cy = (y1 + y2) * 0.5
                    best = {
                        "bbox": (int(x1), int(y1), int(x2), int(y2)),
                        "center": (int(cx), int(cy)),
                        "label": label,
                        "conf": conf,
                        "score": score,
                    }
        self.last_result = best
        return best


def parse_args():
    parser = argparse.ArgumentParser(description="Preview OAK-D RGB and stereo depth streams.")
    parser.add_argument("--fps", type=float, default=60.0, help="Requested RGB/depth FPS.")
    parser.add_argument("--duration", type=float, default=0.0, help="Auto-close after this many seconds. 0 runs until q/Esc.")
    parser.add_argument("--head-model", default="", help="Local YOLO head model path. Empty disables detection.")
    parser.add_argument("--yolo-conf", type=float, default=0.35, help="YOLO confidence threshold.")
    parser.add_argument("--yolo-imgsz", type=int, default=416, help="YOLO inference image size.")
    parser.add_argument("--rgb-res", choices=sorted(COLOR_RESOLUTIONS), default="1080p")
    parser.add_argument("--rgb-binning", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--mono-res", choices=sorted(MONO_RESOLUTIONS), default="400p")
    parser.add_argument("--preview-width", type=int, default=640)
    parser.add_argument("--preview-height", type=int, default=360)
    parser.add_argument("--preset", choices=sorted(PRESETS), default="fast_density")
    parser.add_argument("--lr-check", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--subpixel", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--align-rgb", action=argparse.BooleanOptionalAction, default=False)
    return parser.parse_args()


def main():
    args = parse_args()
    detector = None
    if args.head_model:
        detector = LocalHeadDetector(args.head_model, args.yolo_conf, args.yolo_imgsz)

    pipeline, rgb_queue, depth_queue = create_pipeline(args)
    cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(WINDOW_NAME, 1280, 360)

    pipeline.start()
    with pipeline:
        rgb_frame = None
        depth_frame = None
        rgb_count = 0
        depth_count = 0
        fps_rgb = 0.0
        fps_depth = 0.0
        last_fps_time = time.perf_counter()
        start_time = last_fps_time

        while True:
            rgb_msg = rgb_queue.tryGet()
            if rgb_msg is not None:
                rgb_frame = rgb_msg.getCvFrame()
                rgb_count += 1

            depth_msg = depth_queue.tryGet()
            if depth_msg is not None:
                depth_frame = depth_msg.getFrame()
                depth_count += 1

            now = time.perf_counter()
            if now - last_fps_time >= 0.5:
                elapsed = now - last_fps_time
                fps_rgb = rgb_count / elapsed
                fps_depth = depth_count / elapsed
                rgb_count = 0
                depth_count = 0
                last_fps_time = now

            if rgb_frame is None:
                rgb_vis = np.zeros((360, 640, 3), dtype=np.uint8)
            else:
                rgb_vis = rgb_frame.copy()

            if depth_frame is None:
                depth_vis = np.zeros((360, 640, 3), dtype=np.uint8)
            else:
                depth_vis = depth_to_color(depth_frame)
                if depth_vis.shape[:2] != rgb_vis.shape[:2]:
                    depth_vis = cv2.resize(depth_vis, (rgb_vis.shape[1], rgb_vis.shape[0]), interpolation=cv2.INTER_NEAREST)

            head_depth = None
            if detector is not None and rgb_frame is not None:
                detection = detector.detect(rgb_frame)
                if detection is not None:
                    x1, y1, x2, y2 = detection["bbox"]
                    cx, cy = detection["center"]
                    head_depth = median_depth_m(depth_frame, (cx, cy))
                    cv2.rectangle(rgb_vis, (x1, y1), (x2, y2), (0, 220, 255), 2)
                    cv2.circle(rgb_vis, (cx, cy), 7, (0, 0, 255), -1)
                    label = "local YOLO %s %.2f" % (detection["label"], detection["conf"])
                    if head_depth is not None:
                        label += " | %.2fm" % head_depth
                    cv2.putText(rgb_vis, label, (x1, max(20, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 4, cv2.LINE_AA)
                    cv2.putText(rgb_vis, label, (x1, max(20, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 220, 255), 1, cv2.LINE_AA)

            draw_status(
                rgb_vis,
                [
                    "OAK-D RGB + stereo depth",
                    "RGB FPS: %.1f | Depth FPS: %.1f | YOLO FPS: %.1f" % (fps_rgb, fps_depth, detector.fps if detector else 0.0),
                    "q/Esc quit",
                ],
            )
            combined = np.hstack([rgb_vis, depth_vis])
            cv2.imshow(WINDOW_NAME, combined)

            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break
            if args.duration > 0.0 and now - start_time >= args.duration:
                depth_text = "n/a" if head_depth is None else "%.2fm" % head_depth
                print("OAK-D local YOLO OK | RGB FPS: %.1f | Depth FPS: %.1f | YOLO FPS: %.1f | Head depth: %s" % (fps_rgb, fps_depth, detector.fps if detector else 0.0, depth_text))
                break

    cv2.destroyWindow(WINDOW_NAME)


if __name__ == "__main__":
    main()
