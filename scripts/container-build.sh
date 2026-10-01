#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the driver inside an Ubuntu container against whatever kernel headers
# that release's archive currently provides. Nothing is pinned: the container
# installs linux-headers-generic and the resolved version is logged.
#
#   scripts/container-build.sh [--image IMAGE] [--] [make targets...]
#
#   --image IMAGE   container image (default: ubuntu:24.04)
#   make targets    default: "w1"
#
# Environment:
#   CONTAINER_ENGINE   docker or podman (default: first one found)
#   IN_CONTAINER=1     run the in-container half directly (used by CI jobs
#                      that already run inside the target image)
#
# Results are copied to build/container/<image-tag>/ (logs, resolved kernel
# version, and the built hptiop.ko).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=ubuntu:24.04
while [[ $# -gt 0 ]]; do
	case $1 in
	--image) IMAGE=$2; shift 2 ;;
	--) shift; break ;;
	*) break ;;
	esac
done
TARGETS=("$@")
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=(w1)

# Kernels since 6.14 only run sparse if it understands __typeof_unqual__
# (scripts/checker-valid.sh), which no sparse release does yet. Use the
# distribution's sparse when it passes that probe, otherwise build sparse
# from its git repository.
install_sparse() {
	local cc=$1 probe
	apt-get install -y -qq --no-install-recommends sparse >/dev/null
	probe=$(mktemp --suffix=.c)
	printf 'static inline int u(const int *q)\n{\n\t__typeof_unqual__(*q) v = *q;\n\treturn v;\n}\n' > "$probe"
	if sparse "$probe" 2>&1 | grep -q error; then
		echo "packaged sparse $(sparse --version) is too old; building from git"
		apt-get install -y -qq --no-install-recommends git >/dev/null
		git clone -q --depth 1 https://git.kernel.org/pub/scm/devel/sparse/sparse.git /tmp/sparse
		echo "sparse source: $(git -C /tmp/sparse rev-parse HEAD)"
		make -s -C /tmp/sparse CC="$cc" HAVE_LLVM=no HAVE_GTK=no HAVE_LIBXML=no \
			HAVE_SQLITE=no PREFIX=/usr/local install >/dev/null
		hash -r
	fi
	rm -f "$probe"
	echo "sparse: $(command -v sparse) $(sparse --version)"
}

# In-container half: install headers + matching compiler, then run make.
inside() {
	set -euo pipefail
	local src=$1 out=$2
	shift 2
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends \
		ca-certificates curl make perl kmod linux-headers-generic >/dev/null

	local krel cc pkg
	krel=$(dpkg-query -W -f='${Depends}' linux-headers-generic |
		grep -oE 'linux-headers-[0-9][^ ,]*-generic' | head -n1 |
		sed 's/^linux-headers-//')
	[[ -n $krel ]] || { echo "cannot resolve linux-headers-generic" >&2; exit 1; }
	echo "resolved kernel headers: $krel"

	# The kernel records the exact compiler it was built with; install it.
	cc=$(sed -n 's/^CONFIG_CC_VERSION_TEXT="\([^ ]*\).*/\1/p' \
		"/usr/src/linux-headers-$krel/.config")
	pkg=${cc#x86_64-linux-gnu-}
	apt-get install -y -qq --no-install-recommends "$pkg" libc6-dev >/dev/null
	command -v "$cc" >/dev/null || { echo "compiler $cc not available" >&2; exit 1; }
	if [[ " $* " == *" sparse "* ]]; then
		install_sparse "$cc"
	fi

	rm -rf /tmp/work && mkdir -p /tmp/work
	cp -a "$src/." /tmp/work/
	rm -rf /tmp/work/build/w1 /tmp/work/build/baseline
	find /tmp/work/src \( -name '*.o' -o -name '*.ko' -o -name '*.mod*' \
		-o -name '.*.cmd' -o -name 'Module.symvers' -o -name modules.order \) \
		-delete

	mkdir -p "$out"
	echo "$krel" > "$out/kernel-release"
	local rc=0
	make -C /tmp/work KDIR="/usr/src/linux-headers-$krel" "$@" \
		2>&1 | tee "$out/make.log" || rc=$?
	cp /tmp/work/build/w1/w1.log "$out/" 2>/dev/null || true
	cp /tmp/work/src/hptiop.ko "$out/" 2>/dev/null || true
	cp /tmp/work/tests/static/w1-baseline/*.txt "$out/" 2>/dev/null || true
	return $rc
}

if [[ ${IN_CONTAINER:-0} == 1 ]]; then
	inside "$ROOT" "$ROOT/build/container/${IMAGE//[:\/]/-}" "${TARGETS[@]}"
	exit $?
fi

ENGINE=${CONTAINER_ENGINE:-$(command -v docker || command -v podman)}
[[ -n $ENGINE ]] || { echo "need docker or podman" >&2; exit 1; }
OUT=$ROOT/build/container/${IMAGE//[:\/]/-}
rm -rf "$OUT" && mkdir -p "$OUT"

"$ENGINE" run --rm \
	-v "$ROOT:/src:ro" -v "$OUT:/out" \
	-e IN_CONTAINER=1 \
	"$IMAGE" bash -c "$(declare -f install_sparse inside); inside /src /out ${TARGETS[*]}"
