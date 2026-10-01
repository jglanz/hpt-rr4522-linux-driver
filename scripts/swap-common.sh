# SPDX-License-Identifier: GPL-2.0-only
# shellcheck shell=bash
#
# Shared by swap-driver.sh and rollback.sh. Callers set APPLY (0 = print
# only) and BACKUP (the --backup-dir) before using these helpers.

# shellcheck disable=SC2034 # VERSION and KREL are used by the sourcing scripts
VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$ROOT/dkms.conf")
# shellcheck disable=SC2034
KREL=$(uname -r)
LVMLOCAL=/etc/lvm/lvmlocal.conf
GUARD_MARK='# hptiop-swap: auto-activation guard'

sudo_() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# Print a command; execute it only with --apply. Returns the command's status.
run() {
	echo "+ $*"
	[[ $APPLY -eq 1 ]] || return 0
	"$@"
}

guard_present() { grep -qF "$GUARD_MARK" "$LVMLOCAL" 2>/dev/null; }

# Undo the LVM auto-activation guard: restore the lvmlocal.conf saved by
# swap-driver.sh preflight, or delete the marked block when none was saved.
remove_guard() {
	if [[ -f $BACKUP/lvmlocal.conf.orig ]]; then
		run sudo_ cp -a "$BACKUP/lvmlocal.conf.orig" "$LVMLOCAL"
	elif guard_present; then
		echo "+ remove the '$GUARD_MARK' block from $LVMLOCAL"
		[[ $APPLY -eq 0 ]] ||
			sudo_ sed -i "/^$GUARD_MARK\$/,/^}\$/d" "$LVMLOCAL"
	fi
	if [[ $APPLY -eq 1 ]] && guard_present; then
		echo "ABORT: LVM guard still present in $LVMLOCAL" >&2
		exit 1
	fi
}
