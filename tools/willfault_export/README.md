# Export der Willfault-Modelle (Konzeptseite -> Godot)

Grimhauler und Willamber entstehen auf der Konzeptseite „Willfaults der Hallen“ (three.js r128,
Quellen in den Projektdateien unter `concepts/willfaults_v3/`, Hauptdatei `willfaults3.js`).
`export_creatures.js` schreibt sie als GLB mit der vollen Knotenhierarchie:

- Gelenke behalten ihre Namen (`hips`, `chest`, `upR`, `armL_lo`, `legR_th`, `Axe`, `Edge` …).
  Die Skripte in `scripts/willfaults/` suchen sie über den Namen und animieren sie wie die Konzeptseite.
- Schattenkörper heißen `Body`, Material `Skin`; die Saummaske steckt im Alpha der Vertex-Farbe
  (wie bei den Shades). Die Kopfflamme heißt `HeadHem`.
- Shader-Materialien werden zu Platzhaltern mit dem Namen der Konzeptseite (`Sh` = wabernder Schatten).

Der Hollow One braucht keinen Export: Er ist ein `ShadowBody` mit `ghost = true` und trägt die
Ausrüstung der Shade-Kulturen (verblasst, verschmutzt, zerrissen).

Ablauf:

1. Arbeitsordner anlegen und hineinkopieren: `core.js`, `shades.js`, `frayed.js`, `willfaults3.js`
   der Konzeptseite, dazu `three.min.js` und `examples/js/exporters/GLTFExporter.js` aus three@0.128.0,
   sowie `exp.html` und `export_creatures.js` aus diesem Ordner.
2. `node run_export.js <arbeitsordner> <repo>/assets/models/willfaults`
3. Godot öffnen (oder `godot --headless --import`), damit die GLBs neu importiert werden.
