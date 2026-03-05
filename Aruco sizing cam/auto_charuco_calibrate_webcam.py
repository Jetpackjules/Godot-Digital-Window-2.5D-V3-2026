#!/usr/bin/env python3
"""
Live ChArUco webcam calibration with automatic frame capture.

Features:
- Real-time webcam preview with marker/corner overlay.
- Automatically accepts calibration frames when board visibility and pose diversity are good.
- Calibrates as soon as enough samples are collected.
- Shows side-by-side undistortion preview and saves intrinsics to JSON.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np

ARUCO_DICTS = {
    "DICT_4X4_50": cv2.aruco.DICT_4X4_50,
    "DICT_4X4_100": cv2.aruco.DICT_4X4_100,
    "DICT_4X4_250": cv2.aruco.DICT_4X4_250,
    "DICT_4X4_1000": cv2.aruco.DICT_4X4_1000,
    "DICT_5X5_50": cv2.aruco.DICT_5X5_50,
    "DICT_5X5_100": cv2.aruco.DICT_5X5_100,
    "DICT_5X5_250": cv2.aruco.DICT_5X5_250,
    "DICT_5X5_1000": cv2.aruco.DICT_5X5_1000,
    "DICT_6X6_50": cv2.aruco.DICT_6X6_50,
    "DICT_6X6_100": cv2.aruco.DICT_6X6_100,
    "DICT_6X6_250": cv2.aruco.DICT_6X6_250,
    "DICT_6X6_1000": cv2.aruco.DICT_6X6_1000,
    "DICT_7X7_50": cv2.aruco.DICT_7X7_50,
    "DICT_7X7_100": cv2.aruco.DICT_7X7_100,
    "DICT_7X7_250": cv2.aruco.DICT_7X7_250,
    "DICT_7X7_1000": cv2.aruco.DICT_7X7_1000,
    "DICT_ARUCO_ORIGINAL": cv2.aruco.DICT_ARUCO_ORIGINAL,
}


def normalize_dict_name(name: str) -> str:
    if not name:
        return name
    if name.lower() == "auto":
        return "auto"
    raw = name.strip().upper()
    compact = "".join(ch for ch in raw if ch.isalnum())
    for candidate in ARUCO_DICTS:
        candidate_compact = "".join(ch for ch in candidate if ch.isalnum())
        if compact == candidate_compact:
            return candidate
    return raw


def ensure_highgui_available() -> None:
    build_info = cv2.getBuildInformation()
    gui_line = next((line.strip() for line in build_info.splitlines() if line.strip().startswith("GUI:")), "")
    if "NONE" in gui_line.upper():
        raise RuntimeError(
            "OpenCV GUI support is missing (headless build detected). "
            "Install a GUI-enabled package, e.g.: "
            "`python -m pip uninstall -y opencv-python-headless opencv-python opencv-contrib-python-headless; "
            "python -m pip install opencv-contrib-python`"
        )


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Auto-calibrate camera from live ChArUco board video")
    p.add_argument("--camera", type=int, default=0, help="Webcam index")
    p.add_argument("--width", type=int, default=1280, help="Requested capture width")
    p.add_argument("--height", type=int, default=720, help="Requested capture height")
    p.add_argument("--fps", type=int, default=30, help="Requested capture FPS")

    p.add_argument("--squares-x", type=int, default=8, help="Board squares in X")
    p.add_argument("--squares-y", type=int, default=6, help="Board squares in Y")
    p.add_argument("--square-mm", type=float, default=30.0, help="Square side length (mm)")
    p.add_argument("--marker-mm", type=float, default=22.0, help="Marker side length (mm)")
    p.add_argument(
        "--dict",
        default="DICT_6X6_250",
        help="ArUco dictionary name (e.g. DICT_6X6_250 or dict_6x6250), or 'auto'",
    )

    p.add_argument("--target-frames", type=int, default=28, help="Accepted frames before calibrating")
    p.add_argument("--min-corners", type=int, default=12, help="Minimum ChArUco corners to accept")
    p.add_argument("--cooldown", type=float, default=0.5, help="Minimum seconds between auto-captures")
    p.add_argument(
        "--diversity-threshold",
        type=float,
        default=0.14,
        help="Min feature-space distance from existing accepted frames",
    )
    p.add_argument(
        "--output",
        default="auto",
        help="Output calibration JSON path, or 'auto' to use webcam-based filename",
    )
    p.add_argument(
        "--camera-name",
        default=None,
        help="Optional webcam name to use in auto output filename",
    )
    p.add_argument(
        "--manual-min-frames",
        type=int,
        default=6,
        help="Minimum accepted frames before allowing [c] manual calibration",
    )
    return p.parse_args()


def build_board(args: argparse.Namespace, dict_name: str) -> tuple[cv2.aruco.CharucoBoard, cv2.aruco.Dictionary]:
    if dict_name not in ARUCO_DICTS:
        raise ValueError(f"Unknown dictionary: {dict_name}")
    if args.marker_mm >= args.square_mm:
        raise ValueError("--marker-mm must be smaller than --square-mm")

    dictionary = cv2.aruco.getPredefinedDictionary(ARUCO_DICTS[dict_name])
    board = cv2.aruco.CharucoBoard(
        (args.squares_x, args.squares_y),
        float(args.square_mm),
        float(args.marker_mm),
        dictionary,
    )
    return board, dictionary


def make_detector_params() -> cv2.aruco.DetectorParameters:
    params = cv2.aruco.DetectorParameters()
    params.adaptiveThreshWinSizeMin = 3
    params.adaptiveThreshWinSizeMax = 45
    params.adaptiveThreshWinSizeStep = 4
    params.minMarkerPerimeterRate = 0.01
    params.maxMarkerPerimeterRate = 6.0
    params.minDistanceToBorder = 2
    params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    params.cornerRefinementWinSize = 5
    params.cornerRefinementMaxIterations = 50
    params.cornerRefinementMinAccuracy = 0.01
    if hasattr(params, "detectInvertedMarker"):
        params.detectInvertedMarker = True
    return params


def detect_markers_robust(
    gray: np.ndarray,
    detector: cv2.aruco.ArucoDetector,
    dictionary: cv2.aruco.Dictionary,
    params: cv2.aruco.DetectorParameters,
) -> tuple[List[np.ndarray], np.ndarray | None]:
    variants = [gray, cv2.equalizeHist(gray)]
    best_corners: List[np.ndarray] = []
    best_ids: np.ndarray | None = None
    best_count = -1
    for variant in variants:
        corners, ids, _ = detector.detectMarkers(variant)
        count = 0 if ids is None else int(len(ids))
        if count > best_count:
            best_count = count
            best_corners = corners
            best_ids = ids
        if count > 0:
            continue

        # Fallback for environments where ArucoDetector is less robust.
        corners2, ids2, _ = cv2.aruco.detectMarkers(variant, dictionary, parameters=params)
        count2 = 0 if ids2 is None else int(len(ids2))
        if count2 > best_count:
            best_count = count2
            best_corners = corners2
            best_ids = ids2
    return best_corners, best_ids


def draw_status(
    frame: np.ndarray,
    accepted: int,
    target: int,
    corners_seen: int,
    markers_seen: int,
    dict_name: str,
    auto_ok: bool,
    rms: float | None,
    msg: str,
) -> None:
    h, w = frame.shape[:2]
    panel_w = 460
    panel = np.full((h, panel_w, 3), 28, dtype=np.uint8)

    lines = [
        "Auto ChArUco calibration",
        f"Accepted frames: {accepted}/{target}",
        f"Corners this frame: {corners_seen}",
        f"Markers this frame: {markers_seen}",
        f"Dictionary: {dict_name}",
        f"Auto-capture ready: {'YES' if auto_ok else 'NO'}",
        f"RMS reprojection error: {rms:.4f}" if rms is not None else "RMS reprojection error: n/a",
        "",
        "Move board: center, edges, near, far, tilt",
        "Keys: [q]=quit [c]=calibrate now [space]=force capture",
        msg,
    ]

    y = 36
    for i, line in enumerate(lines):
        color = (235, 235, 235)
        if i == 3:
            color = (80, 210, 80) if auto_ok else (80, 120, 210)
        cv2.putText(panel, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 1, cv2.LINE_AA)
        y += 30

    frame[:, w - panel_w : w] = cv2.addWeighted(frame[:, w - panel_w : w], 0.15, panel, 0.85, 0)


def frame_signature(charuco_corners: np.ndarray, image_size: tuple[int, int]) -> np.ndarray:
    width, height = image_size
    pts = charuco_corners.reshape(-1, 2).astype(np.float32)

    cx, cy = pts.mean(axis=0)
    min_xy = pts.min(axis=0)
    max_xy = pts.max(axis=0)
    box_w = max(1.0, float(max_xy[0] - min_xy[0]))
    box_h = max(1.0, float(max_xy[1] - min_xy[1]))
    area_norm = (box_w * box_h) / float(width * height)

    # Principal orientation gives rough tilt/rotation diversity.
    centered = pts - np.array([[cx, cy]], dtype=np.float32)
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    principal = vt[0]
    angle = float(np.arctan2(principal[1], principal[0]))

    return np.array(
        [
            float(cx / width),
            float(cy / height),
            float(np.sqrt(max(0.0, area_norm))),
            float(np.sin(angle)),
            float(np.cos(angle)),
        ],
        dtype=np.float32,
    )


def is_diverse(sig: np.ndarray, accepted_sigs: List[np.ndarray], threshold: float) -> bool:
    if not accepted_sigs:
        return True
    dmin = min(float(np.linalg.norm(sig - s)) for s in accepted_sigs)
    return dmin >= threshold


def calibrate_charuco(
    all_charuco_corners: List[np.ndarray],
    all_charuco_ids: List[np.ndarray],
    board: cv2.aruco.CharucoBoard,
    image_size: tuple[int, int],
) -> tuple[float, np.ndarray, np.ndarray]:
    rms, camera_matrix, dist_coeffs, _, _ = cv2.aruco.calibrateCameraCharuco(
        charucoCorners=all_charuco_corners,
        charucoIds=all_charuco_ids,
        board=board,
        imageSize=image_size,
        cameraMatrix=None,
        distCoeffs=None,
    )
    return float(rms), camera_matrix, dist_coeffs


def save_calibration(
    output_path: Path,
    image_size: tuple[int, int],
    rms: float,
    camera_matrix: np.ndarray,
    dist_coeffs: np.ndarray,
    args: argparse.Namespace,
    accepted_frames: int,
) -> None:
    data = {
        "created_unix": time.time(),
        "image_width": int(image_size[0]),
        "image_height": int(image_size[1]),
        "rms_reprojection_error": rms,
        "camera_matrix": camera_matrix.tolist(),
        "dist_coeffs": dist_coeffs.reshape(-1).tolist(),
        "board": {
            "squares_x": args.squares_x,
            "squares_y": args.squares_y,
            "square_mm": args.square_mm,
            "marker_mm": args.marker_mm,
            "dictionary": args.dict,
        },
        "accepted_frames": accepted_frames,
    }
    output_path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def sanitize_filename(text: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", text.strip())
    cleaned = re.sub(r"_+", "_", cleaned).strip("._-")
    return cleaned or "camera"


def detect_camera_name_windows(camera_index: int) -> str | None:
    cmd = (
        "Get-CimInstance Win32_PnPEntity | "
        "Where-Object { $_.PNPClass -eq 'Camera' -or $_.Name -match 'camera|webcam|usb video' } | "
        "Select-Object -ExpandProperty Name"
    )
    try:
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-Command", cmd],
            capture_output=True,
            text=True,
            check=False,
            timeout=3,
        )
    except Exception:
        return None

    if proc.returncode != 0:
        return None

    names = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if not names:
        return None
    if 0 <= camera_index < len(names):
        return names[camera_index]
    return names[0]


def resolve_output_path(args: argparse.Namespace) -> Path:
    if args.output != "auto":
        return Path(args.output)

    cam_name = args.camera_name
    if not cam_name:
        cam_name = detect_camera_name_windows(args.camera)
    if not cam_name:
        cam_name = f"camera_{args.camera}"
    safe_name = sanitize_filename(cam_name)
    return Path(f"{safe_name}_calibration.json")


def main() -> None:
    ensure_highgui_available()
    args = parse_args()
    args.dict = normalize_dict_name(args.dict)
    if args.dict != "auto" and args.dict not in ARUCO_DICTS:
        raise ValueError(
            f"Unknown dictionary: {args.dict}. "
            f"Use one of: {', '.join(ARUCO_DICTS.keys())} or 'auto'."
        )

    dict_names = list(ARUCO_DICTS.keys()) if args.dict == "auto" else [args.dict]
    boards = {}
    detectors = {}
    dictionaries = {}
    detector_params = make_detector_params()
    for name in dict_names:
        board, dictionary = build_board(args, name)
        boards[name] = board
        dictionaries[name] = dictionary
        detectors[name] = cv2.aruco.ArucoDetector(dictionary, detector_params)

    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open camera index {args.camera}")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_FPS, args.fps)
    out_path = resolve_output_path(args)

    all_charuco_corners: List[np.ndarray] = []
    all_charuco_ids: List[np.ndarray] = []
    accepted_sigs: List[np.ndarray] = []
    locked_dict_name: str | None = None

    last_accept_time = 0.0
    rms: float | None = None
    camera_matrix: np.ndarray | None = None
    dist_coeffs: np.ndarray | None = None
    status_msg = ""

    print("Live calibration started.")
    print("Press q to quit, c to calibrate now, space to force capture.")
    print(f"Output file: {out_path.resolve()}")

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        h, w = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        best_name = locked_dict_name if locked_dict_name is not None else dict_names[0]
        best_corners: List[np.ndarray] | None = None
        best_ids: np.ndarray | None = None
        charuco_corners: np.ndarray | None = None
        charuco_ids: np.ndarray | None = None
        best_corner_count = -1
        best_marker_count = -1

        search_names = [locked_dict_name] if locked_dict_name is not None else dict_names
        for name in search_names:
            corners, ids = detect_markers_robust(gray, detectors[name], dictionaries[name], detector_params)
            marker_count = 0 if ids is None else int(len(ids))
            tmp_charuco_corners = None
            tmp_charuco_ids = None
            corner_count = 0
            if ids is not None and len(ids) > 0:
                nchar, tmp_charuco_corners, tmp_charuco_ids = cv2.aruco.interpolateCornersCharuco(
                    markerCorners=corners,
                    markerIds=ids,
                    image=gray,
                    board=boards[name],
                )
                if nchar and tmp_charuco_corners is not None:
                    corner_count = int(len(tmp_charuco_corners))

            if corner_count > best_corner_count or (
                corner_count == best_corner_count and marker_count > best_marker_count
            ):
                best_name = name
                best_corner_count = corner_count
                best_marker_count = marker_count
                best_corners = corners
                best_ids = ids
                charuco_corners = tmp_charuco_corners
                charuco_ids = tmp_charuco_ids

        if best_ids is not None and len(best_ids) > 0 and best_corners is not None:
            cv2.aruco.drawDetectedMarkers(frame, best_corners, best_ids)
        if charuco_corners is not None and charuco_ids is not None:
            cv2.aruco.drawDetectedCornersCharuco(frame, charuco_corners, charuco_ids)

        corners_seen = 0 if charuco_corners is None else int(len(charuco_corners))
        markers_seen = 0 if best_ids is None else int(len(best_ids))
        now = time.time()

        auto_ready = False
        auto_msg = status_msg
        if charuco_corners is not None and corners_seen >= args.min_corners:
            sig = frame_signature(charuco_corners, (w, h))
            if (now - last_accept_time) >= args.cooldown and is_diverse(
                sig, accepted_sigs, args.diversity_threshold
            ):
                auto_ready = True
                all_charuco_corners.append(charuco_corners)
                all_charuco_ids.append(charuco_ids)
                accepted_sigs.append(sig)
                last_accept_time = now
                auto_msg = "Auto-captured frame"
                status_msg = auto_msg
                if locked_dict_name is None:
                    locked_dict_name = best_name
                    auto_msg += f" (locked {locked_dict_name})"
                    status_msg = auto_msg
                    print(f"Locked dictionary: {locked_dict_name}")

        if len(all_charuco_corners) >= args.target_frames and camera_matrix is None:
            rms, camera_matrix, dist_coeffs = calibrate_charuco(
                all_charuco_corners,
                all_charuco_ids,
                boards[locked_dict_name or best_name],
                (w, h),
            )
            save_calibration(
                out_path,
                (w, h),
                rms,
                camera_matrix,
                dist_coeffs,
                args,
                len(all_charuco_corners),
            )
            auto_msg = f"Calibrated and saved: {out_path.resolve()}"
            status_msg = auto_msg
            print(auto_msg)

        if camera_matrix is not None and dist_coeffs is not None:
            undistorted = cv2.undistort(frame, camera_matrix, dist_coeffs)
            preview = np.hstack([frame, undistorted])
            draw_status(
                preview,
                len(all_charuco_corners),
                args.target_frames,
                corners_seen,
                markers_seen,
                locked_dict_name or best_name,
                auto_ready,
                rms,
                auto_msg,
            )
            cv2.putText(
                preview,
                "Left: raw  Right: undistorted",
                (20, 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.85,
                (60, 230, 60),
                2,
                cv2.LINE_AA,
            )
            cv2.imshow("Auto ChArUco Calibration", preview)
        else:
            draw_status(
                frame,
                len(all_charuco_corners),
                args.target_frames,
                corners_seen,
                markers_seen,
                locked_dict_name or best_name,
                auto_ready,
                rms,
                auto_msg,
            )
            cv2.imshow("Auto ChArUco Calibration", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        if key == ord(" ") and charuco_corners is not None and corners_seen >= args.min_corners:
            sig = frame_signature(charuco_corners, (w, h))
            all_charuco_corners.append(charuco_corners)
            all_charuco_ids.append(charuco_ids)
            accepted_sigs.append(sig)
            last_accept_time = now
            if locked_dict_name is None:
                locked_dict_name = best_name
                print(f"Locked dictionary: {locked_dict_name}")
            status_msg = f"Force-captured frame {len(all_charuco_corners)}/{args.target_frames}"
            print(status_msg)
        if key == ord("c"):
            if (
                charuco_corners is not None
                and charuco_ids is not None
                and corners_seen >= max(4, args.min_corners // 2)
            ):
                sig = frame_signature(charuco_corners, (w, h))
                all_charuco_corners.append(charuco_corners)
                all_charuco_ids.append(charuco_ids)
                accepted_sigs.append(sig)
                if locked_dict_name is None:
                    locked_dict_name = best_name
                    print(f"Locked dictionary: {locked_dict_name}")
                print("Captured current frame for manual calibration")

            if len(all_charuco_corners) < args.manual_min_frames:
                status_msg = (
                    f"Need >= {args.manual_min_frames} accepted frames for [c], "
                    f"currently {len(all_charuco_corners)}"
                )
                print(status_msg)
                continue

            try:
                rms, camera_matrix, dist_coeffs = calibrate_charuco(
                    all_charuco_corners,
                    all_charuco_ids,
                    boards[locked_dict_name or best_name],
                    (w, h),
                )
                save_calibration(
                    out_path,
                    (w, h),
                    rms,
                    camera_matrix,
                    dist_coeffs,
                    args,
                    len(all_charuco_corners),
                )
                status_msg = f"Manual calibration complete and saved: {out_path.resolve()}"
                print(status_msg)
            except cv2.error as exc:
                status_msg = f"Calibration failed: {exc.err}"
                print(status_msg)

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
