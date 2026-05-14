#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "${PROJECT_DIR:-$PWD}" && pwd)"
PROJECT_NAME="$(basename "$ROOT_DIR")"
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

resolve_gradlew() {
  local candidate=""
  local android_match=""
  local root_match=""
  local fallback=""

  for candidate in \
    "${GRADLEW:-}" \
    "${ANDROID_DIR:-}/gradlew"
  do
    [[ -n "$candidate" ]] || continue
    [[ -x "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  while read -r candidate; do
    [[ -x "$candidate" ]] || continue
    case "$candidate" in
      "$ROOT_DIR/native/android/gradlew")
        printf '%s\n' "$candidate"
        return 0
        ;;
      "$ROOT_DIR/android/gradlew"|*/native/android/gradlew|*/android/gradlew)
        [[ -n "$android_match" ]] || android_match="$candidate"
        ;;
      "$ROOT_DIR/gradlew")
        [[ -n "$root_match" ]] || root_match="$candidate"
        ;;
      *)
        [[ -n "$fallback" ]] || fallback="$candidate"
        ;;
    esac
  done < <(fd -a -t f -g 'gradlew' "$ROOT_DIR")

  for candidate in "$android_match" "$root_match" "$fallback"; do
    [[ -n "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  return 1
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
  local gradlew_path="$1"
  local android_dir="$2"
  local apk_path="$3"

  log "build debug apk"
  (
    cd "$android_dir"
    "$gradlew_path" assembleDebug
  )

  [[ -f "$apk_path" ]] || fail "apk not found: $apk_path"
}

collect_apk() {
  local source_apk_path="$1"

  mkdir -p "$OUTPUT_DIR"
  cp "$source_apk_path" "$OUTPUT_APK_PATH"
}

main() {
  local gradlew_path=""
  local android_dir=""
  local source_apk_path=""

  gradlew_path="$(resolve_gradlew)" || fail "missing gradlew under: $ROOT_DIR"
  android_dir="$(cd "$(dirname "$gradlew_path")" && pwd)"
  source_apk_path="$android_dir/app/build/outputs/apk/debug/app-debug.apk"

  build_apk "$gradlew_path" "$android_dir" "$source_apk_path"
  collect_apk "$source_apk_path"
  open_dir "$OUTPUT_DIR"

  log "done"
  log "project: $PROJECT_NAME"
  log "android_dir: $android_dir"
  log "apk: $OUTPUT_APK_PATH"
}

main "$@"
