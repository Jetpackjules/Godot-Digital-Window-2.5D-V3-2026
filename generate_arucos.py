import cv2
import cv2.aruco as aruco

SCREEN_MARKER_IDS = list(range(6))
WORLD_ANCHOR_MARKER_IDS = [45, 46, 47, 48, 49]

def generate_markers(marker_ids, size=800, prefix="aruco_marker", add_border=True, border_ratio=0.125):
    dictionary = aruco.getPredefinedDictionary(aruco.DICT_4X4_50)
    
    for marker_id in marker_ids:
        # Generate the raw marker
        marker_img = aruco.generateImageMarker(dictionary, marker_id, size)
        
        if add_border:
            # Add a white quiet zone so OpenCV can find markers even near dark backing.
            border_size = max(1, int(round(size * border_ratio)))
            output_img = cv2.copyMakeBorder(
                marker_img, 
                top=border_size, 
                bottom=border_size, 
                left=border_size, 
                right=border_size, 
                borderType=cv2.BORDER_CONSTANT, 
                value=[255, 255, 255]
            )
        else:
            output_img = marker_img
        
        filename = f"{prefix}_{marker_id}.png"
        cv2.imwrite(filename, output_img)
        print(f"Generated {filename}")

if __name__ == "__main__":
    generate_markers(SCREEN_MARKER_IDS, prefix="aruco_marker", add_border=True)
    generate_markers(WORLD_ANCHOR_MARKER_IDS, size=1800, prefix="world_anchor_marker", add_border=False)
    generate_markers(WORLD_ANCHOR_MARKER_IDS, size=1800, prefix="world_anchor_marker_print", add_border=True)
