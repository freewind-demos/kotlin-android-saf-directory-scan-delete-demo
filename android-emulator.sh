#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kotlin-android-saf-directory-scan-delete-demo"
MODULE_DIR="app"
APPLICATION_ID="demos.safdir"
AVD_NAME="Pixel_7_API_35"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
APK_DIRS=("$PWD/dist/android" "$PWD/app/build/outputs/apk")
APK_SOURCE_DIR=""

apks=()
for apk_dir in "${APK_DIRS[@]}"; do
  current_apks=()
  if [[ -d "$apk_dir" ]]; then
    while IFS= read -r apk_path; do
      current_apks+=("$apk_path")
    done < <(/usr/bin/find "$apk_dir" -type f -name '*.apk' | sort)
  fi
  if [[ "${#current_apks[@]}" -gt 0 ]]; then
    apks=("${current_apks[@]}")
    APK_SOURCE_DIR="$apk_dir"
    break
  fi
done

if [[ "${#apks[@]}" -eq 0 ]]; then
  echo "APK not found under:" >&2
  printf '  %s\n' "${APK_DIRS[@]}" >&2
  echo "Run ./android-build.sh first" >&2
  exit 1
fi

if [[ "${#apks[@]}" -ne 1 ]]; then
  echo "Expected exactly one APK under $APK_SOURCE_DIR, got ${#apks[@]}:" >&2
  printf '%s\n' "${apks[@]}" >&2
  exit 1
fi

APK_PATH="${apks[0]}"

find_online_emulator() {
  "$ADB" devices | awk '$1 ~ /^emulator-/ && $2 == "device" { print $1; exit }'
}

find_any_emulator() {
  "$ADB" devices | awk '$1 ~ /^emulator-/ { print $1; exit }'
}

wait_for_online_emulator() {
  for _ in $(seq 1 360); do
    SERIAL="$(find_online_emulator)"
    [[ -n "$SERIAL" ]] && return 0

    OFFLINE_SERIAL="$(find_any_emulator)"
    if [[ -n "$OFFLINE_SERIAL" ]]; then
      "$ADB" reconnect offline >/dev/null 2>&1 || true
    fi

    sleep 2
  done

  return 1
}

wait_for_package_service() {
  for _ in $(seq 1 360); do
    STATE="$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)"
    if [[ "$STATE" == "device" ]]; then
      BOOTED="$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      PACKAGE_READY="$("$ADB" -s "$SERIAL" shell cmd package path android 2>/dev/null | tr -d '\r' || true)"
      if [[ "$BOOTED" == "1" && "$PACKAGE_READY" == package:* ]]; then
        return 0
      fi
    else
      "$ADB" reconnect offline >/dev/null 2>&1 || true
    fi

    sleep 2
  done

  return 1
}

SERIAL="$(find_online_emulator)"

if [[ -z "$SERIAL" ]]; then
  CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  HV_SUPPORT="$(sysctl -n kern.hv_support 2>/dev/null || echo 0)"
  EMULATOR_ARGS=(-avd "$AVD_NAME" -no-snapshot-load -netdelay none -netspeed full)

  if [[ "$HV_SUPPORT" != "1" || "$CPU_BRAND" == *AMD* ]]; then
    EMULATOR_ARGS+=(-accel off -gpu swiftshader_indirect -no-audio)
  fi

  "$EMULATOR" "${EMULATOR_ARGS[@]}" >/tmp/android-emulator-"$PROJECT_NAME".log 2>&1 &

  wait_for_online_emulator || true
  SERIAL="$(find_online_emulator)"
fi

if [[ -z "$SERIAL" ]]; then
  echo "No emulator device found" >&2
  exit 1
fi

"$ADB" -s "$SERIAL" wait-for-device

if ! wait_for_package_service; then
  echo "Emulator package service timeout: $SERIAL" >&2
  echo "Emulator log: /tmp/android-emulator-$PROJECT_NAME.log" >&2
  exit 1
fi

"$ADB" -s "$SERIAL" install -r "$APK_PATH"
"$ADB" -s "$SERIAL" shell monkey -p "$APPLICATION_ID" -c android.intent.category.LAUNCHER 1
echo "$SERIAL"

