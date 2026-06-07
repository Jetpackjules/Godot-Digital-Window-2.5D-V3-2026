import argparse
import os
import sys
import time

print("oakd_v3_camera_viewer.py imported", flush=True)

import cv2
import depthai as dai


SOCKETS = {
    "auto": None,
    "rgb": dai.CameraBoardSocket.CAM_A,
    "left": dai.CameraBoardSocket.CAM_B,
    "right": dai.CameraBoardSocket.CAM_C,
}
LOG_PATH = os.path.join(os.path.dirname(__file__), "oakd_v3_camera_viewer.log")


def log(message):
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), message)
    print(line, flush=True)
    with open(LOG_PATH, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def parse_args():
    parser = argparse.ArgumentParser(description="Small DepthAI v3 Camera-node viewer.")
    parser.add_argument("--socket", choices=sorted(SOCKETS), default="auto")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument("--fps", type=float, default=0.0, help="0 lets DepthAI choose the default FPS.")
    parser.add_argument("--duration", type=float, default=0.0, help="0 runs until q/Esc.")
    parser.add_argument("--first-frame-timeout", type=float, default=10.0)
    parser.add_argument("--list-devices", action="store_true", help="Call getAllAvailableDevices before opening. Can hang if device is in a bad state.")
    parser.add_argument("--hard-exit", action=argparse.BooleanOptionalAction, default=True, help="Bypass current DepthAI shutdown crash.")
    return parser.parse_args()


def draw_text(frame, text, y):
    cv2.putText(frame, text, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4, cv2.LINE_AA)
    cv2.putText(frame, text, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 1, cv2.LINE_AA)


def main():
    sys.stdout.reconfigure(line_buffering=True)
    args = parse_args()
    window_name = "OAK-D DepthAI v3 Camera Viewer"

    with open(LOG_PATH, "w", encoding="utf-8") as handle:
        handle.write("")

    log("DepthAI v3 camera viewer starting")
    log("log path: %s" % LOG_PATH)
    log("python: %s" % sys.executable)
    log("depthai version: %s" % dai.__version__)
    log("opencv version: %s" % cv2.__version__)
    log("args: %s" % vars(args))
    if args.list_devices:
        log("listing devices")
        devices = dai.Device.getAllAvailableDevices()
        log("available devices: %d" % len(devices))
        for index, device_info in enumerate(devices):
            log("device %d: %s" % (index, device_info))
    else:
        log("skipping device list; opening default device directly")

    log("constructing dai.Pipeline(); if it hangs here, DepthAI is waiting on device boot/open")
    try:
        pipeline_context = dai.Pipeline()
    except RuntimeError as error:
        log("ERROR: failed while constructing dai.Pipeline(): %s" % error)
        log("Likely causes: OAK-D is mid-boot/wedged, another process owns it, USB link dropped, or it needs unplug/replug.")
        raise

    log("dai.Pipeline() constructed")
    with pipeline_context as pipeline:
        log("pipeline created")
        camera_node = pipeline.create(dai.node.Camera)
        log("Camera node created")
        if SOCKETS[args.socket] is None:
            log("building default camera")
            camera = camera_node.build()
        else:
            log("building camera socket %s -> %s" % (args.socket, SOCKETS[args.socket]))
            camera = camera_node.build(SOCKETS[args.socket])
        log("camera built")

        if args.fps > 0:
            log("requesting output size=%dx%d fps=%.1f" % (args.width, args.height, args.fps))
            output = camera.requestOutput((args.width, args.height), fps=args.fps)
        else:
            log("requesting output size=%dx%d fps=default" % (args.width, args.height))
            output = camera.requestOutput((args.width, args.height))
        log("output requested")
        queue = output.createOutputQueue(maxSize=4, blocking=False)
        log("output queue created")

        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, args.width, args.height)
        cv2.moveWindow(window_name, 80, 80)
        log("OpenCV window created")

        log("starting pipeline")
        pipeline.start()
        log("pipeline started")
        frames_since_fps = 0
        total_frames = 0
        fps = 0.0
        last_fps = time.perf_counter()
        start_time = last_fps
        first_frame_deadline = last_fps + args.first_frame_timeout
        got_first_frame = False
        log("Running DepthAI v3 viewer. Press q/Esc in the image window to quit.")

        while pipeline.isRunning():
            if args.duration > 0.0 and time.perf_counter() - start_time >= args.duration:
                log("duration reached, closing viewer")
                break
            message = queue.tryGet()
            if message is None:
                if not got_first_frame and time.perf_counter() > first_frame_deadline:
                    log("ERROR: timed out waiting for first frame after %.1f seconds" % args.first_frame_timeout)
                    break
                cv2.waitKey(1)
                time.sleep(0.005)
                continue
            if not got_first_frame:
                log("first frame received")
                got_first_frame = True
            frame = message.getCvFrame()
            frames_since_fps += 1
            total_frames += 1

            now = time.perf_counter()
            if now - last_fps >= 0.5:
                fps = frames_since_fps / (now - last_fps)
                frames_since_fps = 0
                last_fps = now

            draw_text(frame, "DepthAI v3 Camera node | socket %s" % args.socket, 28)
            draw_text(frame, "FPS %.1f | requested %s" % (fps, "default" if args.fps <= 0 else "%.1f" % args.fps), 56)
            draw_text(frame, "q/Esc quit", 84)
            cv2.imshow(window_name, frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                log("quit key pressed")
                break

        elapsed = max(0.001, time.perf_counter() - start_time)
        log("DepthAI v3 viewer closed. total_frames=%d avg_fps=%.1f last_fps=%.1f" % (total_frames, total_frames / elapsed, fps))
        if args.hard_exit:
            log("hard-exit enabled; exiting without normal DepthAI shutdown")
            os._exit(0)

    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
