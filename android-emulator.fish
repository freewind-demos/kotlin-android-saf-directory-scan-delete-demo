#!/usr/bin/env fish

function log
    printf '[dev-android] %s\n' "$argv" >&2
end

function fail
    printf '[dev-android] %s\n' "$argv[1]" >&2
    exit 1
end

function abs_path --argument path_value
    set -l dir_path (dirname "$path_value")
    set -l file_name (basename "$path_value")
    printf '%s/%s\n' (cd "$dir_path"; and pwd) "$file_name"
end

function resolve_script_dir
    set -l script_path (status filename)
    test -n "$script_path"; or fail "cannot resolve script path"
    set -l resolved_script_path (path resolve "$script_path" 2>/dev/null)
    test -n "$resolved_script_path"; or set resolved_script_path (abs_path "$script_path")
    dirname "$resolved_script_path"
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

function resolve_app_build_file --argument android_dir
    for candidate in "$android_dir/app/build.gradle.kts" "$android_dir/app/build.gradle"
        test -f "$candidate"; or continue
        printf '%s\n' "$candidate"
        return 0
    end

    fail "missing app build file under: $android_dir/app"
end

function resolve_app_id --argument app_build_file
    if test -n "$ANDROID_APP_ID"
        printf '%s\n' "$ANDROID_APP_ID"
        return 0
    end

    test -f "$app_build_file"; or fail "missing app build file: $app_build_file"

    set -l app_id_patterns 'applicationId\s*=\s*"([^"]+)"' 'applicationId\s+"([^"]+)"'
    for pattern in $app_id_patterns
        set -g ANDROID_APP_ID (rg -o --replace '$1' "$pattern" "$app_build_file" | head -n 1)
        test -n "$ANDROID_APP_ID"; and break
    end
    test -n "$ANDROID_APP_ID"; or fail "cannot resolve applicationId from: $app_build_file"
    printf '%s\n' "$ANDROID_APP_ID"
end

function list_running_emulators
    for line in ($ANDROID_ADB_BIN devices)
        set -l cols (string split \t -- "$line")
        test (count $cols) -ge 2; or continue
        set -l serial "$cols[1]"
        set -l state "$cols[2]"
        if string match -q 'emulator-*' -- "$serial"; and test "$state" = device
            printf '%s\n' "$serial"
        end
    end
end

function first_running_emulator
    for serial in (list_running_emulators)
        test -n "$serial"; or continue
        printf '%s\n' "$serial"
        return 0
    end

    return 1
end

function pick_avd_name
    if set -q AVD_NAME; and test -n "$AVD_NAME"
        printf '%s\n' "$AVD_NAME"
        return 0
    end

    test -x "$ANDROID_EMULATOR_BIN"; or return 1

    for avd in ($ANDROID_EMULATOR_BIN -list-avds)
        test -n "$avd"; or continue
        printf '%s\n' "$avd"
        return 0
    end

    return 1
end

function wait_for_boot --argument serial
    $ANDROID_ADB_BIN -s "$serial" wait-for-device >/dev/null; or fail "adb wait-for-device failed: $serial"

    for boot_attempt in (seq 120)
        set -l booted ($ANDROID_ADB_BIN -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        if test "$booted" = 1
            $ANDROID_ADB_BIN -s "$serial" shell input keyevent 82 >/dev/null 2>&1
            return 0
        end
        sleep 2
    end

    fail "emulator boot timeout: $serial"
end

function ensure_emulator
    set -l serial (first_running_emulator)
    if test -n "$serial"
        log "reuse emulator: $serial"
        wait_for_boot "$serial"
        printf '%s\n' "$serial"
        return 0
    end

    set -l avd_name (pick_avd_name)
    test -n "$avd_name"; or fail "no running emulator, no AVD found; set AVD_NAME or create one first"
    test -x "$ANDROID_EMULATOR_BIN"; or fail "missing emulator: $ANDROID_EMULATOR_BIN"

    log "start emulator: $avd_name"
    nohup "$ANDROID_EMULATOR_BIN" -avd "$avd_name" >"$ANDROID_EMULATOR_LOG_PATH" 2>&1 &

    for start_attempt in (seq 120)
        set serial (first_running_emulator)
        if test -n "$serial"
            wait_for_boot "$serial"
            printf '%s\n' "$serial"
            return 0
        end
        sleep 2
    end

    fail "emulator start timeout: $avd_name"
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

function install_and_launch --argument serial app_id apk_path
    log "install apk -> $serial"
    $ANDROID_ADB_BIN -s "$serial" install -r "$apk_path"; or fail "install failed: $apk_path"

    log "launch app -> $app_id"
    $ANDROID_ADB_BIN -s "$serial" shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1 >/dev/null; or fail "launch failed: $app_id"
end

function main
    set -l gradlew_path (resolve_gradlew)
    test -n "$gradlew_path"; or fail "missing gradlew under: $ANDROID_ROOT_DIR"

    set -l android_dir (cd (dirname "$gradlew_path"); and pwd)
    test -n "$android_dir"; or fail "cannot resolve android dir from: $gradlew_path"

    set -l apk_path "$android_dir/app/build/outputs/apk/debug/app-debug.apk"
    set -l app_build_file (resolve_app_build_file "$android_dir")
    set -l app_id (resolve_app_id "$app_build_file")

    set -l serial "$ANDROID_SERIAL"
    if test -n "$serial"
        log "use ANDROID_SERIAL: $serial"
        wait_for_boot "$serial"
    else
        set serial (ensure_emulator)
    end

    build_apk "$gradlew_path" "$android_dir" "$apk_path"
    install_and_launch "$serial" "$app_id" "$apk_path"

    log done
    log "android_dir: $android_dir"
    log "apk: $apk_path"
    log "app_id: $app_id"
    log "project: $ANDROID_PROJECT_NAME"
    log "serial: $serial"
end

set -l project_dir (resolve_script_dir)
if set -q PROJECT_DIR; and test -n "$PROJECT_DIR"
    set project_dir "$PROJECT_DIR"
end

set -g ANDROID_ROOT_DIR (cd "$project_dir"; and pwd)
set -g ANDROID_PROJECT_NAME (basename "$ANDROID_ROOT_DIR")
set -g ANDROID_EMULATOR_LOG_PATH "/tmp/$ANDROID_PROJECT_NAME-android-emulator.log"
set -g ANDROID_APP_ID
if set -q APP_ID; and test -n "$APP_ID"
    set ANDROID_APP_ID "$APP_ID"
end

set -l sdk_root "$HOME/Library/Android/sdk"
if set -q ANDROID_HOME; and test -n "$ANDROID_HOME"
    set sdk_root "$ANDROID_HOME"
end
if set -q ANDROID_SDK_ROOT; and test -n "$ANDROID_SDK_ROOT"
    set sdk_root "$ANDROID_SDK_ROOT"
end
set -g ANDROID_SDK_ROOT "$sdk_root"

set -g ANDROID_ADB_BIN "$ANDROID_SDK_ROOT/platform-tools/adb"
if set -q ADB_BIN; and test -n "$ADB_BIN"
    set ANDROID_ADB_BIN "$ADB_BIN"
end

set -g ANDROID_EMULATOR_BIN "$ANDROID_SDK_ROOT/emulator/emulator"
if set -q EMULATOR_BIN; and test -n "$EMULATOR_BIN"
    set ANDROID_EMULATOR_BIN "$EMULATOR_BIN"
end

test -x "$ANDROID_ADB_BIN"; or fail "missing adb: $ANDROID_ADB_BIN"

main $argv
