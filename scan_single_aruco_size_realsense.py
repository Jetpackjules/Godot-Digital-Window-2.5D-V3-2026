import argparse
import json
import math
import time
from pathlib import Path

import cv2
import cv2.aruco as aruco
import numpy as np

try:
    import pyrealsense2 as rs
except Exception as exc:
    raise SystemExit(
        "pyrealsense2 is required for this standalone RealSense scanner. "
        "Install it with: python -m pip install pyrealsense2"
    ) from exc


ARUCO_DICTIONARIES = {
    "4x4_50": aruco.DICT_4X4_50,
    "4x4_100": aruco.DICT_4X4_100,
    "4x4_250": aruco.DICT_4X4_250,
    "4x4_1000": aruco.DICT_4X4_1000,
    "5x5_50": aruco.DICT_5X5_50,
    "5x5_100": aruco.DICT_5X5_100,
    "5x5_250": aruco.DICT_5X5_250,
    "5x5_1000": aruco.DICT_5X5_1000,
    "6x6_50": aruco.DICT_6X6_50,
    "6x6_100": aruco.DICT_6X6_100,
    "6x6_250": aruco.DICT_6X6_250,
    "6x6_1000": aruco.DICT_6X6_1000,
    "7x7_50": aruco.DICT_7X7_50,
    "7x7_100": aruco.DICT_7X7_100,
    "7x7_250": aruco.DICT_7X7_250,
    "7x7_1000": aruco.DICT_7X7_1000,
}


def make_detector_params():
    params = aruco.DetectorParameters()
    params.adaptiveThreshWinSizeMin = 3
    params.adaptiveThreshWinSizeMax = 45
    params.adaptiveThreshWinSizeStep = 4
    params.minMarkerPerimeterRate = 0.01
    params.maxMarkerPerimeterRate = 6.0
    params.minDistanceToBorder = 2
    params.cornerRefinementMethod = aruco.CORNER_REFINE_SUBPIX
    params.cornerRefinementWinSize = 5
    params.cornerRefinementMaxIterations = 50
    params.cornerRefinementMinAccuracy = 0.01
    if hasattr(params, "detectInvertedMarker"):
        params.detectInvertedMarker = True
    return params


def dictionary_items(name):
    if name == "auto":
        preferred = ["4x4_50", "4x4_100", "5x5_100", "5x5_250", "6x6_250", "6x6_1000", "7x7_250"]
        return [(item, ARUCO_DICTIONARIES[item]) for item in preferred]
    if name not in ARUCO_DICTIONARIES:
        raise SystemExit(f"Unknown dictionary {name!r}. Valid: auto, {', '.join(ARUCO_DICTIONARIES)}")
    return [(name, ARUCO_DICTIONARIES[name])]


def image_variants(gray):
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return (
        ("gray", gray),
        ("equalized", cv2.equalizeHist(gray)),
        ("clahe", clahe.apply(gray)),
        ("blurred", cv2.GaussianBlur(gray, (3, 3), 0)),
    )


def format_seen_ids(seen_ids, limit=8):
    if not seen_ids:
        return "none"
    labels = [f"{dict_name}:{found_id}" for dict_name, found_id in seen_ids[:limit]]
    if len(seen_ids) > limit:
        labels.append(f"+{len(seen_ids) - limit} more")
    return ", ".join(labels)


def draw_text_box(image, lines, origin, font_scale=0.65, color=(255, 255, 255), bg=(0, 0, 0)):
    x, y = int(origin[0]), int(origin[1])
    font = cv2.FONT_HERSHEY_SIMPLEX
    thickness = 2
    line_gap = 8
    sizes = [cv2.getTextSize(line, font, font_scale, thickness)[0] for line in lines]
    width = max((size[0] for size in sizes), default=0)
    height = sum(size[1] for size in sizes) + line_gap * max(0, len(lines) - 1)
    pad = 8
    x = max(4, min(x, image.shape[1] - width - pad * 2 - 4))
    y = max(height + pad * 2 + 4, min(y, image.shape[0] - 4))
    top_left = (x, y - height - pad * 2)
    bottom_right = (x + width + pad * 2, y)
    cv2.rectangle(image, top_left, bottom_right, bg, -1, cv2.LINE_AA)
    cv2.rectangle(image, top_left, bottom_right, color, 1, cv2.LINE_AA)

    cursor_y = y - height - pad
    for line, size in zip(lines, sizes):
        cursor_y += size[1]
        cv2.putText(image, line, (x + pad, cursor_y), font, font_scale, color, thickness, cv2.LINE_AA)
        cursor_y += line_gap


def marker_pixel_side(corners_px):
    corners = np.asarray(corners_px, dtype=np.float64)
    side_lengths = np.array(
        [
            np.linalg.norm(corners[1] - corners[0]),
            np.linalg.norm(corners[2] - corners[1]),
            np.linalg.norm(corners[3] - corners[2]),
            np.linalg.norm(corners[0] - corners[3]),
        ],
        dtype=np.float64,
    )
    return float(np.mean(side_lengths))


def draw_marker_overlay(preview, marker, estimate, accepted=True, requested_id=None):
    pts = marker["corners_px"].astype(np.int32)
    line_color = (0, 255, 0) if accepted else (0, 255, 255)
    fill_color = (0, 180, 0) if accepted else (0, 180, 180)
    bg_color = (0, 45, 0) if accepted else (0, 55, 55)
    overlay = preview.copy()
    cv2.fillConvexPoly(overlay, pts, fill_color, cv2.LINE_AA)
    cv2.addWeighted(overlay, 0.22, preview, 0.78, 0.0, preview)

    cv2.polylines(preview, [pts], True, line_color, 4, cv2.LINE_AA)
    for index, point in enumerate(pts):
        cv2.circle(preview, tuple(point), 7, line_color, -1, cv2.LINE_AA)
        cv2.putText(
            preview,
            str(index),
            (int(point[0]) + 8, int(point[1]) - 8),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            line_color,
            2,
            cv2.LINE_AA,
        )

    pixel_side = marker_pixel_side(marker["corners_px"])
    lines = [
        f"id={marker['marker_id']} dict={marker['dictionary']} {marker['variant']}",
        f"pixel side={pixel_side:.1f}px",
    ]
    if not accepted and requested_id is not None and requested_id >= 0:
        lines.append(f"filter wants id={requested_id}; not counting sample")
    if estimate is not None:
        size_m = estimate["size_m"]
        lines.append(f"size={size_m * 1000.0:.1f}mm / {size_m * 39.37007874015748:.3f}in")
    else:
        lines.append("size=waiting for stable depth plane")

    center = pts.mean(axis=0)
    draw_text_box(preview, lines, (center[0] + 18, center[1] - 18), color=line_color, bg=bg_color)


def detect_single_marker(gray, dictionaries, marker_id, params):
    best = None
    best_seen = None
    seen_ids = set()
    rejected_candidates = 0
    variants = image_variants(gray)
    for dict_name, dict_id in dictionaries:
        dictionary = aruco.getPredefinedDictionary(dict_id)
        detector = aruco.ArucoDetector(dictionary, params)
        for variant_name, image in variants:
            corners, ids, rejected = detector.detectMarkers(image)
            rejected_candidates += len(rejected)
            if ids is None:
                continue
            flat_ids = ids.flatten().astype(int).tolist()
            for idx, found_id in enumerate(flat_ids):
                seen_ids.add((dict_name, found_id))
                marker_corners = np.ascontiguousarray(corners[idx].reshape(-1, 1, 2).astype(np.float32))
                cv2.cornerSubPix(gray, marker_corners, (5, 5), (-1, -1), (
                    cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER,
                    40,
                    0.001,
                ))
                perimeter = cv2.arcLength(marker_corners.reshape(4, 2), True)
                candidate = {
                    "dictionary": dict_name,
                    "marker_id": found_id,
                    "variant": variant_name,
                    "corners_px": marker_corners.reshape(4, 2),
                    "perimeter": float(perimeter),
                }
                if best_seen is None or perimeter > best_seen["perimeter"]:
                    best_seen = candidate
                if marker_id >= 0 and found_id != marker_id:
                    continue
                if best is None or perimeter > best["perimeter"]:
                    best = candidate
    diagnostics = {
        "seen_ids": sorted(seen_ids),
        "best_seen": best_seen,
        "rejected_candidates": int(rejected_candidates),
    }
    return best, diagnostics


def intrinsics_to_matrix(intrinsics):
    return {
        "fx": float(intrinsics.fx),
        "fy": float(intrinsics.fy),
        "ppx": float(intrinsics.ppx),
        "ppy": float(intrinsics.ppy),
    }


def deproject_pixel(intr, x, y, depth_m):
    return np.array(
        [
            (float(x) - intr["ppx"]) * depth_m / intr["fx"],
            (float(y) - intr["ppy"]) * depth_m / intr["fy"],
            depth_m,
        ],
        dtype=np.float64,
    )


def corner_ray(intr, corner):
    x, y = corner
    ray = np.array(
        [
            (float(x) - intr["ppx"]) / intr["fx"],
            (float(y) - intr["ppy"]) / intr["fy"],
            1.0,
        ],
        dtype=np.float64,
    )
    return ray


def fit_plane(points):
    centroid = np.mean(points, axis=0)
    centered = points - centroid
    _u, singular_values, vh = np.linalg.svd(centered, full_matrices=False)
    normal = vh[-1, :]
    normal_norm = np.linalg.norm(normal)
    if normal_norm <= 1e-9:
        return None
    normal = normal / normal_norm
    d = -float(np.dot(normal, centroid))
    residuals = np.abs(points @ normal + d)
    return normal, d, residuals, singular_values


def marker_depth_points(depth_m, corners_px, intr, min_depth, max_depth, max_points):
    h, w = depth_m.shape
    mask = np.zeros((h, w), dtype=np.uint8)
    polygon = np.round(corners_px).astype(np.int32)
    cv2.fillConvexPoly(mask, polygon, 255)

    area_px = max(1.0, cv2.contourArea(corners_px.astype(np.float32)))
    kernel_size = int(max(3, min(31, round(math.sqrt(area_px) * 0.08))))
    if kernel_size % 2 == 0:
        kernel_size += 1
    kernel = np.ones((kernel_size, kernel_size), dtype=np.uint8)
    mask = cv2.erode(mask, kernel, iterations=1)

    valid = (mask > 0) & np.isfinite(depth_m) & (depth_m >= min_depth) & (depth_m <= max_depth)
    ys, xs = np.nonzero(valid)
    if len(xs) < 80:
        return None

    if len(xs) > max_points:
        idx = np.linspace(0, len(xs) - 1, max_points).astype(np.int64)
        xs = xs[idx]
        ys = ys[idx]

    depths = depth_m[ys, xs].astype(np.float64)
    points = np.stack(
        [
            (xs.astype(np.float64) - intr["ppx"]) * depths / intr["fx"],
            (ys.astype(np.float64) - intr["ppy"]) * depths / intr["fy"],
            depths,
        ],
        axis=1,
    )
    return points


def estimate_marker_size(depth_m, intr, marker, min_depth, max_depth, max_plane_points):
    points = marker_depth_points(depth_m, marker["corners_px"], intr, min_depth, max_depth, max_plane_points)
    if points is None:
        return None

    plane = fit_plane(points)
    if plane is None:
        return None
    normal, d, residuals, singular_values = plane

    if np.median(residuals) > 0.02:
        keep = residuals <= np.percentile(residuals, 75)
        if int(np.count_nonzero(keep)) >= 80:
            plane = fit_plane(points[keep])
            if plane is not None:
                normal, d, residuals, singular_values = plane

    corners_3d = []
    for corner in marker["corners_px"]:
        ray = corner_ray(intr, corner)
        denom = float(np.dot(normal, ray))
        if abs(denom) <= 1e-9:
            return None
        scale = -d / denom
        if not np.isfinite(scale) or scale <= 0.0:
            return None
        corners_3d.append(ray * scale)

    corners_3d = np.asarray(corners_3d, dtype=np.float64)
    side_lengths = np.array(
        [
            np.linalg.norm(corners_3d[1] - corners_3d[0]),
            np.linalg.norm(corners_3d[2] - corners_3d[1]),
            np.linalg.norm(corners_3d[3] - corners_3d[2]),
            np.linalg.norm(corners_3d[0] - corners_3d[3]),
        ],
        dtype=np.float64,
    )
    diagonals = np.array(
        [
            np.linalg.norm(corners_3d[2] - corners_3d[0]),
            np.linalg.norm(corners_3d[3] - corners_3d[1]),
        ],
        dtype=np.float64,
    )
    return {
        "size_m": float(np.mean(side_lengths)),
        "side_lengths_m": side_lengths.tolist(),
        "diagonals_m": diagonals.tolist(),
        "plane_points": int(len(points)),
        "plane_median_abs_residual_m": float(np.median(residuals)),
        "plane_p90_abs_residual_m": float(np.percentile(residuals, 90)),
        "plane_singular_values": singular_values.tolist(),
        "corners_px": marker["corners_px"].tolist(),
        "corners_3d_m": corners_3d.tolist(),
    }


def summarize(samples):
    sizes = np.array([s["size_m"] for s in samples], dtype=np.float64)
    return {
        "samples": int(len(samples)),
        "size_m_mean": float(np.mean(sizes)),
        "size_m_median": float(np.median(sizes)),
        "size_m_std": float(np.std(sizes)),
        "size_mm_mean": float(np.mean(sizes) * 1000.0),
        "size_mm_median": float(np.median(sizes) * 1000.0),
        "size_inches_mean": float(np.mean(sizes) * 39.37007874015748),
        "size_inches_median": float(np.median(sizes) * 39.37007874015748),
    }


def open_realsense(width, height, fps):
    pipeline = rs.pipeline()
    config = rs.config()
    config.enable_stream(rs.stream.color, width, height, rs.format.bgr8, fps)
    config.enable_stream(rs.stream.depth, width, height, rs.format.z16, fps)
    profile = pipeline.start(config)
    align = rs.align(rs.stream.color)

    depth_sensor = profile.get_device().first_depth_sensor()
    try:
        depth_sensor.set_option(rs.option.emitter_enabled, 1)
    except Exception:
        pass

    color_profile = profile.get_stream(rs.stream.color).as_video_stream_profile()
    intrinsics = intrinsics_to_matrix(color_profile.get_intrinsics())
    return pipeline, align, intrinsics


def main():
    parser = argparse.ArgumentParser(
        description="Standalone RealSense depth scanner for measuring the real side length of one ArUco marker."
    )
    parser.add_argument("--dictionary", default="auto", help="ArUco dictionary, or auto. Example: 4x4_50")
    parser.add_argument("--marker-id", type=int, default=-1, help="Marker id to accept. Default accepts the largest detected marker.")
    parser.add_argument(
        "--samples",
        type=int,
        default=None,
        help="Accepted measurements to collect before stopping. In preview mode, omit or use 0 to run until q.",
    )
    parser.add_argument("--live-window", type=int, default=60, help="Rolling sample count used for live stats when running continuously.")
    parser.add_argument("--warmup", type=int, default=30, help="Frames to discard before measuring.")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--min-depth", type=float, default=0.15)
    parser.add_argument("--max-depth", type=float, default=3.0)
    parser.add_argument("--max-plane-points", type=int, default=2500)
    parser.add_argument("--preview", action="store_true", help="Show a live preview window while scanning.")
    parser.add_argument("--output", type=Path, default=None, help="Optional JSON output path.")
    args = parser.parse_args()
    if args.samples is None:
        args.samples = 0 if args.preview else 60
    if args.samples < 0:
        raise SystemExit("--samples must be 0 or greater.")
    if args.live_window <= 0:
        raise SystemExit("--live-window must be greater than 0.")

    dictionaries = dictionary_items(args.dictionary)
    params = make_detector_params()
    pipeline, align, intr = open_realsense(args.width, args.height, args.fps)
    samples = []
    accepted_count = 0
    active_marker_key = None
    started = time.time()
    continuous = args.samples == 0

    print("Show one flat ArUco marker to the RealSense color camera.")
    print("The reported size is the detected ArUco square side, not the surrounding white quiet zone.")
    print("Default marker mode accepts the largest visible marker. Use --marker-id only when you want one exact id.")
    print("For a fixed calibration run, use --samples 60. In preview mode, press q to stop.")
    print("Keep a white quiet zone visible around all four sides of the black marker.")
    print()

    try:
        frame_index = 0
        last_print = 0.0
        while continuous or len(samples) < args.samples:
            frames = pipeline.wait_for_frames()
            aligned = align.process(frames)
            depth_frame = aligned.get_depth_frame()
            color_frame = aligned.get_color_frame()
            if not depth_frame or not color_frame:
                continue

            frame_index += 1
            if frame_index <= args.warmup:
                continue

            color = np.asanyarray(color_frame.get_data())
            depth = np.asanyarray(depth_frame.get_data()).astype(np.float32) * float(depth_frame.get_units())
            gray = cv2.cvtColor(color, cv2.COLOR_BGR2GRAY)
            marker, diagnostics = detect_single_marker(gray, dictionaries, args.marker_id, params)

            estimate = None
            preview_marker = marker
            preview_estimate = None
            preview_marker_accepted = marker is not None
            if marker is not None:
                estimate = estimate_marker_size(
                    depth,
                    intr,
                    marker,
                    args.min_depth,
                    args.max_depth,
                    args.max_plane_points,
                )
                if estimate is not None:
                    estimate.update(
                        {
                            "dictionary": marker["dictionary"],
                            "marker_id": marker["marker_id"],
                            "timestamp": time.time(),
                        }
                    )
                    marker_key = (estimate["dictionary"], estimate["marker_id"])
                    if active_marker_key != marker_key:
                        samples.clear()
                        active_marker_key = marker_key
                    samples.append(estimate)
                    accepted_count += 1
                    if continuous and len(samples) > args.live_window:
                        del samples[: len(samples) - args.live_window]
                preview_estimate = estimate
            elif diagnostics["best_seen"] is not None:
                preview_marker = diagnostics["best_seen"]
                preview_estimate = estimate_marker_size(
                    depth,
                    intr,
                    preview_marker,
                    args.min_depth,
                    args.max_depth,
                    args.max_plane_points,
                )

            now = time.time()
            if now - last_print >= 0.25:
                if samples:
                    summary = summarize(samples)
                    sample_label = (
                        f"samples={accepted_count} live_window={len(samples)}"
                        if continuous
                        else f"samples={len(samples)}/{args.samples}"
                    )
                    marker_label = f" marker={active_marker_key[0]}:{active_marker_key[1]}" if active_marker_key else ""
                    print(
                        f"{sample_label}{marker_label} "
                        f"mean={summary['size_m_mean']:.5f} m "
                        f"median={summary['size_m_median']:.5f} m "
                        f"std={summary['size_m_std'] * 1000.0:.2f} mm",
                        end="\r",
                    )
                else:
                    if marker is None and args.marker_id >= 0 and diagnostics["seen_ids"]:
                        status = f"saw {format_seen_ids(diagnostics['seen_ids'])}, waiting for id={args.marker_id}"
                    elif marker is None:
                        status = f"searching, rejected candidates={diagnostics['rejected_candidates']}"
                    else:
                        status = f"detected id={marker['marker_id']} but depth/plane not stable"
                    sample_label = "samples=0" if continuous else f"samples=0/{args.samples}"
                    print(f"{sample_label} {status}", end="\r")
                last_print = now

            if args.preview:
                preview = color.copy()
                if preview_marker is not None:
                    draw_marker_overlay(
                        preview,
                        preview_marker,
                        preview_estimate,
                        accepted=preview_marker_accepted,
                        requested_id=args.marker_id,
                    )
                else:
                    if args.marker_id >= 0 and diagnostics["seen_ids"]:
                        label = f"saw {format_seen_ids(diagnostics['seen_ids'])}; waiting for id={args.marker_id}"
                    else:
                        label = f"no marker; rejected candidates={diagnostics['rejected_candidates']}"
                    cv2.putText(preview, label, (20, 36), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 255, 255), 2)
                cv2.imshow("RealSense ArUco Size Scanner", preview)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
    finally:
        pipeline.stop()
        if args.preview:
            cv2.destroyWindow("RealSense ArUco Size Scanner")

    print()
    if not samples:
        print("No valid marker-size samples collected.")
        return

    result = summarize(samples)
    result.update(
        {
            "dictionary": samples[-1]["dictionary"],
            "marker_id": int(samples[-1]["marker_id"]),
            "duration_sec": float(time.time() - started),
            "intrinsics": intr,
            "total_accepted_samples": int(accepted_count),
            "continuous": bool(continuous),
            "raw_samples": samples,
        }
    )

    print(json.dumps({k: v for k, v in result.items() if k != "raw_samples"}, indent=2))
    print(
        "\nHardcode this in Godot/Python as marker_size_m = "
        f"{result['size_m_median']:.6f}"
    )

    if args.output is not None:
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"Wrote full sample log to {args.output}")


if __name__ == "__main__":
    main()
