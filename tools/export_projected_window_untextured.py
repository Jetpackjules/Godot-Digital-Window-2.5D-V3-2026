"""Export the projected medieval window as texture-free GLB and OBJ assets."""

from __future__ import annotations

import json
import struct
from pathlib import Path

import trimesh


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "Views"
    / "Medieval Storm Window"
    / "Assets"
    / "Photoreal Window"
    / "framic_arcade_projected_v12_rounded.glb"
)
EXPORT_DIR = SOURCE.parent / "Exports"
GLB_OUTPUT = EXPORT_DIR / "medieval_window_v12_untextured.glb"
OBJ_OUTPUT = EXPORT_DIR / "medieval_window_v12_untextured.obj"


def texture_free_scene(source: trimesh.Scene) -> trimesh.Scene:
    """Copy geometry and transforms without UVs, textures, or source materials."""
    clean = trimesh.Scene(base_frame=source.graph.base_frame)

    for node_name in source.graph.nodes_geometry:
        transform, geometry_name = source.graph[node_name]
        mesh = source.geometry[geometry_name]
        bare_mesh = trimesh.Trimesh(
            vertices=mesh.vertices.copy(),
            faces=mesh.faces.copy(),
            vertex_normals=mesh.vertex_normals.copy(),
            process=False,
            validate=False,
        )
        clean.add_geometry(
            bare_mesh,
            node_name=node_name,
            geom_name=geometry_name,
            transform=transform,
        )

    return clean


def glb_json(path: Path) -> dict:
    """Return the JSON chunk from a binary glTF for export validation."""
    data = path.read_bytes()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path} is not a glTF 2.0 binary")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"{path} does not begin with a JSON chunk")
    return json.loads(data[20 : 20 + chunk_length].decode("utf-8"))


def main() -> None:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    source = trimesh.load(SOURCE, force="scene", process=False)
    clean = texture_free_scene(source)

    GLB_OUTPUT.write_bytes(trimesh.exchange.gltf.export_glb(clean))
    obj_export = trimesh.exchange.obj.export_obj(
            clean,
            include_normals=True,
            include_color=False,
            include_texture=False,
            return_texture=False,
        ).rstrip() + "\n"
    OBJ_OUTPUT.write_text(
        obj_export,
        encoding="utf-8",
        newline="\n",
    )

    source_triangles = sum(len(mesh.faces) for mesh in source.geometry.values())
    clean_triangles = sum(len(mesh.faces) for mesh in clean.geometry.values())
    metadata = glb_json(GLB_OUTPUT)
    texture_count = len(metadata.get("textures", []))
    image_count = len(metadata.get("images", []))
    obj_text = OBJ_OUTPUT.read_text(encoding="utf-8")

    if clean_triangles != source_triangles:
        raise RuntimeError(
            f"triangle mismatch: source={source_triangles}, export={clean_triangles}"
        )
    if texture_count or image_count:
        raise RuntimeError(
            f"texture data remains: textures={texture_count}, images={image_count}"
        )
    if "mtllib " in obj_text or "usemtl " in obj_text or "\nvt " in obj_text:
        raise RuntimeError("OBJ still contains material or texture-coordinate data")

    print(f"Source parts: {len(source.geometry):,}")
    print(f"Exported triangles: {clean_triangles:,}")
    print(f"GLB textures/images: {texture_count}/{image_count}")
    print(GLB_OUTPUT)
    print(OBJ_OUTPUT)


if __name__ == "__main__":
    main()
