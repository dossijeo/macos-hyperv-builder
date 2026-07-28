# macOS Tahoe on Hyper-V — reproducible builder

This project preserves the configuration and source-level fixes used to run
macOS Tahoe 26.5.2 on a Generation 2 Hyper-V VM. It contains no macOS image,
virtual disk, Apple credential, SSH key or reusable SMBIOS identity.

> [!IMPORTANT]
> This is an engineering project, not a supported Apple or Microsoft
> configuration. Read [LEGAL.md](LEGAL.md) before use. The tested VM provides
> a responsive desktop, networking, SSH, Xcode and clean Hyper-V shutdown.
> Hyper-V does not provide a Metal-capable GPU to the guest. This repository
> includes an experimental CPU-raster backend for Compose Multiplatform iOS;
> it does not add Metal or accelerate arbitrary Metal applications.

## What is preserved

- Pinned OpenCore 1.0.7, Lilu 1.7.2, VirtualSMC 1.3.7 and
  MacHyperVSupport 0.9.9 inputs with SHA-256 verification.
- The tested OpenCore configuration, with the machine identity removed.
- Hyper-V settings: Generation 2, Secure Boot off, fixed memory, clean
  shutdown, and automatic checkpoints disabled.
- The Tahoe graphics deadlock patch for MacHyperVSupport.
- A checksum-pinned release of the two patched BSD-licensed kexts, so a new
  Windows host does not need an existing Mac/Xcode installation to bootstrap.
- The packaging fix that installs the real `hvshutdownd` and
  `hvtimesyncd` plists instead of duplicate `hvfilecopyd` plists.
- A corrected shutdown LaunchDaemon and guest installer.
- Per-machine generation of serial, MLB, UUID, ROM and Hyper-V MAC address.
- Pinned Compose Multiplatform 1.10.0 and Skiko 0.9.37.3 UIKit patches that
  render with Skia on the CPU and present frames through CoreGraphics and
  `CALayer`.
- Guest provisioning for the JDK, Xcode iOS runtime, local patched artifacts,
  automatic Gradle selection and no-Metal performance tuning.

## Current automation boundary

The repository stages and validates all pinned inputs, generates a new private
identity, assembles a validated OpenCore tree and UEFI VHDX, downloads Apple
Recovery directly from Apple, creates a Recovery VHDX and can create and start
the Generation 2 VM:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build.ps1 -DownloadRecovery -CreateVM -StartVM -SwitchName "Default Switch"
```

Generated material is written to ignored `state/`, `.cache/` and `artifacts/`
directories. A self-contained copy of the macOS provisioning tools and their
source patches is staged in `artifacts/guest-tools/`.

The first boot enters Apple Recovery. Disk formatting, the Apple installer
screens and their reboots remain guided because Hyper-V VMConnect does not
provide a stable unattended console API. After installation, run
`guest/install-integration-services.sh` inside macOS and verify clean shutdown.

Xcode itself is not redistributed or downloaded by the Windows builder.
Install Xcode from Apple, then copy `artifacts/guest-tools/` into the guest and
run the provisioning described below. Apple authentication and acceptance of
the Xcode licence cannot be made part of a public, credential-free image.

## iOS Simulator without Metal for Compose

This is a framework-level compatibility backend, not a graphics driver.
Unmodified Compose Multiplatform 1.10.0 calls
`MTLCreateSystemDefaultDevice()` and fails because Hyper-V exposes only its
synthetic 2D framebuffer. The committed patch replaces that UIKit rendering
path:

1. Compose draws into an aligned native buffer through a Skia raster surface.
2. CoreGraphics creates a `CGImage` over the rendered pixels.
3. The image is bridged to Objective-C and assigned to a dedicated `CALayer`.
4. Compose frame invalidation is re-armed after content installation.

After installing Xcode in the guest:

```bash
cd ~/guest-tools
chmod +x ./*.sh
./provision-compose-ios-raster.sh
./tune-no-metal-macos.sh
```

The provisioner is idempotent and performs the following actions:

- downloads the checksum-pinned Intel Temurin 17 JDK;
- completes Xcode first-launch setup when required;
- downloads an iOS Simulator runtime only if none is installed;
- creates a `HyperV-Raster-iOS` device on the newest installed iOS runtime;
- checks out Compose Multiplatform Core and Skiko at pinned commits;
- applies and compiles both CPU-raster patches for `uikitX64`;
- creates an isolated local Maven repository under
  `~/.local/share/macos-hyperv-builder/raster-m2/`;
- installs `~/.gradle/init.d/hyperv-compose-raster.init.gradle`, causing
  Compose 1.10.0 iOS x64 projects to select the patched UIKit artifact.

Use `--no-global-gradle` when the patched artifact should be opt-in. In that
case, pass the repository's
`guest/hyperv-compose-raster.init.gradle` explicitly to Gradle with
`--init-script`.

The tested configuration is Xcode 26.6 with iOS 18.3 and iOS 26.5 runtimes.
Both runtimes render a real Compose application and the minimal raster probe
without a Metal device.

### Scope and limitations

- Only the Intel iOS Simulator target (`iosX64`) and Compose Multiplatform
  1.10.0 are patched.
- Native UIKit and SwiftUI applications already work with the simulator's
  software-capable paths and do not need this patch.
- Direct Metal, SceneKit/RealityKit workloads and third-party renderers that
  insist on Metal still do not work.
- Rendering is CPU-bound. It is suitable for functional and visual
  verification, screenshots and ordinary UI interaction, but not for GPU
  performance measurements.
- A Compose or Skiko upgrade must be rebased and revalidated. The installer
  deliberately pins the known-good source commit and refuses a patch that no
  longer applies.
- Animated desktop wallpaper and background visual analysis consume
  significant CPU without Metal. Use a static wallpaper; the optional tuning
  script disables `mediaanalysisd` for the host user and booted simulators.

## CI

The hosted GitHub Actions workflow:

- validates manifests and plists;
- rejects committed VM or Apple images;
- parses every PowerShell script;
- downloads all pinned archives and checks their SHA-256 values;
- applies the Tahoe patch to pristine MacHyperVSupport 0.9.9 source;
- compiles both patched kexts on a macOS runner;
- applies the Compose and Skiko patches to pinned pristine sources and
  compiles the `uikitX64` KLIB on an Intel macOS runner.

A complete Hyper-V boot cannot run on a GitHub-hosted runner because it
requires a physical Windows host with Hyper-V and a multi-reboot macOS
installer. `self-hosted-smoke.yml` records this boundary explicitly rather
than presenting a false green check.

## Machine identity

`New-MachineIdentity.ps1` uses OpenCore's `macserial` and generates a unique
UUID and locally administered ROM/MAC. Values are stable in the ignored
`state/identity.json` for that deployment. Delete the file only when creating
a genuinely new machine identity.

Never commit `state/identity.json`, an EFI produced from it, Apple account
data, certificates or SSH keys.

## Tested host profile

| Setting | Value |
|---|---|
| Hypervisor | Windows 11 Hyper-V |
| VM generation | 2 |
| vCPU | 8 |
| Memory | 16 GiB, static |
| Secure Boot | Off |
| Automatic stop | ShutDown |
| Automatic checkpoints | Off |
| Guest | macOS Tahoe 26.5.2 (25F84) |
| SMBIOS model | MacBookAir8,1 |

## Licence

The orchestration code is MIT licensed. Patches derived from MacHyperVSupport
retain its BSD-3-Clause licence; the Compose and Skiko patches remain
Apache-2.0. See [THIRD_PARTY.md](THIRD_PARTY.md).
