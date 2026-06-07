import subprocess
import sys


SCRIPT = "experiments/oakd_head_tracker_demo/oakd_stream_benchmark.py"


CASES = [
    ["--no-depth", "--fps", "118", "--rgb-res", "1080p", "--rgb-binning", "--duration", "4"],
    ["--no-depth", "--fps", "60", "--rgb-res", "1080p", "--duration", "4"],
    ["--no-rgb", "--fps", "120", "--mono-res", "400p", "--preset", "fast_density", "--no-lr-check", "--no-subpixel", "--no-align-rgb", "--duration", "4"],
    ["--no-rgb", "--fps", "90", "--mono-res", "400p", "--preset", "fast_density", "--no-lr-check", "--no-subpixel", "--no-align-rgb", "--duration", "4"],
    ["--fps", "90", "--rgb-res", "1080p", "--rgb-binning", "--mono-res", "400p", "--preset", "fast_density", "--no-lr-check", "--no-subpixel", "--no-align-rgb", "--duration", "4"],
    ["--fps", "60", "--rgb-res", "1080p", "--mono-res", "400p", "--preset", "fast_density", "--no-lr-check", "--no-subpixel", "--no-align-rgb", "--duration", "4"],
    ["--fps", "60", "--rgb-res", "1080p", "--mono-res", "400p", "--preset", "density", "--lr-check", "--subpixel", "--align-rgb", "--duration", "4"],
]


def main():
    for case in CASES:
        cmd = [sys.executable, SCRIPT] + case
        print("\n> " + " ".join(cmd), flush=True)
        result = subprocess.run(cmd, text=True)
        if result.returncode != 0:
            print("case failed with exit code", result.returncode, flush=True)


if __name__ == "__main__":
    main()
