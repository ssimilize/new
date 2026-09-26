"""Builds a texture atlas (new UVs) for a mesh with xatlas. System Python (pip install xatlas), called
by bake_texture.py, which runs in Blender and cannot import it.

  python tools/blender/atlas.py <mesh.npz> <uv.npz> <resolution> <padding px>

<mesh.npz>: positions (N, 3) float32, faces (F, 3) uint32 (triangles).
<uv.npz>: uv (F, 3, 2) float32, one UV per face corner in Blender's convention (v up), faces in
the input order; plus charts (int) and coverage (share of the texture inside charts).
"""

import sys

import numpy as np
import xatlas

src, dst, resolution, padding = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
mesh = np.load(src)
positions, faces = mesh["positions"].astype(np.float32), mesh["faces"].astype(np.uint32)

# A mesh that keeps Meshy's UV seams split (export_static.py's buildings: welding would round their
# corners' shading) is welded here, for the charts only: a split seam is a mesh border, which ends a
# chart, so the atlas came out in Meshy's ~1,200 small islands. The UVs stay one per face corner.
# (Monsters are welded on import already.)
unique, inverse = np.unique(np.round(positions, 5), axis=0, return_inverse=True)
if len(unique) < len(positions):
    positions, faces = unique.astype(np.float32), inverse.reshape(-1)[faces].astype(np.uint32)

atlas = xatlas.Atlas()
atlas.add_mesh(positions, faces)
charts = xatlas.ChartOptions()
pack = xatlas.PackOptions()
pack.resolution = resolution
pack.padding = padding
pack.bilinear = True
pack.rotate_charts = True
pack.bruteForce = True  # tighter packing: 44% -> 50% of the Egg Shop's texture, ~2 s more
atlas.generate(charts, pack)
_vmapping, indices, uvs = atlas[0]
if len(indices) != len(faces):
    raise SystemExit(f"xatlas returned {len(indices)} faces for {len(faces)}")

corner_uv = uvs[indices]  # (F, 3, 2), xatlas keeps the face order
tri = corner_uv
area = 0.5 * np.abs((tri[:, 1, 0] - tri[:, 0, 0]) * (tri[:, 2, 1] - tri[:, 0, 1]) - (tri[:, 2, 0] - tri[:, 0, 0]) * (tri[:, 1, 1] - tri[:, 0, 1]))
np.savez(dst, uv=corner_uv.astype(np.float32), charts=atlas.chart_count, coverage=float(area.sum()))
print(f"[atlas] {len(faces)} faces -> {atlas.chart_count} charts, coverage {area.sum():.0%}, padding {padding} px at {resolution}")
