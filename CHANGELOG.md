# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-10-01

First release of the out-of-tree driver. The driver source is the upstream
Linux v6.8 `drivers/scsi/hptiop.c` (driver version v1.10.0) with the changes
below; see [docs/VENDOR-DELTA.md](docs/VENDOR-DELTA.md) for the full analysis.

### Added

- `/proc/scsi/hptiop/<host>` entries (`show_info`), which the HighPoint RAID
  management service (`hptsvr`, `hptraidconf`) uses to find controllers.
- Bidirectional DMA mapping for HighPoint management commands (CDB signature
  `02 48 50 54`), so the firmware may read the request under a strict IOMMU.
- Handling of the firmware's device register/unregister notifications: arrays
  created or deleted with the HighPoint tools appear and disappear without a
  manual SCSI rescan.
- Support for the Ubuntu 26.04 kernel (7.0): `.sdev_configure` and the
  `enum scsi_qc_status` queuecommand return type.
- DKMS configuration, Debian packaging (`hptiop-dkms`), CI and release
  workflows, documentation and tests.

### Changed

- The driver reports version `v2.0.0` in sysfs `driver-version`, `/proc` and
  `modinfo`.
- The PCI device table is `const`.

[Unreleased]: https://github.com/jglanz/hpt-rr4522-linux-driver/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/jglanz/hpt-rr4522-linux-driver/releases/tag/v2.0.0
