"""Baut die Low-Poly-Modelle für Shades und Trainingspuppe in Blender und exportiert sie als glTF.

Aufruf (Blender 4.x):
    blender --background --python tools/blender/build_shade.py -- assets/models
oder mit dem bpy-Modul:
    python tools/blender/build_shade.py assets/models
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


def build_shade(col):
    # --- Becken ---
    p = Part("Pelvis")
    p.loft([(-0.06, 0.11, 0.085, 0, 0), (0.06, 0.13, 0.1, 0, 0)], 6, "Skin")
    p.loft([(0.02, 0.145, 0.115, 0, 0), (0.09, 0.15, 0.12, 0, 0)], 7, "Leather")
    p.box((0.0, 0.055, -0.125), (0.07, 0.07, 0.02), "Trim")  # Gürtelschnalle
    p.build((0, HIP_Y, 0), col)

    # --- Rumpf (am Brustgelenk) ---
    p = Part("Torso")
    p.loft([(0.0, 0.12, 0.09, 0, 0), (0.18, 0.15, 0.11, 0, 0), (0.36, 0.2, 0.135, 0, 0.01),
            (0.47, 0.17, 0.12, 0, 0.01), (0.52, 0.09, 0.08, 0, 0.01)], 6, "Skin", rot=math.pi / 6)
    # gewickelte Stoffbahn um den Bauch
    p.loft([(0.06, 0.14, 0.105, 0, 0), (0.17, 0.16, 0.12, 0, 0)], 6, "ClothDark", rot=0.3)
    p.build((0, CHEST_Y, 0), col)

    # --- Umhang über den Schultern (Poncho mit gezacktem Saum) ---
    p = Part("Mantle")
    p.loft([(0.22, 0.31, 0.26, 0, 0.02, jag(0.05, 3, 7)), (0.31, 0.29, 0.245, 0, 0.02),
            (0.44, 0.2, 0.17, 0, 0.015), (0.52, 0.12, 0.1, 0, 0.01)], 7, "Cloth",
           cap_bottom=False, rot=math.pi / 7)
    p.loft([(0.295, 0.30, 0.255, 0, 0.02), (0.325, 0.293, 0.248, 0, 0.02)], 7, "Trim",
           cap_bottom=False, cap_top=False, rot=math.pi / 7)
    p.build((0, CHEST_Y, 0), col)

    # --- Schal: dicke, schief gewickelte Ringe, verdeckt das untere Gesicht ---
    p = Part("Scarf")
    p.loft([(0.42, 0.2, 0.2, 0, -0.02), (0.48, 0.215, 0.225, 0, -0.035), (0.53, 0.2, 0.215, 0, -0.04)],
           7, "Scarf", rot=0.2)
    p.loft([(0.50, 0.19, 0.2, 0.0, -0.045), (0.555, 0.2, 0.225, 0.0, -0.055), (0.59, 0.17, 0.2, 0.0, -0.05)],
           7, "Scarf", rot=0.7)
    # Knoten an der Seite
    p.loft([(0.42, 0.055, 0.045, 0.17, -0.1), (0.48, 0.07, 0.055, 0.19, -0.11), (0.54, 0.045, 0.04, 0.18, -0.1)],
           5, "Scarf")
    p.build((0, CHEST_Y, 0), col, (0.86, 0.86, 1.0))  # schmaler -> wirkt weniger kopflastig

    p = Part("ScarfTail")  # hängt hinten, schwingt beim Laufen
    w0, w1 = 0.09, 0.06
    p.loft([(0.0, w0, 0.02, 0, 0), (-0.18, w0 * 0.9, 0.02, 0, 0.02), (-0.34, w1, 0.018, 0.01, 0.03),
            (-0.44, 0, 0, 0.02, 0.03)], 4, "Scarf", rot=math.pi / 4)
    p.build((0.08, CHEST_Y + 0.52, 0.17), col)

    # --- Tabard vorne / hinten ---
    for name, z, length, width in [("TabardFront", -0.12, 0.34, 0.15), ("TabardBack", 0.12, 0.40, 0.19)]:
        p = Part(name)
        s = -1 if z < 0 else 1
        hem = [(-width, -length + 0.02), (-width * 0.5, -length - 0.04), (0.0, -length + 0.03),
               (width * 0.5, -length - 0.05), (width, -length)]
        top = [(-width * 0.9, 0.0), (width * 0.9, 0.0)]
        # einfache, leicht gewölbte Stoffplatte mit Zackensaum
        pts_front = [(top[0][0], 0.0, 0.0), (top[1][0], 0.0, 0.0)]
        mid_y = -length * 0.5
        rows = [
            [(-width * 0.9, 0.0, 0.0), (0.0, 0.0, 0.012 * s), (width * 0.9, 0.0, 0.0)],
            [(-width, mid_y, 0.01 * s), (0.0, mid_y, 0.03 * s), (width, mid_y, 0.01 * s)],
            [(hem[0][0], hem[0][1], 0.02 * s), (hem[2][0], hem[2][1], 0.045 * s), (hem[4][0], hem[4][1], 0.02 * s)],
        ]
        mat = "Cloth" if s > 0 else "Cloth"
        for r in range(2):
            for c in range(2):
                a, b, cc, d = rows[r][c], rows[r][c + 1], rows[r + 1][c + 1], rows[r + 1][c]
                p.quad([a, b, cc, d], mat)
                p.quad([d, cc, b, a], "ClothDark")  # Rückseite
        # Zacken
        p.quad([rows[2][0], rows[2][1], (hem[1][0], hem[1][1], 0.035 * s)], mat)
        p.quad([rows[2][1], rows[2][2], (hem[3][0], hem[3][1], 0.035 * s)], mat)
        p.box((0, -0.03, 0.006 * s), (width * 1.9, 0.03, 0.015), "Trim")
        p.build((0, HIP_Y + 0.08, z), col)

    # --- Kopf mit Gesicht und Augen ---
    p = Part("Head")
    p.loft([(-0.15, 0.0, 0.0, 0, 0.0), (-0.1, 0.12, 0.11, 0, 0), (0.02, 0.17, 0.15, 0, 0),
            (0.12, 0.13, 0.12, 0, 0.01), (0.18, 0, 0, 0, 0.02)], 7, "Skin")
    p.build((0, HEAD_Y, 0), col, HEAD_SCALE)

    p = Part("Eyes")
    for sx in (-1, 1):
        cx, cy, cz = 0.062 * sx, 0.01, -0.25
        # schmale, schräge Schlitze: innen tiefer -> entschlossener Blick
        inner, outer = cx - 0.035 * sx, cx + 0.035 * sx
        pts = [(inner, cy - 0.016, cz), (outer, cy + 0.016, cz + 0.01), (outer, cy - 0.004, cz + 0.01), (inner, cy - 0.03, cz)]
        if sx < 0:
            pts = list(reversed(pts))
        p.quad(pts, "Eye")
    p.build((0, HEAD_Y, 0), col, HEAD_SCALE)

    # --- Kopfbedeckungen ---
    def hood_face(li, si, c):
        # Untere vordere Flächen der Kapuze sind die dunkle Gesichtsöffnung
        gz = -c.y  # Blender -> Godot z
        gx = c.x
        if li <= 1 and gz < -0.1 and abs(gx) < 0.16:
            return "Void"
        return None

    p = Part("Hood")
    p.loft([(-0.08, 0.25, 0.25, 0, -0.01), (0.03, 0.245, 0.24, 0, 0.0), (0.13, 0.205, 0.2, 0, 0.03),
            (0.23, 0.14, 0.14, 0, 0.07), (0.30, 0.07, 0.07, 0, 0.12), (0.35, 0, 0, 0, 0.19)],
           7, "Cloth", cap_bottom=False, rot=-math.pi / 2, face_material=hood_face)
    p.loft([(-0.1, 0.26, 0.26, 0, -0.01), (-0.06, 0.255, 0.255, 0, -0.01)], 7, "Trim",
           cap_bottom=False, cap_top=False, rot=-math.pi / 2)
    p.build((0, HEAD_Y, 0), col, HEAD_SCALE)

    p = Part("HornedHelm")
    p.loft([(-0.14, 0.22, 0.22, 0, 0), (0.05, 0.215, 0.215, 0, 0), (0.18, 0.17, 0.17, 0, 0.01),
            (0.26, 0.07, 0.07, 0, 0.02), (0.29, 0, 0, 0, 0.02)], 6, "HelmMetal", cap_bottom=False,
           rot=-math.pi / 2, face_material=lambda li, si, c: "Void" if li == 0 and -c.y < -0.12 and abs(c.x) < 0.12 else None)
    p.box((0, -0.02, -0.215), (0.05, 0.22, 0.04), "HelmMetal")  # Nasenschutz
    for sx in (-1, 1):
        # gebogene Hörner
        pts = []
        for i in range(6):
            t = i / 5
            ang = t * 1.6
            pts.append((0.06 * (1 - t) + 0.001, 0.08 + math.sin(ang) * 0.26 - t * 0.02, 0.0,
                        sx * (0.19 + math.sin(ang * 0.8) * 0.2), 0.02 + (1 - math.cos(ang)) * 0.12))
        rings = [(y, r, r, ox, oz) for (r, y, _, ox, oz) in pts]
        rings[-1] = (rings[-1][0], 0, 0, rings[-1][3], rings[-1][4])
        p.loft(rings, 5, "Bone")
    p.build((0, HEAD_Y, 0), col, HEAD_SCALE)

    p = Part("WideHat")
    p.loft([(-0.02, 0.44, 0.44, 0, 0), (0.02, 0.43, 0.43, 0, 0), (0.2, 0.0, 0.0, 0, 0)], 8, "Cloth")
    p.loft([(-0.14, 0.19, 0.19, 0, 0), (0.0, 0.2, 0.2, 0, 0)], 7, "Void", cap_bottom=False)
    p.build((0, HEAD_Y + 0.08 * HEAD_SCALE, 0), col, HEAD_SCALE)

    # --- Beine: kurz, kräftig oben, laufen in Spitzen aus ---
    for side, sx in (("L", -1), ("R", 1)):
        p = Part("Thigh" + side)
        p.loft([(0.02, 0.08, 0.075, 0, 0), (-0.14, 0.075, 0.07, 0, -0.01), (-THIGH, 0.055, 0.052, 0, 0)],
               5, "Skin", rot=math.pi / 5)
        p.build((sx * 0.085, HIP_Y, 0), col)
        p = Part("Shin" + side)
        p.loft([(0.0, 0.055, 0.052, 0, 0), (-0.17, 0.05, 0.048, 0, -0.012), (-0.31, 0.032, 0.03, 0, -0.008),
                (-SHIN, 0, 0, 0, 0.0)], 5, "Skin", rot=math.pi / 5)
        p.loft([(-0.06, 0.064, 0.06, 0, -0.004), (-0.16, 0.059, 0.056, 0, -0.012)], 5, "Trim", rot=math.pi / 5 + 0.3)
        p.build((sx * 0.085, HIP_Y - THIGH, 0), col)
        # --- Arme: kurz, Spitzen statt Finger ---
        p = Part("UpperArm" + side)
        p.loft([(0.02, 0.058, 0.055, 0, 0), (-0.12, 0.054, 0.05, 0, 0), (-UPPER_ARM, 0.042, 0.04, 0, 0)],
               5, "Skin", rot=math.pi / 5)
        p.build((sx * SHOULDER_X, SHOULDER_Y, 0.02), col)
        p = Part("Forearm" + side)
        p.loft([(0.0, 0.042, 0.04, 0, 0), (-0.165, 0.04, 0.038, 0, 0), (-0.26, 0.03, 0.028, 0, 0),
                (-LOWER_ARM, 0, 0, 0, 0)], 5, "Skin", rot=math.pi / 5)
        p.loft([(-0.05, 0.05, 0.048, 0, 0), (-0.155, 0.047, 0.045, 0, 0)], 5, "Trim", rot=0.4)
        p.build((sx * SHOULDER_X, SHOULDER_Y - UPPER_ARM, 0.02), col)

    # --- Schwert: Griff am Ursprung, Klinge entlang -Z ---
    p = Part("Sword")
    L = 0.78
    hw, ht = 0.042, 0.011

    def sec(z, k):
        return [(0, hw * k, z), (ht * k, 0, z), (0, -hw * k, z), (-ht * k, 0, z)]
    stations = [sec(-0.05, 1.0), sec(-0.45, 1.05), sec(-L * 0.86, 0.85)]
    bm_rings = []
    for s in stations:
        bm_rings.append([p.bm.verts.new(g2b((x, y, z))) for (x, y, z) in s])
    tip = p.bm.verts.new(g2b((0, 0, -L)))
    mi = p.mat("Steel")
    for a, b in zip(bm_rings, bm_rings[1:]):
        for i in range(4):
            f = p.bm.faces.new([a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]])
            f.material_index = mi
    for i in range(4):
        f = p.bm.faces.new([bm_rings[-1][i], bm_rings[-1][(i + 1) % 4], tip])
        f.material_index = mi
    f = p.bm.faces.new(list(reversed(bm_rings[0])))
    f.material_index = mi
    p.box((0, 0, -0.035), (0.03, 0.2, 0.035), "SteelDark")  # Parierstange
    p.box((0, 0.105, -0.03), (0.035, 0.03, 0.05), "SteelDark", rot_x=0.3)
    p.box((0, -0.105, -0.03), (0.035, 0.03, 0.05), "SteelDark", rot_x=-0.3)
    p.box((0, 0, 0.075), (0.032, 0.032, 0.13), "Grip")
    p.box((0, 0, 0.155), (0.045, 0.045, 0.04), "Trim", rot_z=math.pi / 4)
    p.build((0.35, 0.95, -0.25), col)

    # --- Schild: Vorderseite -Z, Ursprung am Griff ---
    p = Part("Shield")
    R = 0.23
    front_z = -0.06
    p.loft([(front_z + 0.035, R * 0.96, R * 0.96, 0, 0), (front_z + 0.01, R, R, 0, 0), (front_z - 0.005, R * 0.93, R * 0.93, 0, 0)],
           8, "ShieldRim", rot=math.pi / 8)
    # Fläche
    p.loft([(front_z - 0.004, R * 0.93, R * 0.93, 0, 0), (front_z - 0.016, R * 0.7, R * 0.7, 0, 0)], 8, "ShieldFace",
           cap_bottom=False, cap_top=False, rot=math.pi / 8)
    p.loft([(front_z - 0.016, R * 0.7, R * 0.7, 0, 0), (front_z - 0.022, R * 0.62, R * 0.62, 0, 0)], 8, "ShieldRim",
           cap_bottom=False, cap_top=False, rot=math.pi / 8)
    p.loft([(front_z - 0.022, R * 0.62, R * 0.62, 0, 0), (front_z - 0.03, R * 0.3, R * 0.3, 0, 0),
            (front_z - 0.065, R * 0.18, R * 0.18, 0, 0), (front_z - 0.075, 0, 0, 0, 0)], 8, "ShieldFace",
           cap_bottom=False, rot=math.pi / 8)
    p.loft([(front_z - 0.07, 0.045, 0.045, 0, 0), (front_z - 0.1, 0, 0, 0, 0)], 4, "Gem", cap_bottom=False)
    p.box((0, 0, 0.0), (0.05, 0.16, 0.04), "Leather")  # Griff innen
    shield = p.build((-0.4, 0.95, -0.2), col)
    # Loft läuft entlang Y; Schild muss entlang Z zeigen -> Mesh um X drehen
    from mathutils import Matrix
    shield.data.transform(Matrix.Rotation(math.radians(90), 4, "X"))


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
    shade = bpy.data.collections.new("Shade")
    bpy.context.scene.collection.children.link(shade)
    build_shade(shade)
    dummy = bpy.data.collections.new("TrainingDummy")
    bpy.context.scene.collection.children.link(dummy)
    build_dummy(dummy)
    # .blend liegt außerhalb des Godot-Imports (art/ hat eine .gdignore)
    blend_dir = os.path.join(os.path.dirname(os.path.dirname(out_dir)), "art", "blender")
    os.makedirs(blend_dir, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, "shade_parts.blend"))
    for name, coll in (("shade_parts", shade), ("dummy_parts", dummy)):
        bpy.ops.object.select_all(action="DESELECT")
        for o in coll.objects:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + ".glb"), export_format="GLB",
                                  use_selection=True, export_yup=True, export_apply=False,
                                  export_normals=True, export_materials="EXPORT")
    print("OK", out_dir)


main()
