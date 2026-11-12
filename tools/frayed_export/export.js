/* Export der Kultur-Figuren für Godot: GLB mit Teilen je Gelenk + JSON mit Stoff-Definitionen */
(function () {
  const T = THREE, PI = Math.PI, V3 = T.Vector3;
  // JS-Gelenk -> Godot-Gelenk (ShadowBody) und JS-Gelenk, dessen Raum dem Godot-Gelenk entspricht
  const MAP = { hips: ['hips', 'hips'], chest: ['chest', 'chest'], neck: ['head', 'head'], head: ['head', 'head'] };
  for (const [s, g] of [['L', 'l'], ['R', 'r']]) {
    Object.assign(MAP, {
      ['thigh' + s]: ['hip_' + g, 'thigh' + s], ['shin' + s]: ['knee_' + g, 'shin' + s], ['tip' + s]: ['knee_' + g, 'shin' + s],
      ['clav' + s]: ['chest', 'chest'], ['up' + s]: ['arm_up_' + g, 'up' + s], ['fore' + s]: ['arm_lo_' + g, 'fore' + s], ['hand' + s]: ['arm_lo_' + g, 'fore' + s]
    });
  }
  const ROTY = new T.Matrix4().makeRotationY(PI);
  // JS-Waffe (Klinge +Y, Breite X, flach Z) -> Godot-Waffe (Klinge -Z, Breite Y, Flachseite X)
  const WEAPON = new T.Matrix4().set(0, 0, -1, 0, 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 1);

  function nameMaterials(M) {
    const names = new Map();
    for (const k in M) { names.set(M[k], k); if (M[k].userData && M[k].userData.weave) names.set(M[k].userData.weave, k + '_W') }
    return names;
  }
  const conv = new Map(); let anon = 0;
  function exportMat(m, names) {
    if (conv.has(m)) return conv.get(m);
    let out;
    const name = names.get(m) || ('Tex' + (anon++));
    if (m.isMeshBasicMaterial) { out = m.clone() }
    else {
      out = new T.MeshStandardMaterial({ color: m.color.clone(), map: m.map || null, roughness: m.roughness ?? 1, metalness: m.metalness ?? 0,
        emissive: m.emissive ? m.emissive.clone() : new T.Color(0), emissiveMap: m.emissiveMap || null, side: T.DoubleSide, transparent: m.transparent, opacity: m.opacity });
      if (m.emissiveIntensity !== undefined) out.emissive.multiplyScalar(m.emissiveIntensity);
      if (m.isMeshPhongMaterial) { out.roughness = 1; out.metalness = 0 }
    }
    out.name = name; out.side = T.DoubleSide; conv.set(m, out); return out;
  }
  // Geometrie in Zielraum backen, nur position/normal/uv behalten, nicht indiziert
  function bake(geo, mat4, keep) {
    let g = geo.index ? geo.toNonIndexed() : geo.clone();
    g.applyMatrix4(mat4);
    const out = new T.BufferGeometry();
    out.setAttribute('position', g.attributes.position);
    if (!g.attributes.normal) g.computeVertexNormals();
    out.setAttribute('normal', g.attributes.normal);
    for (const k of keep) {
      if (g.attributes[k]) out.setAttribute(k, g.attributes[k]);
      else if (k === 'uv') out.setAttribute('uv', new T.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
    }
    // Spiegelung (negative Determinante) -> Wicklung umdrehen
    if (mat4.determinant() < 0) flipWinding(out);
    return out;
  }
  function flipWinding(g) {
    for (const k in g.attributes) { const a = g.attributes[k], n = a.itemSize, arr = a.array;
      for (let i = 0; i < a.count; i += 3) for (let c = 0; c < n; c++) { const t = arr[(i + 1) * n + c]; arr[(i + 1) * n + c] = arr[(i + 2) * n + c]; arr[(i + 2) * n + c] = t } a.needsUpdate = true }
  }
  function concat(geos) {
    const out = new T.BufferGeometry(); if (!geos.length) return null;
    for (const k in geos[0].attributes) {
      const n = geos[0].attributes[k].itemSize, total = geos.reduce((s, g) => s + g.attributes[k].count, 0), arr = new Float32Array(total * n); let o = 0;
      for (const g of geos) { arr.set(g.attributes[k].array.subarray(0, g.attributes[k].count * n), o); o += g.attributes[k].count * n }
      out.setAttribute(k, new T.BufferAttribute(arr, n));
    }
    return out;
  }
  // mehrere (Geometrie, Material) zu einem Mesh mit Gruppen
  function multiMesh(name, list) {
    const byMat = new Map();
    for (const [g, m] of list) { if (!byMat.has(m)) byMat.set(m, []); byMat.get(m).push(g) }
    const geos = [], mats = []; for (const [m, gs] of byMat) { geos.push(concat(gs)); mats.push(m) }
    const g = concat(geos); let start = 0;
    { const n = g.attributes.position.count, idx = new (n > 65535 ? Uint32Array : Uint16Array)(n); for (let i = 0; i < n; i++) idx[i] = i; g.setIndex(new T.BufferAttribute(idx, 1)) }
    geos.forEach((q, i) => { g.addGroup(start, q.attributes.position.count, i); start += q.attributes.position.count });
    const mesh = new T.Mesh(g, mats.length === 1 ? mats[0] : mats); mesh.name = name; return mesh;
  }
  function meshesUnder(obj, stop) {
    const out = [];
    (function rec(o) { for (const c of o.children) { if (stop(c)) continue; if (c.isMesh) out.push(c); rec(c) } })(obj);
    return out;
  }

  window.exportCult = function (key) {
    window.__EXP = null; conv.clear(); anon = 0;
    const d = window.SHADE_BUILDS['c_' + key]({});
    const j = d.j, E = window.__EXP, TB = window.__TABLES, C = TB.CULT[key];
    j.root.updateMatrixWorld(true);
    const jointOf = new Map(); for (const k in j) if (j[k] && j[k].isObject3D && k !== 'root') jointOf.set(j[k], k);
    // Material-Namen aus dem Materialsatz der Figur (Skin-Material = Material der Körperteile)
    const M = window.__MATS.Skin;
    const names = new Map();
    // Materialien über alle Meshes sammeln, Namen über die gemeinsamen Schlüssel aus CMAT/GEAR finden
    const matKeys = window.__MATS || {}; for (const k in matKeys) { names.set(matKeys[k], k); if (matKeys[k].userData && matKeys[k].userData.weave) names.set(matKeys[k].userData.weave, k + '_W') }
    const excluded = new Set();
    for (const h of E.holds) { excluded.add(h.obj); excluded.add(h.fg) }
    for (const sh of E.shields) excluded.add(sh);
    if (d.lamp && d.lamp.parent && d.lamp.parent.parent === j.hips) excluded.add(d.lamp.parent);
    const scene = new T.Scene();
    const toTarget = (fromObj, jsKey) => {
      const [gk, frameKey] = MAP[jsKey]; const fr = j[frameKey];
      const m = new T.Matrix4().copy(fr.matrixWorld).invert().multiply(fromObj.matrixWorld);
      if (frameKey.startsWith('up') || frameKey.startsWith('fore')) m.premultiply(ROTY);
      return [gk, m];
    };
    const parts = {}; const add = (gk, kind, g, m) => { const k = kind + '_' + gk; (parts[k] || (parts[k] = [])).push([g, m]) };
    let headHem = null;
    const gripHands = new Set(E.holds.map(h => h.s));
    for (const [joint, jk] of jointOf) {
      if (!MAP[jk]) continue;
      const ms = meshesUnder(joint, c => jointOf.has(c) || excluded.has(c) || c.isLight);
      // Gruppen mit Flammenhüllen: Hüllen-Geometrie (mit Maske) ersetzt das schwarze Teil
      const shellGroups = new Set(ms.filter(m => m.material.isShaderMaterial).map(m => m.parent));
      const seen = new Set();
      for (const m of ms) {
        const [gk, mat4] = toTarget(m, jk);
        if (m.material.isShaderMaterial) {
          if (seen.has(m.geometry)) continue; seen.add(m.geometry);
          const g0 = m.geometry, isHead = !!g0.attributes.aR;
          const g = bake(g0, mat4, []);
          const src = g0.index ? g0.toNonIndexed() : g0, n = g.attributes.position.count, col = new Float32Array(n * 4);
          for (let i = 0; i < n; i++) {
            col[i * 4 + 3] = src.attributes.aM.getX(i);
            if (isHead) { col[i * 4] = src.attributes.aD.getX(i) * .5 + .5; col[i * 4 + 1] = src.attributes.aD.getY(i) * .5 + .5; col[i * 4 + 2] = src.attributes.aD.getZ(i) * .5 + .5 }
            else { col[i * 4] = col[i * 4 + 1] = col[i * 4 + 2] = .5 }
          }
          g.setAttribute('color', new T.BufferAttribute(col, 4));
          if (isHead) { const uv = new Float32Array(n * 2); for (let i = 0; i < n; i++) uv[i * 2] = src.attributes.aR.getX(i); g.setAttribute('uv', new T.BufferAttribute(uv, 2)) }
          // Hüllen zeigen nach außen (Wicklung gegen den Uhrzeigersinn)
          if (g0.userData.flip) flipWinding(g);
          if (isHead) headHem = g; else add(gk, 'S', g, 'hem');
          continue;
        }
        if (m.material === M) {
          if (shellGroups.has(m.parent)) continue;
          const g = bake(m.geometry, mat4, []), n = g.attributes.position.count, col = new Float32Array(n * 4).fill(.5);
          for (let i = 0; i < n; i++) col[i * 4 + 3] = 0;
          g.setAttribute('color', new T.BufferAttribute(col, 4)); add(gk, 'S', g, 'hem'); continue;
        }
        add(gk, 'G', bake(m.geometry, mat4, ['uv']), exportMat(m.material, names));
      }
    }
    const skinMat = new T.MeshBasicMaterial({ color: 0x000000 }); skinMat.name = 'Skin';
    for (const k in parts) {
      if (k.startsWith('S_')) { const g = concat(parts[k].map(p => p[0])); const mesh = new T.Mesh(g, skinMat); mesh.name = k; scene.add(mesh) }
      else scene.add(multiMesh(k, parts[k]));
    }
    if (headHem) { const mesh = new T.Mesh(headHem, skinMat); mesh.name = 'HeadHem'; scene.add(mesh) }
    // Waffen: Griffmitte im Ursprung
    const info = { culture: key, name: C.name, heat: C.heat, hot: C.hot, hem: C.hem, hemH: C.hemH, body: C.body || {}, gripHands: [...gripHands], ST: TB.ST, SEAT: TB.SEAT };
    for (const h of E.holds) {
      const main = h.s === 'R';
      const inv = new T.Matrix4().copy(h.obj.matrixWorld).invert();
      const shift = new T.Matrix4().makeTranslation(0, -h.gripAt, 0);
      const frame = main ? new T.Matrix4().multiplyMatrices(WEAPON, shift) : shift;
      let lantern = null; if (!main) h.obj.traverse(o => { if (!lantern && o.isGroup && o.children.some(c => c.isLight)) lantern = o });
      const list = [];
      for (const m of meshesUnder(h.obj, c => c === lantern)) list.push([bake(m.geometry, new T.Matrix4().multiplyMatrices(frame, inv).multiply(m.matrixWorld), ['uv']), exportMat(m.material, names)]);
      for (const m of meshesUnder(h.fg, () => false)) list.push([bake(m.geometry, new T.Matrix4().multiplyMatrices(frame, inv).multiply(m.matrixWorld), ['uv']), (m.material === M ? skinMat : exportMat(m.material, names))]);
      scene.add(multiMesh(main ? 'Weapon' : 'Offhand', list));
      if (main) {
        let tip = 0; for (const [g] of list) { const p = g.attributes.position; for (let i = 0; i < p.count; i++) tip = Math.max(tip, -p.getZ(i)) }
        info.weaponLength = +tip.toFixed(3);
      }
      if (lantern) {
        const li = new T.Matrix4().copy(lantern.matrixWorld).invert(), ll = [];
        for (const m of meshesUnder(lantern, () => false)) ll.push([bake(m.geometry, new T.Matrix4().multiplyMatrices(li, m.matrixWorld), ['uv']), exportMat(m.material, names)]);
        scene.add(multiMesh('OffhandLantern', ll));
        const lp = new V3().setFromMatrixPosition(lantern.matrixWorld).applyMatrix4(new T.Matrix4().multiplyMatrices(frame, inv));
        const light = lantern.children.find(c => c.isLight);
        info.offhandLantern = { pos: lp.toArray().map(v => +v.toFixed(4)), light: light.position.toArray() };
      }
    }
    for (const sh of E.shields) {
      const inv = new T.Matrix4().copy(sh.matrixWorld).invert(), list = [];
      for (const m of meshesUnder(sh, () => false)) list.push([bake(m.geometry, new T.Matrix4().multiplyMatrices(inv, m.matrixWorld), ['uv']), exportMat(m.material, names)]);
      scene.add(multiMesh('Shield', list));
    }
    // Stoffe: Ruhelage im Godot-Gelenkraum, Material über ein Platzhalter-Mesh
    info.cloths = [];
    E.cloths.forEach((c, i) => {
      const jk = jointOf.get(c.joint); const [gk, mat4] = toTarget(c.joint, jk);
      const def = { joint: gk, cols: c.cols, rows: c.rows, loc: c.loc.map(l => l.clone().applyMatrix4(mat4).toArray().map(v => +v.toFixed(5))), bend: c.o.bend ?? .25, damp: c.o.damp ?? .985 };
      if (c.mesh) {
        def.mat = 'C' + i + '_mat'; def.us = c.o.us ?? 1; def.vs = c.o.vs ?? 1; def.v0 = c.o.v0 ?? 0;
        const g = new T.BufferGeometry(); g.setAttribute('position', new T.Float32BufferAttribute([0, 0, 0, .001, 0, 0, 0, .001, 0], 3)); g.setAttribute('normal', new T.Float32BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)); g.setAttribute('uv', new T.Float32BufferAttribute([0, 0, 1, 0, 0, 1], 2));
        const mm = new T.Mesh(g, exportMat(c.mesh.material, names)); mm.name = def.mat; scene.add(mm);
      }
      if (c.segs) {
        def.segs = c.segs.map((sg, k) => { const list = meshesUnder(sg, () => false).map(m => { sg.updateMatrixWorld(true); const inv = new T.Matrix4().copy(sg.matrixWorld).invert(); return [bake(m.geometry, inv.multiply(m.matrixWorld), ['uv']), exportMat(m.material, names)] }); const mesh = multiMesh('C' + i + '_s' + k, list); scene.add(mesh); return mesh.name });
        def.segL = c.o.segL;
      }
      if (c.endG) { c.endG.updateMatrixWorld(true); const inv = new T.Matrix4().copy(c.endG.matrixWorld).invert(); const list = meshesUnder(c.endG, () => false).map(m => [bake(m.geometry, new T.Matrix4().multiplyMatrices(inv, m.matrixWorld), ['uv']), exportMat(m.material, names)]); const mesh = multiMesh('C' + i + '_end', list); scene.add(mesh); def.end = mesh.name }
      info.cloths.push(def);
    });
    return new Promise(res => new T.GLTFExporter().parse(scene, buf => {
      const b = new Uint8Array(buf); let s = ''; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode.apply(null, b.subarray(i, i + 8192));
      res({ glb: btoa(s), info });
    }, { binary: true }));
  };
})();
