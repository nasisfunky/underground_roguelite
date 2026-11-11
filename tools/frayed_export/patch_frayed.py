"""Kopiert frayed.js der Konzeptseite und fügt die Export-Haken ein (Waffen, Schilde, Stoffe, Materialien).
Aufruf: python3 patch_frayed.py <konzept-ordner>/frayed.js <ziel>/frayed.js"""
import sys
s = open(sys.argv[1]).read()


def rep(a, b):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, b)


rep("const UP = new V3(0, 1, 0);", "const UP = new V3(0, 1, 0);\n  const EXP = () => window.__EXP || (window.__EXP = { holds: [], shields: [], cloths: [] });")
rep("      p.tube(pts, rad, 7, 'Skin');\n    }\n    fore.add(p.build(M, B));", "      p.tube(pts, rad, 7, 'Skin');\n    }\n    const fg = p.build(M, B); fore.add(fg); EXP().holds.push({ s, obj, fg, gripAt });")
rep("sh.position.set(0, y, 0).addScaledVector(n, off); fore.add(sh);", "sh.position.set(0, y, 0).addScaledVector(n, off); fore.add(sh); EXP().shields.push(sh);")
rep("this.tmp = new V3(); this.tq = new T.Quaternion(); this.down = new V3(0, -1, 0);", "this.tmp = new V3(); this.tq = new T.Quaternion(); this.down = new V3(0, -1, 0); EXP().cloths.push(this);")
rep("Object.assign(window.SHADE_BUILDS, { c_kiln", "window.__TABLES = { ST, SEAT, SL, HEAD, CULT };\n  Object.assign(window.SHADE_BUILDS, { c_kiln")
rep("for (const k of TEXTILE) M[k] = matte(CMAT[k].c);", "for (const k of TEXTILE) M[k] = matte(CMAT[k].c); window.__MATS = M;")
open(sys.argv[2], 'w').write(s)
