# RISC-V GCC Bare-Metal Crosscompiler

This repository provides automated builds of a complete RISC-V bare-metal crosscompiler toolchain, including:
- **binutils**: Assembler, linker, and binary utilities
- **GCC**: C and C++ compiler
- **newlib**: Embedded C library

## Features

- **Portable**: Built using manylinux containers for maximum Linux compatibility
- **Self-contained**: All necessary libraries included with proper RPATH configuration
- **Multi-architecture**: Supports x86_64 and ARM64 (aarch64) Linux systems
- **Automated**: Weekly builds with the latest stable versions
- **Bare-metal**: Configured for embedded systems without OS dependencies

## Target Configuration

- **Target triple**: `riscv64-unknown-elf`
- **Default architecture**: rv64imac
- **Default ABI**: lp64
- **Multilib variants**: Custom configuration with 4 optimized targets:
  - `rv32i/ilp32` - RV32 base integer instruction set
  - `rv32imac/ilp32` - RV32 with integer multiply, atomics, compressed
  - `rv64i/lp64` - RV64 base integer instruction set
  - `rv64imac/lp64` - RV64 with integer multiply, atomics, compressed (default)

## Installation

1. Download the appropriate tarball for your system from the [Releases](https://github.com/edapack/gcc-riscv-bin/releases) page
2. Extract: `tar xzf gcc-riscv-*.tar.gz`
3. Add to PATH: `export PATH=$PWD/gcc-riscv/bin:$PATH`

## Usage

```bash
# Compile with default (rv64imac/lp64)
riscv64-unknown-elf-gcc -o program.elf program.c

# Compile for RV32 base integer
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -o program.elf program.c

# Compile for RV32 with multiply, atomics, compressed
riscv64-unknown-elf-gcc -march=rv32imac -mabi=ilp32 -o program.elf program.c

# Compile for RV64 base integer
riscv64-unknown-elf-gcc -march=rv64i -mabi=lp64 -o program.elf program.c

# Compile with default (rv64imac)
riscv64-unknown-elf-gcc -march=rv64imac -mabi=lp64 -o program.elf program.c

# Check available multilib variants
riscv64-unknown-elf-gcc -print-multi-lib
```

## Build Process

The build process:
1. Builds binutils for RISC-V target
2. Builds GCC stage 1 (without C library)
3. Builds newlib C library
4. Builds GCC stage 2 (complete with C/C++ support)
5. Strips binaries and fixes RPATH for portability
6. Creates portable tarball

### Portability Features

- Uses `patchelf` to set `$ORIGIN`-relative RPATHs
- Detects and reports binaries with hardcoded paths
- Verifies all dependencies are satisfied
- Tests compilation after build

## CI/CD

Automated builds run:
- On every push
- Weekly (Sundays at 12:00 UTC)
- On manual trigger

Builds are created for:
- `manylinux2014_x86_64` (GLIBC 2.17+)
- `manylinux_2_28_x86_64` (GLIBC 2.28+)
- `manylinux_2_28_aarch64` (ARM64, GLIBC 2.28+)

## License

This is a binary distribution. Please refer to the licenses of the individual components:
- GCC: GPL-3.0
- binutils: GPL-3.0
- newlib: Various (BSD-like licenses)
