// Exportiert die drei Kultur-Figuren der Konzeptseite als GLB + JSON für Godot (Playwright + three.js r128).
// Aufruf: node run_export.js <arbeitsordner> <ziel-glb-ordner> <ziel-json-ordner>
// Der Arbeitsordner enthält exp.html, three.min.js, GLTFExporter.js, core.js, shades.js, frayed.js (gepatcht), export.js.
const { chromium } = require('playwright'); const fs = require('fs');
const [dir, outGlb, outJson] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist'] });
  const p = await b.newPage(); const errs = [];
  p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.text().slice(0, 200)) });
  p.on('pageerror', e => errs.push('pageerror: ' + e.message));
  await p.goto('file://' + dir + '/exp.html'); await p.waitForTimeout(500);
  for (const k of ['kiln', 'rimefall', 'glowmire']) {
    const r = await p.evaluate(k => window.exportCult(k), k);
    fs.writeFileSync(`${outGlb}/shade_${k}.glb`, Buffer.from(r.glb, 'base64'));
    fs.writeFileSync(`${outJson}/${k}.json`, JSON.stringify(r.info));
    console.log(k, (r.glb.length * .75 / 1024).toFixed(0) + ' KB', 'cloths', r.info.cloths.length, 'weapon', r.info.weaponLength);
  }
  console.log([...new Set(errs)].slice(0, 15).join('\n') || 'no errors');
  await b.close();
})();
