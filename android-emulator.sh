#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "${PROJECT_DIR:-$PWD}" && pwd)"
PROJECT_NAME="$(basename "$ROOT_DIR")"
ANDROID_DIR="$ROOT_DIR/native/android"
GRADLEW="$ANDROID_DIR/gradlew"
APK_PATH="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
APP_BUILD_FILE="$ANDROID_DIR/app/build.gradle.kts"
EMULATOR_LOG_PATH="/tmp/${PROJECT_NAME}-android-emulator.log"

APP_ID="${APP_ID:-}"

log() {
  printf '[dev-android] %s\n' "$*" >&2
}

fail() {
  printf '[dev-android] %s\n' "$*" >&2
  exit 1
}

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB_BIN="${ADB_BIN:-$SDK_ROOT/platform-tools/adb}"
EMULATOR_BIN="${EMULATOR_BIN:-$SDK_ROOT/emulator/emulator}"

[[ -x "$GRADLEW" ]] || fail "missing gradlew: $GRADLEW"
[[ -x "$ADB_BIN" ]] || fail "missing adb: $ADB_BIN"

resolve_app_id() {
  if [[ -n "$APP_ID" ]]; then
    printf '%s\n' "$APP_ID"
    return 0
  fi

  [[ -f "$APP_BUILD_FILE" ]] || fail "missing app build file: $APP_BUILD_FILE"

  APP_ID="$(
    rg -o --replace '$1' 'applicationId\s*=\s*"([^"]+)"' "$APP_BUILD_FILE" \
      | head -n 1
  )"
  [[ -n "$APP_ID" ]] || fail "cannot resolve applicationId from: $APP_BUILD_FILE"
  printf '%s\n' "$APP_ID"
}

list_running_emulators() {
  "$ADB_BIN" devices | while read -r serial state _; do
    if [[ "$serial" == emulator-* && "$state" == device ]]; then
      printf '%s\n' "$serial"
    fi
  done
}

first_running_emulator() {
  while read -r serial; do
    if [[ -n "$serial" ]]; then
      printf '%s\n' "$serial"
      return 0
    fi
  done < <(list_running_emulators)
  return 1
}

pick_avd_name() {
  if [[ -n "${AVD_NAME:-}" ]]; then
    printf '%s\n' "$AVD_NAME"
    return 0
  fi

  [[ -x "$EMULATOR_BIN" ]] || return 1

  while read -r avd; do
    if [[ -n "$avd" ]]; then
      printf '%s\n' "$avd"
      return 0
    fi
  done < <("$EMULATOR_BIN" -list-avds)

  return 1
}

wait_for_boot() {
  local serial="$1"
  local booted=""

  "$ADB_BIN" -s "$serial" wait-for-device >/dev/null

  for _ in $(seq 1 120); do
    booted="$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [[ "$booted" == "1" ]]; then
      "$ADB_BIN" -s "$serial" shell input keyevent 82 >/dev/null 2>&1 || true
      return 0
    fi
    sleep 2
  done

  fail "emulator boot timeout: $serial"
}

ensure_emulator() {
  local serial=""
  local avd_name=""

  if serial="$(first_running_emulator)"; then
    log "reuse emulator: $serial"
    wait_for_boot "$serial"
    printf '%s\n' "$serial"
    return 0
  fi

  avd_name="$(pick_avd_name)" || fail "no running emulator, no AVD found; set AVD_NAME or create one first"
  [[ -x "$EMULATOR_BIN" ]] || fail "missing emulator: $EMULATOR_BIN"

  log "start emulator: $avd_name"
  nohup "$EMULATOR_BIN" -avd "$avd_name" >"$EMULATOR_LOG_PATH" 2>&1 &

  for _ in $(seq 1 120); do
    if serial="$(first_running_emulator)"; then
      wait_for_boot "$serial"
      printf '%s\n' "$serial"
      return 0
    fi
    sleep 2
  done

  fail "emulator start timeout: $avd_name"
}

build_apk() {
  log "build debug apk"
  (
    cd "$ANDROID_DIR"
    "$GRADLEW" assembleDebug
  )
  [[ -f "$APK_PATH" ]] || fail "apk not found: $APK_PATH"
}

install_and_launch() {
  local serial="$1"
  local app_id="$2"

  log "install apk -> $serial"
  "$ADB_BIN" -s "$serial" install -r "$APK_PATH"

  log "launch app -> $app_id"
  "$ADB_BIN" -s "$serial" shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1 >/dev/null
}

main() {
  local serial=""
  local app_id=""

  app_id="$(resolve_app_id)"

  serial="${ANDROID_SERIAL:-}"
  if [[ -n "$serial" ]]; then
    log "use ANDROID_SERIAL: $serial"
    wait_for_boot "$serial"
  else
    serial="$(ensure_emulator)"
  fi

  build_apk
  install_and_launch "$serial" "$app_id"

  log "done"
  log "apk: $APK_PATH"
  log "app_id: $app_id"
  log "project: $PROJECT_NAME"
  log "serial: $serial"
}

main "$@"
