import argparse
import os
import time

import cv2
import depthai as dai


SOCKETS = {
    "rgb": dai.CameraBoardSocket.CAM_A,
    "left": dai.CameraBoardSocket.CAM_B,
    "right": dai.CameraBoardSocket.CAM_C,
}


def parse_args():
    parser = argparse.ArgumentParser(description="Benchmark DepthAI v3 Camera node output FPS.")
    parser.add_argument("--socket", choices=sorted(SOCKETS), default="rgb")
    parser.add_argument("--fps", type=float, default=90.0)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--warmup", type=float, default=1.0)
    parser.add_argument("--show", action="store_true", help="Display frames. This lowers measured FPS.")
    parser.add_argument("--hard-exit", action="store_true", help="Bypass DepthAI shutdown crash after printing results.")
    return parser.parse_args()


def main():
    args = parse_args()

    with dai.Pipeline() as pipeline:
        cam = pipeline.create(dai.node.Camera).build(SOCKETS[args.socket])
        output_type = dai.ImgFrame.Type.BGR888p if args.socket == "rgb" else dai.ImgFrame.Type.GRAY8
        queue = cam.requestOutput(
            size=(args.width, args.height),
            type=output_type,
            resizeMode=dai.ImgResizeMode.CROP,
            fps=args.fps,
        ).createOutputQueue(maxSize=8, blocking=False)

        pipeline.start()
        start = time.perf_counter()
        warmup_end = start + args.warmup
        end = start + args.duration
        frames = 0
        last_frame = None

        while pipeline.isRunning() and time.perf_counter() < end:
            msg = queue.tryGet()
            if msg is None:
                time.sleep(0.001)
                continue

            now = time.perf_counter()
            if now >= warmup_end:
                frames += 1

            if args.show:
                last_frame = msg.getCvFrame()
                cv2.imshow("OAK-D Camera node benchmark", last_frame)
                if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                    break

        measured = max(0.001, time.perf_counter() - warmup_end)
        print(
            "CameraNode socket=%s requested=%.1f size=%dx%d show=%s -> %.1f FPS"
            % (args.socket, args.fps, args.width, args.height, args.show, frames / measured)
            ,
            flush=True,
        )
        if args.hard_exit:
            os._exit(0)
        pipeline.stop()
        pipeline.wait()

    if args.show:
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
