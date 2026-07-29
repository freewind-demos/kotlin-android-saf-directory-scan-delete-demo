#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kotlin-android-saf-directory-scan-delete-demo"
MODULE_PATH=":app"
MODULE_DIR="app"
BUILD_TYPE="${1:-debug}"

case "$BUILD_TYPE" in
  build|debug)
    BUILD_TYPE="debug"
    TASK="${MODULE_PATH}:assembleDebug"
    VARIANT_DIR="debug"
    ;;
  release)
    TASK="${MODULE_PATH}:assembleRelease"
    VARIANT_DIR="release"
    ;;
  *)
    echo "Usage: ./android-build.sh [build|debug|release]" >&2
    exit 1
    ;;
esac

if [[ "$BUILD_TYPE" == "debug" ]]; then
  APK_DIRS=("$PWD/app/build/outputs/apk/debug")
else
  APK_DIRS=("$PWD/app/build/outputs/apk/release")
fi
for apk_dir in "${APK_DIRS[@]}"; do
  rm -rf "$apk_dir"
done

./gradlew "$TASK"

apks=()
APK_SOURCE_DIR=""
for apk_dir in "${APK_DIRS[@]}"; do
  current_apks=()
  if [[ -d "$apk_dir" ]]; then
    while IFS= read -r apk_path; do
      current_apks+=("$apk_path")
    done < <(/usr/bin/find "$apk_dir" -maxdepth 1 -type f -name '*.apk' | sort)
  fi
  if [[ "${#current_apks[@]}" -gt 0 ]]; then
    apks=("${current_apks[@]}")
    APK_SOURCE_DIR="$apk_dir"
    break
  fi
done

if [[ "${#apks[@]}" -ne 1 ]]; then
  echo "Expected exactly one APK under configured dirs, got ${#apks[@]}:" >&2
  printf '  %s
' "${APK_DIRS[@]}" >&2
  exit 1
fi

APK_PATH="${apks[0]}"
BUILD_TIME="$(date +%H%M)"
TARGET_APK_PATH="$APK_SOURCE_DIR/$PROJECT_NAME-$BUILD_TYPE.$BUILD_TIME.apk"

if [[ "$APK_PATH" != "$TARGET_APK_PATH" ]]; then
  mv -f "$APK_PATH" "$TARGET_APK_PATH"
fi

if command -v open >/dev/null 2>&1; then
  open "$APK_SOURCE_DIR"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$APK_SOURCE_DIR"
fi

echo "$TARGET_APK_PATH"
