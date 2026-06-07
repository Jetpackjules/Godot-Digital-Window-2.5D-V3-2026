import argparse
from pathlib import Path

import cv2


def parse_args():
    parser = argparse.ArgumentParser(description="Generate a printable ChArUco board for OAK-D + RealSense fusion calibration.")
    parser.add_argument("--output", default="experiments/oakd_head_tracker_demo/charuco_8x6_30mm_6x6_250.png")
    parser.add_argument("--squares-x", type=int, default=8)
    parser.add_argument("--squares-y", type=int, default=6)
    parser.add_argument("--square-mm", type=float, default=30.0)
    parser.add_argument("--marker-mm", type=float, default=22.0)
    parser.add_argument("--dpi", type=float, default=300.0)
    parser.add_argument("--margin-mm", type=float, default=12.0)
    return parser.parse_args()


def main():
    args = parse_args()
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_6X6_250)
    board = cv2.aruco.CharucoBoard(
        (args.squares_x, args.squares_y),
        args.square_mm / 1000.0,
        args.marker_mm / 1000.0,
        dictionary,
    )
    px_per_mm = args.dpi / 25.4
    width_px = int(round((args.squares_x * args.square_mm + 2.0 * args.margin_mm) * px_per_mm))
    height_px = int(round((args.squares_y * args.square_mm + 2.0 * args.margin_mm) * px_per_mm))
    margin_px = int(round(args.margin_mm * px_per_mm))
    image = board.generateImage((width_px, height_px), marginSize=margin_px, borderBits=1)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(out_path), image)
    print(out_path.resolve())
    print(f"squares={args.squares_x}x{args.squares_y} square={args.square_mm:.1f}mm marker={args.marker_mm:.1f}mm dpi={args.dpi:.0f}")


if __name__ == "__main__":
    main()
