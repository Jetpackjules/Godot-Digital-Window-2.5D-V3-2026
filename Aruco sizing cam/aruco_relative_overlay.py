#!/usr/bin/env python3
"""
Detect ArUco markers in one image and export relative pose info + visual overlay.

Notes:
- If you do not provide camera intrinsics, this script uses a rough default camera
  matrix based on image size. Relative geometry will be approximate.
- Marker pose is solved using a single assumed marker side length (`--marker-length`).
  Reported distances are in that arbitrary unit unless you set a real marker length.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

import cv2
import numpy as np


ARUCO_DICTS: Dict[str, int] = {
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Estimate relative ArUco marker geometry from one image."
    )
    parser.add_argument("--image", required=True, help="Input image path")
    parser.add_argument(
        "--dict",
        default="auto",
        choices=["auto", *ARUCO_DICTS.keys()],
        help="ArUco dictionary to use, or auto",
    )
    parser.add_argument(
        "--marker-length",
        type=float,
        default=1.0,
        help="Assumed marker side length. Distances are in this unit.",
    )
    parser.add_argument(
        "--intrinsics-json",
        type=str,
        default=None,
        help=(
            "Optional JSON with keys: camera_matrix (3x3), "
            "dist_coeffs (list)."
        ),
    )
    parser.add_argument(
        "--output-overlay",
        type=str,
        default=None,
        help="Output path for overlay image (default: <image>_overlay.png)",
    )
    parser.add_argument(
        "--output-json",
        type=str,
        default=None,
        help="Output path for result JSON (default: <image>_markers.json)",
    )
    return parser.parse_args()


def default_intrinsics(width: int, height: int) -> Tuple[np.ndarray, np.ndarray]:
    focal = float(max(width, height))
    camera_matrix = np.array(
        [[focal, 0.0, width / 2.0], [0.0, focal, height / 2.0], [0.0, 0.0, 1.0]],
        dtype=np.float64,
    )
    dist_coeffs = np.zeros((5, 1), dtype=np.float64)
    return camera_matrix, dist_coeffs


def load_intrinsics(path: str) -> Tuple[np.ndarray, np.ndarray]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    camera_matrix = np.array(data["camera_matrix"], dtype=np.float64)
    dist_coeffs = np.array(data.get("dist_coeffs", [0, 0, 0, 0, 0]), dtype=np.float64)
    if dist_coeffs.ndim == 1:
        dist_coeffs = dist_coeffs.reshape(-1, 1)
    if camera_matrix.shape != (3, 3):
        raise ValueError("camera_matrix must be shape (3,3)")
    return camera_matrix, dist_coeffs


def detect_with_dict(
    gray: np.ndarray, dict_name: str
) -> Tuple[List[np.ndarray], np.ndarray | None]:
    dictionary = cv2.aruco.getPredefinedDictionary(ARUCO_DICTS[dict_name])
    params = cv2.aruco.DetectorParameters()
    detector = cv2.aruco.ArucoDetector(dictionary, params)
    corners, ids, _ = detector.detectMarkers(gray)
    return corners, ids


def detect_markers(
    gray: np.ndarray, dict_choice: str
) -> Tuple[str, List[np.ndarray], np.ndarray]:
    if dict_choice != "auto":
        corners, ids = detect_with_dict(gray, dict_choice)
        if ids is None or len(ids) == 0:
            raise RuntimeError(f"No markers detected using {dict_choice}")
        return dict_choice, corners, ids

    best_name = None
    best_corners = None
    best_ids = None
    best_count = -1
    for name in ARUCO_DICTS:
        corners, ids = detect_with_dict(gray, name)
        count = 0 if ids is None else len(ids)
        if count > best_count:
            best_count = count
            best_name = name
            best_corners = corners
            best_ids = ids

    if best_ids is None or len(best_ids) == 0:
        raise RuntimeError("No markers detected for any supported dictionary")
    return best_name, best_corners, best_ids


def rt_to_transform(rvec: np.ndarray, tvec: np.ndarray) -> np.ndarray:
    rot, _ = cv2.Rodrigues(rvec.reshape(3, 1))
    transform = np.eye(4, dtype=np.float64)
    transform[:3, :3] = rot
    transform[:3, 3] = tvec.reshape(3)
    return transform


def rotation_to_euler_zyx_deg(rot: np.ndarray) -> Tuple[float, float, float]:
    sy = np.sqrt(rot[0, 0] ** 2 + rot[1, 0] ** 2)
    singular = sy < 1e-6

    if not singular:
        x = np.arctan2(rot[2, 1], rot[2, 2])
        y = np.arctan2(-rot[2, 0], sy)
        z = np.arctan2(rot[1, 0], rot[0, 0])
    else:
        x = np.arctan2(-rot[1, 2], rot[1, 1])
        y = np.arctan2(-rot[2, 0], sy)
        z = 0.0

    return tuple(np.degrees([z, y, x]).tolist())


def make_panel(
    base_img: np.ndarray,
    rows: List[str],
    panel_width: int = 560,
) -> np.ndarray:
    h, _w = base_img.shape[:2]
    panel = np.full((h, panel_width, 3), 24, dtype=np.uint8)
    y = 30
    for line in rows:
        cv2.putText(
            panel,
            line,
            (15, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.62,
            (240, 240, 240),
            1,
            cv2.LINE_AA,
        )
        y += 25
        if y >= h - 10:
            break
    return np.hstack([base_img, panel])


def main() -> None:
    args = parse_args()
    image_path = Path(args.image)
    img = cv2.imread(str(image_path))
    if img is None:
        raise FileNotFoundError(f"Could not read image: {image_path}")
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    if args.intrinsics_json:
        camera_matrix, dist_coeffs = load_intrinsics(args.intrinsics_json)
        intrinsics_source = str(Path(args.intrinsics_json))
    else:
        h, w = gray.shape[:2]
        camera_matrix, dist_coeffs = default_intrinsics(w, h)
        intrinsics_source = "default_approx_from_image_size"

    dict_name, corners, ids = detect_markers(gray, args.dict)
    ids_flat = ids.flatten().tolist()

    rvecs, tvecs, _ = cv2.aruco.estimatePoseSingleMarkers(
        corners, args.marker_length, camera_matrix, dist_coeffs
    )

    draw = img.copy()
    cv2.aruco.drawDetectedMarkers(draw, corners, ids)

    transforms = {}
    markers = []

    for i, marker_id in enumerate(ids_flat):
        rvec = rvecs[i].reshape(3, 1)
        tvec = tvecs[i].reshape(3, 1)
        transform = rt_to_transform(rvec, tvec)
        transforms[marker_id] = transform

        cv2.drawFrameAxes(
            draw,
            camera_matrix,
            dist_coeffs,
            rvec,
            tvec,
            args.marker_length * 0.5,
            thickness=2,
        )

        corner_pts = corners[i].reshape(-1, 2)
        center = corner_pts.mean(axis=0)
        side_lengths = [
            float(np.linalg.norm(corner_pts[(k + 1) % 4] - corner_pts[k])) for k in range(4)
        ]
        avg_side_px = float(np.mean(side_lengths))
        rot = transform[:3, :3]
        yaw_deg, pitch_deg, roll_deg = rotation_to_euler_zyx_deg(rot)
        dist_cam = float(np.linalg.norm(tvec))

        cv2.putText(
            draw,
            f"ID {marker_id} d={dist_cam:.2f}",
            (int(center[0]) + 8, int(center[1]) - 8),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 255, 255),
            2,
            cv2.LINE_AA,
        )

        markers.append(
            {
                "id": int(marker_id),
                "center_px": [float(center[0]), float(center[1])],
                "corners_px": corner_pts.astype(float).tolist(),
                "avg_side_px": avg_side_px,
                "rvec_marker_to_camera": rvec.reshape(3).astype(float).tolist(),
                "tvec_marker_to_camera": tvec.reshape(3).astype(float).tolist(),
                "distance_to_camera": dist_cam,
                "yaw_pitch_roll_deg_zyx": [yaw_deg, pitch_deg, roll_deg],
            }
        )

    ref_id = min(ids_flat)
    t_ref = transforms[ref_id]
    t_ref_inv = np.linalg.inv(t_ref)

    marker_by_id = {m["id"]: m for m in markers}
    for marker_id in ids_flat:
        t_i = transforms[marker_id]
        rel = t_ref_inv @ t_i
        rel_t = rel[:3, 3]
        rel_r = rel[:3, :3]
        yaw_deg, pitch_deg, roll_deg = rotation_to_euler_zyx_deg(rel_r)

        marker_by_id[marker_id]["relative_to_ref"] = {
            "ref_id": int(ref_id),
            "tvec": rel_t.astype(float).tolist(),
            "distance": float(np.linalg.norm(rel_t)),
            "yaw_pitch_roll_deg_zyx": [yaw_deg, pitch_deg, roll_deg],
        }

    markers = sorted(markers, key=lambda m: m["id"])
    out = {
        "image": str(image_path),
        "dictionary_used": dict_name,
        "intrinsics_source": intrinsics_source,
        "assumed_marker_length": float(args.marker_length),
        "units_note": "All pose distances are in assumed marker-length units.",
        "reference_marker_id": int(ref_id),
        "markers": markers,
    }

    panel_lines = [
        f"Dictionary: {dict_name}",
        f"Reference ID: {ref_id}",
        f"Marker length (assumed): {args.marker_length:g}",
        f"Intrinsics: {intrinsics_source}",
        "-" * 60,
    ]
    for marker in markers:
        rel = marker["relative_to_ref"]["tvec"]
        panel_lines.append(
            f"ID {marker['id']}: rel xyz=({rel[0]:+.2f}, {rel[1]:+.2f}, {rel[2]:+.2f})"
        )
        panel_lines.append(
            f"    cam d={marker['distance_to_camera']:.2f}, avg side px={marker['avg_side_px']:.1f}"
        )

    overlay = make_panel(draw, panel_lines)

    overlay_path = (
        Path(args.output_overlay)
        if args.output_overlay
        else image_path.with_name(f"{image_path.stem}_overlay.png")
    )
    json_path = (
        Path(args.output_json)
        if args.output_json
        else image_path.with_name(f"{image_path.stem}_markers.json")
    )

    cv2.imwrite(str(overlay_path), overlay)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)

    print(f"Detected {len(markers)} markers using {dict_name}")
    print(f"Reference marker ID: {ref_id}")
    print(f"Overlay image: {overlay_path}")
    print(f"JSON output: {json_path}")


if __name__ == "__main__":
    main()
