#!/bin/bash
# Build the Nios V app on Linux/macOS without RiscFree: any rv32 GCC works.
# Default: xPack riscv-none-elf-gcc (https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack)
# RISCV_BIN=<dir with riscv-none-elf-gcc>  ./build_app.sh
set -euo pipefail
cd "$(dirname "$0")"
RISCV_BIN=${RISCV_BIN:-/workspace/tools/xpack-riscv-none-elf-gcc-14.2.0-3/bin}
SHIM=$PWD/.shim; mkdir -p "$SHIM"
for t in gcc g++ ar objdump objcopy size nm ld as ranlib; do
  ln -sf "$RISCV_BIN/riscv-none-elf-$t" "$SHIM/riscv32-unknown-elf-$t"; done
export PATH=$SHIM:$PATH
# GCC >= 12 needs zicsr/zifencei spelled out (Intel RiscFree GCC is older)
sed -i "s/-march=rv32i -mabi/-march=rv32i_zicsr_zifencei -mabi/" bsp/toolchain.cmake
cmake -S app -B app/build -G "${CMAKE_GEN:-Ninja}" -DCMAKE_BUILD_TYPE=Release
cmake --build app/build -j --target caliptra_host.elf
riscv32-unknown-elf-size app/build/caliptra_host.elf
# RAM init image (Intel word-addressed HEX) via elf2hex from the Quartus Docker image -> ./onchip_mem.hex (project dir)
if [ "${NO_HEX:-0}" != 1 ]; then
  ../dock.sh 'QUARTUS_ROOTDIR=/opt/altera/quartus elf2hex sw/app/build/caliptra_host.elf -o onchip_mem.hex -b 0x00000000 -w 32 -e 0x0000FFFF -r 4'
fi
