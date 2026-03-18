import cv2
import cv2.aruco as aruco
import numpy as np
import json
import os
import socket
import time

TRACKER_CONTROL_PORT = 4244
TRACKER_WINDOW_NAME = "Multi-Monitor ArUco Constellation Tracker"
ROOM_MAP_WINDOW_NAME = "3D Room Spatial Map"
CAMERA_TOGGLE_KEY = ord('v')
CAMERA_KEY_LEFT = 81
CAMERA_KEY_UP = 82
CAMERA_KEY_RIGHT = 83
CAMERA_KEY_DOWN = 84
CAMERA_KEY_LEFT_EX = 2424832
CAMERA_KEY_UP_EX = 2490368
CAMERA_KEY_RIGHT_EX = 2555904
CAMERA_KEY_DOWN_EX = 2621440
CAMERA_INDEX_DEFAULT = 1
CAMERA_INDEX_ENV = "CAMERA_INDEX"
CAMERA_INDEX_AUTO_MAX = 6
PREFERRED_CAMERA_MODES = [
    (2560, 1440),
    (2560, 1080),
    (2304, 1296),
    (1920, 1080),
    (1600, 1200),
    (1280, 960),
    (1280, 720),
]
PREFERRED_CAMERA_FPS = 30
WORLD_ANCHOR_MARKER_IDS = [45, 46, 47, 48, 49]
WORLD_ANCHOR_MARKER_SIZE_INCHES = 6.0
SUBPIX_WIN_SIZE = (5, 5)
SUBPIX_ZERO_ZONE = (-1, -1)
SUBPIX_CRITERIA = (
    cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER,
    40,
    0.001,
)

def make_detector_params():
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

def detect_markers_robust(gray, detector, dictionary, params):
    variants = [gray, cv2.equalizeHist(gray)]
    best_corners = []
    best_ids = None
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

        corners2, ids2, _ = cv2.aruco.detectMarkers(variant, dictionary, parameters=params)
        count2 = 0 if ids2 is None else int(len(ids2))
        if count2 > best_count:
            best_count = count2
            best_corners = corners2
            best_ids = ids2
    if best_ids is not None and len(best_corners) > 0:
        refined_corners = []
        for marker_corners in best_corners:
            pts = np.ascontiguousarray(marker_corners.reshape(-1, 1, 2).astype(np.float32))
            cv2.cornerSubPix(gray, pts, SUBPIX_WIN_SIZE, SUBPIX_ZERO_ZONE, SUBPIX_CRITERIA)
            refined_corners.append(pts.reshape(1, 4, 2))
        best_corners = refined_corners
    return best_corners, best_ids

def frame_signature(charuco_corners, image_size):
    width, height = image_size
    pts = charuco_corners.reshape(-1, 2).astype(np.float32)

    cx, cy = pts.mean(axis=0)
    min_xy = pts.min(axis=0)
    max_xy = pts.max(axis=0)
    box_w = max(1.0, float(max_xy[0] - min_xy[0]))
    box_h = max(1.0, float(max_xy[1] - min_xy[1]))
    area_norm = (box_w * box_h) / float(width * height)

    centered = pts - np.array([[cx, cy]], dtype=np.float32)
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    principal = vt[0]
    angle = float(np.arctan2(principal[1], principal[0]))

    return np.array([
        float(cx / width),
        float(cy / height),
        float(np.sqrt(max(0.0, area_norm))),
        float(np.sin(angle)),
        float(np.cos(angle)),
    ], dtype=np.float32)

def is_diverse(sig, accepted_sigs, threshold):
    if not accepted_sigs:
        return True
    dmin = min(float(np.linalg.norm(sig - s)) for s in accepted_sigs)
    return dmin >= threshold

def create_transform_matrix(rvec, tvec):
    rmat, _ = cv2.Rodrigues(rvec)
    T = np.eye(4, dtype=np.float32)
    T[:3, :3] = rmat
    T[:3, 3] = tvec.flatten()
    return T

def load_screen_configs():
    if os.path.exists("monitor_configs.json"):
        try:
            with open("monitor_configs.json", "r") as f:
                return json.load(f)
        except:
            pass
    return {}

def build_status_frame(title, lines, width=1280, height=720):
    frame = np.full((height, width, 3), 20, dtype=np.uint8)
    cv2.putText(frame, title, (40, 80), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 3, cv2.LINE_AA)

    y = 145
    for line in lines:
        cv2.putText(frame, line, (40, y), cv2.FONT_HERSHEY_SIMPLEX, 0.78, (210, 210, 210), 2, cv2.LINE_AA)
        y += 42

    return frame

def get_capture_dimensions(capture):
    width = int(round(capture.get(cv2.CAP_PROP_FRAME_WIDTH)))
    height = int(round(capture.get(cv2.CAP_PROP_FRAME_HEIGHT)))
    return width, height

def camera_mode_score(width, height):
    return width * height

def open_capture_for_index(index, backends):
    for backend in backends:
        capture = cv2.VideoCapture(index, backend)
        if capture.isOpened():
            return capture
        capture.release()
    return None

def select_best_camera_index(backends):
    best_index = None
    best_score = -1
    best_mode = None

    for index in range(CAMERA_INDEX_AUTO_MAX):
        cap = open_capture_for_index(index, backends)
        if cap is None:
            continue

        if hasattr(cv2, "CAP_PROP_FOURCC"):
            cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        if hasattr(cv2, "CAP_PROP_FPS"):
            cap.set(cv2.CAP_PROP_FPS, PREFERRED_CAMERA_FPS)

        current_mode = get_capture_dimensions(cap)
        current_score = camera_mode_score(*current_mode)
        for width, height in PREFERRED_CAMERA_MODES:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            actual_mode = get_capture_dimensions(cap)
            actual_score = camera_mode_score(*actual_mode)
            if actual_score > current_score:
                current_score = actual_score
                current_mode = actual_mode

        if current_score > best_score:
            best_score = current_score
            best_index = index
            best_mode = current_mode

        cap.release()

    return best_index, best_mode

def infer_calibration_size(camera_matrix):
    if camera_matrix is None:
        return None
    cx = float(camera_matrix[0, 2])
    cy = float(camera_matrix[1, 2])
    inferred_width = int(round(cx * 2.0))
    inferred_height = int(round(cy * 2.0))
    if inferred_width <= 0 or inferred_height <= 0:
        return None
    return inferred_width, inferred_height

def main():
    print("Starting ArUco Constellation Tracker...")
    print("Press 'v' in the camera window to release/reacquire the webcam without stopping the tracker.")
    print("Press 'q' in the camera window to quit.\n")

    # Load the 4x4_50 dictionary we used in Godot
    aruco_dict = aruco.getPredefinedDictionary(aruco.DICT_4X4_50)
    parameters = make_detector_params() # Use the robust parameters!
    detector = aruco.ArucoDetector(aruco_dict, parameters)
    
    # --- CHARUCO CALIBRATION SETUP ---
    charuco_dict = aruco.getPredefinedDictionary(aruco.DICT_6X6_250)
    charuco_board = aruco.CharucoBoard((8, 6), 0.0285, 0.021, charuco_dict)
    charuco_detector = aruco.ArucoDetector(charuco_dict, parameters)
    
    camera_matrix = None
    dist_coeffs = None
    stored_camera_matrix = None
    stored_dist_coeffs = None
    stored_calibration_size = None
    if os.path.exists("camera_calibration.json"):
        try:
            with open("camera_calibration.json", "r") as f:
                calib = json.load(f)
                stored_camera_matrix = np.array(calib["camera_matrix"], dtype=np.float32)
                stored_dist_coeffs = np.array(calib["dist_coeffs"], dtype=np.float32)
                if "image_width" in calib and "image_height" in calib:
                    stored_calibration_size = (int(calib["image_width"]), int(calib["image_height"]))
            print(">>> Successfully loaded camera_calibration.json! Intrinsics are available pending capture-mode validation. <<<")
        except Exception as e:
            print("Failed to load calibration:", e)
            
    all_charuco_corners = []
    all_charuco_ids = []
    accepted_sigs = []
    last_calib_time = time.time()
    
    # Constellation Definitions
    # TL: 40, TR: 41, BL: 42, BR: 43
    # Center Device IDs: 0-5
    
    # --- SLAM SPATIAL GRAPH MEMORY ---
    global_origin_id = None
    # Dictionary mapping screen_id (int) -> {"transform": 4x4 ndarray, "width": float, "height": float}
    global_transforms = {}
    global_anchor_transforms = {} # anchor_id -> {"transform": 4x4 ndarray, "size": float}
    screen_trackers = {} # c_id -> {"rvec": rvec, "tvec": tvec}
    anchor_trackers = {} # anchor_id -> {"rvec": rvec, "tvec": tvec}
    
    # Temporal Smoothing
    smoothed_T_cam = None

    view_pitch = 45.0
    view_yaw = -45.0
    view_dist = 150.0
    view_pan_x = 0.0
    view_pan_y = 0.0
    mouse_is_down = False
    pan_is_down = False
    last_mouse_x = 0
    last_mouse_y = 0
    last_pan_x = 0
    last_pan_y = 0
    rendered_screen_centers = []
    bridge_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    command_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    command_sock.bind(("127.0.0.1", TRACKER_CONTROL_PORT))
    command_sock.setblocking(False)
    last_status_blob = ""
    last_status_time = 0.0
    last_layout_send_time = 0.0
    cap = None
    camera_paused = False
    active_capture_width = 0
    active_capture_height = 0
    active_camera_index = None

    def send_udp_json(payload):
        bridge_sock.sendto(json.dumps(payload).encode('utf-8'), ("127.0.0.1", 4243))

    def send_scan_status(state, message, **extra):
        nonlocal last_status_blob, last_status_time
        payload = {
            "type": "scan_status",
            "state": state,
            "message": message,
        }
        payload.update(extra)
        blob = json.dumps(payload, sort_keys=True)
        now = time.time()
        if blob != last_status_blob or now - last_status_time > 1.0:
            send_udp_json(payload)
            last_status_blob = blob
            last_status_time = now

    def broadcast_layout():
        nonlocal last_layout_send_time
        origin_screen = int(global_origin_id) if global_origin_id is not None else None
        if origin_screen is None and global_transforms:
            sorted_ids = sorted(int(sid) for sid in global_transforms.keys())
            origin_screen = sorted_ids[0]
            print(f">>> WARNING: layout broadcast had no origin; falling back to screen {origin_screen}. <<<")
        layout_payload = {
            "type": "layout_map",
            "origin_screen": origin_screen,
            "screens": {}
        }
        for sid, sdata in global_transforms.items():
            T = sdata["transform"]
            layout_payload["screens"][str(sid)] = {
                "R": T[:3, :3].tolist(),
                "T": T[:3, 3].tolist(),
                "width": sdata["width"],
                "height": sdata["height"]
            }

        send_udp_json(layout_payload)
        last_layout_send_time = time.time()

    def reset_spatial_map():
        nonlocal global_origin_id, smoothed_T_cam
        print(">>> WIPING SPATIAL MAP RE-INITIALIZING <<<")
        global_transforms.clear()
        global_anchor_transforms.clear()
        global_origin_id = None
        rendered_screen_centers.clear()
        screen_trackers.clear()
        anchor_trackers.clear()
        smoothed_T_cam = None

    def configure_active_calibration():
        nonlocal camera_matrix, dist_coeffs, stored_calibration_size
        camera_matrix = None
        dist_coeffs = None

        if stored_camera_matrix is None or stored_dist_coeffs is None:
            return

        if active_capture_width <= 0 or active_capture_height <= 0:
            return

        calib_size = stored_calibration_size
        inferred_size = False
        if calib_size is None:
            calib_size = infer_calibration_size(stored_camera_matrix)
            inferred_size = True

        if calib_size is None:
            print(">>> Stored camera calibration has no usable image size. Recalibrate at the active capture mode. <<<")
            return

        calib_width, calib_height = calib_size
        current_aspect = active_capture_width / float(active_capture_height)
        calib_aspect = calib_width / float(calib_height)
        aspect_delta = abs(current_aspect - calib_aspect)

        if aspect_delta > 0.02:
            print(
                f">>> Stored calibration {calib_width}x{calib_height} is incompatible with active capture "
                f"{active_capture_width}x{active_capture_height} (aspect mismatch). Recalibrate this camera mode. <<<"
            )
            return

        scale_x = active_capture_width / float(calib_width)
        scale_y = active_capture_height / float(calib_height)
        scaled_camera_matrix = stored_camera_matrix.copy().astype(np.float32)
        scaled_camera_matrix[0, 0] *= scale_x
        scaled_camera_matrix[0, 2] *= scale_x
        scaled_camera_matrix[1, 1] *= scale_y
        scaled_camera_matrix[1, 2] *= scale_y
        camera_matrix = scaled_camera_matrix
        dist_coeffs = stored_dist_coeffs.copy().astype(np.float32)

        qualifier = "inferred-size " if inferred_size else ""
        print(
            f">>> Applied {qualifier}camera calibration from {calib_width}x{calib_height} "
            f"to active capture {active_capture_width}x{active_capture_height}. <<<"
        )

    def open_camera():
        nonlocal active_capture_width, active_capture_height, active_camera_index

        backends = []
        if os.name == "nt" and hasattr(cv2, "CAP_DSHOW"):
            backends.append(cv2.CAP_DSHOW)
        backends.append(cv2.CAP_ANY)

        forced_index = os.environ.get(CAMERA_INDEX_ENV, "").strip()
        if forced_index != "":
            try:
                active_camera_index = int(forced_index)
            except ValueError:
                active_camera_index = None
        if active_camera_index is None:
            active_camera_index = CAMERA_INDEX_DEFAULT

        capture = None
        if active_camera_index is not None:
            capture = open_capture_for_index(active_camera_index, backends)
        if capture is None:
            best_index, _ = select_best_camera_index(backends)
            active_camera_index = best_index
            if active_camera_index is not None:
                capture = open_capture_for_index(active_camera_index, backends)
        if capture is None:
            active_camera_index = None

        if capture is None:
            print(">>> Webcam unavailable. Tracker will keep running without it. Press 'v' to retry. <<<")
            return None

        if hasattr(cv2, "CAP_PROP_FOURCC"):
            capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        if hasattr(cv2, "CAP_PROP_FPS"):
            capture.set(cv2.CAP_PROP_FPS, PREFERRED_CAMERA_FPS)
        if hasattr(cv2, "CAP_PROP_BUFFERSIZE"):
            capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        best_mode = get_capture_dimensions(capture)
        best_score = camera_mode_score(*best_mode)

        for width, height in PREFERRED_CAMERA_MODES:
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            actual_mode = get_capture_dimensions(capture)
            actual_score = camera_mode_score(*actual_mode)
            if actual_score > best_score:
                best_mode = actual_mode
                best_score = actual_score

        if best_mode[0] > 0 and best_mode[1] > 0:
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, best_mode[0])
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, best_mode[1])

        active_capture_width, active_capture_height = get_capture_dimensions(capture)
        configure_active_calibration()
        idx_label = active_camera_index if active_camera_index is not None else "unknown"
        print(
            f">>> Webcam[{idx_label}] capture active at {active_capture_width}x{active_capture_height}"
            f" @ target {PREFERRED_CAMERA_FPS}fps. <<<"
        )
        return capture

    def switch_camera_index(delta):
        nonlocal active_camera_index, camera_paused, cap
        prev_index = active_camera_index
        prev_cap = cap

        if active_camera_index is None:
            active_camera_index = 0
        else:
            active_camera_index = (active_camera_index + delta) % CAMERA_INDEX_AUTO_MAX

        release_camera()
        os.environ[CAMERA_INDEX_ENV] = str(active_camera_index)
        cap_local = open_camera()
        if cap_local is None:
            # restore previous camera if the new one fails
            active_camera_index = prev_index
            if active_camera_index is not None:
                os.environ[CAMERA_INDEX_ENV] = str(active_camera_index)
            cap_local = prev_cap
            if cap_local is None and active_camera_index is not None:
                cap_local = open_camera()
            if cap_local is None:
                camera_paused = True
                print(">>> Camera switch failed; staying paused. <<<")
                return None

        camera_paused = False
        return cap_local

    def release_camera():
        nonlocal cap, active_capture_width, active_capture_height, active_camera_index
        if cap is not None:
            cap.release()
            cap = None
        active_capture_width = 0
        active_capture_height = 0
        active_camera_index = None

    def set_camera_paused(paused):
        nonlocal cap, camera_paused
        if paused:
            release_camera()
            camera_paused = True
            print(">>> Webcam capture released. Tracker and bridge remain active. Press 'v' to reacquire. <<<")
            return

        cap = open_camera()
        camera_paused = cap is None
        if not camera_paused:
            print(">>> Webcam capture reacquired. <<<")

    def mouse_callback(event, x, y, flags, param):
        nonlocal view_pitch, view_yaw, view_dist, view_pan_x, view_pan_y, mouse_is_down, pan_is_down, last_mouse_x, last_mouse_y, last_pan_x, last_pan_y, global_origin_id
        global global_transforms
        if event == cv2.EVENT_LBUTTONDOWN:
            mouse_is_down = True
            last_mouse_x = x
            last_mouse_y = y
        elif event == cv2.EVENT_LBUTTONUP:
            mouse_is_down = False
        elif event == cv2.EVENT_MBUTTONDOWN:
            pan_is_down = True
            last_pan_x = x
            last_pan_y = y
        elif event == cv2.EVENT_MBUTTONUP:
            pan_is_down = False
        elif event == cv2.EVENT_MOUSEWHEEL:
            if flags > 0:
                view_dist -= 15.0 # Zoom in
            else:
                view_dist += 15.0 # Zoom out
            view_dist = max(5.0, view_dist)
        elif event == cv2.EVENT_RBUTTONDOWN or event == cv2.EVENT_LBUTTONDBLCLK:
            for s_id, pt in rendered_screen_centers:
                if (x - pt[0])**2 + (y - pt[1])**2 < 40**2:
                    if s_id in global_transforms:
                        print(f"[*] USER DELETED Screen {s_id} from Spatial Map!")
                        del global_transforms[s_id]
                        if s_id == global_origin_id:
                            print("[!] Global Origin Deleted! Wiping entire Spatial Map!")
                            global_origin_id = None
                            global_transforms = {}
                        break
        elif event == cv2.EVENT_MOUSEMOVE:
            if mouse_is_down:
                dx = x - last_mouse_x
                dy = y - last_mouse_y
                view_yaw -= dx * 0.5
                view_pitch += dy * 0.5
                view_pitch = max(-89.0, min(89.0, view_pitch))
                last_mouse_x = x
                last_mouse_y = y
            elif pan_is_down:
                dx = x - last_pan_x
                dy = y - last_pan_y
                pan_scale = view_dist / 600.0 # Scale pan speed relative to zoom level
                view_pan_x -= dx * pan_scale * 5.0
                view_pan_y -= dy * pan_scale * 5.0
                last_pan_x = x
                last_pan_y = y

    cv2.namedWindow(TRACKER_WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.namedWindow(ROOM_MAP_WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(ROOM_MAP_WINDOW_NAME, 1200, 960)
    cv2.setMouseCallback(ROOM_MAP_WINDOW_NAME, mouse_callback)
    cap = open_camera()
    camera_paused = cap is None

    while True:
        try:
            cmd_data, _ = command_sock.recvfrom(65535)
            cmd_json = json.loads(cmd_data.decode("utf-8"))
            cmd_type = cmd_json.get("type")
            if cmd_type == "reset_spatial_map":
                reset_spatial_map()
            elif cmd_type == "pause_camera_capture":
                set_camera_paused(True)
            elif cmd_type == "resume_camera_capture":
                set_camera_paused(False)
            elif cmd_type == "toggle_camera_capture":
                set_camera_paused(not camera_paused)
        except BlockingIOError:
            pass
        except Exception as exc:
            print(f"[tracker] Failed to process control command: {exc}")

        current_frame_screens = []
        current_frame_anchors = []
        ids = None
        frame = None

        if camera_paused or cap is None:
            frame = build_status_frame(
                "WEBCAM RELEASED",
                [
                    "The tracker process is still running.",
                    "Bridge and websocket sync are still active.",
                    f"Last capture mode: {active_capture_width}x{active_capture_height}" if active_capture_width and active_capture_height else "Last capture mode: unknown",
                    f"Last camera index: {active_camera_index}" if active_camera_index is not None else "Last camera index: unknown",
                    "Press 'v' to reacquire the webcam when you want to scan again.",
                    "Existing mapped screens are kept in memory until you reset/rescan.",
                ],
            )
        else:
            ret, frame = cap.read()
            if not ret:
                print(">>> Webcam read failed. Releasing capture but keeping tracker alive. Press 'v' to retry. <<<")
                set_camera_paused(True)
                frame = build_status_frame(
                    "WEBCAM UNAVAILABLE",
                    [
                        "The tracker could not read a frame from the webcam.",
                        f"Last capture mode: {active_capture_width}x{active_capture_height}" if active_capture_width and active_capture_height else "Last capture mode: unknown",
                        f"Last camera index: {active_camera_index}" if active_camera_index is not None else "Last camera index: unknown",
                        "Press 'v' to try opening the webcam again.",
                        "Bridge and websocket sync are still active.",
                    ],
                )
             
        if not camera_paused and cap is not None:
            # Continuous ChArUco Auto-Calibration
            if camera_matrix is None:
                # ArUco detection requires grayscale
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                corners, ids, rejected = detector.detectMarkers(gray)
                
                cv2.putText(frame, f"CALIBRATING SENSOR: {len(all_charuco_corners)}/20", (30, 50), 
                            cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3, cv2.LINE_AA)
                cv2.putText(frame, "Please slowly tilt the ChArUco board!", (30, 90), 
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2, cv2.LINE_AA)
                send_scan_status(
                    "camera_calibrating",
                    "Calibrating webcam intrinsics before layout scanning can begin.",
                    accepted_frames=len(all_charuco_corners),
                    target_frames=20
                )
                
                c_corners, c_ids = detect_markers_robust(gray, charuco_detector, charuco_dict, parameters)
                if c_ids is not None and len(c_ids) > 6:
                    ret, ch_corners, ch_ids = aruco.interpolateCornersCharuco(c_corners, c_ids, gray, charuco_board)
                    if ret > 12: # Min 12 corners for a robust sample
                        aruco.drawDetectedCornersCharuco(frame, ch_corners, ch_ids, (0, 0, 255))
                        
                        sig = frame_signature(ch_corners, (frame.shape[1], frame.shape[0]))
                        if time.time() - last_calib_time > 0.5 and len(all_charuco_corners) < 20 and is_diverse(sig, accepted_sigs, 0.14):
                            all_charuco_corners.append(ch_corners)
                            all_charuco_ids.append(ch_ids)
                            accepted_sigs.append(sig)
                            last_calib_time = time.time()
                            print(f"[*] Captured ChArUco Calibration Frame {len(all_charuco_corners)}/20!")
                            
                            # Briefly flash the screen bright green to indicate a successful capture!
                            cv2.rectangle(frame, (0,0), (frame.shape[1], frame.shape[0]), (0, 255, 0), 15)
                            
                            if len(all_charuco_corners) == 20:
                                print(">>> RUNNING CHARUCO CAMERA CALIBRATION! PLEASE WAIT... <<<")
                                cv2.putText(frame, "PROCESSING CALIBRATION...", (30, 150), 
                                            cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 255), 4, cv2.LINE_AA)
                                cv2.imshow(TRACKER_WINDOW_NAME, frame)
                                cv2.waitKey(1) # Force a tiny frame update so they see the text before it hangs!
                                
                                ret_val, temp_cam, temp_dist, _, _ = aruco.calibrateCameraCharuco(all_charuco_corners, all_charuco_ids, charuco_board, gray.shape[::-1], None, None)
                                camera_matrix = temp_cam
                                dist_coeffs = temp_dist
                                stored_camera_matrix = temp_cam.copy().astype(np.float32)
                                stored_dist_coeffs = temp_dist.copy().astype(np.float32)
                                stored_calibration_size = (int(gray.shape[1]), int(gray.shape[0]))
                                
                                print(f">>> CALIBRATION COMPLETE! RMS Error: {ret_val} <<<")
                                with open("camera_calibration.json", "w") as f:
                                    json.dump({
                                        "camera_matrix": camera_matrix.tolist(),
                                        "dist_coeffs": dist_coeffs.tolist(),
                                        "image_width": int(gray.shape[1]),
                                        "image_height": int(gray.shape[0])
                                    }, f, indent=4)
                                    
                                print("Saved to camera_calibration.json! Perfect Intrinsics locked in!")
            else:
                # We have perfect intrinsics! Immediately undistort the raw webcam feed
                # so the user can visually see the math flattening their curved room!
                frame = cv2.undistort(frame, camera_matrix, dist_coeffs)
                
                # Now run ArUco detection on the mathematically perfect image!
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                corners, ids, rejected = detector.detectMarkers(gray)
         
        if ids is not None:
            # 0. Black out the markers to prevent infinite loops from the webcam seeing the screen!
            for i in range(len(ids)):
                cv2.fillPoly(frame, [np.int32(corners[i])], (0, 0, 0))
                
            # 1. Outline every individual marker found
            aruco.drawDetectedMarkers(frame, corners, ids)
            
            ids_list = ids.flatten().tolist()
            anchor_ids = [i for i, id_val in enumerate(ids_list) if id_val in WORLD_ANCHOR_MARKER_IDS]
            
            # 2. Extract our defined layout markers
            center_ids = [i for i, id_val in enumerate(ids_list) if id_val in range(6)]
            
            # 3. Cluster corners to their nearest center ID
            # This allows multiple physical monitors to be tracked simultaneously!
            for c_idx in center_ids:
                c_id = ids_list[c_idx]
                
                base_id = (c_id % 6) * 4 + 10
                tl_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id]
                tr_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id + 1]
                bl_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id + 2]
                br_ids = [i for i, id_val in enumerate(ids_list) if id_val == base_id + 3]
                
                # Get the absolute pixel center of the central ArUco marker
                c_center = np.mean(corners[c_idx][0], axis=0)
                # Caluclate the pixel perimeter of the center marker
                c_perimeter = cv2.arcLength(corners[c_idx][0], True)
                
                # Helper function to select the best-matching corner marker near the center marker.
                def get_marker_corners(target_idx_list):
                    if not target_idx_list: return None
                    
                    best_idx = None
                    min_dist_to_center = float('inf')
                    
                    for idx in target_idx_list:
                        pt = np.mean(corners[idx][0], axis=0)
                        
                        pt_perimeter = cv2.arcLength(corners[idx][0], True)
                        if pt_perimeter > c_perimeter * 2.5 or pt_perimeter < c_perimeter * 0.4:
                            continue 
                            
                        dist = np.linalg.norm(c_center - pt)
                        if dist < min_dist_to_center:
                            min_dist_to_center = dist
                            best_idx = idx

                    if min_dist_to_center > c_perimeter * 10.0:
                        return None
                    
                    if best_idx is not None:
                        return corners[best_idx][0].astype(np.float32)
                        
                    return None

                def expand_marker_corner(marker_corners, corner_index):
                    best_pt = marker_corners[corner_index]
                    marker_width = np.linalg.norm(marker_corners[0] - marker_corners[1])
                    godot_pad_pixels = marker_width * 0.15
                    direction_vector = best_pt - c_center
                    norm = np.linalg.norm(direction_vector)
                    if norm <= 1e-6:
                        return best_pt
                    direction_vector = direction_vector / norm
                    return best_pt + (direction_vector * godot_pad_pixels)
                
                tl_marker = get_marker_corners(tl_ids)
                tr_marker = get_marker_corners(tr_ids)
                bl_marker = get_marker_corners(bl_ids)
                br_marker = get_marker_corners(br_ids)
                
                # If we successfully locked onto all 4 corners + center...
                if tl_marker is not None and tr_marker is not None and br_marker is not None and bl_marker is not None:
                    # ---------------------------------------------------------
                    # 3D SPATIAL PROJECTION (DEVICE-SPECIFIC SCALE!)
                    # ---------------------------------------------------------
                    configs = load_screen_configs()
                    str_id = str(c_id)
                    
                    if str_id in configs:
                        width_inches = configs[str_id].get("width", 20.9)
                        height_inches = configs[str_id].get("height", 11.7)

                        shortest_dim = min(width_inches, height_inches)
                        marker_size = shortest_dim * 0.40
                        marker_pad = marker_size * 0.15

                        plane_points = np.array([
                            # Top-left marker: TL, TR, BR, BL
                            [marker_pad, marker_pad],
                            [marker_pad + marker_size, marker_pad],
                            [marker_pad + marker_size, marker_pad + marker_size],
                            [marker_pad, marker_pad + marker_size],
                            # Top-right marker
                            [width_inches - marker_pad - marker_size, marker_pad],
                            [width_inches - marker_pad, marker_pad],
                            [width_inches - marker_pad, marker_pad + marker_size],
                            [width_inches - marker_pad - marker_size, marker_pad + marker_size],
                            # Bottom-left marker
                            [marker_pad, height_inches - marker_pad - marker_size],
                            [marker_pad + marker_size, height_inches - marker_pad - marker_size],
                            [marker_pad + marker_size, height_inches - marker_pad],
                            [marker_pad, height_inches - marker_pad],
                            # Bottom-right marker
                            [width_inches - marker_pad - marker_size, height_inches - marker_pad - marker_size],
                            [width_inches - marker_pad, height_inches - marker_pad - marker_size],
                            [width_inches - marker_pad, height_inches - marker_pad],
                            [width_inches - marker_pad - marker_size, height_inches - marker_pad],
                        ], dtype=np.float32)

                        image_points_h = np.vstack([
                            tl_marker,
                            tr_marker,
                            bl_marker,
                            br_marker,
                        ]).astype(np.float32)

                        homography, _ = cv2.findHomography(plane_points, image_points_h, 0)

                        if homography is not None:
                            screen_plane_corners = np.array([
                                [0.0, 0.0],
                                [width_inches, 0.0],
                                [width_inches, height_inches],
                                [0.0, height_inches],
                            ], dtype=np.float32).reshape(1, 4, 2)
                            projected_screen_corners = cv2.perspectiveTransform(screen_plane_corners, homography).reshape(4, 2)
                            tl = projected_screen_corners[0]
                            tr = projected_screen_corners[1]
                            br = projected_screen_corners[2]
                            bl = projected_screen_corners[3]
                        else:
                            tl = expand_marker_corner(tl_marker, 0)
                            tr = expand_marker_corner(tr_marker, 1)
                            bl = expand_marker_corner(bl_marker, 3)
                            br = expand_marker_corner(br_marker, 2)

                        # Construct a polygon defining the physical screen's edge bounds!
                        pts = np.array([tl, tr, br, bl], np.int32)
                        pts = pts.reshape((-1, 1, 2))
                        
                        # Draw a thick green bounding box tracing the perimeter of the physical monitor
                        cv2.polylines(frame, [pts], isClosed=True, color=(0, 255, 0), thickness=3)
                        
                        # Inject a semi-transparent green overlay over the screen
                        overlay = frame.copy()
                        cv2.fillPoly(overlay, [pts], (0, 255, 0))
                        cv2.addWeighted(overlay, 0.2, frame, 0.8, 0, frame)
                        
                        # Render the Device ID prominently above the screen
                        cv2.putText(frame, f"Godot Screen ID: {c_id}", (int(tl[0]), int(tl[1] - 15)), 
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2, cv2.LINE_AA)
                        
                        # Dynamically declare the 3D dimensions of THIS precise screen!
                        w2 = width_inches / 2.0
                        h2 = height_inches / 2.0
                        object_points = np.array([
                            [-w2, -h2, 0],
                            [ w2, -h2, 0],
                            [ w2,  h2, 0],
                            [-w2,  h2, 0]
                        ], dtype=np.float32)
                        
                        # Check if we have real perfectly calibrated intrinsics
                        if camera_matrix is not None:
                            cam_mat_use = camera_matrix
                            dist_use = np.zeros((5, 1), dtype=np.float32) # Undistorted
                            pnp_flags = cv2.SOLVEPNP_IPPE
                        else:
                            # Fake Intrinsics Matrix
                            focal_length = frame.shape[1]
                            center_pt = (frame.shape[1] / 2.0, frame.shape[0] / 2.0)
                            cam_mat_use = np.array([
                                [focal_length, 0, center_pt[0]],
                                [0, focal_length, center_pt[1]],
                                [0, 0, 1]
                            ], dtype=np.float32)
                            dist_use = np.zeros((5, 1), dtype=np.float32)
                            pnp_flags = cv2.SOLVEPNP_ITERATIVE
                            
                        image_points = np.array([tl, tr, br, bl], dtype=np.float32)
                        
                        # TEMPORAL LOCKING: Prevent Necker Flipping by anchoring to the last known pose!
                        tracker = screen_trackers.get(c_id)
                        use_guess = False
                        r_guess, t_guess = None, None
                        if tracker is not None and camera_matrix is not None:
                            r_guess = tracker["rvec"].copy()
                            t_guess = tracker["tvec"].copy()
                            use_guess = True
                            pnp_flags = cv2.SOLVEPNP_ITERATIVE

                        # Project 2D pixels into Physical Space!
                        if use_guess:
                            success, rvec, tvec = cv2.solvePnP(object_points, image_points, cam_mat_use, dist_use, 
                                                               rvec=r_guess, tvec=t_guess,
                                                               useExtrinsicGuess=True, flags=pnp_flags)
                        else:
                            success, rvec, tvec = cv2.solvePnP(object_points, image_points, cam_mat_use, dist_use, flags=pnp_flags)
                        
                        if success:
                            screen_trackers[c_id] = {"rvec": rvec, "tvec": tvec}
                            # Draw full 3D coordinate axes relative to the unique screen size!
                            # Shrunk axis length so OpenCV stops warning about lines extending off-screen!
                            axis_length = float(width_inches * 0.2)
                            cv2.drawFrameAxes(frame, cam_mat_use, dist_use, rvec, tvec, axis_length, 2)
                            
                            dist_inches = np.linalg.norm(tvec)
                            cv2.putText(frame, f"Dist: {dist_inches:.1f}\"", (int(tl[0]), int(tl[1] - 40)), 
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2, cv2.LINE_AA)
                            cv2.putText(frame, f"Size: {width_inches}\"x{height_inches}\"", (int(tl[0]), int(tl[1] - 65)), 
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 1, cv2.LINE_AA)
                            
                            # Save to current frame array for SLAM graph chaining
                            current_frame_screens.append({
                                "screen_id": int(c_id),
                                "width": width_inches,
                                "height": height_inches,
                                "rvec": rvec,
                                "tvec": tvec
                            })
                    else:
                        cv2.putText(frame, "[?] Uncalibrated Screen Size", (int(tl[0]), int(tl[1] - 40)), 
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2, cv2.LINE_AA)

            # 4. Detect reserved world-anchor markers without feeding them into screen stitching.
            anchor_half = WORLD_ANCHOR_MARKER_SIZE_INCHES / 2.0
            anchor_object_points = np.array([
                [-anchor_half, -anchor_half, 0.0],
                [ anchor_half, -anchor_half, 0.0],
                [ anchor_half,  anchor_half, 0.0],
                [-anchor_half,  anchor_half, 0.0],
            ], dtype=np.float32)

            for anchor_idx in anchor_ids:
                anchor_id = int(ids_list[anchor_idx])
                anchor_corners = corners[anchor_idx][0].astype(np.float32)

                if camera_matrix is not None:
                    cam_mat_use = camera_matrix
                    dist_use = np.zeros((5, 1), dtype=np.float32)
                    pnp_flags = cv2.SOLVEPNP_IPPE
                else:
                    focal_length = frame.shape[1]
                    center_pt = (frame.shape[1] / 2.0, frame.shape[0] / 2.0)
                    cam_mat_use = np.array([
                        [focal_length, 0, center_pt[0]],
                        [0, focal_length, center_pt[1]],
                        [0, 0, 1]
                    ], dtype=np.float32)
                    dist_use = np.zeros((5, 1), dtype=np.float32)
                    pnp_flags = cv2.SOLVEPNP_ITERATIVE

                tracker = anchor_trackers.get(anchor_id)
                use_guess = False
                r_guess, t_guess = None, None
                if tracker is not None and camera_matrix is not None:
                    r_guess = tracker["rvec"].copy()
                    t_guess = tracker["tvec"].copy()
                    use_guess = True
                    pnp_flags = cv2.SOLVEPNP_ITERATIVE

                if use_guess:
                    success, rvec, tvec = cv2.solvePnP(
                        anchor_object_points,
                        anchor_corners,
                        cam_mat_use,
                        dist_use,
                        rvec=r_guess,
                        tvec=t_guess,
                        useExtrinsicGuess=True,
                        flags=pnp_flags,
                    )
                else:
                    success, rvec, tvec = cv2.solvePnP(
                        anchor_object_points,
                        anchor_corners,
                        cam_mat_use,
                        dist_use,
                        flags=pnp_flags,
                    )

                if success:
                    anchor_trackers[anchor_id] = {"rvec": rvec, "tvec": tvec}
                    anchor_dist_inches = float(np.linalg.norm(tvec))
                    cv2.drawFrameAxes(frame, cam_mat_use, dist_use, rvec, tvec, WORLD_ANCHOR_MARKER_SIZE_INCHES * 0.35, 2)
                    label_pos = anchor_corners[0].astype(np.int32)
                    cv2.putText(
                        frame,
                        f"World Anchor {anchor_id}",
                        (int(label_pos[0]), int(label_pos[1] - 16)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.65,
                        (0, 215, 255),
                        2,
                        cv2.LINE_AA,
                    )
                    cv2.putText(
                        frame,
                        f'{WORLD_ANCHOR_MARKER_SIZE_INCHES:.1f}" square | {anchor_dist_inches:.1f}"',
                        (int(label_pos[0]), int(label_pos[1] - 40)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        (0, 215, 255),
                        2,
                        cv2.LINE_AA,
                    )
                    current_frame_anchors.append({
                        "anchor_id": anchor_id,
                        "size": WORLD_ANCHOR_MARKER_SIZE_INCHES,
                        "rvec": rvec,
                        "tvec": tvec,
                    })

        # ---------------------------------------------------------
        # SPATIAL GRAPH MAPPING (SLAM)
        # ---------------------------------------------------------
        T_origin_to_cam = None
        
        if current_frame_screens:
            # Case 1: The map is completely empty. We must set the first screen we see as the Origin.
            if global_origin_id is None:
                first_screen = current_frame_screens[0]
                global_origin_id = first_screen["screen_id"]
                # The "Origin" Screen defines the absolute center (0,0,0) of the virtual room.
                global_transforms[global_origin_id] = {
                    "transform": np.eye(4, dtype=np.float32), 
                    "width": first_screen["width"],
                    "height": first_screen["height"]
                }
                print(f"[{global_origin_id}] locked as the Global Graph Origin.")
            
            # Localization: Where is the camera?
            # Find a screen in the current frame that is already mapped in our Graph.
            known_screen = None
            
            # Prioritize the global origin if it's visible to eliminate chaining drift
            for s in current_frame_screens:
                if s["screen_id"] == global_origin_id:
                    known_screen = s
                    break
                    
            # Fallback to any other known screen if the origin isn't visible
            if known_screen is None:
                for s in current_frame_screens:
                    if s["screen_id"] in global_transforms:
                        known_screen = s
                        break
                    
            if known_screen is not None:
                # Calculate Camera Position relative to the Origin
                T_cam_to_known_screen = create_transform_matrix(known_screen["rvec"], known_screen["tvec"])
                T_origin_to_known_screen = global_transforms[known_screen["screen_id"]]["transform"]
                
                # Equation: T_origin_to_screen = T_origin_to_cam * T_cam_to_screen
                # Therefore: T_origin_to_cam = T_origin_to_screen * (T_cam_to_screen)^(-1)
                raw_T_cam = T_origin_to_known_screen @ np.linalg.inv(T_cam_to_known_screen)
                
                # --- Exponential Moving Average (EMA) Smoothing ---
                if smoothed_T_cam is None:
                    smoothed_T_cam = raw_T_cam.copy()
                else:
                    alpha_t = 0.25 # Translation smoothing speed (1.0 = instant, 0.01 = glacial)
                    alpha_r = 0.15 # Rotation smoothing speed
                    
                    # Smooth Translation
                    smoothed_T_cam[:3, 3] = (alpha_t * raw_T_cam[:3, 3]) + ((1.0 - alpha_t) * smoothed_T_cam[:3, 3])
                    
                    # Smooth Rotation (Simple Matrix LERP with SVD Orthogonalization)
                    R_blend = (alpha_r * raw_T_cam[:3, :3]) + ((1.0 - alpha_r) * smoothed_T_cam[:3, :3])
                    U, _, Vt = np.linalg.svd(R_blend)
                    smoothed_T_cam[:3, :3] = U @ Vt
                
                T_origin_to_cam = smoothed_T_cam
                
                # Discovery & Continuous Updating: Map newly seen screens into the Graph, and update existing ones!
                for s in current_frame_screens:
                    c_id = s["screen_id"]
                    # Do not re-update the position of the screen we are currently using as our anchor!
                    # Doing so with a smoothed camera position creates a feedback loop that drags the screen!
                    if c_id != known_screen["screen_id"]:
                        T_cam_to_screen = create_transform_matrix(s["rvec"], s["tvec"])
                        T_origin_to_screen = T_origin_to_cam @ T_cam_to_screen
                        
                        if c_id not in global_transforms:
                            print(f"[{c_id}] mathematical position locked into the Global Graph!")
                            
                        # Continuously update the position of the screen relative to the known camera
                        global_transforms[c_id] = {
                            "transform": T_origin_to_screen,
                            "width": s["width"],
                            "height": s["height"]
                        }

                # Optional world anchors: visible, mappable into the same room space,
                # but intentionally excluded from the screen layout graph and broadcasts.
                for a in current_frame_anchors:
                    T_cam_to_anchor = create_transform_matrix(a["rvec"], a["tvec"])
                    T_origin_to_anchor = T_origin_to_cam @ T_cam_to_anchor
                    global_anchor_transforms[a["anchor_id"]] = {
                        "transform": T_origin_to_anchor,
                        "size": a["size"],
                    }

        # ---------------------------------------------------------
        # 3D ROOM LAYOUT VISUALIZER (INTERACTIVE 3D PERSPECTIVE)
        # ---------------------------------------------------------
        visible_ids = [s["screen_id"] for s in current_frame_screens]
        visible_anchor_ids = [a["anchor_id"] for a in current_frame_anchors]

        if camera_paused or cap is None:
            send_scan_status(
                "camera_paused",
                "Webcam capture is released. Press 'v' in the tracker window to reacquire it.",
                visible_screens=[],
                mapped_screens=sorted(int(sid) for sid in global_transforms.keys())
            )
        elif camera_matrix is not None:
            if not visible_ids:
                send_scan_status(
                    "waiting_for_markers",
                    "Waiting for the screen marker constellation to become visible.",
                    mapped_screens=sorted(int(sid) for sid in global_transforms.keys())
                )
            else:
                mapped_ids = sorted(int(sid) for sid in global_transforms.keys())
                state = "layout_ready" if mapped_ids else "scanning"
                message = (
                    "Layout solved and streaming."
                    if state == "layout_ready"
                    else "Markers detected. Solving screen poses and mapping the room."
                )
                send_scan_status(
                    state,
                    message,
                    visible_screens=visible_ids,
                    mapped_screens=mapped_ids
                )

            if global_transforms and visible_ids and time.time() - last_layout_send_time > 0.75:
                broadcast_layout()

        room_map = np.zeros((800, 800, 3), dtype=np.uint8)
        
        cx, cy = 400, 400
        pitch_rad = np.radians(view_pitch)
        yaw_rad = np.radians(view_yaw)
        
        Rx = np.array([
            [1, 0, 0],
            [0, np.cos(pitch_rad), -np.sin(pitch_rad)],
            [0, np.sin(pitch_rad), np.cos(pitch_rad)]
        ])
        Ry = np.array([
            [np.cos(yaw_rad), 0, np.sin(yaw_rad)],
            [0, 1, 0],
            [-np.sin(yaw_rad), 0, np.cos(yaw_rad)]
        ])
        R_view = Rx @ Ry
        T_view = np.array([view_pan_x, view_pan_y, view_dist])
        
        def project_3d(pt3d_global):
            pt_rotated = R_view @ pt3d_global[:3]
            pt_translated = pt_rotated + T_view
            z = pt_translated[2]
            if z <= 0.1: z = 0.1
            focal = 600.0
            px = int(cx + (pt_translated[0] * focal) / z)
            py = int(cy + (pt_translated[1] * focal) / z)
            return (px, py), z > 0.1

        def draw_line_3d(img, p1_global, p2_global, color, thickness):
            pt1, ok1 = project_3d(p1_global)
            pt2, ok2 = project_3d(p2_global)
            if ok1 and ok2:
                cv2.line(img, pt1, pt2, color, thickness)
                
        # Draw a faint ground grid
        for i in range(-100, 101, 20):
            draw_line_3d(room_map, np.array([i, 20, -100, 1]), np.array([i, 20, 100, 1]), (40, 40, 40), 1)
            draw_line_3d(room_map, np.array([-100, 20, i, 1]), np.array([100, 20, i, 1]), (40, 40, 40), 1)

        rendered_screen_centers.clear()
        for s_id, s_data in global_transforms.items():
            T = s_data["transform"]
            w2 = s_data["width"] / 2.0
            h2 = s_data["height"] / 2.0
            
            # The physical screen lies on its local X/Y plane
            tl_local = np.array([-w2, -h2, 0, 1])
            tr_local = np.array([ w2, -h2, 0, 1])
            bl_local = np.array([-w2,  h2, 0, 1])
            br_local = np.array([ w2,  h2, 0, 1])
            z_up_local = np.array([0, 0, -5, 1]) # Normal extending out
            
            tl_global = T @ tl_local
            tr_global = T @ tr_local
            bl_global = T @ bl_local
            br_global = T @ br_local
            z_up_global = T @ z_up_local
            center_global = T @ np.array([0,0,0,1])
            
            is_visible = s_id in visible_ids
            color = (0, 255, 0) if is_visible else (150, 150, 150)
            
            # Box
            draw_line_3d(room_map, tl_global, tr_global, color, 2)
            draw_line_3d(room_map, tr_global, br_global, color, 2)
            draw_line_3d(room_map, br_global, bl_global, color, 2)
            draw_line_3d(room_map, bl_global, tl_global, color, 2)
            
            # Diagonal
            draw_line_3d(room_map, tl_global, br_global, color, 1)
            
            # Normal tick
            draw_line_3d(room_map, center_global, z_up_global, (255, 0, 0), 2)
            
            # Draw ID Text
            pt_center, ok = project_3d(center_global)
            if ok:
                rendered_screen_centers.append((s_id, pt_center))
                cv2.circle(room_map, pt_center, 4, color, -1)
                cv2.putText(room_map, f"Screen {s_id}", (max(0, pt_center[0]-30), max(0, pt_center[1]-10)), 
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)

        for anchor_id, anchor_data in global_anchor_transforms.items():
            T = anchor_data["transform"]
            half = anchor_data["size"] / 2.0
            tl_local = np.array([-half, -half, 0, 1])
            tr_local = np.array([ half, -half, 0, 1])
            bl_local = np.array([-half,  half, 0, 1])
            br_local = np.array([ half,  half, 0, 1])
            normal_local = np.array([0, 0, -max(half, 2.0), 1])

            tl_global = T @ tl_local
            tr_global = T @ tr_local
            bl_global = T @ bl_local
            br_global = T @ br_local
            normal_global = T @ normal_local
            center_global = T @ np.array([0, 0, 0, 1])

            is_visible = anchor_id in visible_anchor_ids
            color = (0, 215, 255) if is_visible else (90, 120, 140)

            draw_line_3d(room_map, tl_global, tr_global, color, 2)
            draw_line_3d(room_map, tr_global, br_global, color, 2)
            draw_line_3d(room_map, br_global, bl_global, color, 2)
            draw_line_3d(room_map, bl_global, tl_global, color, 2)
            draw_line_3d(room_map, center_global, normal_global, (0, 140, 255), 2)

            pt_center, ok = project_3d(center_global)
            if ok:
                cv2.circle(room_map, pt_center, 4, color, -1)
                cv2.putText(
                    room_map,
                    f"Anchor {anchor_id}",
                    (max(0, pt_center[0] - 32), max(0, pt_center[1] - 10)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    color,
                    1,
                )

        # Draw Camera Frustum
        if T_origin_to_cam is not None:
            c_pos = T_origin_to_cam[:3, 3]
            c_global = np.array([c_pos[0], c_pos[1], c_pos[2], 1])
            
            pt_c, ok = project_3d(c_global)
            if ok:
                cv2.circle(room_map, pt_c, 6, (0, 0, 255), -1)
                cv2.putText(room_map, "Camera", (max(0, pt_c[0]+10), max(0, pt_c[1]+10)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1)
            
            z_forward = T_origin_to_cam @ np.array([0, 0, 20, 1])
            z_left = T_origin_to_cam @ np.array([-10, -10, 20, 1])
            z_right = T_origin_to_cam @ np.array([ 10, -10, 20, 1])
            z_bleft = T_origin_to_cam @ np.array([-10, 10, 20, 1])
            z_bright = T_origin_to_cam @ np.array([ 10, 10, 20, 1])
            
            c_color = (0, 0, 255)
            draw_line_3d(room_map, c_global, z_left, c_color, 1)
            draw_line_3d(room_map, c_global, z_right, c_color, 1)
            draw_line_3d(room_map, c_global, z_bleft, c_color, 1)
            draw_line_3d(room_map, c_global, z_bright, c_color, 1)
            
            draw_line_3d(room_map, z_left, z_right, c_color, 1)
            draw_line_3d(room_map, z_right, z_bright, c_color, 1)
            draw_line_3d(room_map, z_bright, z_bleft, c_color, 1)
            draw_line_3d(room_map, z_bleft, z_left, c_color, 1)

        # Output the live webcam feeds
        if active_capture_width > 0 and active_capture_height > 0:
            cv2.putText(
                frame,
                f"Capture: {active_capture_width}x{active_capture_height} (idx {active_camera_index})",
                (30, frame.shape[0] - 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (255, 255, 255),
                2,
                cv2.LINE_AA,
            )
        cv2.imshow(TRACKER_WINDOW_NAME, frame)
        cv2.imshow(ROOM_MAP_WINDOW_NAME, room_map)
        
        key = cv2.waitKeyEx(1)
        if key == ord('c'):
            print(">>> COMPILING AND BROADCASTING LAYOUT MAP <<<")
            broadcast_layout()
            print("Successfully sent to WebSocket Router!")
        elif key == CAMERA_TOGGLE_KEY:
            set_camera_paused(not camera_paused)
        elif key in (CAMERA_KEY_LEFT, CAMERA_KEY_DOWN, CAMERA_KEY_LEFT_EX, CAMERA_KEY_DOWN_EX, ord('a'), ord('s')):
            print(">>> Switching camera index down. <<<")
            cap = switch_camera_index(-1)
        elif key in (CAMERA_KEY_RIGHT, CAMERA_KEY_UP, CAMERA_KEY_RIGHT_EX, CAMERA_KEY_UP_EX, ord('d'), ord('w')):
            print(">>> Switching camera index up. <<<")
            cap = switch_camera_index(1)

        # Press 'q' to quit
        if key == ord('q'):
            break
        elif key == ord('r') or key == ord('g'):
            reset_spatial_map()
        elif key == ord('x'):
            print(">>> CLEARING SENSOR CALIBRATION <<<")
            camera_matrix = None
            dist_coeffs = None
            stored_camera_matrix = None
            stored_dist_coeffs = None
            stored_calibration_size = None
            all_charuco_corners.clear()
            all_charuco_ids.clear()
            accepted_sigs.clear()
            if os.path.exists("camera_calibration.json"):
                os.remove("camera_calibration.json")
            print("Ready to gather new ChArUco frames!")
            
    release_camera()
    bridge_sock.close()
    command_sock.close()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
