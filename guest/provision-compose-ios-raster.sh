#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/raster-versions.env"
patch_dir="${HYPERV_RASTER_PATCH_DIR:-${repo_root}/patches}"
if [[ ! -d "${patch_dir}" && -d "${script_dir}/patches" ]]; then
    patch_dir="${script_dir}/patches"
fi

work_root="${HYPERV_RASTER_WORK_ROOT:-${HOME}/Library/Caches/macos-hyperv-builder/compose-raster}"
install_root="${HOME}/.local/share/macos-hyperv-builder"
raster_repository="${install_root}/raster-m2/repository"
compose_source="${HYPERV_COMPOSE_SOURCE:-${work_root}/compose-multiplatform-core}"
skiko_source="${HYPERV_SKIKO_SOURCE:-${work_root}/skiko}"
jdk_root="${install_root}/jdks"
install_gradle_init=true
prepare_xcode=true

usage() {
    cat <<'EOF'
Usage: provision-compose-ios-raster.sh [options]

Build and install the experimental Compose Multiplatform UIKit CPU renderer.

Options:
  --no-xcode-setup     Do not run Xcode first-launch/runtime checks.
  --no-global-gradle   Build the artifact but do not enable it globally.
  --work-dir PATH      Override the source/build cache directory.
  -h, --help           Show this help.

Environment:
  HYPERV_RASTER_WORK_ROOT  Alternative source/build cache directory.
  HYPERV_RASTER_JAVA_HOME  Use an existing Intel JDK instead of downloading.
  HYPERV_COMPOSE_SOURCE    Use an existing Compose source checkout.
  HYPERV_SKIKO_SOURCE      Use an existing Skiko source checkout.
  HYPERV_RASTER_REBUILD=1  Force rebuilding existing patched artifacts.
  HYPERV_SIMULATOR_RUNTIME_MAJOR
                           Preferred installed iOS runtime major (default: 18).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-xcode-setup)
            prepare_xcode=false
            shift
            ;;
        --no-global-gradle)
            install_gradle_init=false
            shift
            ;;
        --work-dir)
            [[ $# -ge 2 ]] || { echo "--work-dir requires a path" >&2; exit 2; }
            work_root="$2"
            compose_source="${HYPERV_COMPOSE_SOURCE:-${work_root}/compose-multiplatform-core}"
            skiko_source="${HYPERV_SKIKO_SOURCE:-${work_root}/skiko}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for command in curl git ruby shasum tar xcodebuild xcrun zip; do
    command -v "${command}" >/dev/null ||
        { echo "Required command not found: ${command}" >&2; exit 3; }
done

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
    echo "This backend is tested only on Intel macOS guests." >&2
    exit 4
fi

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

download() {
    local url="$1"
    local output="$2"
    mkdir -p "$(dirname "${output}")"
    if [[ ! -f "${output}" ]]; then
        curl --fail --location --retry 3 --output "${output}.part" "${url}"
        mv "${output}.part" "${output}"
    fi
}

prepare_jdk() {
    if [[ -n "${HYPERV_RASTER_JAVA_HOME:-}" ]]; then
        [[ -x "${HYPERV_RASTER_JAVA_HOME}/bin/java" ]] ||
            { echo "HYPERV_RASTER_JAVA_HOME is not a JDK." >&2; exit 5; }
        export JAVA_HOME="${HYPERV_RASTER_JAVA_HOME}"
        export PATH="${JAVA_HOME}/bin:${PATH}"
        export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.installations.paths=${JAVA_HOME} -Dorg.gradle.java.installations.auto-download=false"
        java -version
        return
    fi

    local archive="${work_root}/downloads/${TEMURIN_ARCHIVE}"
    local destination="${jdk_root}/temurin-${TEMURIN_VERSION}"

    download "${TEMURIN_URL}" "${archive}"
    local actual
    actual="$(sha256_file "${archive}")"
    if [[ "${actual}" != "${TEMURIN_SHA256}" ]]; then
        echo "Temurin checksum mismatch: ${actual}" >&2
        exit 5
    fi

    if [[ ! -x "${destination}/Contents/Home/bin/java" ]]; then
        [[ ! -e "${destination}" ]] ||
            { echo "Incomplete JDK destination already exists: ${destination}" >&2; exit 5; }
        mkdir -p "${work_root}" "${jdk_root}"
        local expanded
        expanded="$(mktemp -d "${work_root}/jdk-expanded.XXXXXX")"
        tar -xzf "${archive}" -C "${expanded}"
        local java_home
        java_home="$(find "${expanded}" -path '*/Contents/Home/bin/java' -type f -print -quit)"
        [[ -n "${java_home}" ]] ||
            { echo "Temurin archive does not contain Contents/Home/bin/java" >&2; exit 5; }
        mv "$(dirname "$(dirname "$(dirname "$(dirname "${java_home}")")")")" \
            "${destination}"
        rm -rf "${expanded}"
    fi

    export JAVA_HOME="${destination}/Contents/Home"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.installations.paths=${JAVA_HOME} -Dorg.gradle.java.installations.auto-download=false"
    java -version
}

prepare_xcode_runtime() {
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        echo "Completing Xcode first-launch setup (administrator access required)."
        sudo xcodebuild -license accept
        sudo xcodebuild -runFirstLaunch
    fi

    local runtime_count
    runtime_count="$(
        xcrun simctl list runtimes -j |
            ruby -rjson -e '
                data = JSON.parse(STDIN.read)
                puts data.fetch("runtimes").count {
                  |r| r["platform"] == "iOS" && r["isAvailable"] != false
                }
            '
    )"
    if [[ "${runtime_count}" == 0 ]]; then
        echo "No iOS Simulator runtime is installed; downloading the Xcode default."
        xcodebuild -downloadPlatform iOS
    fi

    local device_name="HyperV-Raster-iOS"
    if xcrun simctl list devices -j |
        DEVICE_NAME="${device_name}" ruby -rjson -e '
            name = ENV.fetch("DEVICE_NAME")
            data = JSON.parse(STDIN.read)
            exit(data.fetch("devices").values.flatten.any? { |d| d["name"] == name } ? 0 : 1)
        '
    then
        echo "Simulator device ${device_name} already exists."
        return
    fi

    local runtime_id
    local preferred_major="${HYPERV_SIMULATOR_RUNTIME_MAJOR:-18}"
    runtime_id="$(
        xcrun simctl list runtimes -j |
            PREFERRED_MAJOR="${preferred_major}" ruby -rjson -e '
                runtimes = JSON.parse(STDIN.read).fetch("runtimes").select {
                  |r| r["platform"] == "iOS" && r["isAvailable"] != false
                }
                abort "No available iOS runtime" if runtimes.empty?
                preferred = ENV.fetch("PREFERRED_MAJOR")
                candidates = runtimes.select {
                  |r| r["version"].split(".").first == preferred
                }
                selected = (candidates.empty? ? runtimes : candidates).max_by {
                  |r| r["version"].split(".").map(&:to_i)
                }
                warn "Using iOS #{selected.fetch("version")} Simulator runtime."
                puts selected.fetch("identifier")
            '
    )"

    local type_id
    for type_id in \
        com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
        com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
        com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation
    do
        if xcrun simctl list devicetypes |
            grep -Fq "(${type_id})" &&
            xcrun simctl create "${device_name}" "${type_id}" "${runtime_id}"
        then
            return
        fi
    done
    echo "Could not create ${device_name}; use an existing Xcode device profile." >&2
}

checkout_compose() {
    mkdir -p "${work_root}"
    if [[ ! -d "${compose_source}/.git" ]]; then
        git clone --filter=blob:none \
            https://github.com/JetBrains/compose-multiplatform-core.git \
            "${compose_source}"
    fi

    git -C "${compose_source}" fetch --depth=1 origin "${COMPOSE_COMMIT}"
    git -C "${compose_source}" checkout --detach "${COMPOSE_COMMIT}"
    git -C "${compose_source}" reset --quiet

    local patch="${patch_dir}/compose-1.10.0-uikit-cpu-raster.patch"
    if git -C "${compose_source}" apply --reverse --check "${patch}" 2>/dev/null; then
        echo "Compose CPU-raster patch is already applied."
    else
        git -C "${compose_source}" apply --check "${patch}"
        git -C "${compose_source}" apply "${patch}"
    fi
}

checkout_skiko() {
    mkdir -p "${work_root}"
    if [[ ! -d "${skiko_source}/.git" ]]; then
        git clone --filter=blob:none \
            https://github.com/JetBrains/skiko.git \
            "${skiko_source}"
    fi

    git -C "${skiko_source}" fetch --depth=1 origin "${SKIKO_COMMIT}"
    git -C "${skiko_source}" checkout --detach "${SKIKO_COMMIT}"
    git -C "${skiko_source}" reset --quiet

    local patches=(
        "${patch_dir}/skiko-uikit-cpu-raster.patch"
        "${patch_dir}/skiko-uikit-cpu-raster-software-redrawer.patch"
        "${patch_dir}/skiko-uikit-cpu-raster-build-helper.patch"
    )
    local patch
    for patch in "${patches[@]}"; do
        if git -C "${skiko_source}" apply --reverse --check "${patch}" 2>/dev/null; then
            echo "$(basename "${patch}") is already applied."
        else
            git -C "${skiko_source}" apply --check "${patch}"
            git -C "${skiko_source}" apply "${patch}"
        fi
    done
}

build_skiko_raster_artifact() {
    local artifact="${raster_repository}/org/jetbrains/skiko/skiko-iosx64/${SKIKO_RASTER_VERSION}/skiko-iosx64-${SKIKO_RASTER_VERSION}.klib"
    if [[ -f "${artifact}" && "${HYPERV_RASTER_REBUILD:-0}" != 1 ]]; then
        echo "Using existing patched Skiko artifact: ${artifact}"
        return
    fi

    (
        cd "${skiko_source}/skiko"
        ./gradlew \
            publishIosX64PublicationToMavenLocal \
            publishKotlinMultiplatformPublicationToMavenLocal \
            -Dmaven.repo.local="${raster_repository}" \
            -Pdeploy.version="${SKIKO_RASTER_VERSION}" \
            -Pskiko.awt.enabled=false \
            -Pskiko.js.enabled=false \
            -Pskiko.wasm.enabled=false \
            -Pskiko.android.enabled=false \
            -Pskiko.native.enabled=false \
            -Pskiko.native.linux.enabled=false \
            -Pskiko.native.mac.enabled=false \
            -Pskiko.native.ios.enabled=false \
            -Pskiko.native.ios.arm64.enabled=false \
            -Pskiko.native.ios.simulatorArm64.enabled=false \
            -Pskiko.native.ios.x64.enabled=true \
            --console=plain
    )

    [[ -f "${artifact}" ]] ||
        { echo "Patched Skiko iOS x64 artifact was not published." >&2; exit 6; }
    echo "RASTER_SKIKO_KLIB=${artifact}"
    echo "RASTER_SKIKO_SHA256=$(sha256_file "${artifact}")"
}

seed_compose_metadata() {
    local base="https://repo1.maven.org/maven2/org/jetbrains/compose/ui"
    local ui_dir="${raster_repository}/org/jetbrains/compose/ui/ui/${COMPOSE_VERSION}"
    local uikit_dir="${raster_repository}/org/jetbrains/compose/ui/ui-uikitx64/${COMPOSE_VERSION}"

    mkdir -p "${ui_dir}" "${uikit_dir}"
    download \
        "${base}/ui/${COMPOSE_VERSION}/ui-${COMPOSE_VERSION}.module" \
        "${ui_dir}/ui-${COMPOSE_VERSION}.module"
    download \
        "${base}/ui/${COMPOSE_VERSION}/ui-${COMPOSE_VERSION}.pom" \
        "${ui_dir}/ui-${COMPOSE_VERSION}.pom"
    download \
        "${base}/ui-uikitx64/${COMPOSE_VERSION}/ui-uikitx64-${COMPOSE_VERSION}.module" \
        "${uikit_dir}/ui-uikitx64-${COMPOSE_VERSION}.module"
    download \
        "${base}/ui-uikitx64/${COMPOSE_VERSION}/ui-uikitx64-${COMPOSE_VERSION}.pom" \
        "${uikit_dir}/ui-uikitx64-${COMPOSE_VERSION}.pom"
}

build_compose_raster_artifact() {
    local android_placeholder="${work_root}/android-sdk-placeholder"
    local klib_parent="${compose_source}/out/androidx/compose/ui/ui/build/classes/kotlin/uikitX64/main/klib/ui"
    local target_dir="${raster_repository}/org/jetbrains/compose/ui/ui-uikitx64/${COMPOSE_VERSION}"
    local artifact="${target_dir}/ui-uikitx64-${COMPOSE_VERSION}.klib"
    local module="${target_dir}/ui-uikitx64-${COMPOSE_VERSION}.module"

    mkdir -p "${android_placeholder}" "${target_dir}"
    if [[ -f "${artifact}" && "${HYPERV_RASTER_REBUILD:-0}" != 1 ]]; then
        echo "Using existing patched Compose artifact: ${artifact}"
        return
    fi

    (
        cd "${compose_source}"
        ANDROIDX_PROJECTS=KMP \
        ANDROID_SDK_ROOT="${android_placeholder}" \
        SKIKO_VERSION="${SKIKO_RASTER_VERSION}" \
        ./gradlew \
            --init-script "${script_dir}/hyperv-compose-raster.init.gradle" \
            :compose:ui:ui:compileKotlinUikitX64 \
            --console=plain
    )

    [[ -d "${klib_parent}/default" ]] ||
        { echo "Compose UIKit KLIB output was not produced." >&2; exit 6; }
    rm -f "${artifact}.tmp"
    (
        cd "${klib_parent}"
        zip -q -0 -r "${artifact}.tmp" default
    )
    mv "${artifact}.tmp" "${artifact}"

    export RASTER_ARTIFACT="${artifact}"
    export RASTER_MODULE="${module}"
    ruby <<'RUBY'
require "json"
require "digest"

artifact = ENV.fetch("RASTER_ARTIFACT")
module_path = ENV.fetch("RASTER_MODULE")
bytes = File.binread(artifact)
hashes = {
  "size" => bytes.bytesize,
  "sha512" => Digest::SHA512.hexdigest(bytes),
  "sha256" => Digest::SHA256.hexdigest(bytes),
  "sha1" => Digest::SHA1.hexdigest(bytes),
  "md5" => Digest::MD5.hexdigest(bytes),
}

metadata = JSON.parse(File.read(module_path))
matched = false
metadata.fetch("variants").each do |variant|
  Array(variant["files"]).each do |file|
    next unless file["url"] == File.basename(artifact)
    hashes.each { |key, value| file[key] = value }
    matched = true
  end
end
abort "UIKit artifact entry was not found in Gradle module metadata" unless matched
File.write(module_path, JSON.pretty_generate(metadata) + "\n")
puts "RASTER_UI_KLIB=#{artifact}"
puts "RASTER_UI_SHA256=#{hashes.fetch("sha256")}"
RUBY
}

install_init_script() {
    local init_dir="${HOME}/.gradle/init.d"
    mkdir -p "${init_dir}"
    install -m 644 \
        "${script_dir}/hyperv-compose-raster.init.gradle" \
        "${init_dir}/hyperv-compose-raster.init.gradle"
    echo "Gradle CPU-raster selection enabled globally for this user."
}

prepare_jdk
if [[ "${prepare_xcode}" == true ]]; then
    prepare_xcode_runtime
fi
checkout_compose
checkout_skiko
build_skiko_raster_artifact
seed_compose_metadata
build_compose_raster_artifact
if [[ "${install_gradle_init}" == true ]]; then
    install_init_script
fi

echo
echo "Compose UIKit CPU raster backend is installed."
echo "Compose=${COMPOSE_VERSION} commit=${COMPOSE_COMMIT}"
echo "Skiko=${SKIKO_RASTER_VERSION} commit=${SKIKO_COMMIT}"
echo "Repository=${raster_repository}"
xcrun simctl list runtimes
