#!/usr/bin/env bash
# Gera builds/windows/FPSArenaLAN.exe (o jogo inteiro num único .exe).
# Precisa dos templates de exportação 4.7.2 em ~/.local/share/godot/export_templates/4.7.2.stable/
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-./tools/bin/Godot_v4.7.2-stable_linux.x86_64}"
mkdir -p builds/windows
"$GODOT" --headless --path . --import
# O shader baker precisa de GPU: com tela, exporta sem --headless (os shaders
# vão pré-compilados e o primeiro tiro não trava). Sem tela (CI), exporta assim mesmo.
EXPORT_FLAGS=()
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
	echo "Aviso: sem tela; exportando sem pré-compilar shaders."
	EXPORT_FLAGS=(--headless)
fi
"$GODOT" "${EXPORT_FLAGS[@]}" --path . --export-release "Windows Desktop" builds/windows/FPSArenaLAN.exe
cp -f "LEIA-ME Windows.txt" "Testar 2 janelas.bat" builds/windows/
echo "Pronto: builds/windows/FPSArenaLAN.exe"
