#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Compare sparse findings of this tree with those of the unmodified upstream
# driver for the same kernel; fail on any finding the upstream code lacks.
#
#   sparse-compare.sh <sparse.log> <upstream-ref-dir> <kernel-build-dir>
set -euo pipefail

log=${1:?sparse log}
ref=${2:?upstream ref dir}
kdir=${3:?kernel build dir}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$ROOT/build/sparse/ref

# The kernel build skips sparse with only a notice when it is missing or too
# old; a log without CHECK lines means nothing was checked.
if grep -q 'sparse is not available' "$log" || ! grep -q '^ *CHECK ' "$log"; then
	echo "sparse did not run (see $log)" >&2
	exit 1
fi

rm -rf "$work" && mkdir -p "$work"
cp "$ref/hptiop.c" "$ref/hptiop.h" "$work/"
echo 'obj-m := hptiop.o' > "$work/Kbuild"
make -C "$kdir" M="$work" C=2 CF=-D__CHECK_ENDIAN__ modules > "$work/sparse.log" 2>&1
grep -q '^ *CHECK ' "$work/sparse.log" || { echo "sparse did not run on upstream ref" >&2; exit 1; }

# "path/hptiop.c:123:45: warning: msg" -> "hptiop.c: warning: msg"
norm() {
	sed -nE 's#^(.*/)?(hptiop[^/:]*\.[ch]):[0-9]+:[0-9]+: (warning|error): #\2: \3: #p' "$1" |
		sort | uniq -c | sed -E 's/^ *([0-9]+) /\1\t/'
}

new=$(awk -F'\t' '
	NR == FNR { base[$2] = $1; next }
	$1 > (($2 in base) ? base[$2] : 0) { print $2 }
' <(norm "$work/sparse.log") <(norm "$log"))

if [[ -n $new ]]; then
	echo "sparse: new findings:" >&2
	printf '  %s\n' "$new" >&2
	exit 1
fi
echo "sparse: OK ($(norm "$work/sparse.log" | grep -c . || true) inherited finding types)"
