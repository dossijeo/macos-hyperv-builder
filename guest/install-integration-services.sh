#!/bin/bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

bundle="${1:-}"
if [[ -z "${bundle}" || ! -d "${bundle}" ]]; then
  echo "Usage: sudo $0 /path/to/extracted/MacHyperVSupport-release" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
support_dir="/Library/Application Support/MacHyperVSupport"
plist="/Library/LaunchDaemons/fish.goldfish64.hvshutdownd.plist"
label="fish.goldfish64.hvshutdownd"

install -d -o root -g wheel -m 755 "${support_dir}"
install -o root -g wheel -m 755 "${bundle}/Tools/hvshutdownd" \
  "${support_dir}/hvshutdownd"
install -o root -g wheel -m 644 \
  "${script_dir}/fish.goldfish64.hvshutdownd.plist" "${plist}"

plutil -lint "${plist}"
launchctl bootout "system/${label}" 2>/dev/null || true
launchctl bootstrap system "${plist}"
launchctl enable "system/${label}"
launchctl kickstart -k "system/${label}"

launchctl print "system/${label}"
ioreg -l | grep -q HyperVShutdownUserClient
echo "Hyper-V shutdown integration is active."

