#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Fetch upstream reference sources and kernel style tooling from kernel.org.
#
#   scripts/fetch-kernel-tools.sh [--verify]
#
# Downloads into build/kernel-tools/:
#   ref/v6.8/hptiop.{c,h}   upstream base the driver in src/ is derived from
#   ref/v7.0/hptiop.{c,h}   upstream copy for the newest supported kernel
#   checkpatch.pl, spelling.txt, const_structs.checkpatch (from TOOLS_TAG)
#
# With --verify, the downloaded reference files are checked against the
# sha256 sums pinned below, so a silent change upstream cannot go unnoticed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${KERNEL_TOOLS_DIR:-$ROOT/build/kernel-tools}
BASE_URL=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain
TOOLS_TAG=${TOOLS_TAG:-v7.0}

declare -A PINNED=(
	[ref/v6.8/hptiop.c]=3846aa1753981842a898803af2fc798ff2e51b4214f7bd3e27f30f0d9b1be3d5
	[ref/v6.8/hptiop.h]=07f17c0012f96a44a9bc96fe7cdafc8d56152f96e7e79d79a53cd70e13591d93
	[ref/v7.0/hptiop.c]=d3d7f00d3be47593b965f1521c2b7e6cca60242993983a0dd18fa7676972e9bd
	[ref/v7.0/hptiop.h]=07f17c0012f96a44a9bc96fe7cdafc8d56152f96e7e79d79a53cd70e13591d93
)

fetch() {
	local path=$1 tag=$2 dest=$3
	mkdir -p "$(dirname "$dest")"
	curl -fsSL --retry 3 -o "$dest.tmp" "$BASE_URL/$path?h=$tag"
	mv "$dest.tmp" "$dest"
}

for tag in v6.8 v7.0; do
	for f in hptiop.c hptiop.h; do
		fetch "drivers/scsi/$f" "$tag" "$OUT/ref/$tag/$f"
	done
done

fetch scripts/checkpatch.pl "$TOOLS_TAG" "$OUT/checkpatch.pl"
fetch scripts/spelling.txt "$TOOLS_TAG" "$OUT/spelling.txt"
fetch scripts/const_structs.checkpatch "$TOOLS_TAG" "$OUT/const_structs.checkpatch"
chmod +x "$OUT/checkpatch.pl"

sums=$(cd "$OUT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort |
	xargs sha256sum)
printf '%s\n' "$sums" > "$OUT/SHA256SUMS"

if [[ ${1:-} == --verify ]]; then
	rc=0
	for f in "${!PINNED[@]}"; do
		got=$(sha256sum "$OUT/$f" | cut -d' ' -f1)
		if [[ $got != "${PINNED[$f]}" ]]; then
			echo "MISMATCH $f: $got != ${PINNED[$f]}" >&2
			rc=1
		fi
	done
	exit $rc
fi

echo "kernel tools in $OUT"
