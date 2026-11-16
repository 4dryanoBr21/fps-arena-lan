#!/usr/bin/env bash
# Gera builds/android/FPSArenaLAN.apk (assinado com a chave de release).
# Precisa de: templates 4.7.2 com android_release.apk em
#   ~/.local/share/godot/export_templates/4.7.2.stable/
# Android SDK em ~/Android/Sdk (build-tools) e a chave em
#   ~/.local/share/godot/keystores/fps-arena-release.{keystore,env}
# Com o celular ligado no USB (depuração USB ativa): ./export_android.sh --install
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-./Godot_v4.7.2-stable_linux.x86_64}"
KEYS="$HOME/.local/share/godot/keystores/fps-arena-release.env"
set -a; source "$KEYS"; set +a
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/jre}"
mkdir -p builds/android
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Android" builds/android/FPSArenaLAN.apk
cp -f "LEIA-ME Android.txt" builds/android/
echo "Pronto: builds/android/FPSArenaLAN.apk"
if [[ "${1:-}" == "--install" ]]; then
	adb install -r builds/android/FPSArenaLAN.apk
fi
