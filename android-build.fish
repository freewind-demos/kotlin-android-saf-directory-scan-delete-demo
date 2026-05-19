#!/usr/bin/env fish

set -g ANDROID_BUILD_SETTINGS_FILE settings.gradle.kts
set -g ANDROID_BUILD_CONFIG_FILE build.gradle.kts
set -g ANDROID_BUILD_APP_CONFIG_FILE app/build.gradle.kts
set -g ANDROID_BUILD_GRADLEW_FILE gradlew
set -g ANDROID_BUILD_APK_OUTPUT_DIR build/outputs/apk
set -g ANDROID_BUILD_DIST_DIR dist/android
set -g ANDROID_BUILD_DEFAULT_BUILD_TYPE debug
set -g ANDROID_BUILD_DEFAULT_FLAVOR dev

function log
    printf '[android-build] %s\n' "$argv" >&2
end

function fail
    printf '[android-build] %s\n' "$argv[1]" >&2
    exit 1
end

function abs_path --argument path_value
    set -l dir_path (dirname "$path_value")
    set -l file_name (basename "$path_value")
    printf '%s/%s\n' (cd "$dir_path"; and pwd) "$file_name"
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

function list_modules_from_settings --argument settings_path
    rg --no-filename -o --replace '$1' '"(:[^"]+)"' "$settings_path" 2>/dev/null | sort -u
end

function module_to_config --argument project_dir module_name
    set -l relative_dir (string replace -a ':' '/' (string sub -s 2 "$module_name"))
    printf '%s/%s/build.gradle.kts\n' "$project_dir" "$relative_dir"
end

function select_config_from_candidates --argument project_dir
    set -l settings_path "$project_dir/$ANDROID_BUILD_SETTINGS_FILE"
    set -l candidate_configs

    if test -f "$settings_path"
        rg -q 'project\s*\([^)]*\)\s*\.projectDir\s*=' "$settings_path"; and fail "检测到 settings.gradle.kts 使用 projectDir 自定义模块目录。当前脚本不支持。请简化项目，或直接传 --config。"

        for module_name in (list_modules_from_settings "$settings_path")
            set -l candidate (module_to_config "$project_dir" "$module_name")
            test -f "$candidate"; and set candidate_configs $candidate_configs "$candidate"
        end
    else
        for candidate in "$project_dir/$ANDROID_BUILD_APP_CONFIG_FILE" "$project_dir/$ANDROID_BUILD_CONFIG_FILE"
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
        for candidate in $app_configs
            printf '%s\n' "$candidate" >&2
        end
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
    set -l flavors
    for flavor_name in (rg --no-filename -o --replace '$1' '(?:create|register|maybeCreate)\(["'\'']([A-Za-z0-9_-]+)["'\'']\)' "$config_path" 2>/dev/null | sort -u)
        set flavors $flavors "$flavor_name"
    end
    printf '%s\n' $flavors
end

function resolve_flavor --argument config_path explicit_flavor
    if test -n "$explicit_flavor"
        printf '%s\n' "$explicit_flavor"
        return 0
    end

    has_product_flavors "$config_path"; or return 0

    rg -q '["'\'']dev["'\'']|\bdev\s*\{' "$config_path"; and begin
        printf '%s\n' "$ANDROID_BUILD_DEFAULT_FLAVOR"
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

function capitalize_token --argument value
    test -n "$value"; or return 0
    set -l first (string upper (string sub -s 1 -l 1 -- "$value"))
    set -l rest (string sub -s 2 -- "$value")
    printf '%s%s' "$first" "$rest"
end

function to_pascal_case --argument value
    test -n "$value"; or return 0
    set -l parts (string split -r -m 100 '_' -- (string replace -a '-' '_' "$value"))
    set -l result
    for part in $parts
        set result "$result"(capitalize_token "$part")
    end
    printf '%s\n' "$result"
end

function module_path_from_config --argument project_dir config_path
    set -l module_dir (dirname "$config_path")
    if test "$module_dir" = "$project_dir"
        return 0
    end

    set -l relative_dir (string replace "$project_dir/" '' "$module_dir")
    printf ':%s\n' (string replace -a '/' ':' "$relative_dir")
end

function resolve_gradlew --argument project_dir
    set -l gradlew_path "$project_dir/$ANDROID_BUILD_GRADLEW_FILE"
    test -x "$gradlew_path"; or fail "缺少 gradlew：$gradlew_path。请先生成 Android Gradle Wrapper。"
    printf '%s\n' "$gradlew_path"
end

function build_task_name --argument config_path project_dir flavor build_type
    set -l suffix
    if test -n "$flavor"
        set suffix (to_pascal_case "$flavor")(to_pascal_case "$build_type")
    else
        set suffix (to_pascal_case "$build_type")
    end

    set -l module_path (module_path_from_config "$project_dir" "$config_path")
    if test -n "$module_path"
        printf '%s:assemble%s\n' "$module_path" "$suffix"
        return 0
    end

    printf 'assemble%s\n' "$suffix"
end

function resolve_variant_slug --argument flavor build_type
    if test -n "$flavor"
        printf '%s-%s\n' "$flavor" "$build_type"
        return 0
    end

    printf '%s\n' "$build_type"
end

function find_apk --argument module_dir flavor build_type
    set -l apk_root "$module_dir/$ANDROID_BUILD_APK_OUTPUT_DIR"
    test -d "$apk_root"; or fail "缺少 APK 输出目录：$apk_root"

    set -l matched
    set -l flavor_lower (string lower "$flavor")
    set -l build_type_lower (string lower "$build_type")
    for candidate in (fd -a -e apk . "$apk_root")
        set -l lower_path (string lower "$candidate")
        string match -q '*unaligned*' -- "$lower_path"; and continue
        if test -n "$flavor_lower"
            string match -q "*$flavor_lower*" -- "$lower_path"; or continue
        end
        string match -q "*$build_type_lower*" -- "$lower_path"; or continue
        set matched $matched "$candidate"
    end

    if test (count $matched) -eq 1
        printf '%s\n' "$matched[1]"
        return 0
    end

    if test (count $matched) -gt 1
        printf '发现多个 APK 输出文件，请简化产物，或调整脚本规则：\n' >&2
        printf '%s\n' $matched >&2
        exit 1
    end

    set -l all_apks (fd -a -e apk . "$apk_root")
    if test (count $all_apks) -eq 1
        printf '%s\n' "$all_apks[1]"
        return 0
    end

    fail "未找到匹配当前 variant 的 APK。"
end

function open_dir_if_needed --argument dir_path should_open
    test "$should_open" = 1; or return 0

    if command -q open
        open "$dir_path"
        return 0
    end

    if command -q xdg-open
        xdg-open "$dir_path"
        return 0
    end

    log "跳过打开目录：缺少 open/xdg-open"
end

function parse_args
    set -g ANDROID_BUILD_CONFIG
    set -g ANDROID_BUILD_FLAVOR
    set -g ANDROID_BUILD_TYPE "$ANDROID_BUILD_DEFAULT_BUILD_TYPE"
    set -g ANDROID_BUILD_OPEN_DIR 1

    while test (count $argv) -gt 0
        switch "$argv[1]"
            case --config
                test (count $argv) -ge 2; or fail "--config 缺少路径"
                set -g ANDROID_BUILD_CONFIG "$argv[2]"
                set argv $argv[3..-1]
            case --flavor
                test (count $argv) -ge 2; or fail "--flavor 缺少值"
                set -g ANDROID_BUILD_FLAVOR "$argv[2]"
                set argv $argv[3..-1]
            case --build-type
                test (count $argv) -ge 2; or fail "--build-type 缺少值"
                set -g ANDROID_BUILD_TYPE "$argv[2]"
                set argv $argv[3..-1]
            case --no-open-dir
                set -g ANDROID_BUILD_OPEN_DIR 0
                set argv $argv[2..-1]
            case '*'
                fail "未知参数：$argv[1]"
        end
    end
end

function main
    parse_args $argv

    set -l project_dir "$PWD"
    test -n "$project_dir"; or fail "无法确定项目目录"

    set -l config_path (resolve_config_path "$project_dir" "$ANDROID_BUILD_CONFIG")
    set -l module_dir (dirname "$config_path")
    set -l gradlew_path (resolve_gradlew "$project_dir")
    set -l flavor (resolve_flavor "$config_path" "$ANDROID_BUILD_FLAVOR")
    set -l task_name (build_task_name "$config_path" "$project_dir" "$flavor" "$ANDROID_BUILD_TYPE")
    set -l variant_slug (resolve_variant_slug "$flavor" "$ANDROID_BUILD_TYPE")

    log "config: $config_path"
    log "task: $task_name"

    pushd "$project_dir" >/dev/null; or fail "无法进入项目目录：$project_dir"
    "$gradlew_path" "$task_name"
    set -l build_code $status
    popd >/dev/null; or fail "无法离开项目目录：$project_dir"

    test $build_code -eq 0; or fail "Gradle 任务失败：$task_name"

    set -l apk_path (find_apk "$module_dir" "$flavor" "$ANDROID_BUILD_TYPE")
    set -l output_dir "$project_dir/$ANDROID_BUILD_DIST_DIR"
    set -l project_name (basename "$project_dir")
    set -l output_apk_path "$output_dir/$project_name-$variant_slug.apk"

    mkdir -p "$output_dir"; or fail "无法创建输出目录：$output_dir"
    cp "$apk_path" "$output_apk_path"; or fail "无法复制 APK：$apk_path"

    open_dir_if_needed "$output_dir" "$ANDROID_BUILD_OPEN_DIR"

    log done
    log "apk: $output_apk_path"
end

main $argv
