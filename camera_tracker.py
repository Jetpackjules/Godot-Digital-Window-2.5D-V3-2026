import cv2
import cv2.aruco as aruco
import numpy as np
import json
import os
import socket
import time

TRACKER_CONTROL_PORT = 4244

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

def main():
    print("Starting ArUco Constellation Tracker...")
    print("Press 'q' in the camera window to quit.\n")
    
    # Connect to default webcam
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam.")
        return

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
    if os.path.exists("camera_calibration.json"):
        try:
            with open("camera_calibration.json", "r") as f:
                calib = json.load(f)
                camera_matrix = np.array(calib["camera_matrix"], dtype=np.float32)
                dist_coeffs = np.array(calib["dist_coeffs"], dtype=np.float32)
            print(">>> Successfully loaded camera_calibration.json! Perfect Intrinsics applied! <<<")
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
    screen_trackers = {} # c_id -> {"rvec": rvec, "tvec": tvec}
    
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
        layout_payload = {
            "type": "layout_map",
            "origin_screen": int(global_origin_id) if global_origin_id is not None else None,
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
        global_origin_id = None
        rendered_screen_centers.clear()
        screen_trackers.clear()
        smoothed_T_cam = None

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

    cv2.namedWindow("Multi-Monitor ArUco Constellation Tracker", cv2.WINDOW_NORMAL)
    cv2.namedWindow("3D Room Spatial Map", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("3D Room Spatial Map", 1200, 960)
    cv2.setMouseCallback("3D Room Spatial Map", mouse_callback)

    while True:
        try:
            cmd_data, _ = command_sock.recvfrom(65535)
            cmd_json = json.loads(cmd_data.decode("utf-8"))
            if cmd_json.get("type") == "reset_spatial_map":
                reset_spatial_map()
        except BlockingIOError:
            pass
        except Exception as exc:
            print(f"[tracker] Failed to process control command: {exc}")

        ret, frame = cap.read()
        if not ret:
            break
            
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
                            cv2.imshow("Multi-Monitor ArUco Constellation Tracker", frame)
                            cv2.waitKey(1) # Force a tiny frame update so they see the text before it hangs!
                            
                            ret_val, temp_cam, temp_dist, _, _ = aruco.calibrateCameraCharuco(all_charuco_corners, all_charuco_ids, charuco_board, gray.shape[::-1], None, None)
                            camera_matrix = temp_cam
                            dist_coeffs = temp_dist
                            
                            print(f">>> CALIBRATION COMPLETE! RMS Error: {ret_val} <<<")
                            with open("camera_calibration.json", "w") as f:
                                json.dump({
                                    "camera_matrix": camera_matrix.tolist(),
                                    "dist_coeffs": dist_coeffs.tolist()
                                }, f, indent=4)
                                
                            print("Saved to camera_calibration.json! Perfect Intrinsics locked in!")
        else:
            # We have perfect intrinsics! Immediately undistort the raw webcam feed
            # so the user can visually see the math flattening their curved room!
            frame = cv2.undistort(frame, camera_matrix, dist_coeffs)
            
            # Now run ArUco detection on the mathematically perfect image!
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            corners, ids, rejected = detector.detectMarkers(gray)
            
        current_frame_screens = []
        
        if ids is not None:
            # 0. Black out the markers to prevent infinite loops from the webcam seeing the screen!
            for i in range(len(ids)):
                cv2.fillPoly(frame, [np.int32(corners[i])], (0, 0, 0))
                
            # 1. Outline every individual marker found
            aruco.drawDetectedMarkers(frame, corners, ids)
            
            ids_list = ids.flatten().tolist()
            
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
                
                # Helper function to extract exact ArUco corners structurally
                def get_corner_point(target_idx_list, corner_index):
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
                        marker_corners = corners[best_idx][0]
                        
                        # GRAB THE STRUCTURALLY INVARIANT CORNER BY INDEX, ZERO JITTER!
                        best_pt = marker_corners[corner_index]
                                
                        marker_width = np.linalg.norm(marker_corners[0] - marker_corners[1])
                        godot_pad_pixels = marker_width * 0.15
                        
                        direction_vector = best_pt - c_center
                        direction_vector = direction_vector / np.linalg.norm(direction_vector)
                        
                        expanded_pt = best_pt + (direction_vector * godot_pad_pixels)
                        return expanded_pt
                        
                    return None
                
                # Fetch structurally invariant indices! 0=TL, 1=TR, 2=BR, 3=BL
                tl = get_corner_point(tl_ids, 0)
                tr = get_corner_point(tr_ids, 1)
                bl = get_corner_point(bl_ids, 3) # Bottom Left is index 3
                br = get_corner_point(br_ids, 2) # Bottom Right is index 2
                
                # If we successfully locked onto all 4 corners + center...
                if tl is not None and tr is not None and br is not None and bl is not None:
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
                                
                    # ---------------------------------------------------------
                    # 3D SPATIAL PROJECTION (DEVICE-SPECIFIC SCALE!)
                    # ---------------------------------------------------------
                    configs = load_screen_configs()
                    str_id = str(c_id)
                    
                    if str_id in configs:
                        width_inches = configs[str_id].get("width", 20.9)
                        height_inches = configs[str_id].get("height", 11.7)
                        
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

        # ---------------------------------------------------------
        # 3D ROOM LAYOUT VISUALIZER (INTERACTIVE 3D PERSPECTIVE)
        # ---------------------------------------------------------
        visible_ids = [s["screen_id"] for s in current_frame_screens]

        if camera_matrix is not None:
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
        cv2.imshow("Multi-Monitor ArUco Constellation Tracker", frame)
        cv2.imshow("3D Room Spatial Map", room_map)
        
        key = cv2.waitKey(1) & 0xFF
        if key == ord('c'):
            print(">>> COMPILING AND BROADCASTING LAYOUT MAP <<<")
            broadcast_layout()
            print("Successfully sent to WebSocket Router!")

        # Press 'q' to quit
        if key == ord('q'):
            break
        elif key == ord('r') or key == ord('g'):
            reset_spatial_map()
        elif key == ord('x'):
            print(">>> CLEARING SENSOR CALIBRATION <<<")
            camera_matrix = None
            dist_coeffs = None
            all_charuco_corners.clear()
            all_charuco_ids.clear()
            accepted_sigs.clear()
            if os.path.exists("camera_calibration.json"):
                os.remove("camera_calibration.json")
            print("Ready to gather new ChArUco frames!")
            
    cap.release()
    bridge_sock.close()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
