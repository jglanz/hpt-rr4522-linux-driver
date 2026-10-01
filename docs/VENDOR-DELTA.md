# Vendor delta: HighPoint v1.11.0 vs upstream Linux v6.8

This document records where `src/` comes from and why each difference between
HighPoint's last open-source driver and the upstream kernel driver was taken
or left out.

## Sources

| Source | Version | sha256 |
|---|---|---|
| Upstream `drivers/scsi/hptiop.c` | v6.8 (driver v1.10.0) | `3846aa1753981842a898803af2fc798ff2e51b4214f7bd3e27f30f0d9b1be3d5` |
| Upstream `drivers/scsi/hptiop.h` | v6.8 (identical in v7.0) | `07f17c0012f96a44a9bc96fe7cdafc8d56152f96e7e79d79a53cd70e13591d93` |
| Upstream `drivers/scsi/hptiop.c` | v7.0 | `d3d7f00d3be47593b965f1521c2b7e6cca60242993983a0dd18fa7676972e9bd` |
| HighPoint `RR3xxx_4xxx_Linux_Src_v1.11.0_17_09_19.tgz` | v1.11.0 (2017-09-19) | `7b5b41f699f5f148ef1b5c5e29ef6ea19bfed84babaaee36b6e4faaaa81fca64` |
| `vendor/highpoint-v1.11.0/hptiop.c` | from the tarball | `9388786d9949826e6fc916b72b442d84a9fd50a0d48bdac6afb2f617b0df42a2` |
| `vendor/highpoint-v1.11.0/hptiop.h` | from the tarball | `a281cb9538d5d988bfc295579f7c66dbf62e32d3763bc841e7268761f8913379` |

`scripts/fetch-kernel-tools.sh --verify` downloads the upstream files from
git.kernel.org and checks them against these sums. The files in `src/`
started as byte-identical copies of the v6.8 files.

### Ubuntu kernels

Ubuntu's copies of the driver were compared against upstream:

| Ubuntu kernel | `hptiop.c` / `hptiop.h` |
|---|---|
| 24.04, `Ubuntu-6.8.0-142.142` tag | identical to upstream v6.8 |
| 26.04, `Ubuntu-7.0.0-38.38` tag | identical to upstream v7.0 |

So the code that runs on Ubuntu today is exactly the upstream code this tree
is based on, and Ubuntu carries no driver patches that would need porting.

## Upstream changes v6.8 → v7.0

All upstream commits touching the driver between the two supported kernels
are kernel API changes, not functional fixes:

| Commit | Change | Handling |
|---|---|---|
| `f65eb761f811` scsi: hptiop: Switch to using ->device_configure (6.10) | `.slave_configure` → `.device_configure(sdev, lim)` | covered by `HPTIOP_HAVE_SDEV_CONFIGURE` |
| `47c2e30afcec` scsi: Rename .device_configure() into .sdev_configure() (6.14) | rename | `HPTIOP_HAVE_SDEV_CONFIGURE` (6.14+) |
| `c9a71ca13f71` scsi: Constify struct pci_device_id | `const` table | adopted unconditionally (valid on 6.8) |
| `0db3f51839fe` scsi: Change the return type of the .queuecommand() callback (7.0) | `enum scsi_qc_status` | `HPTIOP_HAVE_SCSI_QC_STATUS` |

Kernels 6.10–6.13 used `.device_configure`, which this tree does not shim;
those kernels are not supported.

## HighPoint v1.11.0 vs upstream v6.8

The vendor driver supports kernels back to 2.4 through `LINUX_VERSION_CODE`
branches. The comparison below looks at what each function does on a modern
kernel. 53 functions are identical apart from whitespace; the rest are
classified here.

### Grafted into `src/`

| Vendor behaviour | Why it is needed | Implementation |
|---|---|---|
| `show_info` creating `/proc/scsi/hptiop/<host>` | `hptsvr` discovers controllers by reading `/proc/scsi/scsi` and listing `/proc/scsi/<driver>/`. Without the directory it logs `can not find device` and reports 0 controllers, even though the array works. | `hptiop_show_info()`, per host, same text as the vendor driver (without a trailing space before one newline) |
| `DMA_BIDIRECTIONAL` for CDBs starting with `HPT_SCSI_IOCTL_SIG` (`02 'H' 'P' 'T'`) | Management commands carry the request and the reply in one buffer. SG_IO maps a `SG_DXFER_TO_FROM_DEV` request as `DMA_FROM_DEVICE`, so under a strict IOMMU the firmware may not read the request. With `iommu=pt` or no IOMMU the mapping is not enforced. | `hptiop_buildsgl()`, restricted to passthrough requests |
| Firmware device notifications `REGISTER_DEVICE`/`UNREGISTER_DEVICE` (0x100–0x2ff) → `scsi_add_device()`/`scsi_remove_device()` | Arrays created or deleted through the management tools appear and disappear without a manual rescan. Upstream defines the message codes but ignores them. | `hptiop_queue_hotplug()` queues work on an ordered per-host workqueue, which `hptiop_remove()` stops and drains before removing the host. Unlike the vendor code, the work never outlives the host. |

### Already equivalent upstream

| Vendor | Upstream | Notes |
|---|---|---|
| v1.11.0 "fix init failure with IOMMU enabled": requests addressed by full `dma_addr_t req_phy` | `u32 req_shifted_phy = phy >> 5` | Identical for addresses below 2^37. Request buffers come from `dma_alloc_coherent()` and the coherent DMA mask is left at its 32-bit default, so their addresses are always below 4 GiB. The context/`inlist` encodings compute the same values. |
| PCI ID table (32 devices, including 4520/4522 and 36xx) | same 32 IDs | identical |
| `iop_intr_mvfrey()` read-pointer handling with a local copy | updates `outlist_rptr` in the loop | same result |
| `get_req()`/`free_req()` clearing `next`/`scp` | not cleared | values are always overwritten before use |

### Obsolete or not applicable

| Vendor | Reason |
|---|---|
| `LINUX_VERSION_CODE` branches for 2.4–4.x, `pci_map_*`, `use_sg`, `scp->scsi_done`, `__devinit`, `SA_SHIRQ` | APIs removed from current kernels; upstream uses the modern equivalents |
| `DRIVER_INVALID << 24` in aborted command results | removed from the SCSI midlayer (upstream `16576ad8a8f0`) |
| global HBA list printed in every `/proc` file | per-host output is sufficient for discovery |
| `hptiop_revalidate_device()` (message 0x300–0x3ff) | empty function in the vendor driver |
| one-element arrays `sg_list[1]`, `buf[1]` | upstream uses flexible arrays |

No other functional differences were found. Changes to this list are made in
`src/` with a matching row here.
