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

  for candidate in \
    "${ANDROID_DIR:-}" \
    "$ROOT_DIR/native/android" \
    "$ROOT_DIR/android" \
    "$ROOT_DIR"
  do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate/gradlew" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

main() {
  local android_dir=""
  local code=0

  android_dir="$(resolve_android_dir)" || fail "missing gradlew under: $ROOT_DIR, $ROOT_DIR/android, $ROOT_DIR/native/android"

  log "project=$PROJECT_NAME"
  log "root=$ROOT_DIR"
  log "android_dir=$android_dir"
  log "task=$GRADLE_TASK"
  log "compile start"

  set +e
  (
    cd "$android_dir"
    ./gradlew "$GRADLE_TASK"
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
