"""Build V12: rounded pillar tangencies on the square V11 architecture.

V11's sill, facade, outer jambs, and perimeter returns remain byte-for-byte
equivalent in construction.  V12 changes only the geometry immediately behind
the three supports: main-opening reveal strips stop where they meet a pillar,
and the long rectangular capital sockets are omitted.  The existing rounded
pillar backs and horizontal caps then close each support without visually
turning its semicircular front into a deep D-shaped extrusion.
"""

from __future__ import annotations

import numpy as np

import build_projected_window_v11 as v11


v10 = v11.v10
v9 = v11.v9
v8 = v11.v8
v7 = v11.v7
v6 = v11.v6
base = v11.base

base.TEXTURE = base.ASSET_DIR / "framic_arcade_v12_rounded_projected_2x.png"
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v12_rounded.glb"


def touches_pillar_tangent(u: float, v: float) -> bool:
    """Return true only for reveal segments hidden by a rounded support.

    The reveal needs a small concealed clearance beyond the photographed
    tangent.  Cutting it at the exact radius leaves the final oblique quad
    visible as a thin triangular spike beside the capital.  V10's measured
    clearance removes that spike while leaving every non-pillar reveal intact.
    """
    if v < v7.PROFILE_TOP or v > v7.PROFILE_BOTTOM:
        return False
    return v10.neighbours_pillar(u, v)


def rounded_opening_return(
    source: base.Image.Image,
    opening: v9.Opening,
    index: int,
    depth_field: np.ndarray,
) -> base.trimesh.Trimesh:
    """Use V11's square tunnel, except at a main opening's pillar tangent."""
    u, v = v10.contour_front_uv(source, opening.contour)
    z_front = v9.sample_field(depth_field, u, v)
    depth = {
        "main": v10.MAIN_REVEAL_DEPTH,
        "roof": v10.ROOF_REVEAL_DEPTH,
        "tracery": v10.TRACERY_REVEAL_DEPTH,
    }[opening.kind]
    z_back = np.maximum(z_front - depth, v11.WALL_BACK_Z)
    front = base.source_ray_point(u, v, z_front)
    back = v11.square_back_point(front, z_back)
    vertices = np.vstack((front, back))
    count = len(opening.contour)
    faces: list[list[int]] = []
    for point in range(count):
        nxt = (point + 1) % count
        midpoint_u = float((u[point] + u[nxt]) * 0.5)
        midpoint_v = float((v[point] + v[nxt]) * 0.5)
        if opening.kind == "main" and touches_pillar_tangent(midpoint_u, midpoint_v):
            continue
        faces.extend(
            ([point, nxt, count + nxt], [point, count + nxt, count + point])
        )
    uv = np.vstack(
        (np.column_stack((u, 1.0 - v)), np.column_stack((u, 1.0 - v)))
    )
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv,
            material=base.placeholder_material("Pillar-trimmed square opening return"),
        ),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}_{opening.kind.title()}"
    return mesh


def build() -> None:
    source = v9.clean_source()
    texture = source.resize(
        (source.width * 2, source.height * 2), base.Image.Resampling.LANCZOS
    )
    texture = texture.filter(
        base.ImageFilter.UnsharpMask(radius=0.55, percent=22, threshold=3)
    )
    texture_build = base.TEXTURE.with_suffix(".building")
    texture.save(texture_build, format="PNG", optimize=True)

    v9.WALL_BACK_Z = v11.WALL_BACK_Z
    v9.facade_cell_faces = v10.clipped_facade_cell_faces
    depth_field = v11.lifted_facade_depth_field(source)
    scene = base.trimesh.Scene()

    # These are intentionally the exact V11 builders.
    v11.add_geometry(scene, v11.alpha_facade_front(source, depth_field))
    v11.add_geometry(scene, v11.square_facade_back(source, depth_field))
    for index, opening in enumerate(v10.regularized_openings(source), 1):
        v11.add_geometry(
            scene, rounded_opening_return(source, opening, index, depth_field)
        )
    for geometry in v11.square_outer_returns(source, depth_field):
        v11.add_geometry(scene, geometry)
    for geometry in v11.square_sill():
        v11.add_geometry(scene, geometry)

    # Keep the proven V8 pillars themselves unchanged.  Their own rounded back
    # and caps close the support; no rectangular socket or reveal tail follows
    # the semicircle toward either edge of the sill.
    for pillar_index in range(3):
        for geometry in (
            v8.vertical_pillar_surface(pillar_index, True),
            v8.vertical_pillar_surface(pillar_index, False),
            v8.horizontal_pillar_cap(pillar_index, True),
            v8.horizontal_pillar_cap(pillar_index, False),
        ):
            v11.add_geometry(scene, geometry)
    for geometry in v6.perimeter_skirts():
        v11.add_geometry(scene, geometry)

    glb_build = base.OUTPUT.with_suffix(".building")
    glb_build.write_bytes(base.promote_tangent_semantic(scene.export(file_type="glb")))
    texture_build.replace(base.TEXTURE)
    glb_build.replace(base.OUTPUT)
    triangles = sum(len(geometry.faces) for geometry in scene.geometry.values())
    print(f"Wrote {base.TEXTURE.relative_to(base.ROOT)} ({texture.width}x{texture.height})")
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"V12: {triangles:,} triangles")
    print("V12: V11 sill, facade, outer walls, and arcade retained")
    print("V12: main reveals terminate at rounded pillar tangencies")
    print("V12: no rectangular tails behind the pillar capitals")


if __name__ == "__main__":
    build()
