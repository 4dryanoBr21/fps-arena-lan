#!/usr/bin/env bash
# Gera builds/linux/FPSArenaLAN.x86_64 (o jogo inteiro num único executável)
# e builds/FPSArenaLAN-linux.tar.gz para distribuir (o tar guarda a permissão
# de execução, que um .zip perde).
# Roda no Linux ou no Windows (Git Bash). Precisa do template linux_release.x86_64 4.7.2 em
#   Linux:   ~/.local/share/godot/export_templates/4.7.2.stable/
#   Windows: %APPDATA%\Godot\export_templates\4.7.2.stable\ 
cd "$(dirname "$0")"
ON_WINDOWS=false
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=true ;; esac
if [[ -z "${GODOT:-}" ]]; then
	if $ON_WINDOWS; then GODOT=./tools/bin/Godot_v4.7.2-stable_win64_console.exe
	else GODOT=./tools/bin/Godot_v4.7.2-stable_linux.x86_64; fi
fi
mkdir -p builds/linux
"$GODOT" --headless --path . --import
# O shader baker precisa de GPU: com tela, exporta sem --headless (os shaders
# vão pré-compilados e o primeiro tiro não trava). Sem tela (CI), exporta assim mesmo.
EXPORT_FLAGS=()
if ! $ON_WINDOWS && [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
	echo "Aviso: sem tela; exportando sem pré-compilar shaders."
	EXPORT_FLAGS=(--headless)
fi
"$GODOT" "${EXPORT_FLAGS[@]}" --path . --export-release "Linux" builds/linux/FPSArenaLAN.x86_64
chmod +x builds/linux/FPSArenaLAN.x86_64
cp -f "LEIA-ME Linux.txt" builds/linux/
if $ON_WINDOWS; then
	# No NTFS o chmod não vale: grava a permissão de execução direto no tar.
	python -c "
import tarfile
def mode(info):
    info.mode = 0o755 if info.isdir() or info.name.endswith('.x86_64') else 0o644
    return info
with tarfile.open('builds/FPSArenaLAN-linux.tar.gz', 'w:gz') as tar:
    tar.add('builds/linux', arcname='linux', filter=mode)
"
else
	tar -czf builds/FPSArenaLAN-linux.tar.gz -C builds linux
fi
echo "Pronto: builds/linux/FPSArenaLAN.x86_64 e builds/FPSArenaLAN-linux.tar.gz"
