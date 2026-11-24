#!/usr/bin/env bash
# Gera builds/android/FPSArenaLAN.apk (assinado com a chave de release).
# Precisa de: templates 4.7.2 com android_release.apk em
#   ~/.local/share/godot/export_templates/4.7.2.stable/
# Android SDK (build-tools) e a chave de release:
#   Linux:   ~/Android/Sdk e ~/.local/share/godot/keystores/fps-arena-release.{keystore,env}
#   Windows: %LOCALAPPDATA%\Android\Sdk e %APPDATA%\Godot\keystores\fps-arena-release.{keystore,env}
# (o caminho do SDK e do Java ficam nas Configurações do Editor do Godot, em Export > Android).
# Roda no Linux ou no Windows (Git Bash).
#
#   ./export_android.sh            APK para celulares (ARM)
#   ./export_android.sh --teste    APK que também roda em emulador x86_64
#   ./export_android.sh --install  gera e instala no celular via USB (adb)
set -euo pipefail
cd "$(dirname "$0")"
ON_WINDOWS=false
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=true ;; esac
if $ON_WINDOWS; then
	GODOT="${GODOT:-./tools/bin/Godot_v4.7.2-stable_win64_console.exe}"
	KEYS="${KEYS:-$APPDATA/Godot/keystores/fps-arena-release.env}"
	if [[ -z "${JAVA_HOME:-}" ]]; then
		JAVA_HOME="$(ls -d "/c/Program Files/Eclipse Adoptium"/jdk-17* 2>/dev/null | head -1)"
	fi
else
	GODOT="${GODOT:-./tools/bin/Godot_v4.7.2-stable_linux.x86_64}"
	KEYS="${KEYS:-$HOME/.local/share/godot/keystores/fps-arena-release.env}"
	JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/jre}"
fi
export JAVA_HOME
if [[ -f "$KEYS" ]]; then
	set -a; source "$KEYS"; set +a
else
	echo "Aviso: chave de release não encontrada ($KEYS)."
fi

PRESET="Android"
APK="builds/android/FPSArenaLAN.apk"
if [[ " $* " == *" --teste "* ]]; then
	PRESET="Android (teste x86_64)"
	APK="builds/android/FPSArenaLAN-teste.apk"
fi

mkdir -p builds/android
"$GODOT" --headless --path . --import
# O shader baker precisa de GPU: com tela, exporta sem --headless (os shaders
# vão pré-compilados e o primeiro tiro não trava). Sem tela (CI), exporta assim mesmo.
EXPORT_FLAGS=()
if ! $ON_WINDOWS && [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
	echo "Aviso: sem tela; exportando sem pré-compilar shaders."
	EXPORT_FLAGS=(--headless)
fi
"$GODOT" "${EXPORT_FLAGS[@]}" --path . --export-release "$PRESET" "$APK"
cp -f "LEIA-ME Android.txt" builds/android/
echo "Pronto: $APK"
if [[ " $* " == *" --install "* ]]; then
	adb install -r "$APK"
fi
