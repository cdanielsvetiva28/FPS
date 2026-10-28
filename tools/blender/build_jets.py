"""Build STORMLINE's fighter jets in Blender and export them as .glb for Godot.

Two aircraft with deliberately different silhouettes, so friend and foe read
at a glance:

  * Halvard "Kestrel" (FA-9): twin canted tails, swept wing, tail planes.
    Navy-grey with brass markings. The player's jet.
  * Sevrin "Volkan" (Su-type delta): delta wing, canards, single big tail.
    Slate grey with signal-orange markings. The enemy.

Run from the project root, either:

    blender --background --python tools/blender/build_jets.py

or open this file in Blender's Scripting tab and press Run Script (set
PROJECT_DIR below if Blender can't work out where the project is).

Output: assets/models/jet_halvard.glb and assets/models/jet_sevrin.glb.

Conventions (Blender): nose points +Y, up is +Z, right wing is +X. The glTF
exporter converts this to Godot's -Z forward / +Y up automatically.
Named parts Godot code looks for: "Afterburner*" (scaled with throttle),
"Missile_L" and "Missile_R" (hidden when fired).
"""

import math
import os
from pathlib import Path

import bpy  # noqa: I001 - bpy must be imported before bmesh/mathutils outside Blender
import bmesh
from mathutils import Matrix, Vector

# Set this if running from inside Blender's text editor doesn't find the project.
PROJECT_DIR = ""


def project_dir() -> Path:
    if PROJECT_DIR:
        return Path(PROJECT_DIR)
    here = Path(__file__).resolve() if "__file__" in globals() else Path(os.getcwd())
    for parent in [here, *here.parents]:
        if (parent / "project.godot").exists():
            return parent
    return Path(os.getcwd())


# --- Scene helpers -----------------------------------------------------------

def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)


def material(name: str, color, metallic=0.0, roughness=0.5, emission=None, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    return mat


def make_object(name: str, bm: bmesh.types.BMesh, mat, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def mirrored(points):
    """Mirror a list of (x, y, z) across the X axis."""
    return [(-x, y, z) for x, y, z in points]


# --- Shape builders ----------------------------------------------------------

def loft(name, sections, mat, segments=20, smooth=True):
    """Body of revolution-ish shape from elliptical cross sections.

    sections: list of (y, half_width, half_height, z_center, flat_bottom)
    """
    bm = bmesh.new()
    rings = []
    for y, hw, hh, zc, flat in sections:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            x = math.cos(a) * hw
            z = math.sin(a) * hh
            if flat and z < 0:
                z *= 0.45  # flatter belly
            ring.append(bm.verts.new((x, y, z + zc)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    # Caps.
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return make_object(name, bm, mat, smooth)


def slab(name, outline_top, thickness_root, thickness_tip, mat):
    """A thin wing-like slab from a 2D planform (x, y) outline at z=0.

    Thickness tapers linearly from root (smallest |x|) to tip.
    """
    xs = [abs(p[0]) for p in outline_top]
    x0, x1 = min(xs), max(xs)
    bm = bmesh.new()
    top, bottom = [], []
    for x, y, z in outline_top:
        t = 0.0 if x1 == x0 else (abs(x) - x0) / (x1 - x0)
        half = (thickness_root + (thickness_tip - thickness_root) * t) / 2
        top.append(bm.verts.new((x, y, z + half)))
        bottom.append(bm.verts.new((x, y, z - half)))
    n = len(outline_top)
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], bottom[i], bottom[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return make_object(name, bm, mat)


def cylinder(name, radius_back, radius_front, y_back, y_front, mat, x=0.0, z=0.0, segments=16, cap=True):
    bm = bmesh.new()
    back, front = [], []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        back.append(bm.verts.new((x + math.cos(a) * radius_back, y_back, z + math.sin(a) * radius_back)))
        front.append(bm.verts.new((x + math.cos(a) * radius_front, y_front, z + math.sin(a) * radius_front)))
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((back[i], back[j], front[j], front[i]))
    if cap:
        bm.faces.new(list(reversed(back)))
        bm.faces.new(front)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return make_object(name, bm, mat, smooth=True)


def box(name, size, center, mat, rotation_deg=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    rx, ry, rz = (math.radians(a) for a in rotation_deg)
    rot = Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return make_object(name, bm, mat)


def disc(name, radius, center, normal_axis, mat, segments=20):
    """Flat disc used for roundels. normal_axis: 'Z' (on wing top) or 'X' (on a tail)."""
    bm = bmesh.new()
    verts = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        u, v = math.cos(a) * radius, math.sin(a) * radius
        if normal_axis == "Z":
            p = (center[0] + u, center[1] + v, center[2])
        else:
            p = (center[0], center[1] + u, center[2] + v)
        verts.append(bm.verts.new(p))
    bm.faces.new(verts)
    return make_object(name, bm, mat)


def set_origin(obj, point):
    """Move an object's origin (pivot) to a point without moving its geometry."""
    obj.data.transform(Matrix.Translation(-Vector(point)))
    obj.location = Vector(point)
    return obj


def tilt(obj, axis: str, degrees: float, pivot):
    """Rotate an object's mesh about a pivot point."""
    m = (Matrix.Translation(Vector(pivot)) @ Matrix.Rotation(math.radians(degrees), 4, axis)
         @ Matrix.Translation(-Vector(pivot)))
    obj.data.transform(m)


def missile(name, x, y, z, body_mat, tip_mat):
    parts = [
        cylinder(name, 0.09, 0.09, y - 1.4, y + 1.2, body_mat, x=x, z=z, segments=10),
        cylinder(name + "_Tip", 0.09, 0.01, y + 1.2, y + 1.6, tip_mat, x=x, z=z, segments=10),
    ]
    for i, (dx, dz) in enumerate(((0.22, 0), (-0.22, 0), (0, 0.22), (0, -0.22))):
        parts.append(box(f"{name}_Fin{i}", (abs(dx) * 1.0 + 0.01, 0.35, abs(dz) * 1.0 + 0.01),
                         (x + dx / 2, y - 1.2, z + dz / 2), body_mat))
    return join(parts, name)


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


# --- Aircraft ----------------------------------------------------------------

def build_kestrel(paint, dark, glass, accent, burner):
    """Halvard FA-9 Kestrel: twin tails, swept wing, conventional tail planes."""
    body = loft("Fuselage", [
        (-7.6, 0.75, 0.55, 0.1, True),
        (-6.5, 1.05, 0.7, 0.15, True),
        (-3.0, 1.25, 0.8, 0.2, True),
        (0.5, 1.15, 0.85, 0.25, True),
        (3.0, 0.85, 0.75, 0.3, True),
        (5.0, 0.6, 0.55, 0.25, True),
        (6.8, 0.32, 0.32, 0.15, False),
        (8.2, 0.04, 0.04, 0.1, False),
    ], paint)
    canopy = loft("Canopy", [
        (1.8, 0.05, 0.05, 0.9, False),
        (2.6, 0.42, 0.42, 0.95, False),
        (4.0, 0.45, 0.45, 0.95, False),
        (5.2, 0.05, 0.05, 0.85, False),
    ], glass, segments=16)
    parts = [body]
    for side, sign in (("R", 1), ("L", -1)):
        wing = [(sign * 1.0, 2.0, 0.1), (sign * 5.6, -3.0, 0.0), (sign * 5.6, -4.2, 0.0), (sign * 1.0, -4.6, 0.1)]
        if sign < 0:
            wing.reverse()
        parts.append(slab(f"Wing_{side}", wing, 0.28, 0.08, paint))
        tailplane = [(sign * 1.0, -5.3, 0.15), (sign * 3.4, -6.9, 0.1), (sign * 3.4, -7.6, 0.1), (sign * 1.0, -7.4, 0.15)]
        if sign < 0:
            tailplane.reverse()
        parts.append(slab(f"Tailplane_{side}", tailplane, 0.14, 0.06, paint))
        parts.append(box(f"Intake_{side}", (0.55, 2.6, 0.75), (sign * 1.15, 0.6, -0.15), dark))
        parts.append(disc(f"Roundel_{side}", 0.55, (sign * 4.2, -2.6, 0.12), "Z", accent))
    # Twin tails, canted outward.
    for side, sign in (("R", 1), ("L", -1)):
        fin = vertical_fin(f"Fin_{side}", sign * 0.85, [(-4.7, 0.7), (-7.5, 0.7), (-7.7, 3.3), (-6.4, 3.3)], 0.12, paint)
        tilt(fin, "Y", sign * 18.0, (sign * 0.85, 0, 0.7))
        parts.append(fin)
        flash = vertical_fin(f"FinFlash_{side}", sign * 0.85, [(-6.6, 2.3), (-7.55, 2.3), (-7.65, 2.9), (-6.95, 2.9)], 0.16, accent)
        tilt(flash, "Y", sign * 18.0, (sign * 0.85, 0, 0.7))
        parts.append(flash)
    for i, x in enumerate((0.5, -0.5)):
        parts.append(cylinder(f"Nozzle_{i}", 0.42, 0.5, -8.4, -7.3, dark, x=x, z=0.1, segments=16))
    # Pivot at the nozzle so Godot can stretch the flame with throttle.
    afterburners = [set_origin(cylinder(f"Afterburner_{i}", 0.38, 0.05, -8.4, -10.8, burner, x=x, z=0.1, segments=12),
                               (x, -8.4, 0.1))
                    for i, x in enumerate((0.5, -0.5))]
    missiles = [missile("Missile_R", 3.4, -1.6, -0.3, paint_light(paint), accent),
                missile("Missile_L", -3.4, -1.6, -0.3, paint_light(paint), accent)]
    airframe = join(parts, "Airframe")
    return [airframe, canopy, *afterburners, *missiles]


def build_volkan(paint, dark, glass, accent, burner):
    """Sevrin Volkan: big delta wing, canards, single tall tail."""
    body = loft("Fuselage", [
        (-7.4, 0.8, 0.6, 0.1, True),
        (-5.5, 1.2, 0.75, 0.15, True),
        (-2.0, 1.4, 0.8, 0.2, True),
        (1.5, 1.1, 0.85, 0.25, True),
        (4.0, 0.75, 0.7, 0.3, True),
        (6.0, 0.45, 0.45, 0.2, False),
        (7.8, 0.05, 0.05, 0.1, False),
    ], paint)
    canopy = loft("Canopy", [
        (2.2, 0.05, 0.05, 0.95, False),
        (3.0, 0.4, 0.42, 1.0, False),
        (4.3, 0.42, 0.42, 0.98, False),
        (5.3, 0.05, 0.05, 0.85, False),
    ], glass, segments=16)
    parts = [body]
    for side, sign in (("R", 1), ("L", -1)):
        delta = [(sign * 1.1, 1.5, 0.1), (sign * 6.2, -5.4, 0.0), (sign * 6.2, -6.2, 0.0), (sign * 1.1, -6.6, 0.1)]
        if sign < 0:
            delta.reverse()
        parts.append(slab(f"Wing_{side}", delta, 0.3, 0.07, paint))
        canard = [(sign * 0.9, 4.4, 0.35), (sign * 3.3, 2.5, 0.35), (sign * 3.3, 1.9, 0.35), (sign * 0.9, 2.4, 0.35)]
        if sign < 0:
            canard.reverse()
        parts.append(slab(f"Canard_{side}", canard, 0.1, 0.05, paint))
        parts.append(box(f"Intake_{side}", (0.65, 3.0, 0.8), (sign * 1.25, 0.2, -0.35), dark))
        parts.append(box(f"Chevron_{side}", (2.6, 0.55, 0.34), (sign * 3.9, -4.4, 0.06), accent, (0, 0, sign * 35)))
        parts.append(box(f"WingTip_{side}", (0.12, 1.0, 0.1), (sign * 6.2, -5.75, 0.0), accent))
    fin = vertical_fin("Fin", 0.0, [(-3.8, 0.8), (-7.3, 0.8), (-7.6, 4.0), (-5.9, 4.0)], 0.16, paint)
    parts.append(fin)
    parts.append(box("FinStripe", (0.2, 1.9, 0.6), (0, -6.75, 3.3), accent))
    parts.append(cylinder("Nozzle_0", 0.55, 0.62, -8.2, -7.1, dark, z=0.1, segments=18))
    afterburners = [set_origin(cylinder("Afterburner_0", 0.5, 0.06, -8.2, -11.2, burner, z=0.1, segments=14),
                               (0, -8.2, 0.1))]
    missiles = [missile("Missile_R", 4.0, -2.8, -0.3, paint_light(paint), accent),
                missile("Missile_L", -4.0, -2.8, -0.3, paint_light(paint), accent)]
    airframe = join(parts, "Airframe")
    return [airframe, canopy, *afterburners, *missiles]


def vertical_fin(name, x, outline_yz, thickness, mat):
    """Vertical tail surface at a given X from a (y, z) outline."""
    bm = bmesh.new()
    left = [bm.verts.new((x - thickness / 2, y, z)) for y, z in outline_yz]
    right = [bm.verts.new((x + thickness / 2, y, z)) for y, z in outline_yz]
    bm.faces.new(left)
    bm.faces.new(list(reversed(right)))
    n = len(outline_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left[i], left[j], right[j], right[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return make_object(name, bm, mat)


_light_cache = {}


def paint_light(paint):
    if paint.name not in _light_cache:
        _light_cache[paint.name] = material(paint.name + "_Ordnance", (0.82, 0.82, 0.8), 0.2, 0.5)
    return _light_cache[paint.name]


def export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=False,
                              export_apply=True, export_yup=True)
    print("exported", path)


def build(kind: str) -> None:
    reset_scene()
    _light_cache.clear()
    dark = material("DarkMetal", (0.05, 0.05, 0.055), 0.8, 0.35)
    glass = material("Canopy", (0.08, 0.12, 0.14), 0.9, 0.08)
    burner = material("Afterburner", (1.0, 0.55, 0.2), 0.0, 1.0, emission=(1.0, 0.5, 0.15))
    if kind == "halvard":
        paint = material("HalvardPaint", (0.17, 0.22, 0.3), 0.35, 0.45)
        accent = material("HalvardBrass", (0.78, 0.6, 0.25), 0.8, 0.35)
        build_kestrel(paint, dark, glass, accent, burner)
    else:
        paint = material("SevrinPaint", (0.33, 0.33, 0.31), 0.25, 0.55)
        accent = material("SevrinOrange", (0.95, 0.38, 0.06), 0.1, 0.5)
        build_volkan(paint, dark, glass, accent, burner)
    export(project_dir() / "assets" / "models" / f"jet_{kind}.glb")


if __name__ == "__main__":
    build("halvard")
    build("sevrin")
