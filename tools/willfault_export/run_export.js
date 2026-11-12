// Exportiert Grimhauler und Willamber der Konzeptseite als GLB für Godot (Playwright + three.js r128).
// Aufruf: node run_export.js <arbeitsordner> <ziel-glb-ordner>
// Der Arbeitsordner enthält exp.html, three.min.js, GLTFExporter.js, core.js, shades.js, frayed.js, willfaults3.js, export_creatures.js.
const { chromium } = require('playwright'); const fs = require('fs');
const [dir, outGlb] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist'] });
  const p = await b.newPage(); const errs = [];
  p.on('console', m => { if (m.type() === 'error') errs.push(m.text().slice(0, 200)) });
  p.on('pageerror', e => errs.push('pageerror: ' + e.message));
  await p.goto('file://' + dir + '/exp.html'); await p.waitForTimeout(500);
  for (const k of ['grimhauler', 'willamber']) {
    const r = await p.evaluate(k => window.exportCreature(k), k);
    fs.writeFileSync(`${outGlb}/${k}.glb`, Buffer.from(r.glb, 'base64'));
    console.log(k, (r.glb.length * .75 / 1024).toFixed(0) + ' KB', r.meshes + ' meshes');
  }
  console.log([...new Set(errs)].slice(0, 15).join('\n') || 'no errors');
  await b.close();
})();
