#!/usr/bin/env fish

function log
    printf '[android-gradle-wrapper] %s\n' "$argv" >&2
end

function fail
    printf '[android-gradle-wrapper] %s\n' "$argv[1]" >&2
    exit 1
end

function abs_path --argument path_value
    set -l dir_path (dirname "$path_value")
    set -l file_name (basename "$path_value")
    printf '%s/%s\n' (cd "$dir_path"; and pwd) "$file_name"
end

function resolve_project_dir
    set -l project_dir "$PWD"
    if set -q PROJECT_DIR; and test -n "$PROJECT_DIR"
        set project_dir "$PROJECT_DIR"
    end
    cd "$project_dir"; and pwd
end

function is_gradle_dir --argument dir_path
    for candidate in \
        "$dir_path/settings.gradle.kts" \
        "$dir_path/settings.gradle" \
        "$dir_path/build.gradle.kts" \
        "$dir_path/build.gradle"
        test -f "$candidate"; and return 0
    end
    return 1
end

function resolve_android_dir --argument project_dir
    if set -q ANDROID_DIR; and test -n "$ANDROID_DIR"
        set -l explicit_dir (cd "$ANDROID_DIR"; and pwd)
        test -n "$explicit_dir"; or fail "cannot resolve ANDROID_DIR: $ANDROID_DIR"
        is_gradle_dir "$explicit_dir"; or fail "ANDROID_DIR is not a Gradle project: $explicit_dir"
        printf '%s\n' "$explicit_dir"
        return 0
    end

    for candidate in \
        "$project_dir" \
        "$project_dir/android" \
        "$project_dir/native/android"
        is_gradle_dir "$candidate"; or continue
        printf '%s\n' "$candidate"
        return 0
    end

    fail "cannot find Android Gradle dir under: $project_dir"
end

function first_match --argument pattern
    set -l files $argv[2..-1]
    test (count $files) -gt 0; or return 1

    for value in (rg --no-filename -o --replace '$1' "$pattern" $files 2>/dev/null)
        test -n "$value"; or continue
        printf '%s\n' "$value"
        return 0
    end

    return 1
end

function resolve_agp_version --argument android_dir
    set -l build_files
    for candidate in \
        "$android_dir/settings.gradle.kts" \
        "$android_dir/settings.gradle" \
        "$android_dir/build.gradle.kts" \
        "$android_dir/build.gradle" \
        "$android_dir/gradle/libs.versions.toml"
        test -f "$candidate"; and set build_files $build_files "$candidate"
    end

    test (count $build_files) -gt 0; or return 1

    set -l matched_value

    set matched_value (first_match 'com\.android\.tools\.build:gradle:([0-9]+\.[0-9]+(?:\.[0-9]+)?)' $build_files)
    if test -n "$matched_value"
        printf '%s\n' "$matched_value"
        return 0
    end

    set matched_value (first_match 'id\(["'\'']com\.android\.(?:application|library|test|dynamic-feature)["'\'']\)\s+version\s+["'\'']([0-9]+\.[0-9]+(?:\.[0-9]+)?)["'\'']' $build_files)
    if test -n "$matched_value"
        printf '%s\n' "$matched_value"
        return 0
    end

    set matched_value (first_match 'id\s+["'\'']com\.android\.(?:application|library|test|dynamic-feature)["'\'']\s+version\s+["'\'']([0-9]+\.[0-9]+(?:\.[0-9]+)?)["'\'']' $build_files)
    if test -n "$matched_value"
        printf '%s\n' "$matched_value"
        return 0
    end

    set matched_value (first_match '^\s*(?:agp|androidGradlePlugin)\s*=\s*["'\'']([0-9]+\.[0-9]+(?:\.[0-9]+)?)["'\'']' $build_files)
    if test -n "$matched_value"
        printf '%s\n' "$matched_value"
        return 0
    end

    return 1
end

function map_gradle_version_from_agp --argument agp_version
    set -l parts (string split . -- "$agp_version")
    test (count $parts) -ge 2; or return 1
    set -l major_minor "$parts[1].$parts[2]"

    switch "$major_minor"
        case 9.2
            echo 9.4.1
        case 9.1
            echo 9.3.1
        case 9.0
            echo 9.1.0
        case 8.13 8.12 8.11
            echo 8.13
        case 8.10 8.9
            echo 8.11.1
        case 8.8
            echo 8.10.2
        case 8.7
            echo 8.9
        case 8.6 8.5
            echo 8.7
        case 8.4
            echo 8.6
        case 8.3
            echo 8.4
        case 8.2
            echo 8.2
        case 8.1 8.0
            echo 8.0
        case 7.4
            echo 7.5
        case 7.3
            echo 7.4
        case 7.2
            echo 7.3.3
        case 7.1
            echo 7.2
        case 7.0
            echo 7.0
        case 4.2 4.1
            echo 6.7.1
        case 4.0
            echo 6.1.1
        case 3.6
            echo 5.6.4
        case 3.5
            echo 5.4.1
        case 3.4
            echo 5.1.1
        case 3.3
            echo 4.10.1
        case 3.2
            echo 4.6
        case 3.1
            echo 4.4
        case '*'
            return 1
    end
end

function resolve_gradle_version --argument android_dir
    if set -q GRADLE_VERSION; and test -n "$GRADLE_VERSION"
        printf '%s\n' "$GRADLE_VERSION"
        return 0
    end

    set -l agp_version (resolve_agp_version "$android_dir")
    if test -n "$agp_version"
        set -l gradle_version (map_gradle_version_from_agp "$agp_version")
        if test -n "$gradle_version"
            log "AGP $agp_version -> Gradle $gradle_version"
            printf '%s\n' "$gradle_version"
            return 0
        end
        fail "unsupported AGP version: $agp_version; set GRADLE_VERSION manually"
    end

    set -l default_gradle_version 9.4.1
    log "AGP not found -> default Gradle $default_gradle_version"
    printf '%s\n' "$default_gradle_version"
end

function ensure_command --argument command_name
    command -q "$command_name"; and return 0
    fail "missing command: $command_name"
end

function bootstrap_gradle --argument gradle_version workspace_dir
    ensure_command curl
    ensure_command unzip
    ensure_command java

    set -l dist_dir "$workspace_dir/dist"
    set -l zip_path "$workspace_dir/gradle-$gradle_version-all.zip"
    set -l gradle_home "$dist_dir/gradle-$gradle_version"
    set -l gradle_bin "$gradle_home/bin/gradle"

    if test -x "$gradle_bin"
        printf '%s\n' "$gradle_bin"
        return 0
    end

    mkdir -p "$dist_dir"; or fail "cannot create dist dir: $dist_dir"
    set -l dist_url "https://services.gradle.org/distributions/gradle-$gradle_version-all.zip"

    log "download $dist_url"
    curl -fsSL "$dist_url" -o "$zip_path"; or fail "download failed: $dist_url"

    unzip -q "$zip_path" -d "$dist_dir"; or fail "unzip failed: $zip_path"
    test -x "$gradle_bin"; or fail "gradle bin missing after unzip: $gradle_bin"
    printf '%s\n' "$gradle_bin"
end

function copy_wrapper_files --argument source_dir target_dir
    mkdir -p "$target_dir/gradle/wrapper"; or fail "cannot create wrapper dir under: $target_dir"

    for relative_path in \
        gradlew \
        gradlew.bat \
        gradle/wrapper/gradle-wrapper.jar \
        gradle/wrapper/gradle-wrapper.properties
        set -l source_path "$source_dir/$relative_path"
        set -l target_path "$target_dir/$relative_path"
        test -f "$source_path"; or fail "missing generated wrapper file: $source_path"
        cp "$source_path" "$target_path"; or fail "cannot copy wrapper file: $source_path"
    end

    chmod +x "$target_dir/gradlew"; or fail "cannot chmod gradlew: $target_dir/gradlew"
end

function generate_wrapper --argument android_dir gradle_version workspace_dir
    set -l bootstrap_dir "$workspace_dir/bootstrap"
    mkdir -p "$bootstrap_dir"; or fail "cannot create bootstrap dir: $bootstrap_dir"

    printf 'rootProject.name = "wrapper-bootstrap"\n' >"$bootstrap_dir/settings.gradle.kts"; or fail "cannot write bootstrap settings"
    printf '\n' >"$bootstrap_dir/build.gradle.kts"; or fail "cannot write bootstrap build"

    set -l gradle_bin (bootstrap_gradle "$gradle_version" "$workspace_dir")
    log "generate wrapper via Gradle $gradle_version"

    pushd "$bootstrap_dir" >/dev/null; or fail "cannot enter bootstrap dir: $bootstrap_dir"
    "$gradle_bin" wrapper --gradle-version "$gradle_version" --distribution-type all >/dev/null
    set -l code $status
    popd >/dev/null; or fail "cannot leave bootstrap dir: $bootstrap_dir"

    test $code -eq 0; or fail "wrapper task failed for Gradle $gradle_version"
    copy_wrapper_files "$bootstrap_dir" "$android_dir"
end

function main
    set -l project_dir (resolve_project_dir)
    test -n "$project_dir"; or fail "cannot resolve PROJECT_DIR"

    set -l android_dir (resolve_android_dir "$project_dir")
    set -l gradle_version (resolve_gradle_version "$android_dir")

    set -l workspace_dir (mktemp -d "/tmp/android-gradle-wrapper.XXXXXX")
    test -n "$workspace_dir"; or fail "cannot create temp dir"

    generate_wrapper "$android_dir" "$gradle_version" "$workspace_dir"

    rm -rf "$workspace_dir"

    log done
    log "android_dir: $android_dir"
    log "gradle_version: $gradle_version"
    log "wrapper: $android_dir/gradlew"
end

main $argv
