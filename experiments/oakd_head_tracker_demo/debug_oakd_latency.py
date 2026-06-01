import argparse
import os
import statistics
import sys
import time
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[2]
if str(PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECT_DIR))

from camera_tracker import FAST_FOUNDATION_MODEL_PROFILES, OakDCapture


def percentile(values, pct):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * float(pct) / 100.0))
    return float(ordered[max(0, min(len(ordered) - 1, index))])


def summary(values):
    values = [float(value) for value in values if value is not None]
    if not values:
        return "avg -- p50 -- p95 -- max --"
    return "avg %.1f p50 %.1f p95 %.1f max %.1f" % (
        statistics.fmean(values),
        percentile(values, 50),
        percentile(values, 95),
        max(values),
    )


def run(args):
    capture = None
    try:
        capture = OakDCapture(
            width=args.width,
            height=args.height,
            fps=args.fps,
            rgb_res=args.rgb_res,
            mono_res=args.mono_res,
            preset=args.preset,
            lr_check=args.lr_check,
            subpixel=args.subpixel,
            subpixel_bits=args.subpixel_bits,
            confidence_threshold=args.confidence_threshold,
            median_filter=args.median_filter,
            speckle_filter=args.speckle_filter,
            speckle_range=args.speckle_range,
            depth_source=args.source,
            use_rgb_color_for_host_depth=args.color_mode != "gray",
            host_depth_color_mode=args.color_mode,
            fast_stereo_iters=args.fast_iters,
            fast_stereo_scale=args.fast_scale,
            fast_stereo_torch_compile=args.torch_compile,
            fast_stereo_backend=args.backend,
            fast_stereo_model_profile=args.profile,
        )
    except Exception as exc:
        print("Failed to open OAK-D capture: %s" % exc)
        print("If Godot/the tracker is already using the OAK-D, stop that process and run this script again.")
        return 2

    end_time = time.perf_counter() + max(0.1, args.duration)
    next_print = time.perf_counter() + max(0.25, args.print_interval)
    last_serial = 0
    frame_count = 0
    duplicate_count = 0
    metrics = {
        "frame_age_ms": [],
        "sensor_age_ms": [],
        "color_age_ms": [],
        "sensor_host_age_ms": [],
        "color_host_age_ms": [],
    }
    fast_timing = {}

    try:
        while time.perf_counter() < end_time:
            result = capture.read_latest_with_serial()
            color, depth, serial, frame_time, sensor_age, color_age, sensor_host_age, color_host_age = result
            if color is None or depth is None or serial <= 0:
                time.sleep(0.002)
                continue
            if serial == last_serial:
                duplicate_count += 1
                time.sleep(0.001)
                continue
            last_serial = serial
            frame_count += 1
            now = time.perf_counter()
            metrics["frame_age_ms"].append((now - frame_time) * 1000.0 if frame_time else 0.0)
            metrics["sensor_age_ms"].append(sensor_age)
            metrics["color_age_ms"].append(color_age)
            metrics["sensor_host_age_ms"].append(sensor_host_age)
            metrics["color_host_age_ms"].append(color_host_age)
            worker = getattr(capture, "fast_foundation_worker", None)
            if worker is not None:
                fast_timing = dict(getattr(worker, "timing_ms", {}) or {})
            if now >= next_print:
                valid_depth = int(((depth > 0.05) & (depth < 10.0)).sum())
                total_depth = int(depth.size)
                print(
                    "frames=%d capture=%.1ffps source=%s valid=%.0f%% "
                    "frame_age=%s sensor=%s host=%s color=%s color_host=%s fast=%s"
                    % (
                        frame_count,
                        float(getattr(capture, "capture_fps", 0.0)),
                        getattr(capture, "depth_source", args.source),
                        100.0 * valid_depth / max(1, total_depth),
                        summary(metrics["frame_age_ms"]),
                        summary(metrics["sensor_age_ms"]),
                        summary(metrics["sensor_host_age_ms"]),
                        summary(metrics["color_age_ms"]),
                        summary(metrics["color_host_age_ms"]),
                        ", ".join("%s=%.1fms" % (key, float(value)) for key, value in sorted(fast_timing.items())) or "--",
                    ),
                    flush=True,
                )
                next_print = now + max(0.25, args.print_interval)
            time.sleep(0.001)
    finally:
        if capture is not None and args.close_device:
            capture.release()

    elapsed = max(0.001, args.duration)
    print("\nFinal OAK-D latency report")
    print("frames: %d fresh, %d duplicate polls, %.1f fresh fps" % (frame_count, duplicate_count, frame_count / elapsed))
    for name, values in metrics.items():
        print("%s: %s" % (name, summary(values)))
    if fast_timing:
        print("fast_timing_ms: %s" % ", ".join("%s=%.1f" % (key, float(value)) for key, value in sorted(fast_timing.items())))
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Debug OAK-D capture, queue, host, and FastFoundation latency without Godot.")
    parser.add_argument("--duration", type=float, default=15.0)
    parser.add_argument("--print-interval", type=float, default=2.0)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--rgb-res", default="1080p")
    parser.add_argument("--mono-res", default="400p")
    parser.add_argument("--preset", default="fast_density")
    parser.add_argument("--lr-check", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--subpixel", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--subpixel-bits", type=int, default=3)
    parser.add_argument("--confidence-threshold", type=int, default=160)
    parser.add_argument("--median-filter", default="off")
    parser.add_argument("--speckle-filter", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--speckle-range", type=int, default=0)
    parser.add_argument("--source", choices=("depthai", "fast_foundation", "host_sgbm"), default="fast_foundation")
    parser.add_argument("--backend", choices=("onnx_cuda", "onnx_trt", "pytorch", "trt_engine"), default="onnx_cuda")
    parser.add_argument("--profile", choices=sorted(FAST_FOUNDATION_MODEL_PROFILES), default="rt_256x512_i2")
    parser.add_argument("--fast-iters", type=int, default=4)
    parser.add_argument("--fast-scale", type=float, default=0.5)
    parser.add_argument("--torch-compile", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--color-mode", choices=("gray", "rgb_preview", "rgb_projected", "rgb_projected_stable"), default="gray")
    parser.add_argument(
        "--close-device",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Call DepthAI close at shutdown. Off by default because this Windows stack can crash inside depthai close().",
    )
    return parser.parse_args()


if __name__ == "__main__":
    parsed_args = parse_args()
    exit_code = run(parsed_args)
    if not parsed_args.close_device:
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(exit_code)
    raise SystemExit(exit_code)
