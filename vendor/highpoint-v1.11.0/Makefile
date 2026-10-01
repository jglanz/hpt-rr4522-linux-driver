# $Id: Makefile,v 1.9 2006/11/01 07:13:03 gmm Exp $
#
# RR3xxx driver Makefile for linux
# Copyright (C) 2005 HighPoint Technologies, Inc.
# All Rights Reserved.
#

#
# change KERNELDIR according to your system
#

KERNELDIR := /lib/modules/$(shell uname -r)/build

#
# Debug Options:
#
#   -DDEBUG: include debug code
#   -DDEBUG_LEVEL=x:
#       0 - No debug output message
#       1 - print only error messages
#       2 - print error and warning
#       3 - print all messages (info, warning, error)
#
ifeq ($(DEBUG),1)
DEBUGOPT = -DDBG=1
ifdef DEBUG_LEVEL
DEBUGOPT += -DDEBUG_LEVEL=$(DEBUG_LEVEL)
else
DEBUGOPT += -DDEBUG_LEVEL=1
endif
endif

ARCH := $(shell uname -m)

obj-m := hptiop.o
TARGET := hptiop.ko

EXTRA_CFLAGS := -DLINUX -D_LINUX_ $(DEBUGOPT)

$(TARGET):
	$(MAKE) -C $(KERNELDIR) SUBDIRS=`pwd` modules

clean:
	rm -fr .hptiop.* hptiop.mod.* *.ko .tmp_versions *~ *.o Module.symvers modules.order 

TARGETNAME=$(shell echo $(TARGET) | cut -f1 -d.)
export KERNELDIR KERNEL_VER TARGETNAME

install: $(TARGET)
	@sh install.sh
