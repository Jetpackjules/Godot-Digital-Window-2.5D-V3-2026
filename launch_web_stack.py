import argparse
import subprocess
import sys
import time
from pathlib import Path


PROJECT_DIR = Path(__file__).parent.resolve()
WEB_DIR = PROJECT_DIR / "WEB_EXPORT"


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
    args = parser.parse_args()

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
