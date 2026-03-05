import cv2
import cv2.aruco as aruco
import numpy as np
import json
import os

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
    parameters = aruco.DetectorParameters()
    detector = aruco.ArucoDetector(aruco_dict, parameters)
    
    # Constellation Definitions
    # TL: 40, TR: 41, BL: 42, BR: 43
    # Center Device IDs: 0-5
    
    # --- SLAM SPATIAL GRAPH MEMORY ---
    global_origin_id = None
    # Dictionary mapping screen_id (int) -> {"transform": 4x4 ndarray, "width": float, "height": float}
    global_transforms = {}

    view_pitch = 45.0
    view_yaw = -45.0
    view_dist = 150.0
    mouse_is_down = False
    last_mouse_x = 0
    last_mouse_y = 0

    def mouse_callback(event, x, y, flags, param):
        nonlocal view_pitch, view_yaw, mouse_is_down, last_mouse_x, last_mouse_y
        if event == cv2.EVENT_LBUTTONDOWN:
            mouse_is_down = True
            last_mouse_x = x
            last_mouse_y = y
        elif event == cv2.EVENT_LBUTTONUP:
            mouse_is_down = False
        elif event == cv2.EVENT_MOUSEMOVE:
            if mouse_is_down:
                dx = x - last_mouse_x
                dy = y - last_mouse_y
                view_yaw -= dx * 0.5
                view_pitch += dy * 0.5
                view_pitch = max(-89.0, min(89.0, view_pitch))
                last_mouse_x = x
                last_mouse_y = y

    cv2.namedWindow("3D Room Spatial Map")
    cv2.setMouseCallback("3D Room Spatial Map", mouse_callback)

    while True:
        ret, frame = cap.read()
        if not ret:
            break
            
        # ArUco detection requires grayscale
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        corners, ids, rejected = detector.detectMarkers(gray)
        
        current_frame_screens = []
        
        if ids is not None:
            # 1. Outline every individual marker found
            aruco.drawDetectedMarkers(frame, corners, ids)
            
            ids_list = ids.flatten().tolist()
            
            # 2. Extract our defined layout markers
            center_ids = [i for i, id_val in enumerate(ids_list) if id_val in range(6)]
            
            tl_ids = [i for i, id_val in enumerate(ids_list) if id_val == 40]
            tr_ids = [i for i, id_val in enumerate(ids_list) if id_val == 41]
            bl_ids = [i for i, id_val in enumerate(ids_list) if id_val == 42]
            br_ids = [i for i, id_val in enumerate(ids_list) if id_val == 43]
            
            # 3. Cluster corners to their nearest center ID
            # This allows multiple physical monitors to be tracked simultaneously!
            for c_idx in center_ids:
                c_id = ids_list[c_idx]
                
                # Get the absolute pixel center of the central ArUco marker
                c_center = np.mean(corners[c_idx][0], axis=0)
                # Caluclate the pixel perimeter of the center marker
                c_perimeter = cv2.arcLength(corners[c_idx][0], True)
                
                # Helper function to find the *outermost geometric corner* of a specific marker
                def get_outermost_point(target_idx_list):
                    if not target_idx_list: return None
                    best_pt = None
                    best_marker_center = None
                    min_dist_to_screen_center = float('inf')
                    marker_corners = None
                    
                    # 1. Filter out candidate markers that belong to other screens!
                    valid_idx_list = []
                    for idx in target_idx_list:
                        pt = np.mean(corners[idx][0], axis=0)
                        
                        # Size Check: Corner markers should be physically identical in size to the center marker
                        pt_perimeter = cv2.arcLength(corners[idx][0], True)
                        if pt_perimeter > c_perimeter * 2.5 or pt_perimeter < c_perimeter * 0.4:
                            continue # This marker is way too big/small to belong to this screen!
                            
                        # Distance Check: Is this corner CLOSER to some other Center ID?
                        closest_c_dist = float('inf')
                        closest_c_idx = None
                        for other_c_idx in center_ids:
                            other_c = np.mean(corners[other_c_idx][0], axis=0)
                            d = np.linalg.norm(pt - other_c)
                            if d < closest_c_dist:
                                closest_c_dist = d
                                closest_c_idx = other_c_idx
                                
                        if closest_c_idx == c_idx:
                            valid_idx_list.append(idx) # This corner voted for us!
                            
                    # 2. Find the marker closest to our screen center out of the valid ones
                    for idx in valid_idx_list:
                        mc = np.mean(corners[idx][0], axis=0)
                        dist = np.linalg.norm(c_center - mc)
                        if dist < min_dist_to_screen_center:
                            min_dist_to_screen_center = dist
                            best_marker_center = mc
                            marker_corners = corners[idx][0]
                            
                    if marker_corners is not None:
                        # 3. From the 4 corners of *that* ArUco, find the one FURTHEST from the screen center
                        # (This guarantees we grab the very outer tip of the ArUco square!)
                        max_dist_to_corner = 0
                        for pt in marker_corners:
                            dist = np.linalg.norm(c_center - pt)
                            if dist > max_dist_to_corner:
                                max_dist_to_corner = dist
                                best_pt = pt
                                
                        # 4. Mathematically project vectors outwards to counteract Godot's 15% padding!
                        marker_width = np.linalg.norm(marker_corners[0] - marker_corners[1])
                        godot_pad_pixels = marker_width * 0.15
                        
                        # Create a normalized vector pointing from the screen center to our outer point
                        direction_vector = best_pt - c_center
                        direction_vector = direction_vector / np.linalg.norm(direction_vector)
                        
                        # Push the point outward along that trajectory
                        expanded_pt = best_pt + (direction_vector * godot_pad_pixels)
                        return expanded_pt
                        
                    return None
                
                # Attempt to find the true expanded hardware corners
                tl = get_outermost_point(tl_ids)
                tr = get_outermost_point(tr_ids)
                bl = get_outermost_point(bl_ids)
                br = get_outermost_point(br_ids)
                
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
                        
                        # Fake Intrinsics Matrix
                        focal_length = frame.shape[1]
                        center_pt = (frame.shape[1] / 2.0, frame.shape[0] / 2.0)
                        camera_matrix = np.array([
                            [focal_length, 0, center_pt[0]],
                            [0, focal_length, center_pt[1]],
                            [0, 0, 1]
                        ], dtype=np.float32)
                        dist_coeffs = np.zeros((4, 1), dtype=np.float32)
                        
                        image_points = np.array([tl, tr, br, bl], dtype=np.float32)
                        
                        # Project 2D pixels into Physical Space!
                        success, rvec, tvec = cv2.solvePnP(object_points, image_points, camera_matrix, dist_coeffs)
                        
                        if success:
                            # Draw full 3D coordinate axes relative to the unique screen size!
                            # Shrunk axis length so OpenCV stops warning about lines extending off-screen!
                            axis_length = float(width_inches * 0.2)
                            cv2.drawFrameAxes(frame, camera_matrix, dist_coeffs, rvec, tvec, axis_length, 2)
                            
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
                T_origin_to_cam = T_origin_to_known_screen @ np.linalg.inv(T_cam_to_known_screen)
                
                # Discovery: Map newly seen screens into the Graph!
                for s in current_frame_screens:
                    if s["screen_id"] not in global_transforms:
                        T_cam_to_new_screen = create_transform_matrix(s["rvec"], s["tvec"])
                        # Equation: T_origin_to_new = T_origin_to_cam * T_cam_to_new
                        T_origin_to_new_screen = T_origin_to_cam @ T_cam_to_new_screen
                        
                        global_transforms[s["screen_id"]] = {
                            "transform": T_origin_to_new_screen,
                            "width": s["width"],
                            "height": s["height"]
                        }
                        print(f"[{s['screen_id']}] mathematical position locked into the Global Graph!")

        # ---------------------------------------------------------
        # 3D ROOM LAYOUT VISUALIZER (INTERACTIVE 3D PERSPECTIVE)
        # ---------------------------------------------------------
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
        T_view = np.array([0, 0, view_dist])
        
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

        visible_ids = [s["screen_id"] for s in current_frame_screens]
        
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
        
        # Press 'q' to quit
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
            
    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
