#!/usr/bin/env python3
import json
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
manifest = json.loads((root / "manifests/tahoe-26.json").read_text())
assert manifest["schema"] == 1
assert manifest["vm"]["automaticStopAction"] == "ShutDown"
assert manifest["vm"]["automaticCheckpoints"] is False
assert manifest["vm"]["secureBoot"] is False
for dependency in manifest["dependencies"]:
    assert re.fullmatch(r"[0-9a-f]{64}", dependency["sha256"])
    assert dependency["url"].startswith(
        (
            "https://github.com/acidanthera/",
            "https://github.com/dossijeo/macos-hyperv-builder/releases/",
        )
    )

with (root / "config/opencore.template.plist").open("rb") as stream:
    config = plistlib.load(stream)
generic = config["PlatformInfo"]["Generic"]
assert generic["SystemSerialNumber"] == ""
assert generic["MLB"] == ""
assert generic["SystemUUID"] == ""
assert generic["ROM"] == b""
assert generic["SystemProductName"] == "MacBookAir8,1"

enabled = {
    item["BundlePath"]
    for item in config["Kernel"]["Add"]
    if item.get("Enabled")
}
required = {
    "Lilu.kext",
    "VirtualSMC.kext",
    "MacHyperVSupportMonterey.kext",
    "MacHyperVFramebuffer.kext",
}
assert required <= enabled

plist = plistlib.loads(
    (root / "guest/fish.goldfish64.hvshutdownd.plist").read_bytes()
)
assert plist["Label"] == "fish.goldfish64.hvshutdownd"
assert plist["ProgramArguments"] == [
    "/Library/Application Support/MacHyperVSupport/hvshutdownd"
]

raster_versions = {}
for line in (root / "guest/raster-versions.env").read_text().splitlines():
    if line and not line.startswith("#"):
        key, value = line.split("=", 1)
        raster_versions[key] = value
assert raster_versions["COMPOSE_VERSION"] == "1.10.0"
assert re.fullmatch(r"[0-9a-f]{40}", raster_versions["COMPOSE_COMMIT"])
assert re.fullmatch(r"[0-9a-f]{40}", raster_versions["SKIKO_COMMIT"])
assert raster_versions["SKIKO_RASTER_VERSION"].endswith(
    "-hyperv-raster.1-SNAPSHOT"
)
assert re.fullmatch(r"[0-9a-f]{64}", raster_versions["TEMURIN_SHA256"])
assert raster_versions["TEMURIN_URL"].startswith(
    "https://github.com/adoptium/temurin17-binaries/releases/"
)

raster_patch = (
    root / "patches/compose-1.10.0-uikit-cpu-raster.patch"
).read_text()
for expected in (
    "Surface.makeRasterDirect",
    "CGBitmapContextCreateImage",
    "interpretObjCPointer<Any>(cgImage.rawValue)",
    "redrawer.setNeedsRedraw()",
):
    assert expected in raster_patch

for patch_name in (
    "skiko-uikit-cpu-raster.patch",
    "skiko-uikit-cpu-raster-software-redrawer.patch",
    "skiko-uikit-cpu-raster-build-helper.patch",
):
    assert (root / "patches" / patch_name).is_file()

gradle_init = (root / "guest/hyperv-compose-raster.init.gradle").read_text()
assert "exclusiveContent" in gradle_init
assert 'includeModule("org.jetbrains.compose.ui", "ui-uikitx64")' in gradle_init
assert 'includeGroup("org.jetbrains.skiko")' in gradle_init
assert 'System.getenv("HYPERV_RASTER_REPOSITORY")' in gradle_init
assert "gradle.beforeProject" in gradle_init

simulator_control = (root / "guest/hyperv-simulator.sh").read_text()
assert "xcrun simctl bootstatus" in simulator_control
assert "recover_runaway_windowserver" in simulator_control
assert "sudo killall -9 WindowServer" in simulator_control
assert "CoreSimulator.CoreSimulatorService" in simulator_control
assert "[S]imulatorTrampoline" in simulator_control
assert "HYPERV_WINDOWSERVER_RECOVERY" in simulator_control

tuning = (root / "guest/tune-no-metal-macos.sh").read_text()
assert "com.apple.ReportCrash" in tuning
assert "com.apple.ReportCrash.Root" in tuning
assert "com.apple.diagnosticd" in tuning
assert "mediaanalysisd" in tuning

audio_source = (root / "audio/macos/hyperv-audio-bridge.c").read_text()
for expected in (
    "AudioQueueNewInput",
    "kAudioFormatLinearPCM",
    "format.mSampleRate = 48000.0",
    "format.mChannelsPerFrame = 2",
    "SOCK_DGRAM",
):
    assert expected in audio_source

with (root / "audio/macos/Info.plist").open("rb") as stream:
    audio_info = plistlib.load(stream)
assert audio_info["CFBundleIdentifier"] == "com.dossijeo.hypervaudiobridge"
assert audio_info["LSBackgroundOnly"] is True
assert "NSMicrophoneUsageDescription" in audio_info

with (root / "audio/macos/com.dossijeo.hypervaudiobridge.plist.in").open(
    "rb"
) as stream:
    audio_agent = plistlib.load(stream)
assert audio_agent["Label"] == "com.dossijeo.hypervaudiobridge"
assert audio_agent["ProgramArguments"][:3] == ["/usr/bin/open", "-g", "-j"]
assert "__HOST_ADDRESS__" in audio_agent["ProgramArguments"]

audio_installer = (root / "audio/macos/install.sh").read_text()
assert "BlackHole2ch-0.7.1.pkg" in audio_installer
assert (
    "57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"
    in audio_installer
)
assert "codesign --force --sign -" in audio_installer
assert "pkgutil --check-signature" in audio_installer
assert "launchctl bootstrap" in audio_installer

receiver = (root / "audio/windows/receiver.ps1").read_text()
assert "-ch_layout stereo" in receiver
assert "fifo_size=1000000" in receiver
assert "MacHyperVAudioReceiver-$Port" in receiver

host_installer = (root / "audio/windows/Install-HyperVAudioReceiver.ps1").read_text()
assert "New-NetFirewallRule" in host_installer
assert "Mac Hyper-V Audio Receiver.lnk" in host_installer

orchestrator = (root / "audio/Install-HyperVAudio.ps1").read_text()
assert "GuestAddress" in orchestrator
assert "HostAddress" in orchestrator
assert "scp @sshOptions" in orchestrator

workflow = (root / ".github/workflows/validate.yml").read_text()
assert '$HOME/.m2/repository/org/jetbrains/skiko/$artifact/' in workflow
assert 'cp -R "$source_dir/." "$target_dir/"' in workflow
assert 'deploy_version="${SKIKO_RASTER_VERSION%-SNAPSHOT}"' in workflow
assert "Compile CoreAudio UDP bridge" in workflow
assert "BlackHole2ch-0.7.1.pkg" in workflow

provision = (root / "guest/provision-compose-ios-raster.sh").read_text()
assert 'local deploy_version="${SKIKO_RASTER_VERSION%-SNAPSHOT}"' in provision
assert '-Pdeploy.version="${deploy_version}"' in provision

for file in root.rglob("*"):
    if not file.is_file() or ".git" in file.parts:
        continue
    if file.suffix.lower() in {".vhd", ".vhdx", ".avhdx", ".dmg", ".iso"}:
        raise AssertionError(f"Forbidden image committed: {file}")

print("All repository validations passed.")
