# Troubleshooting

## Which driver is loaded?

```sh
modinfo -n hptiop                                  # updates/dkms/... = this driver
cat /sys/class/scsi_host/host*/driver-version      # v2.0.0 = this driver
dkms status hptiop
```

The in-kernel driver reports `v1.10.0` and has no `/proc/scsi/hptiop/`.

## `hptraidconf` shows no controllers

1. `tests/userspace/discovery_test.sh` checks the three things `hptsvr`
   uses: the `lsmod` entry, `HPT` devices in `/proc/scsi/scsi`, and
   `/proc/scsi/hptiop/<host>`.
2. If `/proc/scsi/hptiop/` is missing, the in-kernel driver is loaded: see
   *DKMS build skipped or failed* below.
3. `hptsvr` scans when it starts. Restart it after changing drivers:
   `sudo /etc/init.d/hptdaemon restart`.
4. `/var/log/hpt_diag.log` shows `can not find device` while discovery fails.

## DKMS build skipped or failed

- `dkms status` shows nothing for the running kernel:
  - Kernel older than 6.8: refused on purpose (`BUILD_EXCLUSIVE_KERNEL`).
  - Headers missing: `sudo apt install linux-headers-$(uname -r)`, then
    `sudo dkms autoinstall`.
- Build errors on a kernel other than Ubuntu 24.04 (6.8) or 26.04 (7.0):
  that kernel is unsupported; its SCSI API probably changed. The in-kernel
  driver stays in use. The log is in
  `/var/lib/dkms/hptiop/2.0.0/build/make.log`.
- `Key was rejected by service`: see [SECURE-BOOT.md](SECURE-BOOT.md).

## New kernel installed, old driver back

DKMS builds for each new kernel when its headers are installed. Install
`linux-headers-generic` so headers follow kernel updates, then:

```sh
sudo dkms autoinstall
sudo update-initramfs -u
```

## The volume group activated by itself

When `hptiop` loads, the array disk appears and udev activates any LVM
volume group on it read-write. `scripts/swap-driver.sh preflight` adds a
guard to `/etc/lvm/lvmlocal.conf` for the duration of a swap:

```
activation {
	auto_activation_volume_list = []
}
```

`swap-driver.sh persist` and `rollback.sh` remove it again (restoring the
saved `lvmlocal.conf`). If a swap was abandoned in between, remove the block
marked `# hptiop-swap: auto-activation guard` by hand and run
`update-initramfs -u`; otherwise no VG is auto-activated at boot.

## The controller did not come back after unloading

If `modprobe hptiop` (either driver) times out and no SCSI host appears,
the firmware is stuck halfway through initialisation. Power the machine off
completely and on again; a warm reboot may not reset the controller.

## IOMMU faults

`AMD-Vi: ... IO_PAGE_FAULT` or `DMAR: [DMA Read] ... fault` mentioning the
controller during management operations indicates a mapping problem. Check
which driver is loaded (above): the in-kernel driver maps management commands
one-way. Please report faults that occur with this driver, including
`journalctl -k`.

## Roll back to the in-kernel driver

```sh
scripts/rollback.sh --vg <vg> --mount <dir>            # dry run
scripts/rollback.sh --vg <vg> --mount <dir> --apply
```

It stops `hptdaemon`, unmounts, deactivates the VG, and removes the
package/DKMS module. It then rebuilds the initramfs, reloads the in-kernel
driver, and activates and mounts again. The in-kernel module file is never
modified by this project.

### Last resort: restore partition table or LVM metadata

Only if the partition table or LVM metadata was damaged, and only after
checking that the disk is the one the backup came from:

```sh
B=/root/hptiop-backup                                  # --backup-dir used before
DISK=$(cat $B/disk-by-id.txt)
lsblk -dno MODEL,SERIAL,SIZE "$DISK"; cat $B/id.txt    # must match exactly
sudo sfdisk "$DISK" < $B/partition-table.sfdisk
sudo vgcfgrestore -f $B/<vg>.vg <vg>
```
