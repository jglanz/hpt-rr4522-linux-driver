#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Create build/release/hptiop-<version>.tar.gz: the DKMS source tree
# (dkms.conf, src/, docs, license) as expected by `dkms ldtarball`-style or
# manual installs into /usr/src/hptiop-<version>.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
version=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
name=hptiop-$version
out=$ROOT/build/release
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/$name/src" "$out"
cp dkms.conf LICENSE README.md CHANGELOG.md "$stage/$name/"
cp src/Kbuild src/hptiop.c src/hptiop.h src/hptiop_compat.h "$stage/$name/src/"
cp -r docs "$stage/$name/"

# Reproducible: fixed owner, mtime from the newest changelog entry, sorted.
mtime=$(date -d "$(sed -n 's/^## \[[0-9][^]]*\] - //p' CHANGELOG.md | head -n1)" +%s)
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$mtime" \
	--mode='u+rwX,go+rX,go-w' \
	-C "$stage" -cf - "$name" | gzip -n > "$out/$name.tar.gz"
echo "$out/$name.tar.gz"
