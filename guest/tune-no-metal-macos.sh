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

while IFS= read -r udid; do
    [[ -n "${udid}" ]] || continue
    xcrun simctl spawn "${udid}" \
        launchctl disable system/com.apple.mediaanalysisd \
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

echo "Disabled mediaanalysisd for the host user and currently booted simulators."
echo "Use a static desktop wallpaper manually; animated Aerial wallpaper is CPU-heavy without Metal."
