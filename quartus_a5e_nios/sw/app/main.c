/* Nios V host app: bring Caliptra 1.x out of reset and read soc_ifc over APB.
 * Base addresses come from the generated BSP system.h (see README address map). */
#include <stdint.h>
#include "sys/alt_stdio.h"
#include "system.h"

#ifdef CALIPTRA_WIN_BASE
#define CALIPTRA_APB_BASE   CALIPTRA_WIN_BASE
#endif
#ifndef CALIPTRA_APB_BASE
#define CALIPTRA_APB_BASE   0x00040000u  /* mm_bridge 's0' in nios_caliptra_sys */
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
#define CPTRA(off)          REG32(CALIPTRA_APB_BASE + (off))

/* Caliptra 1.x APB offsets (18-bit window) */
#define CPTRA_FLOW_STATUS   0x3003Cu
#define CPTRA_HW_REV_ID     0x300D4u
#define CPTRA_FW_REV_ID0    0x300D8u
#define MBOX_LOCK           0x20000u
#define MBOX_USER           0x20004u
#define CPTRA_MBOX_VALID_PAUSER0 0x30048u
#define CPTRA_MBOX_PAUSER_LOCK0  0x3005Cu
#define CPTRA_FUSE_WR_DONE  0x300B0u
#define FUSE_UDS_SEED0      0x30200u
#define HOST_PAUSER         0x00000001u  /* constant PAUSER driven by rtl/avmm_to_apb.sv */

#define CTRL_PWRGOOD        (1u << 0)
#define CTRL_RST_B          (1u << 1)
#define CTRL_BRKPOINT       (1u << 2)
#define ST_READY_FOR_FUSES  (1u << 0)
#define ST_ERROR_FATAL      (1u << 5)
#define ST_ERROR_NON_FATAL  (1u << 6)

static void puthex(const char *l, uint32_t v)
{
    static const char h[] = "0123456789abcdef";
    char b[11] = "0x";
    for (int i = 0; i < 8; i++) b[2 + i] = h[(v >> (28 - 4 * i)) & 0xF];
    b[10] = 0;
    alt_putstr(l); alt_putstr(b); alt_putstr("\n");
}

static void delay(volatile uint32_t n) { while (n--) ; }

int main(void)
{
    REG32(MAGIC_PIO_BASE) = 0x00000001u;               /* stage 1: alive */

    /* power good, then release reset */
    REG32(CTRL_PIO_BASE) = CTRL_PWRGOOD;
    delay(1000);
    REG32(CTRL_PIO_BASE) = CTRL_PWRGOOD | CTRL_RST_B;

    /* wait for ROM-less BootFSM to request fuses */
    uint32_t t = 0;
    while (!(REG32(STATUS_PIO_BASE) & ST_READY_FOR_FUSES)) {
        if (++t > 10000000u) { REG32(MAGIC_PIO_BASE) = 0xDEAD0001u; for (;;) ; }
    }
    REG32(MAGIC_PIO_BASE) = 0x00000002u;               /* stage 2: ready_for_fuses */

    uint32_t hw_rev = CPTRA(CPTRA_HW_REV_ID);
    uint32_t flow   = CPTRA(CPTRA_FLOW_STATUS);
    puthex("CPTRA_HW_REV_ID   = ", hw_rev);   /* expect 0x00000011 */
    puthex("CPTRA_FLOW_STATUS = ", flow);     /* bit30 ready_for_fuses */

    /* Caliptra 1.x HW_REV_ID: CPTRA_GENERATION [15:0] = 0x0011 (major 1, minor 1).
     * Accept any non-zero/non-all-ones value as "bus works". */
    if (hw_rev == 0 || hw_rev == 0xFFFFFFFFu) { REG32(MAGIC_PIO_BASE) = 0xDEAD0002u; for (;;) ; }

    /* Stage 3 (same sequence as sim/tb_boot_apb.sv, which passes in Verilator):
     * our PAUSER (1) is not the default valid mailbox user (0xFFFFFFFF), so register
     * and lock it in slot 0 during the fuse phase, or every mailbox access gets PSLVERR. */
    CPTRA(CPTRA_MBOX_VALID_PAUSER0) = HOST_PAUSER;
    CPTRA(CPTRA_MBOX_PAUSER_LOCK0)  = 1u;
    puthex("MBOX_VALID_PAUSER0= ", CPTRA(CPTRA_MBOX_VALID_PAUSER0));
    REG32(MAGIC_PIO_BASE) = 0x00000003u;

    /* Minimal TEST fuse load: one UDS word, then FUSE_WR_DONE -> BootFSM DONE */
    CPTRA(FUSE_UDS_SEED0)     = 0xDEADBEEFu;
    CPTRA(CPTRA_FUSE_WR_DONE) = 1u;
    delay(1000);
    if (!(CPTRA(CPTRA_FUSE_WR_DONE) & 1u)) { REG32(MAGIC_PIO_BASE) = 0xDEAD0003u; for (;;) ; }
    puthex("CPTRA_FLOW_STATUS = ", CPTRA(CPTRA_FLOW_STATUS));   /* sim: 0x08000000 */
    REG32(MAGIC_PIO_BASE) = 0x00000004u;

    /* Mailbox: first MBOX_LOCK read acquires (0), MBOX_USER must equal our PAUSER */
    uint32_t lk = CPTRA(MBOX_LOCK);
    uint32_t mu = CPTRA(MBOX_USER);
    puthex("MBOX_LOCK (acq)   = ", lk);
    puthex("MBOX_USER         = ", mu);
    if ((lk & 1u) || mu != HOST_PAUSER) { REG32(MAGIC_PIO_BASE) = 0xDEAD0004u; for (;;) ; }

    uint32_t st = REG32(STATUS_PIO_BASE);
    if (st & (ST_ERROR_FATAL | ST_ERROR_NON_FATAL)) { REG32(MAGIC_PIO_BASE) = 0xDEAD0005u; for (;;) ; }
    REG32(MAGIC_PIO_BASE) = 0xCA11F00Du;                 /* success; led = 0x0D */
    for (;;) ;
    return 0;
}
