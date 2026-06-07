import argparse
import os
import time

import cv2
import depthai as dai


def parse_args():
    parser = argparse.ArgumentParser(description="Minimal DepthAI v3 Camera node smoke test.")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument("--fps", type=float, default=0.0, help="0 means let DepthAI choose.")
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--show", action="store_true")
    parser.add_argument("--hard-exit", action="store_true", help="Bypass DepthAI shutdown crash after printing results.")
    return parser.parse_args()


def main():
    args = parse_args()
    with dai.Pipeline() as pipeline:
        cam = pipeline.create(dai.node.Camera).build()
        if args.fps > 0:
            queue = cam.requestOutput((args.width, args.height), fps=args.fps).createOutputQueue()
        else:
            queue = cam.requestOutput((args.width, args.height)).createOutputQueue()

        pipeline.start()
        start = time.perf_counter()
        count = 0
        while pipeline.isRunning() and time.perf_counter() - start < args.duration:
            frame = queue.get()
            count += 1
            if args.show:
                cv2.imshow("OAK-D Camera node smoke", frame.getCvFrame())
                if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                    break

        elapsed = max(0.001, time.perf_counter() - start)
        print("Camera node smoke OK | %.1f FPS | %d frames" % (count / elapsed, count), flush=True)
        if args.hard_exit:
            os._exit(0)

    if args.show:
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
