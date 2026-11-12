"""Baut die Low-Poly-Trainingspuppe in Blender und exportiert sie als glTF.

Aufruf (Blender 4.x):
    blender --background --python tools/blender/build_dummy.py -- assets/models
oder mit dem bpy-Modul:
    python tools/blender/build_dummy.py assets/models
Die .glb-Dateien landen in assets/models, die .blend in art/blender (von Godot ignoriert).

Konventionen:
  - Alle Koordinaten im Skript sind Godot-Koordinaten (Y oben, -Z vorne) und werden beim Bauen
    nach Blender (Z oben) umgerechnet. Der glTF-Export rechnet sie wieder zurück.
  - Jedes Teil ist ein eigenes Objekt. Sein Ursprung ist das Gelenk, um das es sich dreht.
    Gliedmaßen zeigen vom Gelenk aus nach unten (-Y).
  - Die Objekte stehen im .blend zusammengesetzt da, damit man die Figur als Ganzes sieht.
    Godot nutzt nur die Meshes und setzt die Gelenke selbst.
  - Materialnamen (Skin, Cloth, Trim, Scarf, Eye, ...) werden in Godot je nach Figur umgefärbt.
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector


def g2b(v):
    """Godot (x, y, z) -> Blender (x, -z, y)"""
    return Vector((v[0], -v[2], v[1]))


# ------------------------------------------------------------------
# Materialien
# ------------------------------------------------------------------

PALETTE = {
    "Skin": ((0.035, 0.035, 0.05), 0.0, 0.6),
    "Void": ((0.008, 0.008, 0.012), 0.0, 1.0),
    "Cloth": ((0.16, 0.30, 0.30), 0.0, 0.95),
    "ClothDark": ((0.09, 0.17, 0.18), 0.0, 0.95),
    "Trim": ((0.42, 0.62, 0.60), 0.0, 0.9),
    "Scarf": ((0.30, 0.17, 0.38), 0.0, 0.95),
    "Leather": ((0.07, 0.06, 0.06), 0.0, 0.8),
    "Eye": ((1.0, 0.78, 0.18), 4.0, 0.5),
    "Steel": ((0.62, 0.70, 0.70), 0.0, 0.35),
    "SteelDark": ((0.14, 0.16, 0.17), 0.0, 0.5),
    "Grip": ((0.18, 0.10, 0.06), 0.0, 0.9),
    "ShieldFace": ((0.22, 0.36, 0.36), 0.0, 0.5),
    "ShieldRim": ((0.48, 0.70, 0.68), 0.0, 0.45),
    "Gem": ((0.35, 0.95, 1.0), 4.0, 0.3),
    "HelmMetal": ((0.30, 0.25, 0.20), 0.0, 0.5),
    "Bone": ((0.75, 0.68, 0.55), 0.0, 0.8),
    "Wood": ((0.32, 0.22, 0.14), 0.0, 0.95),
    "Straw": ((0.48, 0.36, 0.18), 0.0, 1.0),
    "Rag": ((0.45, 0.18, 0.14), 0.0, 1.0),
    "Stone": ((0.17, 0.26, 0.28), 0.0, 0.95),
}

MATS = {}


def make_materials():
    for name, (rgb, emit, rough) in PALETTE.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = 0.0
        if emit > 0:
            bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit
        m.diffuse_color = (*rgb, 1.0)
        MATS[name] = m


# ------------------------------------------------------------------
# Mesh-Bau
# ------------------------------------------------------------------

class Part:
    """Sammelt Geometrie für ein Objekt (mehrere Materialien möglich)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mat_index = {}

    def mat(self, name):
        if name not in self.mat_index:
            self.mat_index[name] = len(self.mat_index)
        return self.mat_index[name]

    def loft(self, rings, sides, material, cap_bottom=True, cap_top=True, rot=0.0,
             face_material=None):
        """rings: Liste von (y, rx, rz, ox, oz) in Godot-Koordinaten. rx/rz = 0 -> Spitze.
        face_material(ring_i, side_i, center) -> Materialname oder None."""
        mi = self.mat(material)
        loops = []
        for (y, rx, rz, ox, oz, *extra) in rings:
            jag = extra[0] if extra else None
            if rx == 0 and rz == 0:
                loops.append([self.bm.verts.new(g2b((ox, y, oz)))])
                continue
            ring = []
            for i in range(sides):
                a = rot + 2 * math.pi * i / sides
                yy = y + (jag(i) if jag else 0.0)
                ring.append(self.bm.verts.new(g2b((ox + math.cos(a) * rx, yy, oz + math.sin(a) * rz))))
            loops.append(ring)
        for li in range(len(loops) - 1):
            a, b = loops[li], loops[li + 1]
            for i in range(sides):
                if len(a) == 1 and len(b) == 1:
                    continue
                if len(a) == 1:
                    vs = [a[0], b[(i + 1) % sides], b[i]]
                elif len(b) == 1:
                    vs = [a[i], a[(i + 1) % sides], b[0]]
                else:
                    vs = [a[i], a[(i + 1) % sides], b[(i + 1) % sides], b[i]]
                f = self.bm.faces.new(vs)
                f.material_index = mi
                if face_material:
                    c = f.calc_center_median()
                    fm = face_material(li, i, c)
                    if fm:
                        f.material_index = self.mat(fm)
        if cap_bottom and len(loops[0]) > 1:
            f = self.bm.faces.new(list(reversed(loops[0])))
            f.material_index = mi
        if cap_top and len(loops[-1]) > 1:
            f = self.bm.faces.new(loops[-1])
            f.material_index = mi
        return loops

    def box(self, center, size, material, rot_y=0.0, rot_x=0.0, rot_z=0.0):
        mi = self.mat(material)
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = res["verts"]
        from mathutils import Matrix
        m = (Matrix.Translation(g2b(center))
             @ Matrix.Rotation(rot_y, 4, "Z") @ Matrix.Rotation(rot_x, 4, "X") @ Matrix.Rotation(-rot_z, 4, "Y")
             @ Matrix.Diagonal((size[0], size[2], size[1], 1.0)))
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mi

    def quad(self, pts, material):
        f = self.bm.faces.new([self.bm.verts.new(g2b(p)) for p in pts])
        f.material_index = self.mat(material)
        return f

    def jitter(self, amount, seed):
        rnd = random.Random(seed)
        for v in self.bm.verts:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * amount

    def build(self, location=(0, 0, 0), collection=None, scale=1.0):
        if scale != 1.0:
            vec = scale if isinstance(scale, tuple) else (scale, scale, scale)
            bmesh.ops.scale(self.bm, vec=vec, verts=self.bm.verts)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for name, _ in sorted(self.mat_index.items(), key=lambda kv: kv[1]):
            me.materials.append(MATS[name])
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        ob.location = g2b(location)
        (collection or bpy.context.scene.collection).objects.link(ob)
        return ob


def jag(amount, seed, sides):
    rnd = random.Random(seed)
    vals = [rnd.uniform(-amount, amount * 0.3) for _ in range(sides)]
    return lambda i: vals[i % sides]


# ------------------------------------------------------------------
# Proportionen (Godot-Meter). Gedrungen: großer Kopf/Kapuze, kurzer Rumpf, kurze Spitzbeine.
# ------------------------------------------------------------------

HIP_Y = 0.78
CHEST_Y = HIP_Y + 0.04  # Brust-Gelenk
HEAD_Y = CHEST_Y + 0.64
HEAD_SCALE = 0.8  # kleinerer Kopf, weniger Chibi
THIGH = 0.38
SHIN = 0.43
UPPER_ARM = 0.29
LOWER_ARM = 0.33
SHOULDER_X = 0.21
SHOULDER_Y = CHEST_Y + 0.43


def build_dummy(col):
    p = Part("DummyBase")
    p.loft([(0.0, 0.44, 0.44, 0, 0), (0.12, 0.42, 0.42, 0, 0), (0.24, 0.32, 0.32, 0, 0)], 6, "Stone")
    p.jitter(0.015, 5)
    p.build((3.0, 0, 0), col)
    p = Part("DummyBody")  # Ursprung = Wackel-Gelenk über dem Sockel
    p.loft([(0.0, 0.065, 0.065, 0, 0), (1.55, 0.055, 0.055, 0, 0)], 5, "Wood")
    p.loft([(1.05, 0.05, 0.05, -0.55, 0), (1.05, 0.05, 0.05, 0.55, 0)], 5, "Wood")  # Querbalken (flach)
    p.box((0, 1.08, 0), (1.15, 0.08, 0.08), "Wood")
    p.loft([(0.55, 0.2, 0.17, 0, 0), (0.75, 0.29, 0.22, 0, 0), (1.0, 0.27, 0.2, 0, 0),
            (1.2, 0.2, 0.16, 0, 0), (1.28, 0.08, 0.07, 0, 0)], 7, "Straw")
    p.loft([(0.6, 0.23, 0.19, 0, 0), (0.78, 0.3, 0.23, 0, 0)], 7, "Rag", rot=0.3)
    p.loft([(1.3, 0.12, 0.12, 0, 0), (1.42, 0.19, 0.18, 0, 0), (1.6, 0.17, 0.16, 0, 0), (1.72, 0.0, 0.0, 0, 0)], 6, "Straw")
    p.jitter(0.012, 9)
    for sx in (-1, 1):
        p.box((0.06 * sx, 1.5, -0.17), (0.07, 0.02, 0.02), "Leather", rot_z=0.3 * sx)
    p.build((3.0, 0.25, 0), col)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out_dir = os.path.abspath(args[0] if args else ".")
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    # Die alte Shade-Figur ist ersetzt (Frayed-Stil, tools/frayed_export); hier nur noch die Puppe.
    dummy = bpy.data.collections.new("TrainingDummy")
    bpy.context.scene.collection.children.link(dummy)
    build_dummy(dummy)
    # .blend liegt außerhalb des Godot-Imports (art/ hat eine .gdignore)
    blend_dir = os.path.join(os.path.dirname(os.path.dirname(out_dir)), "art", "blender")
    os.makedirs(blend_dir, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, "dummy_parts.blend"))
    for name, coll in (("dummy_parts", dummy),):
        bpy.ops.object.select_all(action="DESELECT")
        for o in coll.objects:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + ".glb"), export_format="GLB",
                                  use_selection=True, export_yup=True, export_apply=False,
                                  export_normals=True, export_materials="EXPORT")
    print("OK", out_dir)


main()
