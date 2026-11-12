# Underground Roguelite – Solo-Prototyp

Low-Poly Action-Roguelite in Godot 4.7. Dieser Stand ist ein Testlevel mit vier Räumen,
um Steuerung, Kamera und Kampfgefühl auszuprobieren. Die Shades im Frayed-Stil stammen aus der
Konzeptseite (siehe unten), die Trainingspuppe aus Blender, die Level-Geometrie entsteht prozedural im Code.

## Modelle

- **Shades** (Spieler, Hollowed): Frayed-Stil aus der Konzeptseite, exportiert über
  `tools/frayed_export` nach `assets/models/shade_<kultur>.glb`. Die alte Kapuzen-Figur ist entfernt.
- **Trainingspuppe**: `tools/blender/build_dummy.py` (Blender) baut `assets/models/dummy_parts.glb`.

Alle Texte im Spiel sind Englisch, Code-Kommentare und Doku Deutsch.

## Starten

1. Godot 4.7 öffnen, **Importieren** und die `project.godot` in diesem Ordner wählen.
2. **F5** startet das Spiel (Hauptszene `scenes/main.tscn`).

## Steuerung

| Eingabe | Aktion |
|---|---|
| WASD | laufen (relativ zur Kamera, der Charakter dreht sich in Laufrichtung) |
| Maus | Kamera drehen (Cursor ist im Spiel versteckt) |
| Linksklick | spielt die eigene Kombo-Kette ab (im Rhythmus nachklicken = nächster Baustein) |
| C | Kombo-Baukasten: Kette zusammenstellen, Waffe und Zweithand wählen (pausiert das Spiel) |
| Mittlere Maustaste | Alternativangriff der Waffe, beim Schwert ein Stich (mehr Reichweite und Schaden, schmal) |
| Mausrad | Zoom |
| Leertaste | springen (halten = höher, antippen = kleiner Hüpfer) |
| Shift halten | sprinten (~7 m/s, kostet Ausdauer; leer = erst nach etwas Erholung wieder) |
| Alt links | rollen (kurz unverwundbar, kostet Ausdauer). Ohne Waffe immer vorwärts in Laufrichtung; mit gezogener Waffe relativ zur Kamera: zurück = Rückwärtsrolle, seitlich = Seitenrolle (Blick bleibt vorn) |
| Y | Waffe ziehen oder wegstecken. Mit Y gezogen bleibt sie gezogen; durch Angriff/Block gezogen wird sie nach 6 s ohne Kampf wieder weggesteckt |
| X | Licht vorhalten oder wegstecken. Mit Licht zieht Y nur die Waffe; X steckt das Licht weg und nimmt den Schild |
| Rechte Maustaste (oder Q) halten | blocken in Kamerarichtung (Ausdauer statt Leben). Q kurz vor dem Treffer = Parade |
| 1 / 2 | Heavy Strike / Shield Bash |
| F2 | Kultur der Spielfigur wechseln (The Kiln → Rimefall → Glowmire) |
| F1 / F3 / Esc | Hilfe / Debug-Anzeige / Pause (gibt den Cursor frei) |

**Ausrüstung:** Einhandwaffe hängt an der linken Hüfte (Säbel und Klinge in einer Scheide, die Axt in einer
Schlaufe), der Schild auf dem Rücken, die Laterne an der rechten Hüfte (Glowmire: Laternenstab schräg auf
dem Rücken). Ohne Waffe in der Hand schwingen die Arme beim Gehen gegengleich zu den Beinen, beim Sprint angewinkelt.

**Klettern:** gegen Gitter oder Flechten laufen. WASD klettert, Leertaste springt von der Wand weg,
Alt lässt los. Oben über eine Kante zieht sich die Figur selbst hoch. Klettern kostet Ausdauer
(Festhalten weniger); ist sie leer, fällt man.

**Schwimmen** (kein Tauchen): Kopf und Schultern bleiben über Wasser. Shift = schneller schwimmen (Ausdauer).
Gegen eine niedrige Kante schwimmen (oder Leertaste) = rausklettern. Waffen und Licht werden beim Klettern
und Schwimmen weggesteckt, das Licht kommt danach wieder.

**Stürze** ab 3,2 m: die Figur rollt sich beim Aufkommen ab, nach vorn, oder nach hinten, wenn vorn kein Platz ist.

## Kombo-Baukasten (Prototyp)

Linksklick spielt eine Kette aus bis zu 5 Bausteinen von links nach rechts ab (leere Plätze und Bausteine
anderer Waffen werden übersprungen; nach 1,4 s ohne Angriff beginnt die Kette vorn). Es gibt keine richtige
oder falsche Reihenfolge: Bausteine **erzeugen** Zustände am Gegner oder ändern den Abstand, und jeder Baustein
**reagiert** auf das, was gerade da ist. Zustände halten einige Sekunden, auch wenn andere Bausteine dazwischen kommen.

- **Reeling** (taumelt, kann nicht angreifen), **Bound** (Klinge gebunden, kann nicht angreifen),
  **Mark** (Lichtmal, bis 3 Stapel). Über dem Gegner als Text, Ring und kreisende Lichtsplitter angezeigt.
- Allgemein: Cut, Backcut, Low Sweep, Shove, Shadow Hook, Bind, Brand Lunge, Kindle (Finisher), Sever (Finisher).
- Waffeneigen: Riposte (Klinge), Impale + Haft Sweep (Speer), Cleave + Beard Hook (Zweihandaxt), Flurry + Slip (Dolch).
- Code: `scripts/combat/combo_module.gd` (Basis), `scripts/combat/combo_modules.gd` (alle Bausteine),
  Zustände und erzwungene Bewegung in `scripts/enemies/enemy.gd`, Menü `scripts/ui/combo_menu.gd`.

**Waffen** (`scripts/combat/weapon_def.gd`): Kulturklinge; Speer (einhändig mit Schild/Dolch/Licht, beidhändig mit freier
linker Hand: mehr Reichweite und Schaden); Zweihandaxt (immer beidhändig, mit Licht einhändig; langsam, schwer);
Dolch (schnell, kurz). Der Dolch geht auch in der Zweithand statt Schild und sticht nach jedem Hieb nach.
Speer und Axt hängen auf dem Rücken. Im Wardens' Ring steht eine Puppengruppe für Bausteine gegen mehrere Ziele.

Es gibt **kein Anvisieren**: Angriffe gehen in Kamerarichtung und treffen alles im Bogen davor.
Jeder Hieb kostet Ausdauer. Während eines Hiebs läuft der Charakter kaum weiter und
verlagert sein Gewicht kurz vor dem Treffer nach vorn.

## Die vier Räume

1. **The Threshold** – Tor nach Vigil, Laufen, Springen, Rampe und Trümmer-Parcours.
2. **Wardens' Ring** – drei Trainingspuppen für Angriffe und Fähigkeiten.
3. **The Sunken Gate** (tiefer gelegen, mit versiegeltem Tor) – Willfaults:
   - **Hollowed** (zwei): humanoide Willfaults, zersplitterte Schatten früherer Shades mit Resten ihrer
     Ausrüstung. Die violetten Augen glühen beim Ausholen auf. Dann blocken, parieren oder durchrollen.
   - **Splinterkin** (Rudel aus vier): lauern am Kristall, weil Willfaults vom Licht angezogen werden.
     Sie umkreisen die Laterne, immer nur einer duckt sich (Augen glühen) und springt geradeaus.
     Seitlich ausweichen oder rollen, danach ist er kurz wehrlos.
   Besiegte Gegner erscheinen nach einigen Sekunden neu.
4. **The Drowned Cistern** (Seitenhalle östlich vom Wardens' Ring) – Bewegung ausprobieren:
   - Becken mit Wasser im Cel-Look (`assets/shaders/water_toon.gdshader`, Vorbild Wind Waker: zwei Farbstufen,
     weißer Schaumrand, wandernde Schaumlinien), Rampe zum Hineinwaten, niedrige Kante zum Rausklettern.
   - Gitterturm (4 m): Eisengitter hochklettern, oben über die Kante ziehen. Von oben ins Becken springen,
     nach Osten abspringen (Abrollen vorwärts) oder nach Norden zur Wand (Abrollen rückwärts).
   - Flechtenturm (7,5 m): mit voller Ausdauer knapp zu schaffen, oben ein Kristall.
   - Flechtenwand an der Nordwand: ohne Ende, irgendwann ist die Ausdauer leer und man stürzt.
   - Lange Wege durch Gang und Halle zum Sprinten, eine Puppe zum Ausprobieren von Ziehen/Wegstecken.

## Bestiarium: neue Willfaults

`scenes/bestiary.tscn` (oder `Willfault Bestiary.bat`) zeigt die drei neuen Willfaults in einer dunklen Halle.
Sie ersetzen noch keine Gegner und haben noch keine Kampf-KI.

- **Grimhauler**: verzerrter Koloss aus Schattenflamme, schleift seine Axt (Funken) und schlägt über Kopf zu.
  Die Schneide glüht vorher weiß-violett auf: Der Schlag ist nicht blockbar. Einschlag mit Schockwelle.
- **Hollow One**: verblassender Wille in der alten Ausrüstung eines Shades (Kiln, Rimefall oder Glowmire,
  verschmutzt und zerrissen). Heller Geisterschleier ohne Beine, schwebt, Augen als schwarze Kreise mit weißem Rand.
- **Willambers**: hagere Wesen aus wabernden Schatten mit leuchtenden Augen. Tauchen aus Schattenlachen auf,
  springen sprunghaft umher, greifen im Schwarm an und tauchen wieder ab.

| Eingabe | Aktion |
|---|---|
| Linke Maustaste ziehen / Mausrad | Kamera drehen / Zoom |
| 1 / 2 / 3 | Grimhauler / Hollow One / Willambers |
| Leertaste | unterwegs ↔ Angriff |
| L | helles ↔ dunkles Licht |
| C | Kultur des Hollow One wechseln |

Modelle: `assets/models/willfaults/*.glb` aus der Konzeptseite, Export siehe `tools/willfault_export/README.md`.

## Spielfigur im Frayed-Stil

Die Shades sind manifestierte Schatten: schwarzer Körper mit flackerndem Flammensaum, am Kopf als
Frisur. Ausrüstung im Stil der Herkunfts-Kaverne, wählbar mit F2:

- **The Kiln**: Kobalt-Glasurhemd, Messing, Krummsäbel, Keramik-Buckler.
- **Rimefall**: Filz und Knochen, Frostglas-Axt, Fellschild.
- **Glowmire**: Lack und Sporenperlen, schmale Klinge, Papierlaterne am Bambusstab (kein Schild,
  Blocken mit der Klinge, die Laterne ersetzt die Gürtellaterne).

Modelle kommen aus der Konzeptseite (Export: `tools/frayed_export/`), der Flammensaum ist ein Shader
(`assets/shaders/frayed_hem.gdshader`), hängende Stoffe, Bänder und Perlenschnüre simuliert
`scripts/player/frayed_cloth.gd` mit Körperkollision. Vorschau aller Kulturen:
`godot --path . tools/preview_frayed.tscn -- <ordner>`, Willfaults: `tools/preview_willfaults.tscn`.

## Game-Feel-Bausteine

Werte stehen als `@export` im Inspector und lassen sich live anpassen (`scripts/player/player.gd`).

- **Input-Buffer** 0,15 s: Rollen, Springen und Fähigkeiten werden vorgemerkt und
  ausgeführt, sobald es geht (z. B. am Ende einer Rolle).
- **Coyote Time** 0,1 s, variable Sprunghöhe, stärkere Fall- als Steiggravitation.
- **Rolle**: Unverwundbarkeit ab dem ersten Frame (0,32 s), Tempo vorne hoch und hinten weich,
  ab 0,36 s abbrechbar, rollt durch Gegner hindurch.
- **Angriffe mit Eingabepuffer**: Ein Klick bis 0,5 s vor dem Kombofenster wird vorgemerkt.
  Rollen bricht einen Hieb ab.
- **Treffer-Feedback**: Hitstop (40–120 ms), Screenshake, Funken, Schadenszahlen, Aufblitzen.
- **Kamera** mit Kollision und weichem Nachführen, folgt der interpolierten Position
  (Physik 60 Hz mit Interpolation, also flüssig bei 144 Hz).

## Aufbau

```
scripts/
  autoload/game.gd        Eingabebelegung, Spielerliste, Licht-Abfrage
  core/low_poly.gd        Flat-Shading-Helfer, Palette, Grundformen
  player/                 Controller, Eingabe, WoW-Kamera, prozedurale Spielfigur
  abilities/              Fähigkeiten-Basis + Heavy Strike, Shield Bash
  combat/                 DamageInfo, Hitbox, Hurtbox
  enemies/                Enemy-Basis, Training Dummy, Willfaults (Hollowed, Splinterkin)
  fx/                     Funken, Zahlen, Staub, Schwungspur
  ui/                     HUD, Aktionsleiste, Zielmarker
  level/test_level.gd     baut die drei Räume
tools/                    Entwicklerwerkzeuge (Spieltest, Screenshots)
```

**Vorbereitet für später**
- *Koop (bis 4)*: Der Spieler-Controller liest nur einen `PlayerInput`. Für Mitspieler wird
  diese Eingabequelle ausgetauscht. Gegner suchen über `Game.nearest_player()` und nicht über
  „den“ Spieler.
- *Schatten/Licht*: Alle Lichtquellen sind in der Gruppe `light_sources`, und
  `Game.light_level_at(pos)` liefert die Helligkeit an einer Stelle (F3 zeigt sie an).
  Darauf bauen später Mechaniken wie „durch Schatten gleiten“ und „zu Licht teleportieren“ auf.

## Arbeitsweisen (aus dem Shooter-Projekt übernommen)

### Level ohne Z-Fighting
Zwei Flächen, die in einer Ebene liegen, in dieselbe Richtung schauen und sich überlappen,
flackern beim Bewegen der Kamera durcheinander. Deshalb:

- **Beim Bauen vermeiden:** Was auf einer Fläche liegt, steht mindestens 1 cm davon ab oder steckt
  sichtbar darin, nie bündig. Abziehbilder (Brandflecken, Ringe) liegen 2–3 cm über dem Boden.
  Wandteile, die sich treffen, bekommen unterschiedliche Höhen/Tiefen oder überlappen deutlich.
- **Automatisch reparieren:** Am Ende des Levelaufbaus schiebt `ZFight.fix()` Kisten, deren
  Flächen bündig aufeinanderliegen, ein paar Zentimeter auseinander (die kräftigere wächst, jede
  höchstens 4-mal; dünne Teile melden sich im Protokoll, die sollte man beim Bauen absetzen).
- **Prüfen:** Der automatische Test scannt alle sichtbaren Dreiecke des Levels (`ZFight.scan()`)
  und schlägt fehl, wenn noch Flächenpaare flackern; er nennt beide Teile und den Ort.
  Nicht gezählt wird, was niemand sieht: Flächen, die nach unten schauen, Stellen, an denen etwas
  dagegensteht, und Flächen gleicher Farbe.
- **Jede Kartenänderung:** Test laufen lassen, Z-Fighting muss 0 sein.

### Feuer (`scripts/fx/flames.gd`)
`Flames.fire(parent, pos, size)` baut ein Feuer aus Schichten:
Flammenzungen (aufrechte Quads mit prozeduralen Flammen-Texturen, nur um die Hochachse zur Kamera
gedreht, additiv, Farbverlauf hell → orange → tiefrot), ein weiß-gelber Kern, aufwirbelnde Glut,
eine dünne Rauchsäule und ein Licht, das über multiplizierte Sinuswellen flackert.

### Explosionen (`scripts/fx/explosion.gd`)
`Explosion.spawn(parent, pos, size)`; zeitlich gestaffelt: Blitzkern und Lichtstoß, Feuerball aus
per Rauschen ausgebeulten Wolken mit Hitze-Rampe (weiß → orange → rot → Rauch, stirbt durch
Erosion statt Ausblenden), Funkenstreifen entlang der Flugbahn, Felssplitter, Staubring,
bleibender Brandfleck, danach die Rauchsäule. Farben gestuft, passend zu den harten Facetten.
**F4** im Spiel zündet eine Test-Explosion vor dem Spieler.

## Automatischer Spieltest

```
godot --headless --path . tools/smoke_test.tscn
```
Der Test prüft Laufen, Sprunghöhe, Rolle, Ausdauer, Hiebe, Kombo, Stich,
Fähigkeiten mit Abklingzeit, Gegnertreffer und Blocken.

```
godot --headless --fixed-fps 60 --path . tools/movement_test.tscn
```
Prüft Tastenbelegung (Alt links, Shift, Y auf QWERTZ), Ziehen/Wegstecken (Gürtel, Rücken, Hand am Griff,
automatisches Wegstecken), Licht vorhalten und Schild-Tausch, natürliche Armbewegung, Sprint und Erschöpfung,
Rollen in alle Richtungen (Richtung, Blick, kein Eintauchen in den Boden), Abrollen nach Stürzen,
Klettern (Tempo, Ausdauer, Rand, Absprung, Hochziehen, Absturz bei leerer Ausdauer), Schwimmen ohne Tauchen,
Reinspringen, Rausklettern und Rauswaten.

```
godot --headless --fixed-fps 60 --path . tools/combat_test.tscn
```
Prüft die Kombo-Kette (Reihenfolge, Überspringen, Zurücksetzen, Ausdauer), alle Zustände und Reaktionen
(Wrench, Pinned, Throw, Snap, Pursuit, Spread, Kindle, Disarm), Ziehen/Stoßen, einen gebundenen Hollowed,
die Waffen (Reichweite, beidhändiger Griff, Zweithand-Dolch, Axt mit Licht) und das Menü.

`tools/move_strips.tscn -- <ordner>` (mit Grafik) speichert Filmstreifen aller Bewegungsabläufe zum Begutachten.

## Animationswerkstatt (Animation Workshop)

In Godot `tools/anim_workshop.tscn` öffnen und mit **F6** starten. Oben drei Modi:

**Animations** – alle Kampfanimationen (`data/anims/*.json`: Hiebe, Stich, Heavy, Shove, Sweep, Hook, Bind, Sever, Rake, Flurry).
- Oben Waffe, Zweithand und Kultur wählen; die Figur trägt dann genau das.
- Zeitleiste unten: klicken = springen, Raute ziehen = Timing ändern, rote Linie = Treffer, heller Bereich = Trail.
- Kugeln in der 3D-Ansicht ziehen: gelb = Griff, cyan = Spitze, orange = Zweithand, kleine orange = deren Ausrichtung.
  Ohne Key an der aktuellen Zeit wird einer angelegt. Rote Griff-Kugel = Arm erreicht die Stelle nicht.
- Rechts in Reitern: **Hands** (Griff, Klingenrichtung, Zweithand), **Body** (Drehung, Vorlage, Seitneigung, Hüfte
  absenken/drehen/verschieben, Kopf, Ellbogen), **Legs** (je Bein vor/zurück, abspreizen, Knie), **Timing**
  (Dauer, Treffer, Trail, Check whole clip). Körperwerte sind Zusätze auf die automatische Haltung (0 = unverändert).
- Copy/Paste (Strg+C/V) überträgt eine ganze Pose auf einen anderen Zeitpunkt, Clean setzt die Körperzusätze zurück.
- **Own version for this weapon**: eigene Fassung der Animation nur für die gewählte Waffe
  (`data/anims/<clip>@<waffe>.json`); ohne eigene Fassung nutzt jede Waffe die allgemeine.

**Weapon poses** – Haltungen je Waffe (`data/poses/<waffe>.json`): Standing, Walking, Combat stance,
die beidhändigen Varianten (Abstand der linken Hand am Schaft einstellbar) und **Stowed** (wo die Waffe weggesteckt hängt).
Die Kulturklingen haben je Kultur eine eigene Datei (kiln/rimefall/glowmire).

**Stowed gear** – für alle Waffen gleich (`data/poses/gear.json`): Schild auf dem Rücken, Zweithand-Dolch am Gürtel,
Laterne am Gürtel und vorgehalten.

**Enemies** – Gegneranimationen, komplett aus Keyframes.
- Splinterkin, Grimhauler, Willambers und das Schweben des Hollow One: je Aktion (z. B. Scuttling, Overhead slam,
  Strike, Hovering) eine Reihe Keys, jeder Key ist die ganze Haltung (Gelenkdrehungen in Grad, Positionen von
  Körper und Füßen in m). Dazwischen weich interpoliert, beim Wechsel der Aktion kurz übergeblendet.
  Automatisch bleiben nur Bein-IK zu den Fuß-Keys, die Axt in der Hand, Schattenfäden und Effekte.
  Ohne Datei gilt die Startfassung: die frühere prozedurale Bewegung, beim Start abgetastet und auf wenige Keys
  verdichtet. **Reset key** / **Reset whole action** holen sie zurück. Gespeichert werden nur geänderte Aktionen
  (`data/enemy_anims/<gegner>.json`, Format-Version 2; ältere Dateien im Zusatz-Format werden ignoriert).
- Hollowed (Shade-Körper): Angriff, Taumeln und Tod sind normale Animationen ("Enemy: Hollowed strike / staggered /
  death", im Animationsmodus mit allen Reitern; die Figur sieht dort wie der Gegner aus). Beim Angriff ist das
  Trail-Fenster die Schlagphase. Der Tod nutzt "Hold last pose at the end" und die Körperwerte Fall over / Sink.
  Gehen und Stehen teilt der Hollowed vorerst mit der Spielfigur.
- Hollow One: die Arme beim Schlag sind der Clip "Enemy: Hollow One strike".

**Save** (Strg+S) schreibt die Datei des aktuellen Modus, im Spiel sofort aktiv. **Revert** lädt die Datei neu,
Strg+Z macht rückgängig. Fehlt eine Datei, gelten die eingebauten Vorgaben.
Kamera: RMB ziehen = drehen, MMB = verschieben, Mausrad = Zoom, Front/Side/3/4/Back/Top = feste Ansichten.
Im Animationsmodus: Leertaste = abspielen, K = Key setzen, Entf = Key löschen, Pfeile = Zeit/Keys.
