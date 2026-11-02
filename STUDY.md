# Study: Caliptra 1.x (passive) on Intel Cyclone 10 GX

Separate from `/workspace/caliptra-agilex` (2.x / Agilex 7). Study date: Nov 1, 2026.

## Why Cyclone 10 GX
Quartus Prime Pro **free mode** (no license file) supports Cyclone 10 GX. That lets us do a real
synth/fit size check without paying for an Agilex 7 license. Largest part: **10CX220YF780E5G**
(~80,330 ALM, 587 M20K, ~11.7 Mbit block RAM).

## Source
- `caliptra-rtl/` = chipsalliance/caliptra-rtl tag **v1.1**, commit `5f85fb4bc95b753a2f7d042db7dc2644ca1e8c49`
  (latest 1.x tag; others: v1.0, v1.0-rc1).
- 1.x SoC interface = **APB** (32b addr/data/PAUSER). No AXI DMA, no subsystem straps, no Adams Bridge (no ML-DSA/ML-KEM).
  1.x is already "passive" by design (SoC boots itself, Caliptra is the RoT behind the mailbox).

## Built
- `rtl/caliptra_passive_top.sv` – wraps `caliptra_top`; exposes APB + status/TRNG/JTAG; ties off QSPI;
  instantiates mailbox SRAM (`caliptra_sram`), ROM (`caliptra_rom_m20k`, $readmemh), VeeR ICCM/DCCM/ICache
  (upstream `caliptra_veer_sram_export`, error injection tied 0). Test obf key is a port – prototype only.
- `caliptra_passive_top.f` – file list (absolute paths). `sim/tb_smoke.sv` – smoke TB.
- `quartus/` – `.qpf/.qsf/.sdc` for 10CX220YF780E5G (virtual pins, 50 MHz clock), `run_synth.sh`.

## Status
| Step | Result |
|---|---|
| Verilator 5.054 lint | **clean, 0 errors** (`lint.log`, common style warnings suppressed) |
| Smoke sim (no ROM image) | **PASS** – `ready_for_fuses` at 275 ns (`sim/run.log`) |
| Quartus synth/fit | **not run** – Quartus not installed on box (see below) |

## Memory estimate (M20K = 512x40 / 1Kx20 / 2Kx10)
| Memory | 1.x size | Shape | M20K | 2.x (v2.1.2) for comparison |
|---|---|---|---|---|
| Mailbox | 128 KiB + ECC | 32768x39 | 64 | 256 KiB -> ~128 |
| ROM | 48 KiB | 6144x64 | 24 | 96 KiB -> ~48 |
| ICCM | 128 KiB + ECC | 4x 8192x39 | 64 | 256 KiB -> ~128 |
| DCCM | 128 KiB + ECC | 4x 8192x39 | 64 | 256 KiB -> ~128 |
| ICache 16 KiB (data+tag) | | | ~12 | ~12 |
| Crypto/FIFO small RAMs (ECC, entropy, etc.) | | | ~10–20 | + Adams Bridge RAMs (large) |
| **Total** | | | **~240–250 (~42% of 587)** | **~450+ before ABR** |

Rule-of-thumb only; Quartus may pack differently or map small arrays to MLAB.

## Logic (ALM) – the real unknown
Caliptra 1.x logic = VeeR EL2 RV32 + ECC P-384 engine + SHA-512/384 + SHA-256 + HMAC-384 + DOE(AES) +
key/data/PCR vaults (lots of flops) + entropy_src/CSRNG + mailbox/soc_ifc. No public ALM figure for Intel parts.
Engineering guess: **~55K–100K ALM** – i.e. somewhere between "fits ~70%" and "does not fit" on 80K ALM.

## Conclusion
- **Memory: fits** comfortably (~42% M20K).
- **Logic: unknown, likely tight** – needs a Quartus synth to decide. Overall verdict: **too tight / unknown**
  (much better odds than 2.x, which is clearly out).
- If it fails, levers: drop DOE/unused debug (JTAG), ICache off, synthesis area mode, or move to Cyclone 10 GX → Arria 10 / Agilex.

## Quartus install (free mode) – not done
The box has no Quartus. Download is ~25+ GB and Intel's Download Center flow wants an account sign-in,
so install was not attempted. Steps for the user:
1. Go to intel.com → FPGA Software Download Center → **Quartus Prime Pro Edition** (Linux), recent version that still lists Cyclone 10 GX.
2. Download the Quartus Prime Pro installer + **Cyclone 10 GX device support** (.qdz) only.
3. Install; at license prompt pick nothing / free mode – Cyclone 10 GX compiles without a license.
4. Then: `cd /workspace/caliptra-c10gx-1x/quartus && ./run_synth.sh` and read the Fitter Resource Usage Summary.

## Next step
Install Quartus Pro (free) on the box, run `run_synth.sh`, record ALM/M20K/Fmax, then decide fit.
Optional before that: yosys/sv2v rough LUT count to pre-screen.

---

## REAL Quartus results — Analysis & Synthesis (2026-11-01)

Tool: Quartus Prime Pro 25.3.0 Build 109 (free mode), Docker `alterafpga/quartuspro-v25.3:cyclone10gx`
Device: 10CX220YF780E5G (80,330 ALMs, 587 M20K, 192 DSP). Top: `caliptra_passive_top` (caliptra-rtl v1.1).
Status: **Synthesis successful** (5 min 41 s, peak ~3.4 GB). Fitter NOT run (pointless at 156%).

| Resource | Used | Available | % |
|---|---|---|---|
| Logic (ALMs, estimate) | **125,236** | 80,330 | **156 %** |
| Combinational ALUTs | 181,406 | — | |
| Dedicated registers | **142,612** | 321,320 | 44 % |
| Block memory bits | 3,833,856 | 12,021,760 | 32 % |
| M20K (est., 512x40 mode) | ~192 (+~24 for ROM once initialised) ≈ **216** | 587 | ~37 % |
| DSP blocks | **49** (43× 27x27, 4× dual 18x18, 2× sum-of-18x18) | 192 | 26 % |

ALUT / register breakdown by top block (inside `caliptra_top`):

| Block | ALUTs | Regs |
|---|---|---|
| ecc_top (ECC P-384) | 48,721 | 51,594 |
| rvtop (VeeR EL2) | 35,300 | 20,739 |
| key_vault | 32,889 | 12,912 |
| hmac | 17,380 | 14,008 |
| pcr_vault | 16,183 | 12,559 |
| soc_ifc_top | 13,784 | 10,230 |
| data_vault | 5,670 | 8,565 |
| sha512 | 4,633 | 5,885 |
| doe (AES) | 3,695 | 3,471 |
| sha256 | 2,468 | 2,472 |

### Verdict: **DOES NOT FIT** the Cyclone 10 GX 10CX220 (largest C10 GX)
- Memory fits easily (~37 % M20K), and DSP fits. **Logic is the blocker: about 1.56× the device**, and that's before adding Nios V or any host logic.
- KV/PCR/DV vaults are built from flops + muxes (no RAM inference), and ECC is massive. Getting to ≤80K ALMs needs about 45K fewer ALMs, which would mean e.g. dropping ECC (not a real Caliptra) or restructuring the vaults into RAM (an RTL redesign).
- Note: Fitter ALM packing is typically within ±10–15 % of the synthesis estimate, so this won't close.
- Caveat: ROM had no init file so it was optimised away (adds ~24 M20K, ~0 ALMs). Error-injection/test logic is removed. Assertions are off.

### Changes needed to make Quartus synthesise v1.1 (all outside upstream tree)
1. Docker needs `--net=host` (otherwise quartus_syn segfaults in the FlexLM host-ID/udev lookup).
2. QSF: removed coverage/, asserts/, *_sva, *_cov_ files; added `VERILOG_MACRO SYNTHESIS=1`, `FPGA_SYN=1`, `VERILOG_CU_MODE MFCU` (Caliptra relies on macros persisting across files).
3. `quartus/syn_src/` overrides: `caliptra_top_tb_pkg.sv` (class wrapped in `ifndef SYNTHESIS`), `caliptra_veer_sram_export.sv` (sim error injection replaced by '0), and `caliptra_sram.sv` (upstream byte-slicing goes out of range for 39-bit; replaced with a word-wide RAM that infers M20K).
- Original QSF kept as `quartus/caliptra_c10gx.qsf.orig`. Re-run: `quartus/run_synth_docker.sh`.
- Logs: `quartus/syn.log`, `quartus/output_files/caliptra_c10gx.syn.rpt`, `.syn.summary`.

## Shrink sketch (analysis only, no new synth) — 2026-11-01
Conversion used: synth ALM estimate / ALUTs = 125,236 / 181,406 ≈ **0.69 ALM per ALUT**. Savings are estimates (±20 %).

| Change | Block ALUTs today | Est. ALM saved | Cost | Still Caliptra-compatible? |
|---|---|---|---|---|
| key_vault flops → M20K (24×512 b, 1 rd + 1 wr port, keep lock/use bits in flops) | 32.9K | ~19–21K | ~13–26 M20K | Yes for FW/API. Needs RTL changes in KV read/write muxes plus clear-on-reset/debug-unlock sequencing (RAM can't clear in 1 cycle, so it needs an FSM sweep). TCB behaviour has to be re-verified. |
| pcr_vault → M20K (32×384 b) | 16.2K | ~9–10K | ~10–20 M20K | Yes, same caveats. Hash-extend path reads one PCR at a time, so it suits RAM. |
| data_vault → M20K (sticky/non-sticky DV) | 5.7K | ~2.5–3K | ~4–8 M20K | Yes, same caveats. |
| VeeR EL2 config trim (no branch predictor / smaller BTB, smaller PIC, no debug triggers, 1 MUL variant) | 35.3K | ~6–9K | — | ISA-compatible. Drops JTAG debug features, which is acceptable for production ROM/FW. |
| soc_ifc trim (WDT/timers/extra mailbox status regs) | 13.8K | ~1–2K | — | Marginal. The mailbox, fuse and reset paths must stay for the passive flow. |
| HMAC (HMAC-384 for key derivation) | 17.4K | 0 (keep) | — | Required for KV derivation. Optional: share SHA-512 core with HMAC (~5–7K) but that is a deep rewrite. |
| **ECC P-384 removed** | 48.7K | **~33K** | — | **No.** No DICE IDevID/LDevID/alias signing, so it is not a real Caliptra RoT. |

### Tiers (logic only, before any Nios V host ≈ 3–6K ALM)
| Tier | Content | Est. ALMs | 10CX220 (80.3K) | Comment |
|---|---|---|---|---|
| T0 | As-built v1.1 | 125.2K | 156 % ✗ | measured |
| T1 | + all three vaults → M20K | ~93K | ~116 % ✗ | biggest TCB-preserving win |
| T2 | T1 + VeeR trim + soc_ifc trim | ~84–86K | ~105 % ✗ (borderline, no room for host or routing) | |
| T3 | T2 + optional SHA/HMAC sharing | ~78–80K | ~98 % ✗ in practice (Fitter cannot close at ~100 %) | heavy RTL rewrite |
| T4 | T1 + ECC removed | ~60K | ~75 % ✓ | not Caliptra (no ECDSA) |

### Targets
- **Cyclone 10 GX 10CX220**: fits only with ECC removed (T4). If ECC is kept, even the optimistic T3 is at ~100 %, so it is **not plausible**.
- **Agilex 5 E-series** (e.g. A5E 052/065, ~177K–224K ALMs; free-mode Quartus Pro covers a subset of E-series. **Verify the exact OPN in the free device list before building**): T0 already fits at ~56–70 %. T1 leaves lots of room for a Nios V host. This is the realistic "midrange" home for an unmodified Caliptra 1.x.
- Agilex 3 (≤ ~46K ALMs): too small even at T4.

### Ordered plan
1. **KV → M20K standalone experiment**: synth `kv` alone (top = key_vault wrapper) as-is vs RAM-backed, and measure the ALM delta. This is the smallest RTL change that proves the biggest TCB-preserving win (~20K ALM).
2. Extend the same pattern to PCR and DV, then re-synth the full passive top (T1 number).
3. In parallel and with no RTL change, retarget the existing project to an Agilex 5 E free-mode device and run synth plus fit. This tells us whether a midrange fit needs any shrinking at all.
4. Do VeeR config trim only if a C10 GX target is still wanted after steps 1–3.

**Verdict:** a C10 GX-class fit that keeps ECC is not plausible. Agilex 5 E (midrange) fits Caliptra 1.x unmodified on paper.

## Agilex 5 E attempt (2026-11-01) — BLOCKED on licensing, no fit numbers

- Image: `alterafpga/quartuspro-v25.3:agilex5` (pulled; Quartus Pro 25.3.0 Build 109). Run with `--net=host`.
- Device DB in image includes A5EC/A5ED 008…065 (e.g. A5EC065BB32AE6S, A5EC052*, A5ED065*).
- Part chosen: **A5EC065BB32AE6S** (largest A5E). Sibling project: `quartus_a5e/` (caliptra_a5e.qsf = C10 QSF with FAMILY/DEVICE swapped; same RTL, syn_src patches, macros). C10 project untouched.
- Result: `quartus_syn` fails immediately:
  `Error (19286): No license for family Agilex 5` (log: `quartus_a5e/flow.log`).
- Why: Quartus Pro "Free Mode" (no license) covers **Cyclone 10 GX only** (Altera Install & Licensing guide 25.3, Table 11).
  Agilex 5 E-Series is "no-cost" but needs a **license file** acquired from Altera's license server
  (GUI: License Setup → Get no-cost licenses → Agilex 5 E-Series Software Enablement, tied to host MAC; or via SSLC account).
  It is NOT auto-fetched at compile time (auto-fetch covers only Nios V / MIPI / MCDMA IP).
- Note: also per 25.3 release notes, A5EC065 is "advance" support (A5EC065BB32-R0 preliminary); final-support A5E parts are only 008/013.
- Next: once a no-cost A5E license (`~/.altera.quartus/quartus2_lic.dat` or LM_LICENSE_FILE) is available in the container, rerun `quartus_a5e/run_a5e_docker.sh` (syn+fit).

## Agilex 5 E (A5EC065BB32AE6S) results — 2026-11-01
- License: SW-AGILEX-5E (fixed, NIC 822B383DBCD0, valid to Nov 2027) at `/workspace/altera_license/SW-AGILEX-5E.dat`, mounted via `run_a5e_docker.sh` (--net=host).
- Quartus Pro 25.3.0, RTL unchanged (Caliptra 1.x v1.1).

### Synthesis — SUCCEEDED
| Resource | Used | Device | % |
|---|---|---|---|
| Logic (ALMs, syn estimate) | 141,256 | 222,400 | 64% |
| Registers | 142,373 | — | — |
| Block memory bits | 3,833,856 | — | — |
| DSP (18x18 fixed) | 49 | — | — |

### Fit — placement SUCCEEDED, routing NOT COMPLETED
- Plan + place passed: `Info (170137): Fitter placement was successful` (15:09 elapsed). Design packs and places on A5EC065.
- Routing: `quartus_fit` OOM-killed by kernel at start of routing (RSS ~13.5 GB; box has 15 GB, no swap). No fit.summary produced.
- Retry with 16 GB swapfile + `--parallel=4` destabilized/restarted the box; abandoned. Needs a host with >=32 GB RAM to finish route + timing.
- Critical warnings only (no errors): missing Reset Release IP, power-up level ignored on cptra_security_state latches, missing I/O standards/pin locations (expected for bare wrapper), 796 comb loops treated as latches.

### Verdict
Caliptra 1.x unmodified fits Agilex 5 E 065 (~64% ALMs, placement proven) with ~80K ALMs headroom for Nios V + glue. Final routed numbers/timing pending a larger-RAM build machine.
Logs: `quartus_a5e/flow.log`, `quartus_a5e/output_files/caliptra_a5e.syn.summary`, `.fit.plan.rpt`.
