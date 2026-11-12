/* Export der Willfault-Modelle der Konzeptseite für Godot: GLB mit der vollen Knotenhierarchie.
   Gelenke behalten ihre Namen (hips, chest, upR, ...), damit Godot sie per Skript animieren kann.
   Flammensaum: Körperteile tragen die Saummaske im Alpha der Vertex-Farbe (wie bei den Shades),
   Kopfflamme heißt HeadHem (Richtung in RGB, Länge in UV.x). Shader-Materialien werden zu Platzhaltern
   mit dem Materialnamen der Konzeptseite (z. B. "Sh" für wabernden Schatten). */
(function () {
  const T = THREE;
  function flipWinding(g) {
    for (const k in g.attributes) { const a = g.attributes[k], n = a.itemSize, arr = a.array;
      for (let i = 0; i < a.count; i += 3) for (let c = 0; c < n; c++) { const t = arr[(i + 1) * n + c]; arr[(i + 1) * n + c] = arr[(i + 2) * n + c]; arr[(i + 2) * n + c] = t } }
  }
  function plain(geo, keep) {
    const g = geo.index ? geo.toNonIndexed() : geo.clone(), out = new T.BufferGeometry();
    out.setAttribute('position', g.attributes.position);
    if (!g.attributes.normal) g.computeVertexNormals();
    out.setAttribute('normal', g.attributes.normal);
    for (const k of keep || []) if (g.attributes[k]) out.setAttribute(k, g.attributes[k]);
    return [out, g];
  }
  window.exportCreature = function (key) {
    const d = window.WILLFAULT_BUILDS['w3_' + key]({});
    const X = d.xp; X.restPose();
    const skip = new Set(X.skip);
    const names = new Map(); for (const k in X.M) names.set(X.M[k], k);
    const conv = new Map(); let anon = 0;
    const named = (n, color) => { const m = new T.MeshBasicMaterial({ color: color || 0 }); m.name = n; return m };
    const skinM = named('Skin'), headHemM = named('HeadHem');
    function mat(m) {
      if (conv.has(m)) return conv.get(m);
      const name = names.get(m) || ('Mat' + (anon++));
      let out;
      if (m.isShaderMaterial) out = named(name, 0x808080);
      else if (m.isMeshBasicMaterial) { out = m.clone(); out.name = name }
      else {
        out = new T.MeshStandardMaterial({ color: m.color.clone(), map: m.map || null, roughness: m.roughness ?? 1, metalness: m.metalness ?? 0,
          emissive: m.emissive ? m.emissive.clone() : new T.Color(0), side: T.DoubleSide });
        if (m.isMeshLambertMaterial || m.isMeshPhongMaterial) { out.roughness = 1; out.metalness = 0 }
        out.name = name;
      }
      conv.set(m, out); return out;
    }
    const copyXf = (a, b) => { b.name = a.name; b.position.copy(a.position); b.quaternion.copy(a.quaternion); b.scale.copy(a.scale) };
    const skinSrc = X.M.Skin;
    function rec(src, dst) {
      const shells = new Set();
      const hasShell = src.children.some(c => c.isMesh && c.material.isShaderMaterial && c.geometry.attributes.aM);
      for (const c of src.children) {
        if (skip.has(c) || c.isLight || c.isPoints || c.isLineSegments) continue;
        let node;
        if (c.isMesh) {
          const m = c.material, g0 = c.geometry;
          if (m.isShaderMaterial && g0.attributes.aM) {
            if (shells.has(g0)) continue; shells.add(g0);
            const isHead = !!g0.attributes.aR;
            const [g, src0] = plain(g0, []), n = g.attributes.position.count, col = new Float32Array(n * 4);
            for (let i = 0; i < n; i++) {
              col[i * 4 + 3] = src0.attributes.aM.getX(i);
              if (isHead) { col[i * 4] = src0.attributes.aD.getX(i) * .5 + .5; col[i * 4 + 1] = src0.attributes.aD.getY(i) * .5 + .5; col[i * 4 + 2] = src0.attributes.aD.getZ(i) * .5 + .5 }
              else col[i * 4] = col[i * 4 + 1] = col[i * 4 + 2] = .5;
            }
            g.setAttribute('color', new T.BufferAttribute(col, 4));
            if (isHead) { const uv = new Float32Array(n * 2); for (let i = 0; i < n; i++) uv[i * 2] = src0.attributes.aR.getX(i); g.setAttribute('uv', new T.BufferAttribute(uv, 2)) }
            if (g0.userData.flip) flipWinding(g);
            node = new T.Mesh(g, isHead ? headHemM : skinM); copyXf(c, node); node.name = isHead ? 'HeadHem' : 'Body';
          } else if (m === skinSrc && hasShell) continue;
          else {
            const [g] = plain(g0, ['uv']);
            node = new T.Mesh(g, m === skinSrc ? skinM : mat(m)); copyXf(c, node);
          }
        } else { node = new T.Object3D(); copyXf(c, node) }
        dst.add(node);
        rec(c, node);
      }
    }
    const scene = new T.Scene(), top = new T.Object3D(); copyXf(X.root, top); top.name = key; top.position.set(0, 0, 0); top.quaternion.identity();
    scene.add(top); rec(X.root, top);
    let count = 0; scene.traverse(o => { if (o.isMesh) count++ });
    return new Promise(res => new T.GLTFExporter().parse(scene, buf => {
      const b = new Uint8Array(buf); let s = ''; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode.apply(null, b.subarray(i, i + 8192));
      res({ glb: btoa(s), meshes: count });
    }, { binary: true }));
  };
})();
