#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Return a host to the in-kernel hptiop driver. The in-kernel module file is
# never modified by this project, so removing the DKMS module and rebuilding
# the initramfs is enough. Prints the commands; runs them only with --apply.
#
#   scripts/rollback.sh --vg VG [--mount DIR] [--backup-dir DIR] [--apply]
#
# Steps:
#   1. stop hptdaemon, unmount, deactivate the VG
#   2. remove the LVM auto-activation guard left by swap-driver.sh, restoring
#      lvmlocal.conf from --backup-dir when it was saved there
#   3. remove the hptiop-dkms package or the DKMS module, depmod
#   4. rebuild the initramfs for the running kernel
#   5. reload hptiop (now the in-kernel driver) and show its version
#   6. activate the VG and mount again
#
# Restoring the partition table or LVM metadata from --backup-dir is a
# separate, manual last resort; see docs/TROUBLESHOOTING.md.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VG='' MNT='' APPLY=0
BACKUP=/var/backups/hptiop-swap
while [[ $# -gt 0 ]]; do
	case $1 in
	--vg) VG=$2; shift 2 ;;
	--mount) MNT=$2; shift 2 ;;
	--backup-dir) BACKUP=$2; shift 2 ;;
	--apply) APPLY=1; shift ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done
[[ -n $VG ]] || { sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# shellcheck source=scripts/swap-common.sh
. "$ROOT/scripts/swap-common.sh"

if [[ -x /etc/init.d/hptdaemon ]]; then
	run sudo_ /etc/init.d/hptdaemon stop || true
fi
if [[ -n $MNT ]] && findmnt "$MNT" >/dev/null; then
	run sudo_ umount "$MNT"
fi
# The VG may be missing when the driver never brought the disk up.
run sudo_ vgchange -an "$VG" || true

if guard_present; then
	remove_guard
fi

if dpkg-query -W -f='${Status}' hptiop-dkms 2>/dev/null | grep -q 'ok installed'; then
	run sudo_ apt-get remove -y hptiop-dkms
elif dkms status "hptiop/$VERSION" 2>/dev/null | grep -q .; then
	run sudo_ dkms remove "hptiop/$VERSION" --all
fi
run sudo_ depmod -a "$KREL"
run sudo_ update-initramfs -u -k "$KREL"

run sudo_ rmmod hptiop || true
run sudo_ modprobe hptiop
if [[ $APPLY -eq 1 ]]; then
	sleep 5
	echo "module: $(modinfo -n hptiop)"
	grep -H . /sys/class/scsi_host/host*/driver-version 2>/dev/null || true
fi

run sudo_ vgchange -ay "$VG"
if [[ -n $MNT ]]; then
	run sudo_ mount "$MNT"
fi
[[ $APPLY -eq 1 ]] || echo "(dry run: add --apply to execute)"
