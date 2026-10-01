# Installation

## Requirements

- Ubuntu 24.04 (6.8 GA kernel) or Ubuntu 26.04 (7.0 GA kernel)
- Kernel headers for every kernel DKMS should build for:
  `sudo apt install linux-headers-generic`
- `dkms` (pulled in by the package)
- Secure Boot: a Machine Owner Key, see [SECURE-BOOT.md](SECURE-BOOT.md)

## Fresh system, or no data on the controller

```sh
sudo apt install ./hptiop-dkms_2.0.0_all.deb
sudo update-initramfs -u
sudo reboot
```

After the reboot, check with the commands in the README's *Verify* section.

## Host whose array holds data

Replacing the module means unloading the driver that serves the array, so
the array must be idle. Three things make this riskier than it looks:

- **LVM auto-activation.** When the driver loads and the array's disk
  appears, udev (`69-lvm.rules`) activates its volume groups read-write
  immediately, before you can check anything.
- **initramfs.** `hptiop` is in the initramfs. A broken module there
  affects the next boot.
- **fstab.** An entry for the array without `nofail` drops the system into
  emergency mode if the array does not appear at boot.

`scripts/swap-driver.sh` performs the change in reversible stages. Every
stage prints its commands and runs them only with `--apply`:

```sh
make                                  # build src/hptiop.ko for this kernel
ID=/dev/disk/by-id/scsi-2...          # the array disk (ls -l /dev/disk/by-id)
VG=my_vg                              # volume group on the array
ARGS="--vg $VG --disk $ID --mount /data --backup-dir /root/hptiop-backup"

sudo umount /data && sudo vgchange -an $VG     # make the array idle
scripts/swap-driver.sh preflight   $ARGS --apply   # backups + LVM guard
scripts/swap-driver.sh live-test   $ARGS --apply   # insmod, verify; nothing persisted
scripts/swap-driver.sh ro-check    $ARGS --apply   # read-only filesystem check
scripts/swap-driver.sh persist     $ARGS --apply   # dkms install, guard removed, initramfs
scripts/swap-driver.sh activate-rw $ARGS --apply   # asks before mounting rw
```

Do not reboot between `preflight` and `persist`: the guard disables LVM
auto-activation, so the array's volume group would not be activated at boot.

What each stage does:

- **preflight** checks that nothing uses the array. It saves the array's
  identity, partition table, LVM metadata, initramfs and `lvmlocal.conf` to
  `--backup-dir`, which must not be on the array. It then adds
  `activation { auto_activation_volume_list = [] }` to
  `/etc/lvm/lvmlocal.conf`. It refuses to run if `/`, `/usr` or `/boot` is
  on the volume group.
- **live-test** unloads the in-kernel driver and loads `src/hptiop.ko` with
  `insmod`. It then verifies the version, `/proc/scsi/hptiop`, that the
  array disk is present, that the VG stayed inactive, and that the kernel log
  has no IOMMU faults. On any failure it reloads the in-kernel driver.
  Nothing is installed, so after `rollback.sh` (which also removes the
  guard) a reboot returns to the in-kernel driver.
- **ro-check** activates the VG with
  `--config 'activation{read_only_volume_list=[…]}'` and marks the LV
  read-only. It runs `xfs_repair -n` and mounts with `ro,norecovery`, so a
  dirty XFS log is not replayed, then unmounts and deactivates.
- **persist** installs through DKMS (or `build/deb/*.deb` if built), checks
  that `modinfo -n hptiop` points into `updates/dkms`, reloads and verifies.
  If any of that fails it uninstalls the DKMS module and reloads the
  in-kernel driver. It then removes the
  guard (restoring the saved `lvmlocal.conf`) and only then rebuilds the
  initramfs, so the guard is never copied into it.
- **activate-rw** activates the VG normally and mounts it, after you type
  `yes`.

If the controller does not come back after an unload (firmware stuck halfway
through initialisation), power the machine off and on. A warm reboot may not
reset the controller. The VG is inactive at that point, so the array is not
being written.

Consider adding `nofail` to the array's fstab entry, so a missing array does
not block booting:

```
/dev/my_vg/my_lv  /data  xfs  defaults,nofail,x-systemd.device-timeout=30s  0 0
```

## HighPoint RAID Management

Install `RAID_Manage_Linux_v3.x.bin` from HighPoint as root. It installs the
`hptsvr` service (`/etc/init.d/hptdaemon`, port 7402) and `hptraidconf`.
Then:

```sh
sudo hptraidconf -u RAID -p hpt query controllers
```

## Uninstall

```sh
sudo apt remove hptiop-dkms        # or: sudo dkms remove hptiop/2.0.0 --all
sudo update-initramfs -u
```

On a host whose array holds data, use `scripts/rollback.sh` (see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md)).
