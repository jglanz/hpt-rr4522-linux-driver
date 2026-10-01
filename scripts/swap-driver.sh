#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Replace the in-kernel hptiop with this driver on a host whose RocketRAID
# array holds data, one reversible stage at a time. Every stage prints the
# commands it would run; nothing changes unless --apply is given.
#
#   scripts/swap-driver.sh <stage> --vg VG --disk /dev/disk/by-id/ID \
#                          [--mount DIR] [--backup-dir DIR] [--apply]
#
# Stages, in order:
#   preflight      read-only checks; save partition table and LVM metadata to
#                  --backup-dir; install the LVM auto-activation guard
#   live-test      unload the in-kernel hptiop, insmod src/hptiop.ko, verify;
#                  on failure reload the in-kernel driver (nothing persisted)
#   ro-check       activate VG read-only, xfs_repair -n, mount ro,norecovery,
#                  unmount, deactivate
#   persist        unload, dkms install, depmod, reload, verify, remove the
#                  LVM guard, rebuild the initramfs for the running kernel
#   activate-rw    activate the VG read-write and mount --mount (asks first)
#
# The LVM guard (activation/auto_activation_volume_list = [] in
# /etc/lvm/lvmlocal.conf) stops udev from activating the array's VG read-write
# the moment a driver load makes its disk appear. While it is in place, no VG
# is auto-activated, so do not reboot between preflight and persist (an fstab
# entry for the array without "nofail" would stop the boot). The guard is
# removed before the initramfs is rebuilt, so it never reaches the initramfs.
# Rollback: scripts/rollback.sh.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${1:-}
shift || true
VG='' DISK='' MNT='' APPLY=0
BACKUP=/var/backups/hptiop-swap
while [[ $# -gt 0 ]]; do
	case $1 in
	--vg) VG=$2; shift 2 ;;
	--disk) DISK=$2; shift 2 ;;
	--mount) MNT=$2; shift 2 ;;
	--backup-dir) BACKUP=$2; shift 2 ;;
	--apply) APPLY=1; shift ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done
[[ -n $STAGE && -n $VG && -n $DISK ]] || {
	sed -n '4,28p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

# shellcheck source=scripts/swap-common.sh
. "$ROOT/scripts/swap-common.sh"
die() { echo "ABORT: $*" >&2; exit 1; }

lv_active() {
	sudo_ lvs --noheadings -o lv_name --select lv_active=active "$VG" 2>/dev/null | grep -q .
}
refcount() { lsmod | awk '$1 == "hptiop" { print $3 }'; }
loaded_version() {
	local h
	for h in /sys/class/scsi_host/host*; do
		if [[ $(cat "$h/proc_name" 2>/dev/null) == hptiop ]]; then
			cat "$h/driver-version"
			return
		fi
	done
}

require_guard() {
	[[ $APPLY -eq 0 ]] || guard_present || die "LVM guard missing: run preflight"
}

assert_quiescent() {
	[[ -z $MNT ]] || ! findmnt "$MNT" >/dev/null || die "$MNT is mounted"
	! lv_active || die "VG $VG has active LVs"
	! pgrep -x hptsvr >/dev/null || die "hptsvr is running (stop hptdaemon first)"
	local rc
	rc=$(refcount)
	[[ -z $rc || $rc == 0 ]] || die "hptiop refcount $rc"
}

assert_root_not_on_vg() {
	local m src
	for m in / /usr /boot; do
		src=$(findmnt -no SOURCE "$m" 2>/dev/null || true)
		[[ $src != */"$VG"-* && $src != */"$VG"/* ]] ||
			die "$m is on VG $VG; this procedure would make the host unbootable"
	done
}

verify_loaded() {
	local want=$1 n
	sleep 5
	[[ $(loaded_version) == "$want" ]] || die "driver-version $(loaded_version), want $want"
	readlink -e "$DISK" >/dev/null || die "$DISK did not reappear"
	if [[ $want == "v$VERSION" ]]; then
		for n in /sys/class/scsi_host/host*; do
			[[ $(cat "$n/proc_name") == hptiop ]] || continue
			[[ -r /proc/scsi/hptiop/${n##*/host} ]] || die "/proc/scsi/hptiop/${n##*/host} missing"
		done
	fi
	! lv_active || die "VG $VG auto-activated: LVM guard not effective"
	if journalctl -k --since -2min --no-pager |
		grep -E 'IO_PAGE_FAULT|DMAR:.*fault|AMD-Vi.*(fault|error)|hptiop.*(error|timeout|fail)'; then
		die "kernel log shows faults"
	fi
	echo "verified: $(loaded_version), $(readlink -e "$DISK"), VG inactive"
}

# Until persist installs the DKMS module, modprobe resolves to the in-kernel
# driver.
reload_in_tree() {
	echo "reloading the in-kernel hptiop"
	run sudo_ rmmod hptiop || true
	run sudo_ modprobe hptiop || true
	if [[ $APPLY -eq 1 ]]; then
		sleep 5
		echo "loaded: $(loaded_version)"
	fi
	echo "If the controller does not come back, power the host off and on;"
	echo "the VG is inactive, so the array is not being written."
}

# Undo a partial persist: uninstall the DKMS module so that modprobe resolves
# to the in-kernel driver again, then reload it.
persist_failed() {
	echo "persist failed; removing the DKMS module and reloading the in-kernel driver" >&2
	if dpkg-query -W -f='${Status}' hptiop-dkms 2>/dev/null | grep -q 'ok installed'; then
		run sudo_ apt-get remove -y hptiop-dkms || true
	fi
	run sudo_ dkms remove "hptiop/$VERSION" --all || true
	run sudo_ depmod -a "$KREL" || true
	reload_in_tree
}

case $STAGE in
preflight)
	[[ -n $(readlink -e "$DISK") ]] || die "$DISK not found"
	echo "array disk: $(readlink -e "$DISK") $(lsblk -dno MODEL,SERIAL,SIZE "$DISK")"
	assert_root_not_on_vg
	assert_quiescent
	if [[ -n $MNT && $(readlink -f "$BACKUP") == "$(readlink -f "$MNT")"* ]]; then
		die "--backup-dir must not be on the array"
	fi
	run sudo_ mkdir -p "$BACKUP"
	if [[ $APPLY -eq 1 ]]; then
		lsblk -dno MODEL,SERIAL,SIZE "$DISK" | sudo_ tee "$BACKUP/id.txt" >/dev/null
		echo "$DISK" | sudo_ tee "$BACKUP/disk-by-id.txt" >/dev/null
		sudo_ sfdisk -d "$DISK" | sudo_ tee "$BACKUP/partition-table.sfdisk" >/dev/null
		sudo_ vgcfgbackup -f "$BACKUP/$VG.vg" "$VG"
		sudo_ cp -a "/boot/initrd.img-$KREL" "$BACKUP/"
		if [[ -f $LVMLOCAL ]] && ! guard_present; then
			sudo_ cp -a "$LVMLOCAL" "$BACKUP/lvmlocal.conf.orig"
		fi
		(cd "$BACKUP" && sudo_ sha256sum -- * | sudo_ tee SHA256SUMS >/dev/null)
	else
		echo "+ save id, sfdisk -d, vgcfgbackup, initrd, $LVMLOCAL to $BACKUP"
	fi
	if guard_present; then
		echo "LVM guard already present"
	else
		echo "+ append auto_activation_volume_list = [] to $LVMLOCAL"
		if [[ $APPLY -eq 1 ]]; then
			printf '\n%s\nactivation {\n\tauto_activation_volume_list = []\n}\n' \
				"$GUARD_MARK" | sudo_ tee -a "$LVMLOCAL" >/dev/null
			sudo_ lvmconfig activation/auto_activation_volume_list
		fi
	fi
	echo "Do not reboot until persist has completed (the guard disables VG auto-activation)."
	;;
live-test)
	[[ -f $ROOT/src/hptiop.ko ]] || die "build src/hptiop.ko first (make)"
	require_guard
	assert_quiescent
	run sync
	run sudo_ modprobe -r hptiop || die "cannot unload hptiop"
	if ! run sudo_ insmod "$ROOT/src/hptiop.ko"; then
		reload_in_tree
		die "insmod failed; in-kernel driver reloaded"
	fi
	if [[ $APPLY -eq 1 ]] && ! (verify_loaded "v$VERSION"); then
		reload_in_tree
		die "live test failed; in-kernel driver reloaded"
	fi
	;;
ro-check)
	require_guard
	if [[ $APPLY -eq 1 ]]; then
		[[ $(loaded_version) == "v$VERSION" ]] || die "loaded driver is $(loaded_version), not v$VERSION"
		! lv_active || die "VG $VG already active"
		mapfile -t LVS < <(sudo_ lvs --noheadings -o lv_path "$VG" | tr -d ' ')
		(( ${#LVS[@]} > 0 )) || die "no LVs found in $VG"
	else
		LVS=("<each LV of $VG>")
	fi
	tmp=$(mktemp -d)
	cleanup() {
		if [[ $APPLY -eq 1 ]]; then
			if mountpoint -q "$tmp"; then sudo_ umount "$tmp"; fi
			sudo_ vgchange -an "$VG" >/dev/null || true
		fi
		rmdir "$tmp" 2>/dev/null || true
	}
	trap cleanup EXIT
	run sudo_ vgchange -ay --config "activation{read_only_volume_list=[\"$VG\"]}" "$VG"
	for lv in "${LVS[@]}"; do
		run sudo_ blockdev --setro "$lv"
		if [[ $APPLY -eq 1 ]] && ! sudo_ xfs_repair -n "$lv"; then
			echo "xfs_repair -n on $lv reported problems or a dirty log; not replaying it"
		fi
		run sudo_ mount -o ro,norecovery "$lv" "$tmp"
		[[ $APPLY -eq 0 ]] || sudo_ ls "$tmp" | head
		run sudo_ umount "$tmp"
	done
	run sudo_ vgchange -an "$VG"
	;;
persist)
	require_guard
	assert_root_not_on_vg
	assert_quiescent
	# Any exit (failed command, die) before verification completes undoes
	# the install; an ERR trap would not see failures inside functions.
	persist_ok=0
	trap '[[ $? -eq 0 || $persist_ok -eq 1 ]] || persist_failed' EXIT
	run sudo_ rmmod hptiop
	deb=$ROOT/build/deb/hptiop-dkms_${VERSION}_all.deb
	if [[ -f $deb ]]; then
		run sudo_ apt-get install -y "$deb"
	else
		run sudo_ dkms add "$ROOT"
		run sudo_ dkms install "hptiop/$VERSION" -k "$KREL"
	fi
	if [[ $APPLY -eq 1 && $(modinfo -n hptiop) != */updates/dkms/* ]]; then
		die "depmod does not prefer the DKMS module"
	fi
	run sudo_ modprobe hptiop
	[[ $APPLY -eq 0 ]] || verify_loaded "v$VERSION"
	persist_ok=1
	trap - EXIT
	# The lvm2 initramfs hook copies /etc/lvm; remove the guard first so it
	# never reaches the initramfs.
	remove_guard
	run sudo_ update-initramfs -u -k "$KREL"
	if [[ $APPLY -eq 1 ]]; then
		lsinitramfs "/boot/initrd.img-$KREL" | grep 'updates/dkms/hptiop.ko' ||
			die "initramfs does not contain the DKMS hptiop"
	fi
	echo "VG auto-activation is restored; the VG stays inactive until activate-rw or a reboot."
	;;
activate-rw)
	[[ -n $MNT ]] || die "--mount required"
	! guard_present || die "LVM guard still present: run persist"
	if [[ $APPLY -eq 1 ]]; then
		read -r -p "Activate $VG read-write and mount $MNT? [yes/N] " ans
		[[ $ans == yes ]] || die "not confirmed"
		mapfile -t LVS < <(sudo_ lvs --noheadings -o lv_path "$VG" | tr -d ' ')
		(( ${#LVS[@]} > 0 )) || die "no LVs found in $VG"
	else
		LVS=()
	fi
	run sudo_ vgchange -ay "$VG"
	for lv in "${LVS[@]}"; do
		run sudo_ blockdev --setrw "$lv"
	done
	run sudo_ mount "$MNT"
	;;
*)
	echo "unknown stage $STAGE" >&2
	exit 2
	;;
esac
[[ $APPLY -eq 1 ]] || echo "(dry run: add --apply to execute)"
