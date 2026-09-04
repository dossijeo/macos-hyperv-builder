#!/bin/bash
set -euo pipefail

label="com.dossijeo.hypervaudiobridge"
user_id="$(id -u)"
app_dir="${HOME}/Applications/HyperV Audio Bridge.app"
launch_agent="${HOME}/Library/LaunchAgents/${label}.plist"

launchctl bootout "gui/${user_id}/${label}" >/dev/null 2>&1 || true
pkill -u "${user_id}" -x HyperVAudioBridge >/dev/null 2>&1 || true
rm -f "${launch_agent}"
rm -rf "${app_dir}"

if [[ "${1:-}" == "--remove-blackhole" ]]; then
  sudo rm -rf "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
  sudo /usr/bin/killall coreaudiod 2>/dev/null || true
  echo "Bridge and BlackHole 2ch removed."
else
  echo "Bridge removed. BlackHole 2ch was left installed."
fi
