#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Read-only smoke test on a host with a RocketRAID RR4520/RR4522 installed and
# the DKMS driver loaded. Exits 77 (skipped) when no such controller exists.
#
#   tests/hw/smoke.sh [--expect-version X.Y.Z] [--no-management]
#
# Checks:
#   - the loaded hptiop is the DKMS build (modinfo path under updates/dkms)
#   - sysfs driver-version matches the expected version
#   - /proc/scsi/hptiop/<host> exists for every hptiop host
#   - the controller's RCM device answers INQUIRY (sg_inq, if installed)
#   - tests/userspace/discovery_test.sh passes
#   - no IOMMU/DMA faults or hptiop errors in this boot's kernel log
#   - hptraidconf (if installed) reports >= 1 controller; read-only queries
#
# Only "query" commands are sent to the controller.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
EXPECT=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$ROOT/dkms.conf")
MGMT=1
while [[ $# -gt 0 ]]; do
	case $1 in
	--expect-version) EXPECT=$2; shift 2 ;;
	--no-management) MGMT=0; shift ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

LSPCI=${LSPCI_CMD:-lspci}
if ! { $LSPCI -n -d 1103:4522; $LSPCI -n -d 1103:4520; } 2>/dev/null | grep -q .; then
	echo "skip: no RocketRAID RR4520/RR4522 controller present"
	exit 77
fi

fail=0
pass() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }
# expect <ok message> <failure message> <command...>
expect() {
	local ok=$1 ko=$2
	shift 2
	if "$@"; then pass "$ok"; else bad "$ko"; fi
}

path=$(modinfo -n hptiop 2>/dev/null)
expect "module path $path" "modinfo -n hptiop is $path, not the DKMS build" \
	test "${path#*/updates/dkms/}" != "$path"

hosts=()
for h in /sys/class/scsi_host/host*; do
	[[ $(cat "$h/proc_name" 2>/dev/null) == hptiop ]] && hosts+=("${h##*/host}")
done
[[ ${#hosts[@]} -gt 0 ]] || bad "no SCSI host driven by hptiop"

for n in "${hosts[@]}"; do
	v=$(cat "/sys/class/scsi_host/host$n/driver-version")
	expect "host$n driver-version $v" "host$n driver-version $v, expected v$EXPECT" \
		test "$v" = "v$EXPECT"
	expect "/proc/scsi/hptiop/$n present" "/proc/scsi/hptiop/$n missing" \
		test -r "/proc/scsi/hptiop/$n"
done

if command -v sg_inq >/dev/null; then
	rcm=$(lsscsi -g 2>/dev/null | awk '/HPT +RCM DEVICE/ { print $NF; exit }')
	if [[ -n $rcm ]]; then
		expect "INQUIRY on RCM device $rcm" "INQUIRY on RCM device $rcm failed" \
			sg_inq -o "$rcm"
	fi
fi

expect "hptsvr discovery interfaces" "discovery_test.sh failed" \
	"$ROOT/tests/userspace/discovery_test.sh"

faults=$(journalctl -k -b --no-pager 2>/dev/null |
	grep -E 'IO_PAGE_FAULT|DMAR:.*fault|AMD-Vi.*(fault|error)|hptiop.*(error|timeout|fail)' || true)
expect "no IOMMU/DMA faults or hptiop errors this boot" "kernel log faults:
$faults" test -z "$faults"

if [[ $MGMT -eq 1 ]]; then
	if command -v hptraidconf >/dev/null; then
		out=$(hptraidconf -u RAID -p hpt query controllers 2>&1)
		# hptsvr names controllers by product ("RocketRAID 4522 ...").
		if grep -Eqi 'RocketRAID|RR45[0-9]{2}' <<<"$out"; then
			pass "hptraidconf reports a controller"
		else
			bad "hptraidconf query controllers:
$out"
		fi
		expect "hptraidconf query arrays" "hptraidconf query arrays failed" \
			hptraidconf -u RAID -p hpt query arrays
	else
		echo "skip: hptraidconf not installed"
	fi
fi

exit $fail
