# hptiop DKMS driver for HighPoint RocketRAID RR4522

An out-of-tree build of the Linux `hptiop` SCSI driver for HighPoint
RocketRAID 3xxx/4xxx controllers, packaged for DKMS. It is the upstream
kernel driver plus the pieces HighPoint's RAID management software needs to
see and manage the controller.

## Why

The `hptiop` driver shipped with the kernel runs the array fine, but
HighPoint's RAID Management software (`hptsvr` web UI and the `hptraidconf`
CLI, package `RAID_Manage_Linux_v3.x`) reports no controllers:

```
$ sudo hptraidconf -u RAID -p hpt query controllers
(no controllers)
$ tail /var/log/hpt_diag.log
[hptsvr]WARN: can not find device.
[hptsvr]INFO: controller count:0
```

`hptsvr` finds controllers through `/proc/scsi/hptiop/<host>`, which only
HighPoint's own driver creates, and it sends management commands in a form the
upstream driver maps one-way. This driver adds both, without changing the
upstream I/O path. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Supported systems

| Distribution | Kernel | Status |
|---|---|---|
| Ubuntu 24.04 LTS | 6.8 (GA kernel) | supported, tested in CI |
| Ubuntu 26.04 LTS | 7.0 (GA kernel) | supported, tested in CI |

Any other kernel, including those between 6.8 and 7.0, the 24.04 HWE kernels,
Debian and mainline, is **untested and unsupported**. DKMS refuses kernels
older than 6.8; on other newer kernels the build may fail, in which case the
in-kernel driver keeps working.

Controllers: every PCI ID of the upstream driver (RR3xxx, RR4xxx, RR36xx),
including RR4520 (`1103:4520`) and RR4522 (`1103:4522`). Development and
hardware testing use an RR4522.

## Install

From a release `.deb` (installs the DKMS source; DKMS builds the module for
each installed kernel):

```sh
sudo apt install linux-headers-generic
sudo apt install ./hptiop-dkms_2.0.0_all.deb
sudo update-initramfs -u
```

If an array on the controller is in use, read
[docs/INSTALL.md](docs/INSTALL.md) first: the module can only be swapped with
the array unmounted, and LVM may re-activate volumes when the disk reappears.

From source:

```sh
make                 # build src/hptiop.ko for the running kernel
make check           # static checks
sudo dkms add .
sudo dkms install hptiop/2.0.0
```

With Secure Boot enabled, the module must be signed with an enrolled key; see
[docs/SECURE-BOOT.md](docs/SECURE-BOOT.md).

## Verify

```sh
cat /sys/class/scsi_host/host*/driver-version     # v2.0.0
ls /proc/scsi/hptiop/                             # one entry per controller
modinfo -n hptiop                                 # .../updates/dkms/hptiop.ko*
sudo hptraidconf -u RAID -p hpt query controllers
tests/hw/smoke.sh                                 # read-only hardware test
```

## Documentation

- [docs/INSTALL.md](docs/INSTALL.md): installation, including on a host whose
  array holds data
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the driver and the
  management service interact, and what differs from upstream
- [docs/VENDOR-DELTA.md](docs/VENDOR-DELTA.md): the HighPoint v1.11.0 vs
  upstream comparison behind each change
- [docs/SECURE-BOOT.md](docs/SECURE-BOOT.md): module signing
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): common problems and
  rollback
- [docs/RELEASING.md](docs/RELEASING.md): making a release
- [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
  [CHANGELOG.md](CHANGELOG.md)

## License

GPL-2.0-only, the license of the upstream driver and of HighPoint's source
release. See [LICENSE](LICENSE). The pristine HighPoint v1.11.0 sources are
kept in `vendor/highpoint-v1.11.0/` for reference and are not built.

This project is not affiliated with HighPoint Technologies, Inc.
