# Export der Frayed-Figuren (Konzeptseite -> Godot)

Die Spielfiguren im Frayed-Stil entstehen auf der Konzeptseite "Frayed Cultures" (three.js r128,
Quellen in den Projektdateien unter `concepts/frayed_cultures/`). Dieses Skript exportiert sie
für Godot:

- `assets/models/shade_<kultur>.glb`: Teile je Gelenk der `ShadowBody`
  (`S_<gelenk>` schwarzer Körper mit Flammenmaske in der Vertex-Farbe, `G_<gelenk>` Ausrüstung,
  `HeadHem` Kopfflamme mit Frisur, `Weapon`, `Shield`, `Offhand`, `C<n>_*` Stoffteile).
- `data/outfits/<kultur>.json`: Glimmfarben, Frisur, Körperpolster und alle Stoffe
  (Ruhelage im Godot-Gelenkraum).

Ablauf:

1. Arbeitsordner anlegen, `core.js` und `shades.js` der Konzeptseite hineinkopieren,
   dazu `three.min.js` und `examples/js/exporters/GLTFExporter.js` aus three@0.128.0.
2. `python3 patch_frayed.py <konzept>/frayed.js <arbeitsordner>/frayed.js`
3. `exp.html` und `export.js` in den Arbeitsordner kopieren.
4. `node run_export.js <arbeitsordner> <repo>/assets/models <repo>/data/outfits`
5. Godot öffnen (oder `godot --headless --import`), damit die GLBs neu importiert werden.
