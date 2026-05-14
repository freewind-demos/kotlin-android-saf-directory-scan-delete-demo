#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "${PROJECT_DIR:-$PWD}" && pwd)"
PROJECT_NAME="$(basename "$ROOT_DIR")"
GRADLE_TASK="${GRADLE_TASK:-assembleDebug}"

log() {
  printf '[android-compile] %s\n' "$*"
}

fail() {
  local code="${2:-1}"
  log "COMPILE_STATUS=failure"
  log "$1"
  exit "$code"
}

resolve_android_dir() {
  local candidate=""
  local gradlew_path=""
  local android_match=""
  local root_match=""
  local fallback=""

  for candidate in \
    "${GRADLEW:-}" \
    "${ANDROID_DIR:-}/gradlew"
  do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate" ]]; then
      cd "$(dirname "$candidate")" && pwd
      return 0
    fi
  done

  while read -r candidate; do
    [[ -x "$candidate" ]] || continue
    case "$candidate" in
      "$ROOT_DIR/native/android/gradlew")
        gradlew_path="$candidate"
        break
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

  for candidate in "$gradlew_path" "$android_match" "$root_match" "$fallback"; do
    [[ -n "$candidate" ]] || continue
    cd "$(dirname "$candidate")" && pwd
    return 0
  done

  return 1
}

main() {
  local android_dir=""
  local code=0

  android_dir="$(resolve_android_dir)" || fail "missing gradlew under: $ROOT_DIR"

  log "project=$PROJECT_NAME"
  log "root=$ROOT_DIR"
  log "android_dir=$android_dir"
  log "task=$GRADLE_TASK"
  log "compile start"

  set +e
  (
    cd "$android_dir"
    "$android_dir/gradlew" "$GRADLE_TASK"
  )
  code=$?
  set -e

  if [[ "$code" -ne 0 ]]; then
    fail "gradle task failed: $GRADLE_TASK" "$code"
  fi

  log "COMPILE_STATUS=success"
  log "compile done"
}

main "$@"
