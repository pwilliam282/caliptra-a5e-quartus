# nios_caliptra_top — DEVICE_PRODUCTION (debug locked) boot, Verilator

Production-flow **mimic** using STUDY keys/entropy (not real production secrets).

- Straps: lifecycle `2'b11` (Production), `debug_locked=1`, STUDY `cptra_obf_key`.
- Fuses: `fw/fuse_image.hex` from `scripts/gen_fuse_image.py`: LIFE_CYCLE=3,
  KEY_MANIFEST_PK_HASH / OWNER_PK_HASH = SHA-384 of the bundle's vendor/owner pub-key
  descriptors (12 BE words), PK_HASH_MASK=0, SVN fuses 0 (bundle FMC/RT SVN = 0), STUDY UDS/FE.
- SoC host also programs `CPTRA_WDT_CFG` (0x30110/0x30114) = 100,000,000 before fuses:
  a debug-locked ROM arms WDT1 from this register, and 0 means a 1-cycle timeout,
  which raised HW_ERROR_FATAL=0x4 (NMI) at cycle 213002 on the first run. Fixed in
  `tb_nios_top_fw.sv`, `tb_boot_apb_fw.sv`, and Nios `sw/app/main.c`.

Run: `./run_nios_top_fw.sh +nowaves +max_cycles=200000000`

Result (2026-11-03): **PASS**
```
[state] LifecycleState = Production
[state] DebugLocked = Yes
[state] Starting the WD Timer 100000000 cycles
[14362301] MBOX_STATUS=2          (FIRMWARE_LOAD accepted: vendor+owner sig/PK-hash checks passed)
[24064873] ready_for_runtime
TB_NIOS_TOP PASS cyc=24064873 trng=32      wall ~2103 s
```
No fatal/non-fatal FW error codes. Full log: `nios_top_fw_run.log`.

Scope: Verilator covers the FPGA glue RTL + Caliptra with a behavioral Nios host. The full
Platform Designer Nios V IP system needs Intel Questa/ModelSim with Quartus sim libraries.
