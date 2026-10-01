# Architecture

## Components

```
 hptraidconf (CLI) / web browser
        │ TCP 127.0.0.1:7402
        ▼
 hptsvr (HighPoint RAID management service, userspace)
   1. lsmod | grep -E 'hptnvme|rr3740|…|hptiop'      → driver loaded?
   2. /proc/scsi/scsi                               → HPT devices
   3. /proc/scsi/hptiop/<host_no>                   → controller hosts
   4. SG_IO on the controller's sg nodes            → management commands
        │
        ▼
 hptiop (this driver)  ── SCSI midlayer ──  /dev/sdX (arrays)
        │ request queue / doorbell / messages (MMIO)
        ▼
 RocketRAID firmware (IOP)
```

The controller presents each array (and each pass-through disk) as a SCSI
disk on target id `n`, and a `HPT RCM DEVICE` processor device on a high
target id (32 on an RR4522) that the management service talks to.

## I/O path

Unchanged from upstream v6.8. `queuecommand` takes a request slot, builds a
scatter/gather list with `scsi_dma_map()`, and posts the request to the
firmware's inbound list (`hptiop_post_req_mvfrey()` on RR4520/RR4522).
Completions arrive through the interrupt handler.

## Changes compared with upstream

### `/proc/scsi/hptiop/<host_no>`

`show_info` in the host template makes the SCSI midlayer create the file when
the kernel is built with `CONFIG_SCSI_PROC_FS` (Ubuntu kernels are). It prints
driver version, IRQ, SDRAM size, reset count, SG limit and request size,
matching HighPoint's driver. `hptsvr` needs the file to exist; without
`CONFIG_SCSI_PROC_FS` management does not work.

### Bidirectional management commands

`hptsvr` sends vendor commands whose CDB begins with the signature
`HPT_SCSI_IOCTL_SIG` (bytes `02 48 50 54`, `{2,'H','P','T'}`). The buffer
holds the request on the way in and the firmware's reply on the way out.

SG_IO with `SG_DXFER_TO_FROM_DEV` becomes a `REQ_OP_DRV_IN` request, and the
midlayer sets `sc_data_direction = DMA_FROM_DEVICE`. The kernel copies the
user data into the buffer, but the DMA mapping allows only device writes.
With a strict IOMMU the firmware's read of the request faults
(`AMD-Vi: IO_PAGE_FAULT`, `DMAR: DRHD: handling fault`). `swiotlb` bouncing
is not affected: since 6.0 it copies the buffer for every direction.

`hptiop_buildsgl()` therefore sets `DMA_BIDIRECTIONAL` before `scsi_dma_map()`
for passthrough requests carrying the signature. Filesystem I/O never matches.

### Device hot-plug notifications

The firmware posts `REGISTER_DEVICE_n` / `UNREGISTER_DEVICE_n` messages
(0x100–0x2ff) when an array is created or deleted. They arrive in interrupt
context, so `hptiop_message_callback()` queues a work item on an ordered
per-host workqueue; the work calls `scsi_add_device()` or
`scsi_remove_device()` for target `n`. Notifications are ignored until
`scsi_scan_host()` has run, because the firmware is already started before
the host is registered and the initial scan finds every existing device.
`hptiop_remove()` stops new work under the host lock and destroys (drains)
the workqueue before `scsi_remove_host()`.

## Kernel compatibility

`src/hptiop.c` tests only `HPTIOP_HAVE_*` macros; the version checks live in
`src/hptiop_compat.h`.

| Item | 6.8 (Ubuntu 24.04) | 7.0 (Ubuntu 26.04) | Macro |
|---|---|---|---|
| Device configure hook | `.slave_configure(sdev)` + `blk_queue_max_hw_sectors()` | `.sdev_configure(sdev, lim)`, `lim->max_hw_sectors` | `HPTIOP_HAVE_SDEV_CONFIGURE` (≥ 6.14) |
| `queuecommand` return | `int` | `enum scsi_qc_status` | `HPTIOP_HAVE_SCSI_QC_STATUS` (≥ 7.0) |
| PCI ID table | `const` accepted | `const` | none |

Adding a kernel means adding a CI cell and, if its API differs, a macro here.

## Packaging

- `dkms.conf` builds `src/` with Kbuild (`make -C <kernel> M=…/src`) and
  installs into `/lib/modules/<kernel>/updates/dkms/`. depmod searches
  `updates` before the in-kernel `kernel/` tree, so `modprobe hptiop` loads
  this module while the distribution's file stays untouched.
- The module keeps the name `hptiop`: `hptsvr` looks for it by name in
  `lsmod`, and the in-kernel driver remains the automatic fallback.
- `hptiop` is part of the initramfs on systems that boot with the controller
  present, so `update-initramfs -u` is part of installation.
- `debian/` builds `hptiop-dkms_<version>_all.deb` with `dh-dkms`; its
  maintainer scripts run `dkms add/build/install` and `dkms remove`.
