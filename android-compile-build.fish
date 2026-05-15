#!/usr/bin/env fish

function log
    printf '[build-android] %s\n' "$argv" >&2
end

function fail
    printf '[build-android] %s\n' "$argv[1]" >&2
    exit 1
end

function abs_path --argument path_value
    set -l dir_path (dirname "$path_value")
    set -l file_name (basename "$path_value")
    printf '%s/%s\n' (cd "$dir_path"; and pwd) "$file_name"
end

function resolve_gradlew
    set -l candidate
    set -l explicit_candidates
    set -l android_match
    set -l root_match
    set -l fallback

    if set -q GRADLEW; and test -n "$GRADLEW"
        set explicit_candidates $explicit_candidates "$GRADLEW"
    end

    if set -q ANDROID_DIR; and test -n "$ANDROID_DIR"
        set explicit_candidates $explicit_candidates "$ANDROID_DIR/gradlew"
    end

    for candidate in $explicit_candidates
        test -x "$candidate"; or continue
        abs_path "$candidate"
        return 0
    end

    for candidate in (fd -a -t f -g gradlew "$ANDROID_ROOT_DIR")
        test -x "$candidate"; or continue
        switch "$candidate"
            case "$ANDROID_ROOT_DIR/native/android/gradlew"
                printf '%s\n' "$candidate"
                return 0
            case "$ANDROID_ROOT_DIR/android/gradlew" '*/native/android/gradlew' '*/android/gradlew'
                if test -z "$android_match"
                    set android_match "$candidate"
                end
            case "$ANDROID_ROOT_DIR/gradlew"
                if test -z "$root_match"
                    set root_match "$candidate"
                end
            case '*'
                if test -z "$fallback"
                    set fallback "$candidate"
                end
        end
    end

    for candidate in "$android_match" "$root_match" "$fallback"
        test -n "$candidate"; or continue
        printf '%s\n' "$candidate"
        return 0
    end

    return 1
end

function open_dir --argument dir_path
    test "$ANDROID_OPEN_DIR_AFTER_BUILD" = 1; or return 0

    if command -q open
        open "$dir_path"
        return 0
    end

    if command -q xdg-open
        xdg-open "$dir_path"
        return 0
    end

    log "skip open dir: no opener found"
end

function build_apk --argument gradlew_path android_dir apk_path
    log "build debug apk"

    pushd "$android_dir" >/dev/null; or fail "cannot enter android dir: $android_dir"
    $gradlew_path assembleDebug
    set -l code $status
    popd >/dev/null; or fail "cannot leave android dir: $android_dir"

    test $code -eq 0; or fail "gradle task failed: assembleDebug"
    test -f "$apk_path"; or fail "apk not found: $apk_path"
end

function collect_apk --argument source_apk_path
    mkdir -p "$ANDROID_OUTPUT_DIR"; or fail "cannot create output dir: $ANDROID_OUTPUT_DIR"
    cp "$source_apk_path" "$ANDROID_OUTPUT_APK_PATH"; or fail "cannot copy apk: $source_apk_path"
end

function main
    set -l gradlew_path (resolve_gradlew)
    test -n "$gradlew_path"; or fail "missing gradlew under: $ANDROID_ROOT_DIR"

    set -l android_dir (cd (dirname "$gradlew_path"); and pwd)
    test -n "$android_dir"; or fail "cannot resolve android dir from: $gradlew_path"

    set -l source_apk_path "$android_dir/app/build/outputs/apk/debug/app-debug.apk"

    build_apk "$gradlew_path" "$android_dir" "$source_apk_path"
    collect_apk "$source_apk_path"
    open_dir "$ANDROID_OUTPUT_DIR"

    log done
    log "project: $ANDROID_PROJECT_NAME"
    log "android_dir: $android_dir"
    log "apk: $ANDROID_OUTPUT_APK_PATH"
end

set -l project_dir "$PWD"
if set -q PROJECT_DIR; and test -n "$PROJECT_DIR"
    set project_dir "$PROJECT_DIR"
end

set -g ANDROID_ROOT_DIR (cd "$project_dir"; and pwd)
set -g ANDROID_PROJECT_NAME (basename "$ANDROID_ROOT_DIR")
set -g ANDROID_OUTPUT_DIR "$ANDROID_ROOT_DIR/dist/android"
set -g ANDROID_OUTPUT_APK_PATH "$ANDROID_OUTPUT_DIR/$ANDROID_PROJECT_NAME-android-debug.apk"
set -g ANDROID_OPEN_DIR_AFTER_BUILD 1
if set -q OPEN_DIR_AFTER_BUILD; and test -n "$OPEN_DIR_AFTER_BUILD"
    set ANDROID_OPEN_DIR_AFTER_BUILD "$OPEN_DIR_AFTER_BUILD"
end

main $argv
