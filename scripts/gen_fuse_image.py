#!/usr/bin/env python3
"""Generate fw/fuse_image.hex: the SoC "OTP" image that soc_fuse_ctrl pushes into
Caliptra 1.x soc_ifc FUSE_* registers (APB 0x30200..0x30348, 83 words, in order).
One 32-bit word per line ($readmemh). TEST VALUES ONLY - never production secrets.

Key choices for the caliptra-sw rom-1.1.1 / FW bundle in fw/:
  * KEY_MANIFEST_PK_HASH = 0  -> 1.x ROM skips vendor PK-hash check (unprovisioned
    test flow, same as the passing sim/tb_boot_apb_fw.sv). Put the real SHA-384 of
    the vendor key descriptor here when you sign your own FW.
  * OWNER_PK_HASH = 0, SVNs = 0, ANTI_ROLLBACK_DISABLE = 0, LMS_VERIFY = 0, LIFE_CYCLE = 0.
"""
import os
UDS = [0xDEADBEEF] + [0x55AA0000 | i for i in range(1, 12)]        # 384-bit test UDS seed
FE  = [0xFE000000 | i for i in range(8)]                            # 256-bit test field entropy
fuses = {}
def put(base, words):
    for i, w in enumerate(words): fuses[base + 4*i] = w
put(0x200, UDS)                 # FUSE_UDS_SEED[0..11]
put(0x230, FE)                  # FUSE_FIELD_ENTROPY[0..7]
put(0x250, [0]*12)              # FUSE_KEY_MANIFEST_PK_HASH[0..11]
put(0x280, [0])                 # FUSE_KEY_MANIFEST_PK_HASH_MASK
put(0x284, [0]*12)              # FUSE_OWNER_PK_HASH[0..11]
put(0x2b4, [0])                 # FUSE_FMC_KEY_MANIFEST_SVN
put(0x2b8, [0]*4)               # FUSE_RUNTIME_SVN[0..3]
put(0x2c8, [0])                 # FUSE_ANTI_ROLLBACK_DISABLE
put(0x2cc, [0]*24)              # FUSE_IDEVID_CERT_ATTR[0..23]
put(0x32c, [0]*4)               # FUSE_IDEVID_MANUF_HSM_ID[0..3]
put(0x33c, [0])                 # FUSE_LIFE_CYCLE
put(0x340, [0])                 # FUSE_LMS_VERIFY
put(0x344, [0])                 # FUSE_LMS_REVOCATION
put(0x348, [0x00000001])        # FUSE_SOC_STEPPING_ID (A0 test)
addrs = list(range(0x200, 0x34c, 4))
assert sorted(fuses) == addrs, "fuse map has holes"
out = os.path.join(os.path.dirname(__file__), "..", "fw", "fuse_image.hex")
with open(out, "w") as f:
    for a in addrs: f.write("%08x\n" % fuses[a])
print("wrote %s (%d words)" % (out, len(addrs)))
