#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Check the interfaces the HighPoint RAID management service (hptsvr) uses to
# discover controllers, in the order it uses them:
#
#   1. `lsmod` output matches its driver regex and lists hptiop
#   2. /proc/scsi/scsi lists at least one "Vendor: HPT" device
#   3. every SCSI host driven by hptiop has /proc/scsi/hptiop/<host_no>
#
#   discovery_test.sh               check the running system
#   discovery_test.sh --self-test   check the fixtures (no hardware needed)
#
# Environment overrides (used by --self-test):
#   PROC_ROOT  default /proc
#   SYS_ROOT   default /sys
#   LSMOD_CMD  default lsmod
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

# Driver names hptsvr greps for in lsmod output.
HPTSVR_LSMOD_RE='hptnvme|rr3740|rr640l|rr272|ssd711x|rsnvme|hptiop'

check() {
	local proc=${PROC_ROOT:-/proc} sys=${SYS_ROOT:-/sys}
	local lsmod_cmd=${LSMOD_CMD:-lsmod}
	local fail=0 hosts=0 h n

	if ! $lsmod_cmd | cut -d' ' -f1 | grep -Eq "^($HPTSVR_LSMOD_RE)$"; then
		echo "FAIL: no HighPoint driver in lsmod output"
		fail=1
	fi

	if ! grep -q 'Vendor: HPT ' "$proc/scsi/scsi" 2>/dev/null; then
		echo "FAIL: no HPT device in $proc/scsi/scsi"
		fail=1
	fi

	for h in "$sys"/class/scsi_host/host*; do
		[[ -r $h/proc_name ]] || continue
		[[ $(cat "$h/proc_name") == hptiop ]] || continue
		hosts=$((hosts + 1))
		n=${h##*/host}
		if [[ -r $proc/scsi/hptiop/$n ]]; then
			echo "ok: host$n has $proc/scsi/hptiop/$n"
		else
			echo "FAIL: host$n is driven by hptiop but $proc/scsi/hptiop/$n is missing"
			fail=1
		fi
	done

	if [[ $hosts -eq 0 ]]; then
		echo "FAIL: no SCSI host with proc_name hptiop"
		fail=1
	fi
	return $fail
}

if [[ ${1:-} == --self-test ]]; then
	rc=0
	for fx in good missing-proc; do
		d=$HERE/fixtures/$fx
		out=$(PROC_ROOT=$d/proc SYS_ROOT=$d/sys LSMOD_CMD="cat $d/lsmod.txt" check) &&
			got=pass || got=fail
		want=$([[ $fx == good ]] && echo pass || echo fail)
		if [[ $got == "$want" ]]; then
			echo "self-test $fx: $got (expected)"
		else
			echo "self-test $fx: $got, expected $want" >&2
			printf '%s\n' "$out" >&2
			rc=1
		fi
	done
	exit $rc
fi

check
