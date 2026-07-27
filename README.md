# macOS Tahoe on Hyper-V — reproducible builder

This project preserves the configuration and source-level fixes used to run
macOS Tahoe 26.5.2 on a Generation 2 Hyper-V VM. It contains no macOS image,
virtual disk, Apple credential, SSH key or reusable SMBIOS identity.

> [!IMPORTANT]
> This is an engineering project, not a supported Apple or Microsoft
> configuration. Read [LEGAL.md](LEGAL.md) before use. The tested VM provides
> a responsive desktop, networking, SSH, Xcode and clean Hyper-V shutdown.
> Hyper-V does not provide a Metal-capable GPU to the guest; iOS Simulator
> workloads that require Metal remain outside the supported scope.

## What is preserved

- Pinned OpenCore 1.0.7, Lilu 1.7.2, VirtualSMC 1.3.7 and
  MacHyperVSupport 0.9.9 inputs with SHA-256 verification.
- The tested OpenCore configuration, with the machine identity removed.
- Hyper-V settings: Generation 2, Secure Boot off, fixed memory, clean
  shutdown, and automatic checkpoints disabled.
- The Tahoe graphics deadlock patch for MacHyperVSupport.
- The packaging fix that installs the real `hvshutdownd` and
  `hvtimesyncd` plists instead of duplicate `hvfilecopyd` plists.
- A corrected shutdown LaunchDaemon and guest installer.
- Per-machine generation of serial, MLB, UUID, ROM and Hyper-V MAC address.

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
directories.

The first boot enters Apple Recovery. Disk formatting, the Apple installer
screens and their reboots remain guided because Hyper-V VMConnect does not
provide a stable unattended console API. After installation, run
`guest/install-integration-services.sh` inside macOS and verify clean shutdown.

## CI

The hosted GitHub Actions workflow:

- validates manifests and plists;
- rejects committed VM or Apple images;
- parses every PowerShell script;
- downloads all pinned archives and checks their SHA-256 values;
- applies the Tahoe patch to pristine MacHyperVSupport 0.9.9 source;
- compiles both patched kexts on a macOS runner.

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
| vCPU | 4 |
| Memory | 16 GiB, static |
| Secure Boot | Off |
| Automatic stop | ShutDown |
| Automatic checkpoints | Off |
| Guest | macOS Tahoe 26.5.2 (25F84) |
| SMBIOS model | MacBookAir8,1 |

## Licence

The orchestration code is MIT licensed. Patches derived from
MacHyperVSupport retain its BSD-3-Clause licence. See
[THIRD_PARTY.md](THIRD_PARTY.md).
