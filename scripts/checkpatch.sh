#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Run the kernel's checkpatch.pl --strict over src/ and fail on findings that
# the unmodified upstream v6.8 files do not already have.
#
# Upstream hptiop.c/h carry style findings of their own; rewriting them would
# turn this tree into a reformat of the upstream driver, so they are counted
# as a baseline instead. Every other file (hptiop_compat.h) must be clean.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=${KERNEL_TOOLS_DIR:-$ROOT/build/kernel-tools}
[[ -x $TOOLS/checkpatch.pl ]] || "$ROOT/scripts/fetch-kernel-tools.sh" --verify

# checkpatch.pl reads spelling.txt and const_structs.checkpatch from its own
# directory, which fetch-kernel-tools.sh populates. It exits 1 both for
# findings and for usage errors, so usage errors are detected from the output.
#
# Ignored everywhere: ALLOC_WITH_SIZEOF recommends kmalloc_obj(), which does
# not exist on the 6.8 kernel this driver supports.
# Ignored in hptiop_compat.h only: that file exists to test
# LINUX_VERSION_CODE, which checkpatch flags for in-tree code.
run_checkpatch() {
	local out ignore=FILE_PATH_CHANGES,SPDX_LICENSE_TAG,ALLOC_WITH_SIZEOF
	[[ ${1##*/} == hptiop_compat.h ]] &&
		ignore+=,LINUX_VERSION_CODE,CONSTANT_COMPARISON
	out=$("$TOOLS/checkpatch.pl" --strict --no-tree --show-types --no-summary \
		--emacs --ignore "$ignore" -f "$1" 2>&1) || true
	if grep -qE '^(Usage:|Unknown option)' <<<"$out"; then
		echo "checkpatch.pl did not run on $1:" >&2
		printf '%s\n' "$out" | head -n 5 >&2
		exit 2
	fi
	printf '%s\n' "$out" | grep -E '^[^ #+].*:[0-9]+: (ERROR|WARNING|CHECK):' || true
}

# "file:line: TYPE:CODE: message" -> "TYPE:CODE: message" counted.
findings() {
	run_checkpatch "$1" | sed -E 's/^[^:]*:[0-9]+: //' |
		{ grep -E '^(ERROR|WARNING|CHECK):' || true; } | sort | uniq -c | sed -E 's/^ *([0-9]+) /\1\t/'
}

rc=0
for f in "$ROOT"/src/hptiop.c "$ROOT"/src/hptiop.h "$ROOT"/src/hptiop_compat.h; do
	name=${f##*/}
	ref=$TOOLS/ref/v6.8/$name
	cur=$(findings "$f")
	if [[ -f $ref ]]; then
		base=$(findings "$ref")
	else
		base=
	fi
	new=$(awk -F'\t' '
		NR == FNR { base[$2] = $1; next }
		$1 > (($2 in base) ? base[$2] : 0) {
			printf "%s (+%d)\n", $2, $1 - (($2 in base) ? base[$2] : 0)
		}' <(printf '%s\n' "$base") <(printf '%s\n' "$cur"))
	if [[ -n $new ]]; then
		echo "checkpatch: new findings in src/$name:" >&2
		printf '  %s\n' "$new" >&2
		run_checkpatch "$f" | grep -F -f <(printf '%s\n' "$new" | sed -E 's/ \(\+[0-9]+\)$//') >&2 || true
		rc=1
	else
		echo "checkpatch: src/$name OK ($(printf '%s' "$cur" | grep -c . || true) inherited finding types)"
	fi
done
exit $rc
