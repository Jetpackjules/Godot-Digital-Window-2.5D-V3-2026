import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


PROJECT_DIR = Path(__file__).parent.resolve()
WEB_DIR = PROJECT_DIR / "WEB_EXPORT"


def realsense_available() -> bool:
    try:
        import pyrealsense2 as rs
    except Exception as exc:
        print(f"[stack] RealSense auto-select skipped: pyrealsense2 unavailable ({exc})")
        return False
    try:
        context = rs.context()
        devices = context.query_devices()
        count = len(devices)
        if count > 0:
            print(f"[stack] RealSense auto-select found {count} device(s)")
            return True
        print("[stack] RealSense auto-select found no devices")
        return False
    except Exception as exc:
        print(f"[stack] RealSense auto-select failed: {exc}")
        return False


def start_process(
    label: str,
    script_path: Path,
    cwd: Path,
    *,
    inherit_stdin: bool = False,
) -> subprocess.Popen:
    process = subprocess.Popen(
        [sys.executable, str(script_path)],
        cwd=str(cwd),
        stdin=None if inherit_stdin else subprocess.DEVNULL,
    )
    print(f"[stack] started {label} (pid={process.pid})")
    return process


def stop_process(label: str, process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return

    print(f"[stack] stopping {label}...")
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        print(f"[stack] {label} did not exit in time, killing it")
        process.kill()
        process.wait(timeout=5)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Launch the web server, WebSocket bridge, and tracker together."
    )
    parser.add_argument(
        "--no-web",
        action="store_true",
        help="Do not launch the static Godot web server.",
    )
    parser.add_argument(
        "--no-tracker",
        action="store_true",
        help="Do not launch the OpenCV tracker.",
    )
    parser.add_argument(
        "--camera-source",
        choices=("auto", "webcam", "realsense"),
        default=None,
        help="Initial tracker camera source. Defaults to auto, which starts with RealSense when a device is present.",
    )
    args = parser.parse_args()

    requested_camera_source = args.camera_source or os.environ.get("TRACKER_CAMERA_SOURCE", "auto")
    requested_camera_source = requested_camera_source.strip().lower()
    if requested_camera_source == "auto":
        selected_camera_source = "realsense" if realsense_available() else "webcam"
    elif requested_camera_source in ("webcam", "realsense"):
        selected_camera_source = requested_camera_source
    else:
        print(f"[stack] unknown TRACKER_CAMERA_SOURCE={requested_camera_source!r}; falling back to auto")
        selected_camera_source = "realsense" if realsense_available() else "webcam"
    os.environ["TRACKER_CAMERA_SOURCE"] = selected_camera_source
    print(f"[stack] TRACKER_CAMERA_SOURCE={selected_camera_source}")

    processes: list[tuple[str, subprocess.Popen]] = []

    try:
        processes.append(
            ("bridge", start_process("bridge", PROJECT_DIR / "udp_to_websocket_bridge.py", PROJECT_DIR))
        )

        if not args.no_web:
            processes.append(
                ("web", start_process("web", WEB_DIR / "serve_godot.py", WEB_DIR))
            )

        if not args.no_tracker:
            processes.append(
                (
                    "tracker",
                    start_process(
                        "tracker",
                        PROJECT_DIR / "camera_tracker.py",
                        PROJECT_DIR,
                        inherit_stdin=True,
                    ),
                )
            )

        print("[stack] running. Press Ctrl+C to stop all services.")

        while True:
            time.sleep(1.0)
            for label, process in processes:
                exit_code = process.poll()
                if exit_code is not None:
                    print(f"[stack] {label} exited with code {exit_code}")
                    return exit_code

    except KeyboardInterrupt:
        print("\n[stack] shutdown requested")
        return 0
    finally:
        for label, process in reversed(processes):
            stop_process(label, process)


if __name__ == "__main__":
    raise SystemExit(main())
