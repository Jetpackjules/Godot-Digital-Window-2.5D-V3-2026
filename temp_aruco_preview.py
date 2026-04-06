import time

import cv2
import cv2.aruco as aruco


WINDOW_NAME = "Quick ArUco Preview"
CAMERA_INDEX = 0
PREFERRED_MODES = [
    (2560, 1440),
    (1920, 1080),
    (1280, 720),
    (640, 480),
]

DICTIONARIES = [
    ("4x4_50", aruco.DICT_4X4_50),
    ("aruco_original", aruco.DICT_ARUCO_ORIGINAL),
    ("6x6_250", aruco.DICT_6X6_250),
    ("5x5_100", aruco.DICT_5X5_100),
    ("apriltag_36h11", aruco.DICT_APRILTAG_36h11),
]


def open_camera(index: int) -> cv2.VideoCapture:
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(index)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open camera index {index}")

    for width, height in PREFERRED_MODES:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        if actual_w >= width and actual_h >= height:
            break

    cap.set(cv2.CAP_PROP_FPS, 30)
    return cap


def main() -> None:
    cap = open_camera(CAMERA_INDEX)

    params = aruco.DetectorParameters()
    params.cornerRefinementMethod = aruco.CORNER_REFINE_SUBPIX
    detectors = []
    for dict_name, dict_id in DICTIONARIES:
        dictionary = aruco.getPredefinedDictionary(dict_id)
        detectors.append((dict_name, aruco.ArucoDetector(dictionary, params)))

    cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(WINDOW_NAME, 1280, 720)

    prev_time = time.time()
    fps = 0.0

    try:
        while True:
            ok, frame = cap.read()
            if not ok or frame is None:
                print("Frame grab failed.")
                break

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            total_markers = 0
            hit_dicts = []
            for dict_name, detector in detectors:
                corners, ids, _ = detector.detectMarkers(gray)
                if ids is None or len(ids) == 0:
                    continue

                total_markers += len(ids)
                hit_dicts.append(dict_name)
                ids = ids.flatten()
                for marker_corners, marker_id in zip(corners, ids):
                    pts = marker_corners.reshape((4, 2)).astype(int)
                    cv2.polylines(frame, [pts], True, (0, 255, 0), 6, cv2.LINE_AA)

                    center = pts.mean(axis=0).astype(int)
                    cv2.circle(frame, tuple(center), 8, (0, 255, 0), -1, cv2.LINE_AA)
                    cv2.putText(
                        frame,
                        f"{dict_name} id={int(marker_id)}",
                        (center[0] + 12, center[1] - 12),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.8,
                        (0, 255, 0),
                        2,
                        cv2.LINE_AA,
                    )

            now = time.time()
            dt = max(now - prev_time, 1e-6)
            fps = 0.9 * fps + 0.1 * (1.0 / dt)
            prev_time = now

            mode_text = (
                f"Cam {CAMERA_INDEX} | {int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}x"
                f"{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))} | "
                f"markers: {total_markers} | fps: {fps:.1f}"
            )
            cv2.putText(
                frame,
                mode_text,
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.0,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                frame,
                f"dict hits: {', '.join(hit_dicts) if hit_dicts else 'none'}",
                (20, 80),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                frame,
                "ESC or Q to quit",
                (20, 120),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )

            cv2.imshow(WINDOW_NAME, frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q"), ord("Q")):
                break
    finally:
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
