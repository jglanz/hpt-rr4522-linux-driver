#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Exercise the DKMS life cycle in a clean Ubuntu container, against whatever
# kernel headers the release's archive currently provides:
#
#   1. dkms add/build/install from the source tree, check modinfo, dkms remove
#   2. install the hptiop-dkms .deb (build/deb/), check dkms status, purge
#
#   scripts/dkms-container-test.sh [--image IMAGE]   (default: ubuntu:24.04)
#
# Environment:
#   CONTAINER_ENGINE   docker or podman (default: first one found)
#   IN_CONTAINER=1     run directly in the current system (CI jobs)
#
# The .deb part runs only when build/deb/hptiop-dkms_<version>_all.deb exists
# (scripts/build-deb.sh).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=ubuntu:24.04
[[ ${1:-} == --image ]] && IMAGE=$2

inside() {
	set -euo pipefail
	local src=$1
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends \
		ca-certificates dkms kmod make linux-headers-generic >/dev/null

	local krel cc ver
	krel=$(dpkg-query -W -f='${Depends}' linux-headers-generic |
		grep -oE 'linux-headers-[0-9][^ ,]*-generic' | head -n1 |
		sed 's/^linux-headers-//')
	echo "resolved kernel headers: $krel"
	cc=$(sed -n 's/^CONFIG_CC_VERSION_TEXT="\([^ ]*\).*/\1/p' \
		"/usr/src/linux-headers-$krel/.config")
	apt-get install -y -qq --no-install-recommends "${cc#x86_64-linux-gnu-}" \
		libc6-dev >/dev/null
	ver=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$src/dkms.conf")

	# The kernel's own modules, so that depmod has a complete tree and the
	# test proves updates/dkms takes precedence over the in-kernel hptiop.
	local pkgs=("linux-modules-$krel")
	apt-cache show "linux-modules-extra-$krel" >/dev/null 2>&1 &&
		pkgs+=("linux-modules-extra-$krel")
	apt-get install -y -qq --no-install-recommends "${pkgs[@]}" >/dev/null
	local intree
	intree=$(find "/lib/modules/$krel/kernel" -name 'hptiop.ko*' | head -n1)
	[[ -n $intree ]] || { echo "in-kernel hptiop not found for $krel" >&2; exit 1; }
	echo "in-kernel module: $intree"

	echo "== dkms from source tree"
	mkdir -p "/usr/src/hptiop-$ver/src"
	cp "$src/dkms.conf" "/usr/src/hptiop-$ver/"
	cp "$src"/src/{Kbuild,hptiop.c,hptiop.h,hptiop_compat.h} "/usr/src/hptiop-$ver/src/"
	dkms add "hptiop/$ver"
	dkms build "hptiop/$ver" -k "$krel"
	dkms install "hptiop/$ver" -k "$krel" --force
	local ko
	ko=$(find "/lib/modules/$krel/updates/dkms" -name 'hptiop.ko*' | head -n1)
	[[ -n $ko ]] || { echo "module not installed under updates/dkms" >&2; exit 1; }
	modinfo -F version "$ko" | grep -qx "$ver"
	modinfo -F vermagic "$ko" | grep -q "^$krel "
	modinfo -F alias "$ko" | grep -q 'v00001103d00004522'
	local resolved
	resolved=$(modinfo -k "$krel" -n hptiop 2>&1) || true
	if [[ $resolved != "$ko" ]]; then
		echo "depmod does not resolve hptiop to $ko (got: $resolved)" >&2
		ls -la "/lib/modules/$krel" >&2
		grep -n hptiop "/lib/modules/$krel/modules.dep" >&2 || true
		kmod --version >&2
		exit 1
	fi
	echo "ok: $ko"
	dkms remove "hptiop/$ver" --all
	[[ ! -e $ko ]] || { echo "dkms remove left $ko" >&2; exit 1; }
	rm -rf "/usr/src/hptiop-$ver"

	local deb=$src/build/deb/hptiop-dkms_${ver}_all.deb
	if [[ -f $deb ]]; then
		echo "== hptiop-dkms package"
		apt-get install -y -qq "$deb" >/dev/null
		dkms status "hptiop/$ver" -k "$krel" | grep -q installed
		find "/lib/modules/$krel/updates/dkms" -name 'hptiop.ko*' | grep -q .
		apt-get purge -y -qq hptiop-dkms >/dev/null
		if find "/lib/modules/$krel/updates/dkms" -name 'hptiop.ko*' 2>/dev/null | grep -q .; then
			echo "purge left the module installed" >&2
			exit 1
		fi
		[[ ! -d /usr/src/hptiop-$ver ]] || { echo "purge left /usr/src/hptiop-$ver" >&2; exit 1; }
		echo "ok: package install/purge"
	else
		echo "skip: $deb not built"
	fi
	echo "dkms-container-test: OK ($krel)"
}

if [[ ${IN_CONTAINER:-0} == 1 ]]; then
	inside "$ROOT"
	exit $?
fi

ENGINE=${CONTAINER_ENGINE:-$(command -v docker || command -v podman)}
[[ -n $ENGINE ]] || { echo "need docker or podman" >&2; exit 1; }
"$ENGINE" run --rm -v "$ROOT:/src:ro" -e IN_CONTAINER=1 "$IMAGE" \
	bash -c "$(declare -f inside); inside /src"
