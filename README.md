# Underground Roguelite – Solo-Prototyp

Low-Poly Action-Roguelite in Godot 4.7. Dieser Stand ist ein Testlevel mit drei Räumen,
um Steuerung, Kamera und Kampfgefühl auszuprobieren. Die Figuren (Shades, Trainingspuppe)
sind in Blender gebaut, die Level-Geometrie entsteht noch prozedural im Code.

## Modelle (Blender)

- Quelle: `tools/blender/build_shade.py` baut alle Teile per Skript.
- Ergebnis: `art/blender/shade_parts.blend` zum Ansehen und Bearbeiten und
  `assets/models/*.glb` für Godot.
- Jedes Körperteil ist ein eigenes Objekt mit dem Gelenk als Ursprung. Godot animiert die Teile
  prozedural (`scripts/player/shadow_body.gd`).
- Materialnamen wie `Cloth`, `Trim`, `Scarf` und `Eye` werden in Godot je nach Figur umgefärbt.
- Wer in der .blend etwas von Hand ändert, exportiert danach die Collection „Shade“ als
  `assets/models/shade_parts.glb` (glTF, +Y oben). Objektnamen nicht ändern.
Alle Texte im Spiel sind Englisch, Code-Kommentare und Doku Deutsch.

## Starten

1. Godot 4.7 öffnen, **Importieren** und die `project.godot` in diesem Ordner wählen.
2. **F5** startet das Spiel (Hauptszene `scenes/main.tscn`).

## Steuerung

| Eingabe | Aktion |
|---|---|
| WASD | laufen |
| Linke Maus halten | Kamera frei drehen |
| Rechte Maus halten | Kamera drehen, Charakter schaut mit (A/D = seitwärts) |
| Beide Maustasten | vorwärts laufen und lenken, WASD wird dazugerechnet |
| Mausrad | Zoom |
| Leertaste | springen (halten = höher, antippen = kleiner Hüpfer) |
| Shift | rollen in Laufrichtung (kurz unverwundbar, kostet Ausdauer) |
| Q halten | blocken (Ausdauer statt Leben). Q kurz vor dem Treffer = Parade |
| Tab | nächstes Ziel |
| Linksklick auf Gegner | Gegner anvisieren |
| 1 / 2 | Heavy Strike / Shield Bash |
| F1 / F2 / F3 / Esc | Hilfe / Steuerungsmodus / Debug-Anzeige / Pause |

Der **Standardangriff läuft automatisch** (wie Auto-Attack in WoW), sobald das Ziel in
Reichweite und vor dem Charakter ist. Ein Ziel wird automatisch nach Nähe gewählt.
Fähigkeiten auf 1–9 ersetzen den Auto-Angriff für ihre Dauer.

**F2** schaltet zwischen zwei Steuerungsmodi um:
- *Hybrid* (Standard): WASD läuft relativ zur Kamera, der Charakter dreht sich in Laufrichtung.
- *Klassisch*: wie WoW-Standard, A/D drehen den Charakter, die Kamera schwenkt hinterher.

## Die drei Räume

1. **Hall of Pillars** – Laufen, Springen, Rampe und Plattform-Parcours mit Lücke.
2. **Training Yard** – drei Trainingspuppen für Auto-Angriff und Fähigkeiten.
3. **Sealed Hall** (tiefer gelegen, mit versiegeltem Tor) – drei Hollow Shades, die zurückschlagen.
   Die Augen glühen beim Ausholen auf. Dann blocken, parieren oder durchrollen.
   Besiegte Gegner erscheinen nach einigen Sekunden neu.

## Game-Feel-Bausteine

Werte stehen als `@export` im Inspector und lassen sich live anpassen (`scripts/player/player.gd`).

- **Input-Buffer** 0,15 s: Rollen, Springen und Fähigkeiten werden vorgemerkt und
  ausgeführt, sobald es geht (z. B. am Ende einer Rolle).
- **Coyote Time** 0,1 s, variable Sprunghöhe, stärkere Fall- als Steiggravitation.
- **Rolle**: Unverwundbarkeit ab dem ersten Frame (0,32 s), Tempo vorne hoch und hinten weich,
  ab 0,36 s abbrechbar, rollt durch Gegner hindurch.
- **Auto-Angriff als Oberkörper-Animation**: Laufen wird nie blockiert. Rollen oder Blocken
  bricht den Schwung ab, und der nächste kommt dann schneller.
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
  enemies/                Enemy-Basis, Training Dummy, Hollow Shade
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

## Automatischer Spieltest

```
godot --headless --path . tools/smoke_test.tscn
```
Der Test prüft Laufen, Sprunghöhe, Rolle, Ausdauer, Auto-Angriff, Tab-Zielwechsel,
Fähigkeiten mit Abklingzeit, Gegnertreffer und Blocken.

## Animationswerkstatt (Animation Workshop)

Die Kampfanimationen (Auto-Hiebe Vorhand/Rückhand, Heavy Strike) sind Keyframe-Daten in
`data/anims/*.json`. Das Spiel lädt sie beim Start; bearbeitet werden sie in der Werkstatt:

1. In Godot `tools/anim_workshop.tscn` öffnen und mit **F6** (aktuelle Szene starten) laufen lassen.
2. Oben die Animation wählen. Zeitleiste unten: klicken = springen, Raute ziehen = Timing eines Keys ändern,
   rote Linie = Trefferzeitpunkt, heller Bereich = Klingen-Trail.
3. In der 3D-Ansicht die Kugeln mit der linken Maustaste ziehen:
   gelb = Schwertgriff, cyan = Klingenspitze, orange = Schild, kleine orange = Schild-Ausrichtung.
   Steht an der aktuellen Zeit noch kein Key, wird automatisch einer angelegt.
   Rote Griff-Kugel = der Arm erreicht diese Position nicht.
4. Rechts: Werte des Keys (Körperdrehung, Vorlage, Hüfte absenken, genaue Koordinaten),
   Dauer, Trefferzeitpunkt, Trail-Fenster.
5. **Check clip** prüft die ganze Animation darauf, ob Klinge oder Arm durch den Körper gehen.
6. **Save** (Strg+S) schreibt die JSON-Datei, danach im Spiel sofort aktiv.

Start und Ende jeder Animation sind immer die aktuelle Grundhaltung (z. B. Kampfhaltung),
dadurch gibt es keine harten Übergänge. Steuerung: RMB ziehen = Kamera drehen, MMB = verschieben,
Mausrad = Zoom, Leertaste = abspielen, K = Key setzen, Entf = Key löschen, Pfeile = Zeit/Keys, Strg+Z = rückgängig.
