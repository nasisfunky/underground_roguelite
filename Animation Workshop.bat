@echo off
rem Startet die Animationswerkstatt direkt (ohne Godot-Editor).
set GODOT=G:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot nicht gefunden: %GODOT%
  echo Bitte den Pfad oben in dieser Datei anpassen.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." res://tools/anim_workshop.tscn
