import argparse
import time

import depthai as dai


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
    rgb_queue = None
    depth_queue = None

    if args.rgb:
        color = pipeline.create(dai.node.ColorCamera)
        color.setBoardSocket(dai.CameraBoardSocket.CAM_A)
        color.setResolution(COLOR_RESOLUTIONS[args.rgb_res])
        color.setPreviewSize(args.rgb_width, args.rgb_height)
        color.setInterleaved(False)
        color.setColorOrder(dai.ColorCameraProperties.ColorOrder.BGR)
        if args.rgb_binning:
            color.initialControl.setMisc("downsampling-mode", "binning")
        color.setFps(args.fps)
        rgb_queue = color.preview.createOutputQueue(maxSize=8, blocking=False)

    if args.depth:
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
        stereo.setOutputSize(args.depth_width, args.depth_height)
        stereo.setLeftRightCheck(args.lr_check)
        stereo.setSubpixel(args.subpixel)
        if args.align_rgb:
            stereo.setDepthAlign(dai.CameraBoardSocket.CAM_A)

        mono_left.out.link(stereo.left)
        mono_right.out.link(stereo.right)
        depth_queue = stereo.depth.createOutputQueue(maxSize=8, blocking=False)

    return pipeline, rgb_queue, depth_queue


def drain_queue(queue):
    if queue is None:
        return 0
    count = 0
    while True:
        msg = queue.tryGet()
        if msg is None:
            break
        count += 1
    return count


def run_case(args):
    pipeline, rgb_queue, depth_queue = create_pipeline(args)
    pipeline.start()

    rgb_total = 0
    depth_total = 0
    start = time.perf_counter()
    warmup_end = start + args.warmup
    end = start + args.duration

    with pipeline:
        while time.perf_counter() < end:
            rgb_count = drain_queue(rgb_queue)
            depth_count = drain_queue(depth_queue)
            now = time.perf_counter()
            if now >= warmup_end:
                rgb_total += rgb_count
                depth_total += depth_count
            time.sleep(0.001)

    measured = max(0.001, time.perf_counter() - warmup_end)
    rgb_fps = rgb_total / measured if args.rgb else 0.0
    depth_fps = depth_total / measured if args.depth else 0.0
    print(
        "rgb=%s depth=%s fps_req=%.1f rgb_res=%s mono_res=%s preset=%s lr=%s subpixel=%s align_rgb=%s -> RGB %.1f fps | Depth %.1f fps"
        % (
            args.rgb,
            args.depth,
            args.fps,
            args.rgb_res,
            args.mono_res,
            args.preset,
            args.lr_check,
            args.subpixel,
            args.align_rgb,
            rgb_fps,
            depth_fps,
        )
    )


def parse_args():
    parser = argparse.ArgumentParser(description="Measure raw OAK-D RGB/depth stream FPS without display or YOLO.")
    parser.add_argument("--rgb", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--depth", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--fps", type=float, default=60.0)
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--warmup", type=float, default=1.0)
    parser.add_argument("--rgb-res", choices=sorted(COLOR_RESOLUTIONS), default="1080p")
    parser.add_argument("--rgb-width", type=int, default=640)
    parser.add_argument("--rgb-height", type=int, default=360)
    parser.add_argument("--rgb-binning", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--mono-res", choices=sorted(MONO_RESOLUTIONS), default="400p")
    parser.add_argument("--depth-width", type=int, default=640)
    parser.add_argument("--depth-height", type=int, default=360)
    parser.add_argument("--preset", choices=sorted(PRESETS), default="fast_density")
    parser.add_argument("--lr-check", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--subpixel", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--align-rgb", action=argparse.BooleanOptionalAction, default=False)
    return parser.parse_args()


if __name__ == "__main__":
    run_case(parse_args())
