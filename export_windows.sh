#!/usr/bin/env bash
# Gera builds/windows/FPSArenaLAN.exe (o jogo inteiro num único .exe).
# Precisa dos templates de exportação 4.7.2 em ~/.local/share/godot/export_templates/4.7.2.stable/
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-./Godot_v4.7.2-stable_linux.x86_64}"
mkdir -p builds/windows
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Windows Desktop" builds/windows/FPSArenaLAN.exe
cp -f "LEIA-ME Windows.txt" "Testar 2 janelas.bat" builds/windows/
echo "Pronto: builds/windows/FPSArenaLAN.exe"
