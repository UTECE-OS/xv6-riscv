# xv6-riscv (Verified Edition)

This repository contains the source code for the **xv6-riscv** operating system (the verified release `verified-v2` from MIT PDOS), fully patched and optimized for native **Linux** and **Windows (WSL 2)** environments.

---

## 1. Prerequisites and Toolchain Installation

To compile and run xv6-riscv on **Ubuntu / Debian** or **WSL 2**, install the required toolchains and emulator packages:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y git build-essential gdb-multiarch qemu-system-misc qemu-system-riscv gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu python3 bc
```

### Toolchain Component Summary:
* **`gcc-riscv64-linux-gnu` & `binutils-riscv64-linux-gnu`:** GNU cross-compiler, assembler, and linker toolchain targeting 64-bit RISC-V (`rv64gc`) on an x86/ARM host machine.
* **`qemu-system-riscv`:** Full-system hardware emulator simulating a multi-core RISC-V board (`virt` machine).
* **`build-essential` & `make`:** Host C compiler and GNU Make build system used to compile host tools (such as `mkfs`) and orchestrate the build.
* **`gdb-multiarch`:** Multi-architecture GNU debugger for step-by-step kernel and user-space debugging.
* **`python3` & `bc`:** Required for automated test runner scripts (`test-xv6.py`) and toolchain version validation in the `Makefile`.

---

## 2. Directory Structure and System Architecture

```text
.
├── kernel/        # Core operating system supervisor-mode code
├── user/          # User-space applications, runtime library, and system tests
├── mkfs/          # Host-side file system formatter and disk image builder
├── docs/          # Textbook (PDF), architectural documentation, and engineering logs
├── Makefile       # Compilation rules, dependencies, and QEMU configuration
└── test-xv6.py    # Automated test runner and validation script
```

### Detailed Component Breakdown:

### 1. `kernel/` (Kernel Space / Supervisor Mode)
Contains all code executing in RISC-V Supervisor mode (`S-mode`):
* **Bootstrapping and Initialization:**
  * `entry.S`: The initial assembly entry point executed by QEMU upon reset; sets up the initial stack for each CPU core (hart) and jumps to C code.
  * `start.c`: Configures machine mode (`M-mode`), delegates interrupts/exceptions to supervisor mode, configures hardware timers, and transitions to `S-mode`.
  * `main.c`: Coordinates subsystem initialization (memory allocator, page tables, trap handlers, process table, disk driver, file system) and spawns the first user process.
* **Process Management and Scheduling:**
  * `proc.c` & `proc.h`: Implements the process table, process lifecycle states (`UNUSED`, `USED`, `SLEEPING`, `RUNNABLE`, `RUNNING`, `ZOMBIE`), context switching, process lifecycle primitives (`fork`, `exit`, `wait`, `sleep`, `wakeup`), and the Round-Robin CPU scheduler.
  * `swtch.S`: Low-level assembly context switch routine saving and restoring callee-saved registers.
* **Virtual Memory and Paging:**
  * `vm.c`: Implements the 3-level page table mechanism conforming to the RISC-V Sv39 standard (39-bit virtual addressing, 4 KB page frames), kernel address space mappings, and user page table allocation/translation.
  * `kalloc.c`: Physical memory allocator managing 4 KB page frames via a linked list free list.
* **Traps, Interrupts, and System Calls:**
  * `trampoline.S`: Critical assembly page mapped at the very top of both user and kernel address spaces (`TRAMPOLINE`) facilitating secure user $\leftrightarrow$ kernel state transitions.
  * `trap.c`: Supervisor trap dispatcher handling timer interrupts, device interrupts, page faults, and system call traps.
  * `syscall.c` & `syscall.h`: System call vector table and argument extraction helper routines (`argint`, `argaddr`, `argstr`).
  * `sysproc.c` & `sysfile.c`: Implementations of process-related and file-related system calls.
* **Multi-Layered File System:**
  * `virtio_disk.c`: Device driver for the QEMU VirtIO MMIO block device.
  * `bio.c`: Buffer cache layer providing an LRU caching mechanism for disk sectors with synchronized locking.
  * `log.c`: Crash recovery logging layer implementing transactional commits to preserve file system consistency across sudden crashes.
  * `fs.c` & `fs.h`: Inode management, directory lookups, path resolution, and block allocation.
  * `file.c`: File descriptor table and uniform file abstractions.
  * `pipe.c`: Unix unidirectional inter-process communication (IPC) pipe implementation with circular ring buffering.
* **Synchronization and Hardware Drivers:**
  * `spinlock.c` & `sleeplock.c`: Spinlocks (for short, non-blocking critical sections) and sleep-locks (for blocking operations like I/O).
  * `uart.c` & `console.c`: 16550A UART serial driver handling keyboard input and console output.
  * `plic.c`: Platform-Level Interrupt Controller configuration.

### 2. `user/` (User Space / User Mode)
Contains programs compiled to run in RISC-V User mode (`U-mode`):
* **Core Unix Utilities:**
  * `sh.c`: Minimalist Unix command shell supporting command execution, I/O redirection (`<`, `>`), and pipelines (`|`).
  * `ls.c`, `cat.c`, `echo.c`, `grep.c`, `mkdir.c`, `rm.c`, `ln.c`, `wc.c`, `kill.c`: Fundamental command-line utilities.
* **User Runtime and Standard Library:**
  * `init.c`: PID 1 (ancestor of all user processes); sets up the console and spawns the interactive shell.
  * `ulib.c`: Standard user utility library (string manipulation, formatted input/output helpers).
  * `printf.c`: Formatted user-space printing routine (`printf`).
  * `umalloc.c`: User-space heap memory allocator implementing `malloc()` and `free()` via first-fit free-list algorithm.
  * `usys.pl`: Perl script that automatically generates RISC-V assembly stubs invoking the `ecall` instruction for each system call.
* **Test Suites:**
  * `usertests.c`: Comprehensive stress-test suite validating edge cases, concurrency, file system integrity, and memory boundaries.
  * `forktest.c`, `grind.c`, `stressfs.c`, `logstress.c`: Targeted stress testing tools.

### 3. `mkfs/`
Contains `mkfs.c`, a host tool compiled by your host's native GCC. It constructs and formats the virtual disk image (`fs.img`), initializes superblock and inode tables, and writes user binaries into the image.

### 4. `docs/`
Contains `xv6-simple-unix-like-teaching-OS.pdf` (the official textbook by MIT faculty Frans Kaashoek, Robert Morris, and Russ Cox), explaining the design and implementation of xv6-riscv in depth. It also contains local developer logs (`ROADMAP.md` and `CONVERSATION.md`), which are excluded from Git version control.

---

## 3. Command and Usage Reference

### A. Compiling and Running xv6
* **Launch xv6 inside the current terminal:**
  ```bash
  make qemu
  ```
* **Launch xv6 in a new, independent terminal window (Windows / WSL 2):**
  ```bash
  cmd.exe /c start wsl make qemu
  ```
* **Clean all compiled binaries and build artifacts:**
  ```bash
  make clean
  ```
* **Build kernel and disk image without launching QEMU:**
  ```bash
  make -j4 kernel/kernel fs.img
  ```

### B. Debugging with GDB
* **Start QEMU frozen and waiting for a GDB connection:**
  ```bash
  make qemu-gdb
  ```
* In a separate terminal, attach the multi-architecture debugger:
  ```bash
  gdb-multiarch
  ```
  *(The repository includes a `.gdbinit` configuration configured to connect to `localhost:26000`).*

### C. Exiting xv6 (Shutting Down QEMU)
Since xv6 operates over a virtual serial console without a graphical window (`-nographic` flag):
1. Press **`Ctrl + A`** together.
2. Release both keys.
3. Press **`X`**.

### D. Automated Test Execution
* **Quick validation suite (recommended, completes in ~15-20s):**
  ```bash
  python3 test-xv6.py -q usertests
  ```
* **Run a single specific test (e.g., `copyin` or `forktest`):**
  ```bash
  python3 test-xv6.py copyin
  ```
* **Full stress-test suite (~3-5 minutes):**
  ```bash
  python3 test-xv6.py usertests
  ```

---

## 4. Path and File System Nuances in xv6
* **No `PATH` Environment Variable:**
  xv6 does not implement environment variables or a `$PATH` lookup list. When inside a subdirectory (e.g., `/salam`), executing `ls` directly will result in `exec ls failed`.
  To execute programs from a subdirectory, supply:
  * Absolute path: `/ls`
  * Relative path: `../ls`
  * Or navigate back to the root directory: `cd ..`

---

## 5. Original MIT Acknowledgments and Notices

> The following text is preserved verbatim from the original MIT xv6 distribution:

xv6 is a re-implementation of Dennis Ritchie's and Ken Thompson's Unix
Version 6 (v6). xv6 loosely follows the structure and style of v6,
but is implemented for a modern RISC-V multiprocessor using ANSI C.

### ACKNOWLEDGMENTS

xv6 is inspired by John Lions's Commentary on UNIX 6th Edition (Peer
to Peer Communications; ISBN: 1-57398-013-7; 1st edition (June 14,
2000)). See also https://pdos.csail.mit.edu/6.1810/, which provides
pointers to on-line resources for v6.

The following people have made contributions: Russ Cox (context switching,
locking), Cliff Frey (MP), Xiao Yu (MP), Nickolai Zeldovich, and Austin
Clements.

We are also grateful for the bug reports and patches contributed by
Abhinavpatel00, Takahiro Aoyagi, Marcelo Arroyo, Hirbod Behnam, Silas
Boyd-Wickizer, Anton Burtsev, carlclone, Ian Chen, clivezeng, Dan
Cross, Cody Cutler, Mike CAT, Tej Chajed, Asami Doi, Wenyang Duan,
echtwerner, eyalz800, Nelson Elhage, Saar Ettinger, Alice Ferrazzi,
Nathaniel Filardo, flespark, Peter Froehlich, Yakir Goaron, Shivam
Handa, Matt Harvey, Bryan Henry, jaichenhengjie, Jim Huang, Matúš
Jókay, John Jolly, Alexander Kapshuk, Anders Kaseorg, kehao95,
Wolfgang Keller, Jungwoo Kim, Jonathan Kimmitt, Eddie Kohler, Vadim
Kolontsov, Austin Liew, Bruce Lowekamp, l0stman, Pavan Maddamsetti,
Imbar Marinescu, Yandong Mao, Matan Shabtay, Hitoshi Mitake, Carmi
Merimovich, mes900903, Mark Morrissey, mtasm, Joel Nider, Hayato Ohhashi,
OptimisticSide, papparapa, phosphagos, Harry Porter, Greg Price, Zheng
qhuo, Quancheng, RayAndrew, Jude Rich, segfault, Ayan Shafqat, Eldar
Sehayek, Yongming Shen, Fumiya Shigemitsu, snoire, Taojie, Cam Tenny,
tyfkda, Warren Toomey, Stephen Tu, Alissa Tung, Rafael Ubal, unicornx,
Amane Uehara, Pablo Ventura, Luc Videau, Xi Wang, WaheedHafez, Keiichi
Watanabe, Lucas Wolf, Nicolas Wolovick, wxdao, Grant Wu, x653, Andy
Zhang, Jindong Zhang, Icenowy Zheng, ZhUyU1997, and Zou Chang Wei.

### ERROR REPORTS & PURPOSE

Please send errors and suggestions to Frans Kaashoek and Robert Morris
(kaashoek,rtm@mit.edu). The main purpose of xv6 is as a teaching
operating system for MIT's 6.1810, so we are more interested in
simplifications and clarifications than new features.
