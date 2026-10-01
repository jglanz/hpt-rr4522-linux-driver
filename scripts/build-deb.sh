#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the hptiop-dkms .deb in a clean Ubuntu container and run lintian.
#
#   scripts/build-deb.sh [--image IMAGE]      (default image: ubuntu:24.04)
#
# Environment:
#   CONTAINER_ENGINE   docker or podman (default: first one found)
#   IN_CONTAINER=1     build directly in the current (Debian/Ubuntu) system
#
# Output: build/deb/hptiop-dkms_<version>_all.deb and lintian.log
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=ubuntu:24.04
[[ ${1:-} == --image ]] && IMAGE=$2

inside() {
	set -euo pipefail
	local src=$1 out=$2
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends \
		build-essential debhelper dh-dkms dpkg-dev lintian >/dev/null

	rm -rf /tmp/pkg && mkdir -p /tmp/pkg/hptiop-dkms
	tar -C "$src" --exclude=./build --exclude=./.git -cf - . |
		tar -C /tmp/pkg/hptiop-dkms -xf -
	cd /tmp/pkg/hptiop-dkms
	dpkg-buildpackage -us -uc -b

	mkdir -p "$out"
	cp /tmp/pkg/*.deb /tmp/pkg/*.buildinfo /tmp/pkg/*.changes "$out/"
	# Lint the binary package that is published. The .changes file is not
	# uploaded to an archive, and its suite name (debian/changelog) is only
	# meaningful for a PPA upload, see docs/RELEASING.md.
	lintian --fail-on error,warning --info /tmp/pkg/*.deb 2>&1 |
		tee "$out/lintian.log"
}

OUT=$ROOT/build/deb
if [[ ${IN_CONTAINER:-0} == 1 ]]; then
	inside "$ROOT" "$OUT"
	exit $?
fi

ENGINE=${CONTAINER_ENGINE:-$(command -v docker || command -v podman)}
[[ -n $ENGINE ]] || { echo "need docker or podman" >&2; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT"
"$ENGINE" run --rm -v "$ROOT:/src:ro" -v "$OUT:/out" -e IN_CONTAINER=1 \
	"$IMAGE" bash -c "$(declare -f inside); inside /src /out"
ls -l "$OUT"/*.deb
