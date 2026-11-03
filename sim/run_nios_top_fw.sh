#!/bin/bash
# Sim the real nios_caliptra_top glue (fuse ctrl IP + FW store + mailbox FIRMWARE_LOAD) with a behavioral Nios.
set -eo pipefail; cd "$(dirname "$0")"; : # needs verilator >= 5.0 on PATH; run from repo with caliptra-rtl/ at the root
N=../quartus_a5e_nios/rtl
verilator --binary -j 8 -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-UNOPTFLAT -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD \
  --timing --top-module tb_nios_top_fw -Mdir obj_nios_top_fw -f boot_apb.f \
  $N/avmm_to_apb.sv $N/soc_fuse_ctrl.sv $N/soc_fw_store.sv $N/nios_caliptra_top.sv tb_nios_top_fw.sv > nios_top_fw_build.log 2>&1
start=$(date +%s); ./obj_nios_top_fw/Vtb_nios_top_fw "$@" | tee nios_top_fw_run.log
echo "wall_time_s=$(( $(date +%s)-start ))" | tee -a nios_top_fw_run.log
