K=kernel
U=user
O=build

OBJS = \
  $K/entry.o \
  $K/start.o \
  $K/console.o \
  $K/printk.o \
  $K/uart.o \
  $K/kalloc.o \
  $K/spinlock.o \
  $K/string.o \
  $K/main.o \
  $K/vm.o \
  $K/proc.o \
  $K/swtch.o \
  $K/trampoline.o \
  $K/trap.o \
  $K/syscall.o \
  $K/sysproc.o \
  $K/bio.o \
  $K/fs.o \
  $K/log.o \
  $K/sleeplock.o \
  $K/file.o \
  $K/pipe.o \
  $K/exec.o \
  $K/sysfile.o \
  $K/kernelvec.o \
  $K/plic.o \
  $K/virtio_disk.o

KOBJS = $(addprefix $(O)/, $(OBJS))

# riscv64-unknown-elf- or riscv64-linux-gnu-
# perhaps in /opt/riscv/bin
#TOOLPREFIX = 

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if riscv64-unknown-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-unknown-elf-'; \
	elif riscv64-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-elf-'; \
	elif riscv64-none-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-none-elf-'; \
	elif riscv64-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-linux-gnu-'; \
	elif riscv64-unknown-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-unknown-linux-gnu-'; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find a riscv64 version of GCC/binutils." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

QEMU = qemu-system-riscv64
MIN_QEMU_VERSION = 7.2

CC = $(TOOLPREFIX)gcc
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
ifndef GDB
GDB = $(shell if which gdb-multiarch >/dev/null 2>&1; then echo 'gdb-multiarch'; else echo 'gdb'; fi)
endif

# Deterministic builds.
DETFLAGS = -ffile-prefix-map=$(CURDIR)=.

CFLAGS = -Wall -Werror -Wno-unknown-attributes -O -fno-omit-frame-pointer -ggdb -gdwarf-2
CFLAGS += $(DETFLAGS)
CFLAGS += -march=rv64gc
CFLAGS += -std=gnu99
CFLAGS += -MD
CFLAGS += -mcmodel=medany
CFLAGS += -ffreestanding
CFLAGS += -fno-common -nostdlib
CFLAGS += -fno-builtin-strncpy -fno-builtin-strncmp -fno-builtin-strlen -fno-builtin-memset
CFLAGS += -fno-builtin-memmove -fno-builtin-memcmp -fno-builtin-log -fno-builtin-bzero
CFLAGS += -fno-builtin-strchr -fno-builtin-exit -fno-builtin-malloc -fno-builtin-putc
CFLAGS += -fno-builtin-free
CFLAGS += -fno-builtin-memcpy -Wno-main
CFLAGS += -fno-builtin-printf -fno-builtin-fprintf -fno-builtin-vprintf
CFLAGS += -I.
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)

# Disable PIE when possible (for Ubuntu 16.10 toolchain)
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

LDFLAGS = -z max-page-size=4096

$(O)/kernel $(O)/user $(O)/mkfs:
	@mkdir -p $@

$(O)/$K/kernel: $(KOBJS) $K/kernel.ld | $(O)/kernel
	$(LD) $(LDFLAGS) -T $K/kernel.ld -o $@ $(KOBJS) 
	$(OBJDUMP) -S $@ > $(O)/$K/kernel.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(O)/$K/kernel.sym

# Compatibility target
kernel/kernel: $(O)/$K/kernel

$(O)/$K/%.o: $K/%.c | $(O)/kernel
	$(CC) $(CFLAGS) -c -o $@ $<

$(O)/$K/%.o: $K/%.S | $(O)/kernel
	$(CC) -march=rv64gc -g $(DETFLAGS) -c -o $@ $<

tags: $(OBJS)
	etags kernel/*.S kernel/*.c

ULIB = $(O)/$U/ulib.o $(O)/$U/usys.o $(O)/$U/printf.o $(O)/$U/umalloc.o

$(O)/$U/_%: $(O)/$U/%.o $(ULIB) $U/user.ld | $(O)/user
	$(LD) $(LDFLAGS) -T $U/user.ld -o $@ $< $(ULIB)
	$(OBJDUMP) -S $@ > $(O)/$U/$*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(O)/$U/$*.sym

$(O)/$U/%.o: $U/%.c | $(O)/user
	$(CC) $(CFLAGS) -c -o $@ $<

$(O)/$U/usys.S : $U/usys.pl | $(O)/user
	perl $U/usys.pl > $@

$(O)/$U/usys.o : $(O)/$U/usys.S | $(O)/user
	$(CC) $(CFLAGS) -c -o $@ $<

$(O)/$U/_forktest: $(O)/$U/forktest.o $(ULIB) | $(O)/user
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $(O)/$U/forktest.o $(O)/$U/ulib.o $(O)/$U/usys.o
	$(OBJDUMP) -S $@ > $(O)/$U/forktest.asm

$(O)/mkfs/mkfs: mkfs/mkfs.c $K/fs.h $K/param.h | $(O)/mkfs
	gcc -Wno-unknown-attributes -I. -o $@ mkfs/mkfs.c

# Prevent deletion of intermediate files, e.g. cat.o, after first build, so
# that disk image changes after first build are persistent until clean.  More
# details:
# http://www.gnu.org/software/make/manual/html_node/Chained-Rules.html
.PRECIOUS: $(O)/$K/%.o $(O)/$U/%.o

UPROGS=\
	$(O)/$U/_cat\
	$(O)/$U/_echo\
	$(O)/$U/_forktest\
	$(O)/$U/_grep\
	$(O)/$U/_init\
	$(O)/$U/_kill\
	$(O)/$U/_ln\
	$(O)/$U/_ls\
	$(O)/$U/_mkdir\
	$(O)/$U/_rm\
	$(O)/$U/_sh\
	$(O)/$U/_stressfs\
	$(O)/$U/_usertests\
	$(O)/$U/_grind\
	$(O)/$U/_wc\
	$(O)/$U/_zombie\
	$(O)/$U/_logstress\
	$(O)/$U/_forphan\
	$(O)/$U/_dorphan\
	$(O)/$U/_sync\

fs.img: $(O)/mkfs/mkfs user/WELCOME $(UPROGS)
	$(O)/mkfs/mkfs fs.img user/WELCOME $(UPROGS)

-include $(O)/$K/*.d $(O)/$U/*.d

clean: 
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	*/*.o */*.d */*.asm */*.sym \
	$K/kernel fs.img \
	mkfs/mkfs .gdbinit \
        $U/usys.S \
	$(UPROGS)
	rm -rf $(O) .gdb

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
ifndef CPUS
CPUS := 3
endif

QEMUOPTS = -machine virt -bios none -kernel $(O)/$K/kernel -m 128M -smp $(CPUS) -nographic
QEMUOPTS += -global virtio-mmio.force-legacy=false
QEMUOPTS += -drive file=fs.img,if=none,format=raw,id=x0
QEMUOPTS += -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0

QEMUOPTS += -serial mon:stdio

qemu: check-qemu-version $(O)/$K/kernel fs.img
	$(QEMU) $(QEMUOPTS)

.gdb:
	@mkdir -p .gdb

.gdb/.gdbinit: | .gdb
	@echo "set confirm off" > $@
	@echo "set architecture riscv:rv64" >> $@
	@echo "target remote 127.0.0.1:$(GDBPORT)" >> $@
	@echo "symbol-file $(O)/$K/kernel" >> $@
	@echo "set disassemble-next-line auto" >> $@
	@echo "set riscv use-compressed-breakpoints yes" >> $@

qemu-gdb: $(O)/$K/kernel .gdb/.gdbinit fs.img
	@echo "*** Now run 'make gdb' in another window." 1>&2
	$(QEMU) $(QEMUOPTS) -S $(QEMUGDB)

gdb: .gdb/.gdbinit
	$(GDB) -x .gdb/.gdbinit

print-gdbport:
	@echo $(GDBPORT)

QEMU_VERSION := $(shell $(QEMU) --version | head -n 1 | sed -E 's/^QEMU emulator version ([0-9]+\.[0-9]+)\..*/\1/')
check-qemu-version:
	@if [ "$(shell echo "$(QEMU_VERSION) >= $(MIN_QEMU_VERSION)" | bc)" -eq 0 ]; then \
		echo "ERROR: Need qemu version >= $(MIN_QEMU_VERSION)"; \
		exit 1; \
	fi

.PHONY: fmt
fmt:
	clang-format -i $(wildcard kernel/*.[ch] user/*.[ch] mkfs/*.c)

# Automated testing targets
ARGS ?= usertests
test:
	python3 tests/test-xv6.py $(ARGS)

test-quick:
	python3 tests/test-xv6.py -q usertests

.PHONY: test test-quick
