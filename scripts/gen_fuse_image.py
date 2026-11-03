#!/usr/bin/env python3
"""Generate fw/fuse_image.hex: the SoC "OTP" image that soc_fuse_ctrl pushes into
Caliptra 1.x soc_ifc FUSE_* registers (APB 0x30200..0x30348, 83 words, in order).
One 32-bit word per line ($readmemh).

PRODUCTION-LIFECYCLE *MIMIC* (FPGA study). UDS / field entropy are fixed STUDY values,
NOT real production secrets. Values are chosen so the rom-1.1.1 ROM verification passes
under DEVICE_PRODUCTION + debug locked with the test-signed bundle in fw/:
  * LIFE_CYCLE = 0b11 (Production)
  * KEY_MANIFEST_PK_HASH = SHA-384(preamble.vendor_pub_keys) of fw/caliptra-fw-bundle.bin
  * OWNER_PK_HASH        = SHA-384(preamble.owner_pub_keys)
    both as 12 big-endian words (caliptra-sw bytes_to_be_words_48, as in
    rom/dev/tests/rom_integration_tests/test_warm_reset.rs)
  * PK_HASH_MASK = 0 (no vendor ECC key revoked)
  * FMC/RT SVN fuses = 0: bundle TOC SVNs are 0, ROM requires image SVN >= fuse SVN.
"""
import os, struct, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLE = os.path.join(HERE, "..", "fw", "caliptra-fw-bundle.bin")
# ImageManifest layout (caliptra-sw 1.x image/types): marker,size | vendor_pub_keys(4*96 ECC + 32*48 LMS)
# | ecc/lms idx (8) | vendor_sigs (96+1620) | owner_pub_keys (96+48) | ...
VENDOR_OFF, VENDOR_LEN = 8, 4*96 + 32*48
OWNER_OFF, OWNER_LEN = VENDOR_OFF + VENDOR_LEN + 8 + 96 + 1620, 96 + 48
b = open(BUNDLE, "rb").read()
marker, msize = struct.unpack_from("<II", b, 0)
assert marker == 0x4E414D43, "bad MANIFEST_MARKER %08x" % marker
def be_words(d): return list(struct.unpack(">12I", d))
VENDOR_HASH = be_words(hashlib.sha384(b[VENDOR_OFF:VENDOR_OFF+VENDOR_LEN]).digest())
OWNER_HASH  = be_words(hashlib.sha384(b[OWNER_OFF:OWNER_OFF+OWNER_LEN]).digest())
fmc_svn = struct.unpack_from("<I", b, msize - 208 + 32)[0]
rt_svn  = struct.unpack_from("<I", b, msize - 104 + 32)[0]
assert fmc_svn == 0 and rt_svn == 0, "bundle SVN changed; set SVN fuses <= image SVN"
UDS = [0x1F2E3D4C ^ (0x9E3779B9 * (i + 1) & 0xFFFFFFFF) for i in range(12)]   # STUDY UDS seed
FE  = [0xA7C3E519 ^ (0x85EBCA6B * (i + 1) & 0xFFFFFFFF) for i in range(8)]    # STUDY field entropy
fuses = {}
def put(base, words):
    for i, w in enumerate(words): fuses[base + 4*i] = w
put(0x200, UDS)                 # FUSE_UDS_SEED[0..11]
put(0x230, FE)                  # FUSE_FIELD_ENTROPY[0..7]
put(0x250, VENDOR_HASH)              # FUSE_KEY_MANIFEST_PK_HASH[0..11]
put(0x280, [0])                 # FUSE_KEY_MANIFEST_PK_HASH_MASK
put(0x284, OWNER_HASH)              # FUSE_OWNER_PK_HASH[0..11]
put(0x2b4, [0])                 # FUSE_FMC_KEY_MANIFEST_SVN
put(0x2b8, [0]*4)               # FUSE_RUNTIME_SVN[0..3]
put(0x2c8, [0])                 # FUSE_ANTI_ROLLBACK_DISABLE
put(0x2cc, [0]*24)              # FUSE_IDEVID_CERT_ATTR[0..23]
put(0x32c, [0]*4)               # FUSE_IDEVID_MANUF_HSM_ID[0..3]
put(0x33c, [0x3])               # FUSE_LIFE_CYCLE
put(0x340, [0])                 # FUSE_LMS_VERIFY
put(0x344, [0])                 # FUSE_LMS_REVOCATION
put(0x348, [0x00000001])        # FUSE_SOC_STEPPING_ID (A0 test)
addrs = list(range(0x200, 0x34c, 4))
assert sorted(fuses) == addrs, "fuse map has holes"
out = os.path.join(os.path.dirname(__file__), "..", "fw", "fuse_image.hex")
with open(out, "w") as f:
    for a in addrs: f.write("%08x\n" % fuses[a])
print("wrote %s (%d words)" % (out, len(addrs)))
