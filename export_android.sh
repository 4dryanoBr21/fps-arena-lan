#!/usr/bin/env bash
# Gera builds/android/FPSArenaLAN.apk (assinado com a chave de release).
# Precisa de: templates 4.7.2 com android_release.apk em
#   ~/.local/share/godot/export_templates/4.7.2.stable/
# Android SDK em ~/Android/Sdk (build-tools) e a chave em
#   ~/.local/share/godot/keystores/fps-arena-release.{keystore,env}
#
#   ./export_android.sh            APK para celulares (ARM)
#   ./export_android.sh --teste    APK que também roda em emulador x86_64
#   ./export_android.sh --install  gera e instala no celular via USB (adb)
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-./tools/bin/Godot_v4.7.2-stable_linux.x86_64}"
KEYS="${KEYS:-$HOME/.local/share/godot/keystores/fps-arena-release.env}"
if [[ -f "$KEYS" ]]; then
	set -a; source "$KEYS"; set +a
fi
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/jre}"

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
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
	echo "Aviso: sem tela; exportando sem pré-compilar shaders."
	EXPORT_FLAGS=(--headless)
fi
"$GODOT" "${EXPORT_FLAGS[@]}" --path . --export-release "$PRESET" "$APK"
cp -f "LEIA-ME Android.txt" builds/android/
echo "Pronto: $APK"
if [[ " $* " == *" --install "* ]]; then
	adb install -r "$APK"
fi
