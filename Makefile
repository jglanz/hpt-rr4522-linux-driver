# SPDX-License-Identifier: GPL-2.0-only
#
# Out-of-tree build of the hptiop driver.
#
#   make                      build src/hptiop.ko for the running kernel
#   make KDIR=<build dir>     build against another kernel's headers
#   make check                all static checks (no root, no hardware)
#   make help                 list targets

SHELL := /bin/bash
VERSION := 2.0.0
KDIR ?= /lib/modules/$(shell uname -r)/build
KREL := $(shell cat $(KDIR)/include/config/kernel.release 2>/dev/null)
BUILD := $(CURDIR)/build

# Build with the exact compiler the kernel was built with when it is
# installed (Ubuntu names it e.g. x86_64-linux-gnu-gcc-13); fall back to the
# default compiler otherwise.
KCC := $(firstword $(subst ",,$(shell sed -n 's/^CONFIG_CC_VERSION_TEXT=//p' $(KDIR)/.config 2>/dev/null)))
ifneq ($(KCC),)
ifneq ($(shell command -v $(KCC) 2>/dev/null),)
KMAKE_CC := CC=$(KCC)
endif
endif

KMAKE = $(MAKE) -C $(KDIR) M=$(CURDIR)/src $(KMAKE_CC) HPTIOP_VERSION=$(VERSION)

# Upstream tag whose unmodified hptiop.c defines the W=1 baseline for KREL.
REF_TAG = $(if $(filter 6.8.%,$(KREL)),v6.8,$(if $(filter 7.0.%,$(KREL)),v7.0,unsupported))
REF_DIR = $(BUILD)/kernel-tools/ref/$(REF_TAG)

SHELL_SCRIPTS := $(wildcard scripts/*.sh tools/*.sh tests/*/*.sh)

.PHONY: all modules clean w1 w1-baseline sparse checkpatch jargon shellcheck \
	version-check discovery-test upstream-diff check deb dkms-test container-build \
	kernel-tools help

all modules:
	$(KMAKE) modules

clean:
	$(KMAKE) clean
	rm -rf $(BUILD)/w1 $(BUILD)/baseline $(BUILD)/sparse

kernel-tools:
	scripts/fetch-kernel-tools.sh --verify

w1:
	@mkdir -p $(BUILD)/w1
	$(KMAKE) clean >/dev/null
	$(KMAKE) W=1 modules 2>&1 | tee $(BUILD)/w1/w1.log; test $${PIPESTATUS[0]} -eq 0
	tests/static/w1-baseline_test.sh $(BUILD)/w1/w1.log $(KREL)

w1-baseline: $(REF_DIR)/hptiop.c
	rm -rf $(BUILD)/baseline && mkdir -p $(BUILD)/baseline
	cp $(REF_DIR)/hptiop.c $(REF_DIR)/hptiop.h $(BUILD)/baseline/
	echo 'obj-m := hptiop.o' > $(BUILD)/baseline/Kbuild
	$(MAKE) -C $(KDIR) M=$(BUILD)/baseline $(KMAKE_CC) W=1 modules 2>&1 | \
		tee $(BUILD)/baseline/w1.log; test $${PIPESTATUS[0]} -eq 0
	tests/static/w1-baseline_test.sh --generate $(BUILD)/baseline/w1.log $(KREL)

$(BUILD)/kernel-tools/ref/%/hptiop.c:
	scripts/fetch-kernel-tools.sh --verify

sparse:
	@command -v sparse >/dev/null || { echo "sparse not installed"; exit 1; }
	@mkdir -p $(BUILD)/sparse
	$(KMAKE) clean >/dev/null
	$(KMAKE) C=2 CF=-D__CHECK_ENDIAN__ modules 2>&1 | tee $(BUILD)/sparse/sparse.log; \
		test $${PIPESTATUS[0]} -eq 0
	scripts/sparse-compare.sh $(BUILD)/sparse/sparse.log $(REF_DIR) $(KDIR)

checkpatch: $(BUILD)/kernel-tools/checkpatch.pl
	scripts/checkpatch.sh

$(BUILD)/kernel-tools/checkpatch.pl:
	scripts/fetch-kernel-tools.sh --verify

jargon:
	tests/static/no-session-jargon_test.sh

version-check:
	tests/static/version-consistency_test.sh

shellcheck:
	shellcheck -x $(SHELL_SCRIPTS)

discovery-test:
	tests/userspace/discovery_test.sh --self-test

# Changes of src/ relative to the upstream v6.8 driver it is based on.
upstream-diff: $(BUILD)/kernel-tools/ref/v6.8/hptiop.c
	-diff -u $(BUILD)/kernel-tools/ref/v6.8/hptiop.c src/hptiop.c
	-diff -u $(BUILD)/kernel-tools/ref/v6.8/hptiop.h src/hptiop.h

check: jargon version-check shellcheck discovery-test checkpatch w1

deb:
	scripts/build-deb.sh

dkms-test:
	scripts/dkms-container-test.sh

container-build:
	scripts/container-build.sh

help:
	@echo "Targets: all clean w1 w1-baseline sparse checkpatch jargon"
	@echo "         version-check shellcheck discovery-test upstream-diff check deb"
	@echo "         dkms-test container-build kernel-tools"
	@echo "Variables: KDIR=<kernel build dir> (default: running kernel)"
