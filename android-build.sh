#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "${PROJECT_DIR:-$PWD}" && pwd)"
PROJECT_NAME="$(basename "$ROOT_DIR")"
ANDROID_DIR="$ROOT_DIR/native/android"
GRADLEW="$ANDROID_DIR/gradlew"
SOURCE_APK_PATH="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
OUTPUT_DIR="$ROOT_DIR/dist/android"
OUTPUT_APK_PATH="$OUTPUT_DIR/${PROJECT_NAME}-android-debug.apk"
OPEN_DIR_AFTER_BUILD="${OPEN_DIR_AFTER_BUILD:-1}"

log() {
  printf '[build-android] %s\n' "$*" >&2
}

fail() {
  printf '[build-android] %s\n' "$*" >&2
  exit 1
}

open_dir() {
  local dir="$1"

  [[ "$OPEN_DIR_AFTER_BUILD" == "1" ]] || return 0

  if command -v open >/dev/null 2>&1; then
    open "$dir"
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$dir"
    return 0
  fi

  log "skip open dir: no opener found"
}

build_apk() {
  [[ -x "$GRADLEW" ]] || fail "missing gradlew: $GRADLEW"

  log "build debug apk"
  (
    cd "$ANDROID_DIR"
    "$GRADLEW" assembleDebug
  )

  [[ -f "$SOURCE_APK_PATH" ]] || fail "apk not found: $SOURCE_APK_PATH"
}

collect_apk() {
  mkdir -p "$OUTPUT_DIR"
  cp "$SOURCE_APK_PATH" "$OUTPUT_APK_PATH"
}

main() {
  build_apk
  collect_apk
  open_dir "$OUTPUT_DIR"

  log "done"
  log "project: $PROJECT_NAME"
  log "apk: $OUTPUT_APK_PATH"
}

main "$@"
