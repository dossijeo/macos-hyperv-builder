# Third-party components

The builder downloads, but does not vendor:

- [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg), BSD-3-Clause.
- [Lilu](https://github.com/acidanthera/Lilu), BSD-3-Clause.
- [VirtualSMC](https://github.com/acidanthera/VirtualSMC), BSD-3-Clause.
- [MacHyperVSupport](https://github.com/acidanthera/MacHyperVSupport),
  BSD-3-Clause.

The Tahoe compatibility patch in this repository modifies
MacHyperVSupport-derived source and is distributed under the same
BSD-3-Clause terms.

Release assets named `tahoe-hyperv-kexts-*.zip` contain only the two
MacHyperVSupport-derived kext bundles built from the committed patch. They do
not contain Apple software.

macOS and Xcode are Apple software and are not distributed by this project.
