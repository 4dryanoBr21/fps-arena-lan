#!/usr/bin/env bash
# Gera a versão de navegador em builds/web/ (index.html + .wasm + .pck) e
# builds/FPSArenaLAN-web.zip para distribuir.
# Sem threads: roda em qualquer servidor HTTP comum, sem cabeçalhos especiais
# (COOP/COEP). Para jogar na LAN, sirva a pasta pelo PC do host com
#   python tools/servir_web.py
# e abra no navegador o endereço que ele mostrar.
# Precisa dos templates web 4.7.2 (web_nothreads_release.zip) em
#   Linux:   ~/.local/share/godot/export_templates/4.7.2.stable/
#   Windows: %APPDATA%\Godot\export_templates\4.7.2.stable\
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${GODOT:-}" ]]; then
	case "$(uname -s)" in
		MINGW*|MSYS*|CYGWIN*) GODOT=./tools/bin/Godot_v4.7.2-stable_win64_console.exe ;;
		*) GODOT=./tools/bin/Godot_v4.7.2-stable_linux.x86_64 ;;
	esac
fi
rm -rf builds/web
mkdir -p builds/web
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Web" builds/web/index.html
cp -f "LEIA-ME Web.txt" builds/web/
rm -f builds/FPSArenaLAN-web.zip
if command -v zip > /dev/null; then
	(cd builds/web && zip -qr ../FPSArenaLAN-web.zip .)
else
	python3 -c "import shutil; shutil.make_archive('builds/FPSArenaLAN-web', 'zip', 'builds/web')" 2>/dev/null \
		|| python -c "import shutil; shutil.make_archive('builds/FPSArenaLAN-web', 'zip', 'builds/web')"
fi
echo "Pronto: builds/web/ e builds/FPSArenaLAN-web.zip"
