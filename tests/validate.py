#!/usr/bin/env python3
import json
import pathlib
import plistlib
import re
import sys

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

for file in root.rglob("*"):
    if not file.is_file() or ".git" in file.parts:
        continue
    if file.suffix.lower() in {".vhd", ".vhdx", ".avhdx", ".dmg", ".iso"}:
        raise AssertionError(f"Forbidden image committed: {file}")

print("All repository validations passed.")
