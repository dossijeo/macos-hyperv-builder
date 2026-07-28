#!/usr/bin/env bash
set -euo pipefail

device_name="${HYPERV_SIMULATOR_DEVICE:-HyperV-Raster-iOS}"
windowserver_limit="${HYPERV_WINDOWSERVER_CPU_LIMIT:-200}"

usage() {
    cat <<'EOF'
Usage: hyperv-simulator.sh <boot|shutdown|status> [device name]

Controls one iOS Simulator device and protects the no-Metal Hyper-V desktop
from a runaway WindowServer after simulator shutdown.

Environment:
  HYPERV_SIMULATOR_DEVICE        Default device name.
  HYPERV_WINDOWSERVER_CPU_LIMIT  Recovery threshold in percent (default: 200).
  HYPERV_WINDOWSERVER_RECOVERY   Set to 0 to report saturation without
                                 restarting the graphical login session.
EOF
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
action="$1"
if [[ $# -ge 2 ]]; then
    device_name="$2"
fi

for command in ruby xcrun; do
    command -v "${command}" >/dev/null ||
        { echo "Required command not found: ${command}" >&2; exit 3; }
done

device_udid() {
    xcrun simctl list devices -j |
        DEVICE_NAME="${device_name}" ruby -rjson -e '
            name = ENV.fetch("DEVICE_NAME")
            devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
            matches = devices.select { |d| d["name"] == name && d["isAvailable"] != false }
            abort "Simulator device not found: #{name}" if matches.empty?
            puts matches.first.fetch("udid")
        '
}

device_state() {
    local udid="$1"
    xcrun simctl list devices -j |
        DEVICE_UDID="${udid}" ruby -rjson -e '
            udid = ENV.fetch("DEVICE_UDID")
            device = JSON.parse(STDIN.read).fetch("devices").values.flatten.find {
              |d| d["udid"] == udid
            }
            abort "Simulator device disappeared: #{udid}" unless device
            puts device.fetch("state")
        '
}

windowserver_cpu() {
    local pid
    pid="$(pgrep -x WindowServer | head -1 || true)"
    if [[ -z "${pid}" ]]; then
        echo 0
        return
    fi
    ps -p "${pid}" -o %cpu= | awk '{ printf "%d\n", $1 }'
}

recover_runaway_windowserver() {
    local over_limit=0
    local sample
    for _ in 1 2 3 4 5; do
        sample="$(windowserver_cpu)"
        echo "WindowServer CPU: ${sample}%"
        if (( sample >= windowserver_limit )); then
            over_limit=$((over_limit + 1))
        else
            over_limit=0
        fi
        (( over_limit < 3 )) || break
        sleep 2
    done

    (( over_limit >= 3 )) || return 0
    echo "WindowServer remained saturated after Simulator shutdown." >&2
    if [[ "${HYPERV_WINDOWSERVER_RECOVERY:-1}" == 0 ]]; then
        return 10
    fi

    echo "Restarting the graphical login session to prevent a VM-wide freeze." >&2
    sudo -n killall -9 WindowServer 2>/dev/null || sudo killall -9 WindowServer
}

udid="$(device_udid)"
case "${action}" in
    boot)
        if [[ "$(device_state "${udid}")" == "Shutdown" ]]; then
            xcrun simctl boot "${udid}"
        fi
        xcrun simctl bootstatus "${udid}" -b
        echo "${device_name} (${udid}) is booted."
        ;;
    shutdown)
        # Acquire administrator access while the desktop is still responsive.
        if [[ "${HYPERV_WINDOWSERVER_RECOVERY:-1}" != 0 ]]; then
            sudo -v
        fi
        killall Simulator 2>/dev/null || true
        if [[ "$(device_state "${udid}")" != "Shutdown" ]]; then
            xcrun simctl shutdown "${udid}"
        fi
        for _ in $(seq 1 30); do
            [[ "$(device_state "${udid}")" == "Shutdown" ]] && break
            sleep 1
        done
        [[ "$(device_state "${udid}")" == "Shutdown" ]] ||
            { echo "Simulator did not shut down cleanly." >&2; exit 4; }
        pkill -TERM -f '[c]om.apple.CoreSimulator.CoreSimulatorService' \
            2>/dev/null || true
        pkill -TERM -f '[S]imulatorTrampoline' 2>/dev/null || true
        sleep 2
        recover_runaway_windowserver
        echo "${device_name} (${udid}) is shut down."
        ;;
    status)
        echo "${device_name} (${udid}): $(device_state "${udid}")"
        echo "WindowServer CPU: $(windowserver_cpu)%"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
