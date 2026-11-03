/* Nios V SoC host for Caliptra 1.x (passive) on Agilex 5 E.
 * Mimics a real SoC boot of Caliptra 1.x:
 *   1. power-good / reset release                         (SoC power sequencer)
 *   2. wait ready_for_fuses, register mailbox PAUSER       (SoC boot firmware)
 *   3. soc_fuse_ctrl pushes the OTP fuse image + FUSE_WR_DONE (SoC fuse controller IP)
 *   4. service etrng_req with 12 TRNG words (SoC TRNG)     -- whole boot
 *   5. wait ready_for_fw_push, mailbox FIRMWARE_LOAD of the FW bundle read from
 *      soc_fw_store (stand-in for SoC boot flash)
 *   6. wait ready_for_runtime, read FW_REV_ID
 * MAGIC_PIO milestones (led = MAGIC[7:0]) are listed in README.md.
 * Same sequence as sim/tb_boot_apb_fw.sv (passes in Verilator). TEST KEYS/ENTROPY ONLY. */
#include <stdint.h>
#include "sys/alt_stdio.h"
#include "system.h"

#ifdef CALIPTRA_WIN_BASE
#define SOC_WIN_BASE        CALIPTRA_WIN_BASE
#else
#define SOC_WIN_BASE        0x00040000u  /* mm_bridge 's0' in nios_caliptra_sys (256 KiB) */
#endif
#ifndef CTRL_PIO_BASE
#define CTRL_PIO_BASE       0x00080010u
#endif
#ifndef STATUS_PIO_BASE
#define STATUS_PIO_BASE     0x00080020u
#endif
#ifndef MAGIC_PIO_BASE
#define MAGIC_PIO_BASE      0x00080030u
#endif

#define REG32(a)            (*(volatile uint32_t *)(uintptr_t)(a))
#define CPTRA(off)          REG32(SOC_WIN_BASE + (off))      /* Caliptra APB (0x2xxxx/0x3xxxx) */
#define FWSTORE(i)          REG32(SOC_WIN_BASE + 0x00000u + 4u * (i))
#define FUSECTL(off)        REG32(SOC_WIN_BASE + 0x1F000u + (off))

/* ---- Caliptra 1.x APB map (caliptra_reg_defines.svh, minus 0x3003_0000 high bits) ---- */
#define MBOX_LOCK           0x20000u
#define MBOX_USER           0x20004u
#define MBOX_CMD            0x20008u
#define MBOX_DLEN           0x2000Cu
#define MBOX_DATAIN         0x20010u
#define MBOX_DATAOUT        0x20014u
#define MBOX_EXECUTE        0x20018u
#define MBOX_STATUS         0x2001Cu
#define CPTRA_FLOW_STATUS   0x3003Cu
#define CPTRA_MBOX_VALID_PAUSER0 0x30048u
#define CPTRA_MBOX_PAUSER_LOCK0  0x3005Cu
#define CPTRA_TRNG_DATA0    0x30078u   /* 12 words .. 0x300A4 */
#define CPTRA_TRNG_STATUS   0x300ACu   /* bit1 DATA_WR_DONE */
#define CPTRA_FUSE_WR_DONE  0x300B0u
#define CPTRA_HW_REV_ID     0x300D4u
#define CPTRA_FW_REV_ID0    0x300D8u
#define CPTRA_FW_REV_ID1    0x300DCu
#define HOST_PAUSER         0x00000001u  /* constant PAUSER driven by rtl/avmm_to_apb.sv */
#define MBOX_CMD_FWLD       0x46574C44u  /* "FWLD" FIRMWARE_LOAD */
#define MBOX_ST_DATA_READY  1u
#define MBOX_ST_CMD_COMPLETE 2u
#define MBOX_ST_CMD_FAILURE 3u

/* ---- soc_fuse_ctrl (rtl/soc_fuse_ctrl.sv) ---- */
#define FC_ID               0x00u        /* 0x46555345 */
#define FC_CTRL             0x04u        /* bit0 START, bit1 CLEAR */
#define FC_STATUS           0x08u        /* bit0 BUSY bit1 DONE bit2 ERR bit3 RFF */
#define FC_COUNT            0x0Cu
#define FC_FW_BYTES         0x10u
#define FC_NUM_FUSES        0x14u

/* ---- STATUS_PIO bits (rtl/nios_caliptra_top.sv) ---- */
#define CTRL_PWRGOOD        (1u << 0)
#define CTRL_RST_B          (1u << 1)
#define ST_READY_FOR_FUSES  (1u << 0)
#define ST_READY_FOR_FW     (1u << 1)
#define ST_READY_FOR_RT     (1u << 2)
#define ST_ERROR_FATAL      (1u << 5)
#define ST_ERROR_NON_FATAL  (1u << 6)
#define ST_ETRNG_REQ        (1u << 7)

static inline void magic(uint32_t v) { REG32(MAGIC_PIO_BASE) = v; }
static void fail(uint32_t code) { magic(code); for (;;) ; }
static inline uint32_t status(void) { return REG32(STATUS_PIO_BASE); }

static void puthex(const char *l, uint32_t v)
{
    static const char h[] = "0123456789abcdef";
    char b[11] = "0x";
    for (int i = 0; i < 8; i++) b[2 + i] = h[(v >> (28 - 4 * i)) & 0xF];
    b[10] = 0;
    alt_putstr(l); alt_putstr(b); alt_putstr("\n");
}
static void delay(volatile uint32_t n) { while (n--) ; }

/* ---- SoC TRNG stand-in: 1.x RTL here has no internal TRNG, so the ROM/FW raise
 * etrng_req and the SoC must supply 12 x 32b. xorshift = TEST ENTROPY ONLY. ---- */
static uint32_t rng_state = 0x1234ABCDu;
static uint32_t trng_reqs;
static uint32_t xorshift32(void)
{
    uint32_t x = rng_state; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return rng_state = x;
}
static void trng_service(void)
{
    if (!(status() & ST_ETRNG_REQ)) return;
    for (uint32_t i = 0; i < 12; i++) CPTRA(CPTRA_TRNG_DATA0 + 4u * i) = xorshift32();
    CPTRA(CPTRA_TRNG_STATUS) = 2u;                     /* DATA_WR_DONE */
    trng_reqs++;
    for (uint32_t t = 0; (status() & ST_ETRNG_REQ) && t < 100000u; t++) ;
}
static void check_fatal(void) { if (status() & ST_ERROR_FATAL) fail(0xDEAD00FFu); }

/* wait for STATUS_PIO bit while servicing TRNG */
static void wait_status(uint32_t bit, uint32_t timeout_code)
{
    for (uint32_t t = 0; !(status() & bit); t++) {
        trng_service(); check_fatal();
        if (t > 200000000u) fail(timeout_code);
    }
}

int main(void)
{
    magic(0x00000001u);                                  /* M1 alive */

    /* 1. power good, then release reset */
    REG32(CTRL_PIO_BASE) = CTRL_PWRGOOD;
    delay(1000);
    REG32(CTRL_PIO_BASE) = CTRL_PWRGOOD | CTRL_RST_B;

    /* 2. ready_for_fuses */
    wait_status(ST_READY_FOR_FUSES, 0xDEAD0001u);
    magic(0x00000002u);
    uint32_t hw_rev = CPTRA(CPTRA_HW_REV_ID);
    puthex("CPTRA_HW_REV_ID   = ", hw_rev);
    if (hw_rev == 0 || hw_rev == 0xFFFFFFFFu) fail(0xDEAD0002u);

    /* PAUSER=1 is not a default valid mailbox user: register + lock slot 0 (fuse phase only) */
    CPTRA(CPTRA_MBOX_VALID_PAUSER0) = HOST_PAUSER;
    CPTRA(CPTRA_MBOX_PAUSER_LOCK0)  = 1u;
    magic(0x00000003u);

    /* 3. fuse controller IP pushes the full OTP image (83 FUSE_* words) + FUSE_WR_DONE */
    if (FUSECTL(FC_ID) != 0x46555345u) fail(0xDEAD0003u);
    FUSECTL(FC_CTRL) = 1u;                               /* START */
    uint32_t fs;
    for (uint32_t t = 0; ((fs = FUSECTL(FC_STATUS)) & 1u) || !(fs & 6u); t++)
        if (t > 1000000u) fail(0xDEAD0004u);
    if (fs & 4u) fail(0xDEAD0005u);                      /* PSLVERR or not ready_for_fuses */
    puthex("FUSE words written= ", FUSECTL(FC_COUNT));  /* 84 = 83 fuses + FUSE_WR_DONE */
    if (!(CPTRA(CPTRA_FUSE_WR_DONE) & 1u)) fail(0xDEAD0006u);
    puthex("CPTRA_FLOW_STATUS = ", CPTRA(CPTRA_FLOW_STATUS));
    magic(0x00000004u);

    /* 4/5. ROM boots (TRNG serviced meanwhile) until ready_for_fw_push */
    wait_status(ST_READY_FOR_FW, 0xDEAD0007u);
    magic(0x00000005u);
    puthex("ready_for_fw_push, trng_reqs = ", trng_reqs);

    /* mailbox FIRMWARE_LOAD */
    uint32_t fw_bytes = FUSECTL(FC_FW_BYTES);
    uint32_t t = 0;
    while (CPTRA(MBOX_LOCK) & 1u) { trng_service(); if (++t > 10000000u) fail(0xDEAD0008u); }
    if (CPTRA(MBOX_USER) != HOST_PAUSER) fail(0xDEAD0009u);
    CPTRA(MBOX_CMD)  = MBOX_CMD_FWLD;
    CPTRA(MBOX_DLEN) = fw_bytes;
    uint32_t words = (fw_bytes + 3u) / 4u;
    for (uint32_t i = 0; i < words; i++) {
        CPTRA(MBOX_DATAIN) = FWSTORE(i);
        if ((i & 0xFFu) == 0) trng_service();
    }
    CPTRA(MBOX_EXECUTE) = 1u;
    magic(0x00000006u);
    puthex("FIRMWARE_LOAD bytes= ", fw_bytes);

    uint32_t mst;
    t = 0;
    while (((mst = CPTRA(MBOX_STATUS)) & 0xFu) == 0) {
        trng_service(); check_fatal();
        if (++t > 200000000u) fail(0xDEAD000Au);
    }
    puthex("MBOX_STATUS       = ", mst);
    CPTRA(MBOX_EXECUTE) = 0u;                            /* release mailbox */
    if ((mst & 0xFu) == MBOX_ST_CMD_FAILURE) fail(0xDEAD000Bu);
    magic(0x00000007u);

    /* 6. runtime */
    wait_status(ST_READY_FOR_RT, 0xDEAD000Cu);
    puthex("ready_for_runtime FLOW_STATUS = ", CPTRA(CPTRA_FLOW_STATUS));
    puthex("CPTRA_FW_REV_ID0  = ", CPTRA(CPTRA_FW_REV_ID0));
    puthex("CPTRA_FW_REV_ID1  = ", CPTRA(CPTRA_FW_REV_ID1));
    if (status() & (ST_ERROR_FATAL | ST_ERROR_NON_FATAL)) fail(0xDEAD000Du);
    magic(0xCA11F00Du);                                  /* success; led = 0x0D */
    for (;;) trng_service();                             /* keep serving runtime TRNG requests */
    return 0;
}
