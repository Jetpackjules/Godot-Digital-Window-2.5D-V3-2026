import argparse
import os
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from camera_tracker import (  # noqa: E402
    DEFAULT_FAST_FOUNDATION_ONNX,
    DEFAULT_FAST_FOUNDATION_TRT_ENGINE,
    ensure_fast_foundation_onnx_dll_paths,
)


def main():
    parser = argparse.ArgumentParser(
        description="Build a native TensorRT .engine for the Fast-FoundationStereo single ONNX model."
    )
    parser.add_argument("--onnx", default=DEFAULT_FAST_FOUNDATION_ONNX, help="Input single ONNX model path.")
    parser.add_argument("--engine", default=DEFAULT_FAST_FOUNDATION_TRT_ENGINE, help="Output .engine path.")
    parser.add_argument("--workspace-gb", type=float, default=16.0, help="TensorRT workspace memory limit in GB.")
    parser.add_argument("--optimization-level", type=int, default=5, help="TensorRT builder optimization level.")
    parser.add_argument("--no-fp16", action="store_true", help="Disable FP16 engine build.")
    parser.add_argument("--force", action="store_true", help="Overwrite an existing engine.")
    args = parser.parse_args()

    onnx_path = os.path.abspath(args.onnx)
    engine_path = os.path.abspath(args.engine)
    if not os.path.isfile(onnx_path):
        raise FileNotFoundError(f"ONNX model not found: {onnx_path}")
    if os.path.exists(engine_path) and not args.force:
        print(f"Engine already exists: {engine_path}")
        print("Use --force to rebuild it.")
        return 0

    dll_dirs = ensure_fast_foundation_onnx_dll_paths()
    import tensorrt as trt

    logger = trt.Logger(trt.Logger.WARNING)
    explicit_batch = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    builder = trt.Builder(logger)
    network = builder.create_network(explicit_batch)
    parser = trt.OnnxParser(network, logger)

    print(f"TensorRT: {trt.__version__}")
    print(f"DLL dirs added: {len(dll_dirs)}")
    print(f"ONNX:   {onnx_path}")
    print(f"Engine: {engine_path}")
    print("Parsing ONNX...")
    with open(onnx_path, "rb") as onnx_file:
        parsed = parser.parse(onnx_file.read())
    if not parsed:
        for i in range(parser.num_errors):
            print(parser.get_error(i))
        raise RuntimeError(f"TensorRT failed to parse ONNX with {parser.num_errors} errors.")

    print(f"Inputs: {network.num_inputs}, outputs: {network.num_outputs}, layers: {network.num_layers}")
    for i in range(network.num_inputs):
        tensor = network.get_input(i)
        print(f"  input[{i}] {tensor.name} shape={tuple(tensor.shape)} dtype={tensor.dtype}")
    for i in range(network.num_outputs):
        tensor = network.get_output(i)
        print(f"  output[{i}] {tensor.name} shape={tuple(tensor.shape)} dtype={tensor.dtype}")

    config = builder.create_builder_config()
    workspace_bytes = int(max(1.0, args.workspace_gb) * (1024 ** 3))
    config.set_memory_pool_limit(trt.MemoryPoolType.WORKSPACE, workspace_bytes)
    try:
        config.builder_optimization_level = int(max(0, min(5, args.optimization_level)))
    except Exception:
        pass
    if not args.no_fp16 and builder.platform_has_fast_fp16:
        config.set_flag(trt.BuilderFlag.FP16)
        print("FP16: enabled")
    else:
        print("FP16: disabled")

    os.makedirs(os.path.dirname(engine_path), exist_ok=True)
    print("Building TensorRT engine. This can take several minutes the first time...")
    start = time.perf_counter()
    serialized_engine = builder.build_serialized_network(network, config)
    elapsed = time.perf_counter() - start
    if serialized_engine is None:
        raise RuntimeError("TensorRT builder returned no engine.")

    tmp_path = engine_path + ".tmp"
    with open(tmp_path, "wb") as engine_file:
        engine_file.write(serialized_engine)
    os.replace(tmp_path, engine_path)
    print(f"Done in {elapsed:.1f}s")
    print(f"Wrote {os.path.getsize(engine_path) / (1024 * 1024):.1f} MB: {engine_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
