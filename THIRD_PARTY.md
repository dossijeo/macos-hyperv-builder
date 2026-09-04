# Third-party components

The builder downloads, but does not vendor:

- [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg), BSD-3-Clause.
- [Lilu](https://github.com/acidanthera/Lilu), BSD-3-Clause.
- [VirtualSMC](https://github.com/acidanthera/VirtualSMC), BSD-3-Clause.
- [MacHyperVSupport](https://github.com/acidanthera/MacHyperVSupport),
  BSD-3-Clause.
- [Compose Multiplatform Core](https://github.com/JetBrains/compose-multiplatform-core),
  Apache-2.0.
- [Skiko](https://github.com/JetBrains/skiko), Apache-2.0.
- [Eclipse Temurin](https://github.com/adoptium/temurin17-binaries),
  GPL-2.0 with the Classpath Exception.
- [BlackHole](https://github.com/ExistentialAudio/BlackHole), GPL-3.0. The
  optional audio installer downloads the official package; it is not vendored
  or redistributed by this repository.

The Tahoe compatibility patch in this repository modifies
MacHyperVSupport-derived source and is distributed under the same
BSD-3-Clause terms.

The UIKit CPU-raster patches modify Compose Multiplatform Core and Skiko
source and are distributed under Apache-2.0. The project stores only source
patches. The guest provisioner downloads the pinned upstream sources and
builds the local Kotlin/Native artifacts on the user's machine.

Release assets named `tahoe-hyperv-kexts-*.zip` contain only the two
MacHyperVSupport-derived kext bundles built from the committed patch. They do
not contain Apple software.

macOS, Xcode and iOS Simulator runtimes are Apple software and are not
distributed by this project.
