#!/usr/bin/env bash
set -euo pipefail

# Background visual analysis is disproportionately expensive on a macOS guest
# with only the Hyper-V framebuffer. The launchctl disable state is persistent
# for this user and can be reverted with `launchctl enable`.
user_domain="gui/${UID}"
launchctl disable "${user_domain}/com.apple.mediaanalysisd" 2>/dev/null || true
launchctl bootout \
    "${user_domain}" \
    /System/Library/LaunchAgents/com.apple.mediaanalysisd.plist \
    2>/dev/null || true

# Simulator wallpaper and accessibility extensions can crash repeatedly when
# Metal is unavailable. ReportCrash may then consume an entire CPU indefinitely.
# This optional tuning script favors VM responsiveness; existing .ips reports
# remain available and the agent can be restored with launchctl enable.
launchctl disable "${user_domain}/com.apple.ReportCrash" 2>/dev/null || true
launchctl bootout "${user_domain}/com.apple.ReportCrash" 2>/dev/null || true
pkill -9 -f '[/]ReportCrash agent' 2>/dev/null || true

echo "Disabling the system crash reporter requires administrator access."
sudo launchctl disable system/com.apple.ReportCrash.Root 2>/dev/null || true
sudo launchctl bootout system/com.apple.ReportCrash.Root 2>/dev/null || true
sudo pkill -9 -f '[/]ReportCrash daemon' 2>/dev/null || true

while IFS= read -r udid; do
    [[ -n "${udid}" ]] || continue
    xcrun simctl spawn "${udid}" \
        launchctl disable system/com.apple.mediaanalysisd \
        2>/dev/null || true
    xcrun simctl spawn "${udid}" \
        launchctl disable system/com.apple.diagnosticd \
        2>/dev/null || true
    xcrun simctl spawn "${udid}" \
        launchctl bootout system/com.apple.diagnosticd \
        2>/dev/null || true
done < <(
    xcrun simctl list devices -j |
        ruby -rjson -e '
            data = JSON.parse(STDIN.read)
            data.fetch("devices").each_value do |devices|
              devices.select { |d| d["state"] == "Booted" }.each {
                |d| puts d.fetch("udid")
              }
            end
        '
)

echo "Disabled background analysis, simulator diagnostics and crash reporters."
echo "Use a static desktop wallpaper manually; animated Aerial wallpaper is CPU-heavy without Metal."
