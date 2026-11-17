#!/usr/bin/env bash
# Gera builds/linux/FPSArenaLAN.x86_64 (o jogo inteiro num único executável)
# e builds/FPSArenaLAN-linux.tar.gz para distribuir (o tar guarda a permissão
# de execução, que um .zip perde).
# Precisa do template linux_release.x86_64 4.7.2 em
#   ~/.local/share/godot/export_templates/4.7.2.stable/
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-./tools/bin/Godot_v4.7.2-stable_linux.x86_64}"
mkdir -p builds/linux
"$GODOT" --headless --path . --import
# O shader baker precisa de GPU: com tela, exporta sem --headless (os shaders
# vão pré-compilados e o primeiro tiro não trava). Sem tela (CI), exporta assim mesmo.
EXPORT_FLAGS=()
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
	echo "Aviso: sem tela; exportando sem pré-compilar shaders."
	EXPORT_FLAGS=(--headless)
fi
"$GODOT" "${EXPORT_FLAGS[@]}" --path . --export-release "Linux" builds/linux/FPSArenaLAN.x86_64
chmod +x builds/linux/FPSArenaLAN.x86_64
cp -f "LEIA-ME Linux.txt" builds/linux/
tar -czf builds/FPSArenaLAN-linux.tar.gz -C builds linux
echo "Pronto: builds/linux/FPSArenaLAN.x86_64 e builds/FPSArenaLAN-linux.tar.gz"
