import cv2
import cv2.aruco as aruco
import numpy as np
import os

def generate_markers(num_markers=6, size=800, border_bits=1):
    dictionary = aruco.getPredefinedDictionary(aruco.DICT_4X4_50)
    
    for i in range(num_markers):
        # Generate the raw marker
        marker_img = aruco.generateImageMarker(dictionary, i, size)
        
        # Add a white border (ArUco needs quiet zone, usually exactly 1 bit wide, but we'll add a bit more for safety)
        border_size = size // 8
        bordered_img = cv2.copyMakeBorder(
            marker_img, 
            top=border_size, 
            bottom=border_size, 
            left=border_size, 
            right=border_size, 
            borderType=cv2.BORDER_CONSTANT, 
            value=[255, 255, 255]
        )
        
        filename = f"aruco_marker_{i}.png"
        cv2.imwrite(filename, bordered_img)
        print(f"Generated {filename}")

if __name__ == "__main__":
    generate_markers()
