import pathlib
import struct

import numpy as np


SOURCE_DIR = pathlib.Path(__file__).resolve().parents[2] / "stereo 4" / "stereo 4"
OUTPUT_PATH = pathlib.Path(__file__).resolve().parent / "point_cloud_sequence.bin"
MESH_OUTPUT_PATH = pathlib.Path(__file__).resolve().parent / "point_cloud_mesh_sequence.bin"
TARGET_POINTS_PER_FRAME = 90000
MESH_GRID_STEP = 4
MAX_TRIANGLE_EDGE_M = 0.08
MAGIC = b"PCSEQ01\n"
MESH_MAGIC = b"PCMSH01\n"


def read_open3d_ply(path: pathlib.Path) -> np.ndarray:
    with path.open("rb") as handle:
        vertex_count = None
        while True:
            line = handle.readline()
            if not line:
                raise ValueError(f"{path} ended before PLY header completed")
            if line.startswith(b"element vertex"):
                vertex_count = int(line.split()[-1])
            if line.strip() == b"end_header":
                break

        if vertex_count is None:
            raise ValueError(f"{path} does not declare a vertex count")

        dtype = np.dtype(
            [
                ("x", "<f8"),
                ("y", "<f8"),
                ("z", "<f8"),
                ("r", "u1"),
                ("g", "u1"),
                ("b", "u1"),
            ]
        )
        return np.frombuffer(handle.read(), dtype=dtype, count=vertex_count)


def converted_positions(vertices: np.ndarray) -> np.ndarray:
    # Match the lab-provided preview script: Open3D x/y/z -> Godot-ish x/up/depth.
    return np.column_stack(
        [
            vertices["x"].astype(np.float32),
            vertices["z"].astype(np.float32),
            -vertices["y"].astype(np.float32),
        ]
    )


def main() -> None:
    source_files = sorted(SOURCE_DIR.glob("*_cloud.ply"))
    if not source_files:
        raise FileNotFoundError(f"No *_cloud.ply files found in {SOURCE_DIR}")

    frames = []
    all_positions = []
    rng = np.random.default_rng(2500)

    for path in source_files:
        vertices = read_open3d_ply(path)
        positions = converted_positions(vertices)
        colors = np.column_stack([vertices["r"], vertices["g"], vertices["b"]]).astype(np.uint8)

        if len(vertices) > TARGET_POINTS_PER_FRAME:
            indices = rng.choice(len(vertices), TARGET_POINTS_PER_FRAME, replace=False)
            indices.sort()
            positions = positions[indices]
            colors = colors[indices]

        frames.append((positions, colors))
        all_positions.append(positions)

    center = np.vstack(all_positions).mean(axis=0).astype(np.float32)

    with OUTPUT_PATH.open("wb") as handle:
        handle.write(MAGIC)
        handle.write(struct.pack("<II", len(frames), TARGET_POINTS_PER_FRAME))
        handle.write(struct.pack("<fff", *center.tolist()))
        for positions, colors in frames:
            if len(positions) != TARGET_POINTS_PER_FRAME:
                raise ValueError("All frames must share one fixed point count")
            positions = (positions - center).astype("<f4")
            for point, color in zip(positions, colors):
                handle.write(struct.pack("<fffBBBB", point[0], point[1], point[2], color[0], color[1], color[2], 255))

    print(f"Wrote {OUTPUT_PATH}")
    print(f"Frames: {len(frames)}")
    print(f"Points per frame: {TARGET_POINTS_PER_FRAME}")
    print(f"Center: {center.tolist()}")
    write_mesh_sequence(source_files, center)


def write_mesh_sequence(source_files: list[pathlib.Path], center: np.ndarray) -> None:
    with MESH_OUTPUT_PATH.open("wb") as handle:
        handle.write(MESH_MAGIC)
        handle.write(struct.pack("<Ifff", len(source_files), *center.tolist()))

        for path in source_files:
            frame_id = path.name.split("_", 1)[0]
            depth = np.load(SOURCE_DIR / f"{frame_id}_depth_m.npy")
            vertices = read_open3d_ply(path)
            positions = converted_positions(vertices)
            colors = np.column_stack([vertices["r"], vertices["g"], vertices["b"]]).astype(np.uint8)

            valid_pixels = depth > 0.0
            if int(valid_pixels.sum()) != len(vertices):
                raise ValueError(f"{path.name}: valid depth count does not match PLY vertices")

            full_index = np.full(depth.shape, -1, dtype=np.int32)
            full_index[valid_pixels] = np.arange(len(vertices), dtype=np.int32)

            sampled_rows = np.arange(0, depth.shape[0], MESH_GRID_STEP, dtype=np.int32)
            sampled_cols = np.arange(0, depth.shape[1], MESH_GRID_STEP, dtype=np.int32)
            sampled_full_index = full_index[np.ix_(sampled_rows, sampled_cols)]
            sampled_valid = sampled_full_index >= 0

            compact_index = np.full(sampled_full_index.shape, -1, dtype=np.int32)
            kept_source_indices = sampled_full_index[sampled_valid]
            compact_index[sampled_valid] = np.arange(len(kept_source_indices), dtype=np.int32)

            mesh_positions = (positions[kept_source_indices] - center).astype("<f4")
            mesh_colors = colors[kept_source_indices]
            mesh_indices = []

            for row in range(compact_index.shape[0] - 1):
                for col in range(compact_index.shape[1] - 1):
                    a = compact_index[row, col]
                    b = compact_index[row, col + 1]
                    c = compact_index[row + 1, col]
                    d = compact_index[row + 1, col + 1]
                    if a >= 0 and b >= 0 and c >= 0:
                        append_triangle_if_coherent(mesh_indices, mesh_positions, a, c, b)
                    if b >= 0 and c >= 0 and d >= 0:
                        append_triangle_if_coherent(mesh_indices, mesh_positions, b, c, d)

            handle.write(struct.pack("<II", len(mesh_positions), len(mesh_indices)))
            for point, color in zip(mesh_positions, mesh_colors):
                handle.write(struct.pack("<fffBBBB", point[0], point[1], point[2], color[0], color[1], color[2], 255))
            handle.write(np.asarray(mesh_indices, dtype="<u4").tobytes())

            print(f"Mesh frame {frame_id}: vertices {len(mesh_positions)} triangles {len(mesh_indices) // 3}")

    print(f"Wrote {MESH_OUTPUT_PATH}")


def append_triangle_if_coherent(indices: list[int], positions: np.ndarray, a: int, b: int, c: int) -> None:
    pa = positions[a]
    pb = positions[b]
    pc = positions[c]
    if (
        np.linalg.norm(pa - pb) <= MAX_TRIANGLE_EDGE_M
        and np.linalg.norm(pb - pc) <= MAX_TRIANGLE_EDGE_M
        and np.linalg.norm(pc - pa) <= MAX_TRIANGLE_EDGE_M
    ):
        indices.extend([a, b, c])


if __name__ == "__main__":
    main()
