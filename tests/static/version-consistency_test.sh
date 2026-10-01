#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# The package version is written in several places; they must all agree:
# Makefile, dkms.conf, debian/changelog, and the newest CHANGELOG.md release.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

make_v=$(sed -n 's/^VERSION := //p' Makefile)
dkms_v=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
deb_v=$(sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' debian/changelog)
chlog_v=$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -n1)

rc=0
for pair in "dkms.conf:$dkms_v" "debian/changelog:$deb_v" "CHANGELOG.md:$chlog_v"; do
	name=${pair%%:*}
	v=${pair#*:}
	if [[ $v != "$make_v" ]]; then
		echo "version mismatch: Makefile=$make_v $name=${v:-<none>}" >&2
		rc=1
	fi
done

# The BUILD_EXCLUSIVE_KERNEL pattern must accept the supported kernels and
# refuse anything older than 6.8.
re=$(sed -n 's/^BUILD_EXCLUSIVE_KERNEL="\(.*\)"/\1/p' dkms.conf)
for k in 6.8.0-142-generic 6.8.0-146-generic 7.0.0-38-generic 6.14.0-1-generic 10.1.0-1-generic; do
	[[ $k =~ $re ]] || { echo "dkms.conf refuses supported/newer kernel $k" >&2; rc=1; }
done
for k in 6.7.0-1-generic 6.5.0-45-generic 5.15.0-100-generic 4.19.0-1-amd64; do
	[[ $k =~ $re ]] && { echo "dkms.conf accepts too-old kernel $k" >&2; rc=1; }
done

[[ $rc -eq 0 ]] && echo "version-consistency: OK ($make_v)"
exit $rc
