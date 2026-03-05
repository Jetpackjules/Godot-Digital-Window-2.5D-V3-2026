#!/usr/bin/env python3
"""
Generate a printable ChArUco board on a selected paper size.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np


def mm_to_px(mm: float, dpi: int) -> int:
    return int(round(mm * dpi / 25.4))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate a printable ChArUco board.")
    p.add_argument("--output", default="charuco_board_a4_300dpi.png", help="Output image path")
    p.add_argument("--dpi", type=int, default=300, help="Print DPI")
    p.add_argument(
        "--paper",
        choices=["a4", "letter"],
        default="a4",
        help="Paper size",
    )
    p.add_argument(
        "--orientation",
        choices=["portrait", "landscape"],
        default="portrait",
        help="Page orientation",
    )
    p.add_argument("--squares-x", type=int, default=8, help="Number of board squares in X")
    p.add_argument("--squares-y", type=int, default=6, help="Number of board squares in Y")
    p.add_argument("--square-mm", type=float, default=25.0, help="Square side length in mm")
    p.add_argument("--marker-mm", type=float, default=18.0, help="Marker side length in mm")
    p.add_argument("--dict", default="DICT_6X6_250", help="ArUco dictionary name")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    if not hasattr(cv2.aruco, args.dict):
        raise ValueError(f"Unknown dictionary: {args.dict}")
    if args.marker_mm >= args.square_mm:
        raise ValueError("--marker-mm must be smaller than --square-mm")

    aruco_dict = cv2.aruco.getPredefinedDictionary(getattr(cv2.aruco, args.dict))
    board = cv2.aruco.CharucoBoard(
        (args.squares_x, args.squares_y), args.square_mm, args.marker_mm, aruco_dict
    )

    # Paper size in mm
    if args.paper == "a4":
        page_w_mm, page_h_mm = 210.0, 297.0
    else:
        page_w_mm, page_h_mm = 215.9, 279.4

    if args.orientation == "landscape":
        page_w_mm, page_h_mm = page_h_mm, page_w_mm

    page_w_px = mm_to_px(page_w_mm, args.dpi)
    page_h_px = mm_to_px(page_h_mm, args.dpi)

    board_w_px = mm_to_px(args.squares_x * args.square_mm, args.dpi)
    board_h_px = mm_to_px(args.squares_y * args.square_mm, args.dpi)

    if board_w_px > page_w_px or board_h_px > page_h_px:
        raise ValueError("Board does not fit A4 with current settings")

    board_img = board.generateImage((board_w_px, board_h_px))

    page = np.full((page_h_px, page_w_px), 255, dtype=np.uint8)
    x0 = (page_w_px - board_w_px) // 2
    y0 = (page_h_px - board_h_px) // 2
    page[y0 : y0 + board_h_px, x0 : x0 + board_w_px] = board_img

    # Minimal print metadata text
    text = (
        f"ChArUco {args.squares_x}x{args.squares_y}, square={args.square_mm:g}mm, "
        f"marker={args.marker_mm:g}mm, {args.dict}, print at 100%"
    )
    cv2.putText(
        page,
        text,
        (mm_to_px(6, args.dpi), page_h_px - mm_to_px(8, args.dpi)),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        0,
        1,
        cv2.LINE_AA,
    )

    out = Path(args.output)
    cv2.imwrite(str(out), page)

    print(f"Wrote: {out.resolve()}")
    print(
        f"Board size: {args.squares_x * args.square_mm:g}mm x "
        f"{args.squares_y * args.square_mm:g}mm"
    )
    print("Print at 100% scale (disable fit-to-page).")


if __name__ == "__main__":
    main()
