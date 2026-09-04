#!/bin/bash
set -euo pipefail

blackhole_url="https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg"
blackhole_sha256="57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"
label="com.dossijeo.hypervaudiobridge"

usage() {
  cat <<'EOF'
Usage: ./install.sh HOST_IPV4 [PORT] [--non-interactive]

Installs BlackHole 2ch, builds the bridge application and starts it for the
current graphical user. The default UDP port is 4010.
EOF
}

host_address="${1:-}"
port="${2:-4010}"
mode="${3:-}"
if [[ -z "${host_address}" || ! "${host_address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  usage >&2
  exit 2
fi
if [[ ! "${port}" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
  echo "Invalid UDP port: ${port}" >&2
  exit 2
fi
if [[ ${EUID} -eq 0 ]]; then
  echo "Run this installer as the logged-in desktop user, not with sudo." >&2
  exit 2
fi

for octet in ${host_address//./ }; do
  if ((octet < 0 || octet > 255)); then
    echo "Invalid IPv4 address: ${host_address}" >&2
    exit 2
  fi
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
user_id="$(id -u)"
app_dir="${HOME}/Applications/HyperV Audio Bridge.app"
executable="${app_dir}/Contents/MacOS/HyperVAudioBridge"
launch_agent="${HOME}/Library/LaunchAgents/${label}.plist"
log_path="${HOME}/Library/Logs/hyperv-audio-bridge"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

blackhole_info="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver/Contents/Info"
installed_version="$(defaults read "${blackhole_info}" CFBundleShortVersionString 2>/dev/null || true)"
if [[ "${installed_version}" == "0.7.1" ]]; then
  echo "BlackHole 2ch 0.7.1 is already installed."
else
  echo "Downloading checksum-pinned BlackHole 2ch 0.7.1..."
  pkg="${temp_dir}/BlackHole2ch-0.7.1.pkg"
  curl -LfsS "${blackhole_url}" -o "${pkg}"
  echo "${blackhole_sha256}  ${pkg}" | shasum -a 256 -c -
  pkgutil --check-signature "${pkg}"
  sudo -v
  sudo /usr/sbin/installer -pkg "${pkg}" -target /
  sudo /usr/bin/killall coreaudiod 2>/dev/null || true
fi

mkdir -p "${app_dir}/Contents/MacOS" \
  "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
xcrun clang -O2 -Wall -Wextra \
  "${script_dir}/hyperv-audio-bridge.c" \
  -framework AudioToolbox -framework CoreFoundation \
  -o "${executable}"
chmod 755 "${executable}"
install -m 644 "${script_dir}/Info.plist" "${app_dir}/Contents/Info.plist"
codesign --force --sign - "${app_dir}"

install -m 600 "${script_dir}/${label}.plist.in" "${launch_agent}"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:3 ${app_dir}" "${launch_agent}"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:5 ${host_address}" "${launch_agent}"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:6 ${port}" "${launch_agent}"
/usr/libexec/PlistBuddy -c "Set :StandardOutPath ${log_path}.out.log" "${launch_agent}"
/usr/libexec/PlistBuddy -c "Set :StandardErrorPath ${log_path}.err.log" "${launch_agent}"
plutil -lint "${app_dir}/Contents/Info.plist" "${launch_agent}"

launchctl bootout "gui/${user_id}/${label}" >/dev/null 2>&1 || true
pkill -u "${user_id}" -x HyperVAudioBridge >/dev/null 2>&1 || true
launchctl bootstrap "gui/${user_id}" "${launch_agent}"

if [[ "${mode}" != "--non-interactive" ]]; then
  echo
  echo "Allow microphone access for HyperV Audio Bridge in the macOS prompt."
  read -r -p "After accepting it, press Return to finish: "
fi

bridge_stable=false
for attempt in 1 2 3; do
  pkill -u "${user_id}" -x HyperVAudioBridge >/dev/null 2>&1 || true
  /usr/bin/open -g -j "${app_dir}" --args "${host_address}" "${port}"
  sleep 2
  if pgrep -u "${user_id}" -x HyperVAudioBridge >/dev/null; then
    sleep 5
    if pgrep -u "${user_id}" -x HyperVAudioBridge >/dev/null; then
      bridge_stable=true
      break
    fi
  fi
  echo "Bridge launch attempt ${attempt} did not remain active; retrying..." >&2
done

if [[ "${bridge_stable}" != true ]]; then
  echo "The bridge is installed but is not running." >&2
  echo "Check Privacy & Security > Microphone, then run:" >&2
  echo "open -g -j '${app_dir}' --args '${host_address}' '${port}'" >&2
  exit 1
fi

echo "Hyper-V audio bridge is running at 48 kHz stereo -> ${host_address}:${port}."
echo "A macOS restart is recommended after the first BlackHole installation."
