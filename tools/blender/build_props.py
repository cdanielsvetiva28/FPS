"""Build STORMLINE's environment props in Blender and export them as .glb.

Props: shipping containers (3 colours), a concrete jersey barrier, a sandbag
wall, oil drums (3 colours), a guard tower, a chain-link fence frame, a
floodlight pole, two rocks and a Weatherline pylon.

Run from the project root:

    blender --background --python tools/blender/build_props.py

or open it in Blender's Scripting tab and press Run Script.

Output: assets/models/props/*.glb. Every prop's origin is at the centre of its
base. Blender: +Y forward, +Z up (the exporter converts to Godot's Y-up).
"""

import math
import os
import random
from pathlib import Path

import bpy  # noqa: I001 - bpy must be imported before bmesh/mathutils outside Blender
import bmesh
from mathutils import Matrix, Vector, noise

PROJECT_DIR = ""


def project_dir() -> Path:
    if PROJECT_DIR:
        return Path(PROJECT_DIR)
    here = Path(__file__).resolve() if "__file__" in globals() else Path(os.getcwd())
    for parent in [here, *here.parents]:
        if (parent / "project.godot").exists():
            return parent
    return Path(os.getcwd())


# --- Helpers -------------------------------------------------------------------

_materials = {}


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)
    _materials.clear()


def material(name, color, metallic=0.0, roughness=0.6, emission=None):
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 5.0
    _materials[name] = mat
    return mat


class Builder:
    """Accumulates geometry into one bmesh, one material slot per material."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _add(self, temp: bmesh.types.BMesh, mat, matrix: Matrix, smooth=False):
        temp.transform(matrix)
        mesh = bpy.data.meshes.new("tmp")
        temp.to_mesh(mesh)
        temp.free()
        slot = self._slot(mat)
        offset = len(self.bm.faces)
        self.bm.from_mesh(mesh)
        self.bm.faces.ensure_lookup_table()
        for face in self.bm.faces[offset:]:
            face.material_index = slot
            face.smooth = smooth
        bpy.data.meshes.remove(mesh)

    def box(self, size, center, mat, rotation=(0, 0, 0)):
        temp = bmesh.new()
        bmesh.ops.create_cube(temp, size=1.0)
        bmesh.ops.scale(temp, vec=Vector(size), verts=temp.verts)
        self._add(temp, mat, Matrix.Translation(Vector(center)) @ euler(rotation))

    def beam(self, a, b, thickness, mat):
        """Square beam from point a to point b."""
        a, b = Vector(a), Vector(b)
        direction = b - a
        temp = bmesh.new()
        bmesh.ops.create_cube(temp, size=1.0)
        bmesh.ops.scale(temp, vec=Vector((thickness, thickness, direction.length)), verts=temp.verts)
        rot = direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
        self._add(temp, mat, Matrix.Translation((a + b) / 2) @ rot)

    def rounded_box(self, size, center, mat, rotation=(0, 0, 0), bevel=0.05):
        temp = bmesh.new()
        bmesh.ops.create_cube(temp, size=1.0)
        bmesh.ops.scale(temp, vec=Vector(size), verts=temp.verts)
        bmesh.ops.bevel(temp, geom=list(temp.edges) + list(temp.verts), offset=bevel, segments=3,
                        affect="EDGES", profile=0.7)
        self._add(temp, mat, Matrix.Translation(Vector(center)) @ euler(rotation), smooth=True)

    def cylinder(self, radius, depth, center, mat, segments=16, rotation=(0, 0, 0), radius_top=None):
        temp = bmesh.new()
        bmesh.ops.create_cone(temp, cap_ends=True, segments=segments, radius1=radius,
                              radius2=radius if radius_top is None else radius_top, depth=depth)
        self._add(temp, mat, Matrix.Translation(Vector(center)) @ euler(rotation), smooth=True)

    def sphere(self, radius, center, mat, scale=(1, 1, 1), rotation=(0, 0, 0), segments=12, rings=8):
        temp = bmesh.new()
        bmesh.ops.create_uvsphere(temp, u_segments=segments, v_segments=rings, radius=radius)
        bmesh.ops.scale(temp, vec=Vector(scale), verts=temp.verts)
        self._add(temp, mat, Matrix.Translation(Vector(center)) @ euler(rotation), smooth=True)

    def torus(self, major, minor, center, mat, segments=24, sides=8):
        temp = bmesh.new()
        verts_rings = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring = []
            for j in range(sides):
                b = 2 * math.pi * j / sides
                r = major + math.cos(b) * minor
                ring.append(temp.verts.new((math.cos(a) * r, math.sin(a) * r, math.sin(b) * minor)))
            verts_rings.append(ring)
        for i in range(segments):
            for j in range(sides):
                r0, r1 = verts_rings[i], verts_rings[(i + 1) % segments]
                temp.faces.new((r0[j], r1[j], r1[(j + 1) % sides], r0[(j + 1) % sides]))
        self._add(temp, mat, Matrix.Translation(Vector(center)), smooth=True)

    def extrude_profile(self, profile_yz, length, mat):
        """Extrude a closed (y, z) profile along X, centred."""
        temp = bmesh.new()
        left = [temp.verts.new((-length / 2, y, z)) for y, z in profile_yz]
        right = [temp.verts.new((length / 2, y, z)) for y, z in profile_yz]
        temp.faces.new(left)
        temp.faces.new(list(reversed(right)))
        n = len(profile_yz)
        for i in range(n):
            j = (i + 1) % n
            temp.faces.new((left[i], left[j], right[j], right[i]))
        bmesh.ops.recalc_face_normals(temp, faces=temp.faces)
        self._add(temp, mat, Matrix.Identity(4))

    def finish(self, name):
        mesh = bpy.data.meshes.new(name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mat in self.mats:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def euler(rotation_deg) -> Matrix:
    rx, ry, rz = (math.radians(a) for a in rotation_deg)
    return (Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X"))


def export(name: str) -> None:
    path = project_dir() / "assets" / "models" / "props" / f"{name}.glb"
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_apply=True, export_yup=True)
    print("exported", path)


# --- Props -----------------------------------------------------------------------

def container(name, paint_color):
    """20 ft shipping container: corrugated walls, corner posts, doors with lock bars."""
    reset_scene()
    paint = material("Paint", paint_color, 0.3, 0.55)
    dark = material("Frame", (0.08, 0.08, 0.085), 0.6, 0.5)
    L, W, H = 6.06, 2.44, 2.59
    b = Builder()
    # Corner posts and rails.
    for x in (-L / 2 + 0.08, L / 2 - 0.08):
        for y in (-W / 2 + 0.08, W / 2 - 0.08):
            b.box((0.16, 0.16, H), (x, y, H / 2), dark)
    for z in (0.08, H - 0.08):
        for y in (-W / 2 + 0.08, W / 2 - 0.08):
            b.box((L, 0.16, 0.16), (0, y, z), dark)
        for x in (-L / 2 + 0.08, L / 2 - 0.08):
            b.box((0.16, W, 0.16), (x, 0, z), dark)
    # Corrugated long walls.
    for side in (-1, 1):
        y = side * (W / 2 - 0.06)
        b.box((L - 0.3, 0.03, H - 0.3), (0, y, H / 2), paint)
        x = -L / 2 + 0.25
        while x < L / 2 - 0.2:
            b.box((0.11, 0.06, H - 0.32), (x, y + side * 0.03, H / 2), paint)
            x += 0.21
    # Roof with ribs across.
    b.box((L - 0.2, W - 0.2, 0.03), (0, 0, H - 0.05), paint)
    x = -L / 2 + 0.3
    while x < L / 2 - 0.2:
        b.box((0.12, W - 0.25, 0.04), (x, 0, H - 0.02), paint)
        x += 0.45
    # Back wall (corrugated, vertical ribs).
    xb = -L / 2 + 0.06
    b.box((0.03, W - 0.3, H - 0.3), (xb, 0, H / 2), paint)
    y = -W / 2 + 0.25
    while y < W / 2 - 0.2:
        b.box((0.06, 0.11, H - 0.32), (xb - 0.03, y, H / 2), paint)
        y += 0.21
    # Doors: two panels, four lock bars, handles.
    xd = L / 2 - 0.05
    for side in (-1, 1):
        b.box((0.05, W / 2 - 0.2, H - 0.3), (xd, side * (W / 4 - 0.02), H / 2), paint)
        for k in (0.25, 0.75):
            ybar = side * (W / 2 - 0.15) * k + side * 0.05
            b.cylinder(0.025, H - 0.35, (xd + 0.06, ybar, H / 2), dark, segments=8)
            b.box((0.05, 0.05, 0.25), (xd + 0.09, ybar + side * 0.06, 1.15), dark)
    b.box((0.06, 0.02, H - 0.3), (xd + 0.01, 0, H / 2), dark)
    b.finish("Container")
    export(name)


def jersey_barrier():
    reset_scene()
    concrete = material("Concrete", (0.5, 0.49, 0.46), 0.0, 0.9)
    paint = material("HazardPaint", (0.9, 0.75, 0.15), 0.0, 0.7)
    b = Builder()
    profile = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.13, 0.26), (0.08, 0.81),
               (-0.08, 0.81), (-0.13, 0.26), (-0.3, 0.08)]
    b.extrude_profile(profile, 3.0, concrete)
    # Painted stripes on the top edge.
    for x in (-1.2, -0.4, 0.4, 1.2):
        b.box((0.35, 0.17, 0.02), (x, 0, 0.815), paint)
    # Lifting slots at the base.
    for x in (-0.9, 0.9):
        b.box((0.3, 0.62, 0.07), (x, 0, 0.04), material("Shadow", (0.1, 0.1, 0.1), 0.0, 1.0))
    b.finish("Barrier")
    export("jersey_barrier")


def sandbag_wall():
    """Six rows of staggered, slightly slumped sandbags, two deep, 3 m long."""
    reset_scene()
    random.seed(7)
    burlap = [material("Burlap", (0.42, 0.36, 0.25), 0.0, 0.95),
              material("BurlapDark", (0.34, 0.29, 0.2), 0.0, 0.95)]
    b = Builder()
    bag_l, bag_w, bag_h = 0.5, 0.3, 0.15
    for row in range(6):
        z = bag_h / 2 + row * (bag_h - 0.012)
        offset = (bag_l / 2) if row % 2 else 0.0
        for depth_y in (-0.16, 0.16):
            x = -1.5 + bag_l / 2 + offset
            while x <= 1.5 - bag_l / 2 + 0.01:
                b.rounded_box((bag_l * random.uniform(0.94, 1.0), bag_w, bag_h),
                              (x + random.uniform(-0.015, 0.015), depth_y + random.uniform(-0.015, 0.015), z),
                              random.choice(burlap), rotation=(random.uniform(-3, 3), 0, random.uniform(-4, 4)),
                              bevel=0.06)
                x += bag_l
    b.finish("Sandbags")
    export("sandbag_wall")


def oil_drum(name, color):
    reset_scene()
    paint = material("DrumPaint", color, 0.4, 0.5)
    rim = material("DrumRim", tuple(c * 0.7 for c in color), 0.5, 0.45)
    b = Builder()
    b.cylinder(0.29, 0.88, (0, 0, 0.44), paint, segments=20)
    for z in (0.02, 0.3, 0.58, 0.86):
        b.cylinder(0.3, 0.035, (0, 0, z), rim, segments=20)
    b.cylinder(0.04, 0.03, (0.15, 0.05, 0.89), rim, segments=8)
    b.finish("Drum")
    export(name)


def guard_tower():
    """Wooden watchtower: braced legs, deck, plank walls, ladder, tin roof."""
    reset_scene()
    wood = material("Wood", (0.42, 0.3, 0.19), 0.0, 0.85)
    wood_dark = material("WoodDark", (0.3, 0.21, 0.13), 0.0, 0.9)
    tin = material("Tin", (0.45, 0.47, 0.48), 0.7, 0.45)
    b = Builder()
    deck_z, half_base, half_top = 4.0, 1.75, 1.45
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in corners:
        b.beam((sx * half_base, sy * half_base, 0), (sx * half_top, sy * half_top, deck_z + 1.1), 0.2, wood)
    # Cross bracing on each side.
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        for z0, z1 in ((0.3, 2.0), (2.0, 3.8)):
            t0 = half_base + (half_top - half_base) * z0 / (deck_z + 1.1)
            t1 = half_base + (half_top - half_base) * z1 / (deck_z + 1.1)
            b.beam((ax * t0, ay * t0, z0), (bx * t1, by * t1, z1), 0.09, wood_dark)
            b.beam((bx * t0, by * t0, z0), (ax * t1, ay * t1, z1), 0.09, wood_dark)
    b.box((3.4, 3.4, 0.15), (0, 0, deck_z), wood)
    # Plank walls (open on the ladder side, -Y).
    for side, (sx, sy) in enumerate(((0, 1), (1, 0), (-1, 0))):
        for k in range(4):
            z = deck_z + 0.2 + k * 0.24
            if sx == 0:
                b.box((3.3, 0.06, 0.2), (0, sy * 1.65, z), wood if k % 2 else wood_dark)
            else:
                b.box((0.06, 3.3, 0.2), (sx * 1.65, 0, z), wood if k % 2 else wood_dark)
    # Roof posts and a pitched tin roof.
    for sx, sy in corners:
        b.box((0.12, 0.12, 2.2), (sx * 1.55, sy * 1.55, deck_z + 1.1), wood)
    for side in (-1, 1):
        b.box((4.0, 2.2, 0.05), (0, side * 1.0, deck_z + 2.45), tin, rotation=(side * 14, 0, 0))
    # Ladder on the -Y side.
    for x in (-0.3, 0.3):
        b.beam((x, -2.3, 0), (x, -1.75, deck_z + 0.9), 0.07, wood)
    for k in range(12):
        t = (k + 0.5) / 12
        b.box((0.6, 0.05, 0.05), (0, -2.3 + 0.55 * t, (deck_z + 0.9) * t), wood_dark)
    b.finish("Tower")
    export("guard_tower")


def fence_frame():
    """Fence posts, rails and barbed wire for a 3 m segment. The chain-link
    mesh itself is a textured quad added in Godot."""
    reset_scene()
    steel = material("Galvanized", (0.6, 0.62, 0.63), 0.8, 0.4)
    wire = material("Wire", (0.35, 0.35, 0.36), 0.8, 0.5)
    b = Builder()
    for x in (-1.5, 1.5):
        b.cylinder(0.045, 2.5, (x, 0, 1.25), steel, segments=10)
        b.beam((x, 0, 2.45), (x, 0.32, 2.8), 0.04, steel)
    b.cylinder(0.03, 3.0, (0, 0, 2.4), steel, segments=8, rotation=(0, 90, 0))
    b.cylinder(0.02, 3.0, (0, 0, 0.1), steel, segments=8, rotation=(0, 90, 0))
    for k, (y, z) in enumerate(((0.1, 2.55), (0.2, 2.67), (0.3, 2.78))):
        b.cylinder(0.008, 3.0, (0, y, z), wire, segments=5, rotation=(0, 90, 0))
        for i in range(10):
            b.box((0.05, 0.01, 0.05), (-1.4 + i * 0.31 + k * 0.1, y, z), wire, rotation=(0, 45, 0))
    b.finish("FenceFrame")
    export("fence_frame")


def light_pole():
    reset_scene()
    steel = material("Galvanized", (0.55, 0.57, 0.58), 0.8, 0.4)
    lamp = material("Lamp", (1.0, 0.92, 0.75), 0.0, 0.3, emission=(1.0, 0.9, 0.7))
    b = Builder()
    b.cylinder(0.12, 7.0, (0, 0, 3.5), steel, segments=12, radius_top=0.07)
    b.box((0.5, 0.5, 0.25), (0, 0, 0.12), steel)
    b.beam((0, 0, 6.8), (0, 1.2, 7.1), 0.08, steel)
    b.box((0.5, 0.35, 0.2), (0, 1.35, 7.05), steel)
    b.box((0.42, 0.28, 0.02), (0, 1.35, 6.94), lamp)
    b.finish("LightPole")
    export("light_pole")


def rock(name, seed, detail=3):
    """Lumpy low-poly rock, about 2 m across. Scale it up for cliffs."""
    reset_scene()
    stone = material("Stone", (0.27, 0.25, 0.23), 0.0, 0.92)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=1.0)
    offset = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in bm.verts:
        n = noise.fractal(v.co * 1.3 + offset, 0.6, 2.0, 4)
        v.co *= 1.0 + 0.35 * n
        v.co.z *= 0.65
        if v.co.z < -0.15:
            v.co.z = -0.15 + (v.co.z + 0.15) * 0.2  # Flat-ish bottom.
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.15)), verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(stone)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    export(name)


def weatherline_pylon():
    """45 m lattice tower with an emitter ring and beacon (see docs/STORY.md)."""
    reset_scene()
    steel = material("Steel", (0.62, 0.64, 0.66), 0.85, 0.35)
    dark = material("DarkSteel", (0.2, 0.21, 0.22), 0.8, 0.4)
    glow = material("EmitterGlow", (0.4, 0.8, 1.0), 0.0, 0.3, emission=(0.3, 0.75, 1.0))
    beacon = material("Beacon", (1.0, 0.15, 0.1), 0.0, 0.3, emission=(1.0, 0.1, 0.05))
    b = Builder()
    height, base, top = 45.0, 4.5, 1.2
    levels = 9
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]

    def half(z):
        return base + (top - base) * (z / height)

    for sx, sy in corners:
        b.beam((sx * base, sy * base, 0), (sx * top, sy * top, height), 0.35, steel)
        b.box((1.2, 1.2, 0.6), (sx * base, sy * base, 0.3), dark)
    for k in range(levels):
        z0 = height * k / levels
        z1 = height * (k + 1) / levels
        for i in range(4):
            (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
            h0, h1 = half(z0), half(z1)
            b.beam((ax * h1, ay * h1, z1), (bx * h1, by * h1, z1), 0.18, steel)
            b.beam((ax * h0, ay * h0, z0), (bx * h1, by * h1, z1), 0.12, steel)
            b.beam((bx * h0, by * h0, z0), (ax * h1, ay * h1, z1), 0.12, steel)
    # Emitter: a ring of vanes around the top with a glowing core.
    b.cylinder(0.8, 6.0, (0, 0, height + 3.0), dark, segments=12)
    b.torus(4.5, 0.35, (0, 0, height + 2.0), steel, segments=32)
    b.torus(4.5, 0.12, (0, 0, height + 2.0), glow, segments=32, sides=6)
    for i in range(8):
        a = 2 * math.pi * i / 8
        b.beam((math.cos(a) * 0.8, math.sin(a) * 0.8, height + 1.0), (math.cos(a) * 4.5, math.sin(a) * 4.5, height + 2.0), 0.15, steel)
    b.sphere(0.6, (0, 0, height + 6.4), beacon)
    b.finish("Pylon")
    export("weatherline_pylon")


def pine_tree():
    """Low-poly conifer for forests (used via MultiMesh, so one mesh)."""
    reset_scene()
    bark = material("Bark", (0.25, 0.17, 0.11), 0.0, 0.95)
    needles = material("Needles", (0.13, 0.24, 0.12), 0.0, 0.9)
    b = Builder()
    b.cylinder(0.25, 3.0, (0, 0, 1.5), bark, segments=6, radius_top=0.15)
    for i, (z, r, h) in enumerate(((3.0, 2.6, 4.0), (5.0, 2.1, 3.6), (7.0, 1.5, 3.0), (8.8, 0.9, 2.4))):
        b.cylinder(r, h, (0, 0, z + h / 2 - 0.6), needles, segments=7, radius_top=0.05)
    b.finish("Pine")
    export("pine_tree")


if __name__ == "__main__":
    container("container_red", (0.55, 0.12, 0.08))
    container("container_blue", (0.1, 0.24, 0.42))
    container("container_green", (0.18, 0.32, 0.2))
    jersey_barrier()
    sandbag_wall()
    oil_drum("oil_drum_blue", (0.08, 0.2, 0.45))
    oil_drum("oil_drum_red", (0.55, 0.1, 0.07))
    oil_drum("oil_drum_olive", (0.3, 0.33, 0.18))
    guard_tower()
    fence_frame()
    light_pole()
    rock("rock_a", 1)
    rock("rock_b", 2)
    weatherline_pylon()
    pine_tree()
