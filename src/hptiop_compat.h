/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Kernel API differences between the supported kernels.
 *
 * The driver source is the upstream v6.8 hptiop.c. Ubuntu 24.04 (6.8) and
 * Ubuntu 26.04 (7.0) are the supported targets; every kernel-version test
 * lives in this file and is exposed to hptiop.c as a feature macro, so the
 * driver itself only ever tests HPTIOP_HAVE_* symbols.
 */
#ifndef _HPTIOP_COMPAT_H_
#define _HPTIOP_COMPAT_H_

#include <linux/version.h>

/*
 * v6.10 replaced .slave_configure with .device_configure(sdev, lim), and
 * v6.14 renamed it to .sdev_configure(sdev, lim); queue limits are then set
 * through @lim instead of blk_queue_max_hw_sectors().
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 14, 0)
#define HPTIOP_HAVE_SDEV_CONFIGURE 1
#endif

/* v7.0 changed the .queuecommand return type to enum scsi_qc_status. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
#define HPTIOP_HAVE_SCSI_QC_STATUS 1
#endif

#ifdef HPTIOP_HAVE_SCSI_QC_STATUS
#define HPTIOP_QC_RET enum scsi_qc_status
#else
#define HPTIOP_QC_RET int
#endif

#endif /* _HPTIOP_COMPAT_H_ */
