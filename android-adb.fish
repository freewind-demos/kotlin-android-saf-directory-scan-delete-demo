#!/usr/bin/env fish

set -g ANDROID_ADB_DEFAULT_SDK_ROOT "$HOME/Library/Android/sdk"
set -g ANDROID_ADB_DEFAULT_BUILD_SCRIPT android-build.fish
set -g ANDROID_ADB_DEFAULT_BUILD_TYPE debug
set -g ANDROID_ADB_DEFAULT_LOG_PREFIX '[android-adb]'

function log
    printf '%s %s\n' "$ANDROID_ADB_DEFAULT_LOG_PREFIX" "$argv" >&2
end

function fail
    printf '%s %s\n' "$ANDROID_ADB_DEFAULT_LOG_PREFIX" "$argv[1]" >&2
    exit 1
end

function abs_path --argument path_value
    set -l dir_path (dirname "$path_value")
    set -l file_name (basename "$path_value")
    printf '%s/%s\n' (cd "$dir_path"; and pwd) "$file_name"
end

function build_script_path
    set -l script_dir (cd (dirname (status filename)); and pwd)
    set -l build_script "$script_dir/$ANDROID_ADB_DEFAULT_BUILD_SCRIPT"
    test -x "$build_script"; or fail "缺少 build 脚本：$build_script"
    printf '%s\n' "$build_script"
end

function settings_path --argument project_dir
    printf '%s/settings.gradle.kts\n' "$project_dir"
end

function classify_config --argument config_path
    rg -q 'com\.android\.application' "$config_path"; and begin
        printf 'app\n'
        return 0
    end

    rg -q 'com\.android\.library' "$config_path"; and begin
        printf 'library\n'
        return 0
    end

    printf 'other\n'
end

function list_modules_from_settings --argument settings_file
    rg --no-filename -o --replace '$1' '"(:[^"]+)"' "$settings_file" 2>/dev/null | sort -u
end

function module_to_config --argument project_dir module_name
    set -l relative_dir (string replace -a ':' '/' (string sub -s 2 "$module_name"))
    printf '%s/%s/build.gradle.kts\n' "$project_dir" "$relative_dir"
end

function select_config_from_candidates --argument project_dir
    set -l settings_file (settings_path "$project_dir")
    set -l candidate_configs

    if test -f "$settings_file"
        rg -q 'project\s*\([^)]*\)\s*\.projectDir\s*=' "$settings_file"; and fail "检测到 settings.gradle.kts 使用 projectDir 自定义模块目录。当前脚本不支持。请简化项目，或直接传 --config。"

        for module_name in (list_modules_from_settings "$settings_file")
            set -l candidate (module_to_config "$project_dir" "$module_name")
            test -f "$candidate"; and set candidate_configs $candidate_configs "$candidate"
        end
    else
        for candidate in "$project_dir/app/build.gradle.kts" "$project_dir/build.gradle.kts"
            test -f "$candidate"; and set candidate_configs $candidate_configs "$candidate"
        end
    end

    set -l app_configs
    set -l library_configs
    for candidate in $candidate_configs
        switch (classify_config "$candidate")
            case app
                set app_configs $app_configs "$candidate"
            case library
                set library_configs $library_configs "$candidate"
        end
    end

    if test (count $app_configs) -eq 1
        printf '%s\n' "$app_configs[1]"
        return 0
    end

    if test (count $app_configs) -gt 1
        printf '发现多个 Android App 配置文件，请传 --config 指定其一：\n' >&2
        printf '%s\n' $app_configs >&2
        exit 1
    end

    if test (count $library_configs) -gt 0
        fail "当前项目只发现 Android Library 配置：检测到 com.android.library。该脚本只支持 Android App。"
    end

    fail "缺少 Android App 配置文件：未找到包含 com.android.application 的 build.gradle.kts。"
end

function resolve_config_path --argument project_dir explicit_config
    if test -n "$explicit_config"
        set -l config_path "$explicit_config"
        if not string match -q '/*' -- "$config_path"
            set config_path "$project_dir/$config_path"
        end
        set config_path (abs_path "$config_path")
        test -f "$config_path"; or fail "指定的配置文件不存在：$config_path"

        switch (classify_config "$config_path")
            case app
                printf '%s\n' "$config_path"
                return 0
            case library
                fail "当前配置是 Android Library：检测到 com.android.library。该脚本只支持 Android App。"
            case '*'
                fail "指定的配置文件不是 Android App 配置：$config_path"
        end
    end

    select_config_from_candidates "$project_dir"
end

function has_product_flavors --argument config_path
    rg -q 'productFlavors' "$config_path"
end

function list_flavors --argument config_path
    rg --no-filename -o --replace '$1' '(?:create|register|maybeCreate)\(["'\'']([A-Za-z0-9_-]+)["'\'']\)' "$config_path" 2>/dev/null | sort -u
end

function resolve_flavor --argument config_path explicit_flavor
    if test -n "$explicit_flavor"
        printf '%s\n' "$explicit_flavor"
        return 0
    end

    has_product_flavors "$config_path"; or return 0

    rg -q '["'\'']dev["'\'']|\bdev\s*\{' "$config_path"; and begin
        printf 'dev\n'
        return 0
    end

    set -l flavors (list_flavors "$config_path")
    if test (count $flavors) -eq 1
        printf '%s\n' "$flavors[1]"
        return 0
    end

    printf '检测到 productFlavors，但无法确定默认 flavor。请传 --flavor。候选：\n' >&2
    printf '%s\n' $flavors >&2
    exit 1
end

function resolve_variant_slug --argument flavor build_type
    if test -n "$flavor"
        printf '%s-%s\n' "$flavor" "$build_type"
        return 0
    end

    printf '%s\n' "$build_type"
end

function resolve_app_id --argument config_path
    for pattern in \
        'applicationId\s*=\s*"([^"]+)"' \
        'applicationId\s+"([^"]+)"'
        set -l app_id (rg --no-filename -o --replace '$1' "$pattern" "$config_path" | head -n 1)
        test -n "$app_id"; and begin
            printf '%s\n' "$app_id"
            return 0
        end
    end

    fail "无法从配置文件解析 applicationId：$config_path"
end

function resolve_sdk_root
    if set -q ANDROID_SDK_ROOT; and test -n "$ANDROID_SDK_ROOT"
        printf '%s\n' "$ANDROID_SDK_ROOT"
        return 0
    end

    if set -q ANDROID_HOME; and test -n "$ANDROID_HOME"
        printf '%s\n' "$ANDROID_HOME"
        return 0
    end

    printf '%s\n' "$ANDROID_ADB_DEFAULT_SDK_ROOT"
end

function resolve_adb_bin --argument sdk_root
    set -l adb_bin "$sdk_root/platform-tools/adb"
    test -x "$adb_bin"; or fail "缺少 adb：$adb_bin"
    printf '%s\n' "$adb_bin"
end

function resolve_emulator_bin --argument sdk_root
    set -l emulator_bin "$sdk_root/emulator/emulator"
    test -x "$emulator_bin"; or fail "缺少 emulator：$emulator_bin"
    printf '%s\n' "$emulator_bin"
end

function list_online_devices --argument adb_bin
    for line in ($adb_bin devices)
        set -l cols (string split \t -- "$line")
        test (count $cols) -ge 2; or continue
        test "$cols[2]" = device; or continue
        printf '%s\n' "$cols[1]"
    end
end

function list_real_devices --argument adb_bin
    for serial in (list_online_devices "$adb_bin")
        string match -q 'emulator-*' -- "$serial"; and continue
        printf '%s\n' "$serial"
    end
end

function list_running_emulators --argument adb_bin
    for serial in (list_online_devices "$adb_bin")
        string match -q 'emulator-*' -- "$serial"; or continue
        printf '%s\n' "$serial"
    end
end

function wait_for_device_ready --argument adb_bin serial
    $adb_bin -s "$serial" wait-for-device >/dev/null; or fail "adb wait-for-device 失败：$serial"

    for _attempt in (seq 120)
        set -l booted ($adb_bin -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        if test "$booted" = 1
            $adb_bin -s "$serial" shell input keyevent 82 >/dev/null 2>&1
            return 0
        end
        sleep 2
    end

    fail "设备启动超时：$serial"
end

function pick_avd_name --argument emulator_bin explicit_avd
    if test -n "$explicit_avd"
        printf '%s\n' "$explicit_avd"
        return 0
    end

    for avd_name in ($emulator_bin -list-avds)
        test -n "$avd_name"; or continue
        printf '%s\n' "$avd_name"
        return 0
    end

    fail "未发现可用 AVD。请先创建模拟器，或传 --avd。"
end

function ensure_emulator --argument adb_bin emulator_bin explicit_serial explicit_avd log_path
    if test -n "$explicit_serial"
        wait_for_device_ready "$adb_bin" "$explicit_serial"
        printf '%s\n' "$explicit_serial"
        return 0
    end

    set -l running_emulators (list_running_emulators "$adb_bin")
    if test (count $running_emulators) -ge 1
        wait_for_device_ready "$adb_bin" "$running_emulators[1]"
        printf '%s\n' "$running_emulators[1]"
        return 0
    end

    set -l avd_name (pick_avd_name "$emulator_bin" "$explicit_avd")
    log "start emulator: $avd_name"
    nohup "$emulator_bin" -avd "$avd_name" >"$log_path" 2>&1 &

    for _attempt in (seq 120)
        set -l emulators (list_running_emulators "$adb_bin")
        if test (count $emulators) -ge 1
            wait_for_device_ready "$adb_bin" "$emulators[1]"
            printf '%s\n' "$emulators[1]"
            return 0
        end
        sleep 2
    end

    fail "模拟器启动超时：$avd_name"
end

function pick_target_device --argument adb_bin sdk_root explicit_serial explicit_avd log_path
    if test -n "$explicit_serial"
        if string match -q 'emulator-*' -- "$explicit_serial"
            set -l emulator_bin (resolve_emulator_bin "$sdk_root")
            set -l resolved_serial (ensure_emulator "$adb_bin" "$emulator_bin" "$explicit_serial" "$explicit_avd" "$log_path")
            printf '%s\n' "$resolved_serial"
            return 0
        end

        wait_for_device_ready "$adb_bin" "$explicit_serial"
        printf '%s\n' "$explicit_serial"
        return 0
    end

    set -l real_devices (list_real_devices "$adb_bin")
    if test (count $real_devices) -eq 1
        wait_for_device_ready "$adb_bin" "$real_devices[1]"
        printf '%s\n' "$real_devices[1]"
        return 0
    end

    if test (count $real_devices) -gt 1
        printf '发现多个真机，请传 --serial 指定：\n' >&2
        printf '%s\n' $real_devices >&2
        exit 1
    end

    set -l emulator_bin (resolve_emulator_bin "$sdk_root")
    set -l resolved_serial (ensure_emulator "$adb_bin" "$emulator_bin" "" "$explicit_avd" "$log_path")
    printf '%s\n' "$resolved_serial"
end

function build_once --argument build_script project_dir config flavor build_type
    set -l build_args --no-open-dir --build-type "$build_type"
    test -n "$config"; and set build_args $build_args --config "$config"
    test -n "$flavor"; and set build_args $build_args --flavor "$flavor"

    pushd "$project_dir" >/dev/null; or fail "无法进入项目目录：$project_dir"
    "$build_script" $build_args
    set -l build_code $status
    popd >/dev/null; or fail "无法离开项目目录：$project_dir"
    return $build_code
end

function resolve_output_apk_path --argument project_dir flavor build_type
    set -l project_name (basename "$project_dir")
    set -l variant_slug (resolve_variant_slug "$flavor" "$build_type")
    printf '%s/dist/android/%s-%s.apk\n' "$project_dir" "$project_name" "$variant_slug"
end

function install_and_launch --argument adb_bin serial app_id apk_path
    test -f "$apk_path"; or fail "缺少 APK：$apk_path"
    log "install apk -> $serial"
    $adb_bin -s "$serial" install -r "$apk_path"; or fail "安装失败：$apk_path"

    log "launch app -> $app_id"
    $adb_bin -s "$serial" shell am force-stop "$app_id" >/dev/null 2>&1
    $adb_bin -s "$serial" shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1 >/dev/null; or fail "启动失败：$app_id"
end

function watch_command
    command -q fswatch; or fail "缺少 fswatch。请先安装，或去掉 --watch。"
    printf 'fswatch\n'
end

function watch_paths --argument project_dir
    printf '%s\n' \
        "$project_dir" \
        "$project_dir/app" \
        "$project_dir/src" \
        "$project_dir/gradle.properties" \
        "$project_dir/build.gradle.kts" \
        "$project_dir/settings.gradle.kts"
end

function run_once --argument adb_bin sdk_root build_script project_dir config flavor build_type serial avd emulator_log_path
    set -l resolved_serial (pick_target_device "$adb_bin" "$sdk_root" "$serial" "$avd" "$emulator_log_path")

    build_once "$build_script" "$project_dir" "$config" "$flavor" "$build_type"; or return 1

    set -l app_id (resolve_app_id "$config")
    set -l apk_path (resolve_output_apk_path "$project_dir" "$flavor" "$build_type")
    install_and_launch "$adb_bin" "$resolved_serial" "$app_id" "$apk_path"

    log "done"
    log "serial: $resolved_serial"
    log "apk: $apk_path"
    log "app_id: $app_id"
end

function watch_loop --argument adb_bin sdk_root build_script project_dir config flavor build_type serial avd emulator_log_path
    log "watch start"

    run_once "$adb_bin" "$sdk_root" "$build_script" "$project_dir" "$config" "$flavor" "$build_type" "$serial" "$avd" "$emulator_log_path"; or true

    set -l watcher (watch_command)
    $watcher -0 -r \
        --exclude '/\.git/' \
        --exclude '/\.gradle/' \
        --exclude '/build/' \
        --exclude '/dist/' \
        --exclude '/node_modules/' \
        (watch_paths "$project_dir") | while read -z _
        log "change detected"
        run_once "$adb_bin" "$sdk_root" "$build_script" "$project_dir" "$config" "$flavor" "$build_type" "$serial" "$avd" "$emulator_log_path"; or log "build failed, wait next change"
    end
end

function parse_args
    set -g ANDROID_ADB_CONFIG
    set -g ANDROID_ADB_FLAVOR
    set -g ANDROID_ADB_BUILD_TYPE "$ANDROID_ADB_DEFAULT_BUILD_TYPE"
    set -g ANDROID_ADB_SERIAL
    set -g ANDROID_ADB_AVD
    set -g ANDROID_ADB_WATCH 0

    while test (count $argv) -gt 0
        switch "$argv[1]"
            case --config
                test (count $argv) -ge 2; or fail "--config 缺少路径"
                set -g ANDROID_ADB_CONFIG "$argv[2]"
                set argv $argv[3..-1]
            case --flavor
                test (count $argv) -ge 2; or fail "--flavor 缺少值"
                set -g ANDROID_ADB_FLAVOR "$argv[2]"
                set argv $argv[3..-1]
            case --build-type
                test (count $argv) -ge 2; or fail "--build-type 缺少值"
                set -g ANDROID_ADB_BUILD_TYPE "$argv[2]"
                set argv $argv[3..-1]
            case --serial
                test (count $argv) -ge 2; or fail "--serial 缺少值"
                set -g ANDROID_ADB_SERIAL "$argv[2]"
                set argv $argv[3..-1]
            case --avd
                test (count $argv) -ge 2; or fail "--avd 缺少值"
                set -g ANDROID_ADB_AVD "$argv[2]"
                set argv $argv[3..-1]
            case --watch
                set -g ANDROID_ADB_WATCH 1
                set argv $argv[2..-1]
            case '*'
                fail "未知参数：$argv[1]"
        end
    end
end

function main
    parse_args $argv

    set -l project_dir "$PWD"
    set -l build_script (build_script_path)
    set -l config_path (resolve_config_path "$project_dir" "$ANDROID_ADB_CONFIG")
    set -l flavor (resolve_flavor "$config_path" "$ANDROID_ADB_FLAVOR")
    set -l sdk_root (resolve_sdk_root)
    set -l adb_bin (resolve_adb_bin "$sdk_root")
    set -l project_name (basename "$project_dir")
    set -l emulator_log_path "/tmp/$project_name-android-emulator.log"

    if test "$ANDROID_ADB_WATCH" = 1
        watch_loop "$adb_bin" "$sdk_root" "$build_script" "$project_dir" "$config_path" "$flavor" "$ANDROID_ADB_BUILD_TYPE" "$ANDROID_ADB_SERIAL" "$ANDROID_ADB_AVD" "$emulator_log_path"
        return 0
    end

    run_once "$adb_bin" "$sdk_root" "$build_script" "$project_dir" "$config_path" "$flavor" "$ANDROID_ADB_BUILD_TYPE" "$ANDROID_ADB_SERIAL" "$ANDROID_ADB_AVD" "$emulator_log_path"
end

main $argv
