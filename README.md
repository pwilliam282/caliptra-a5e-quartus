# Caliptra 1.x on Agilex 5 E (Quartus project)

Passive Caliptra 1.x (v1.1) Quartus Prime Pro 25.3 project targeting **A5EC065BB32AE6S**.

## Contents
- `quartus_a5e/` — QSF/QPF, SDC, `run_a5e_docker.sh`, `flow.log`, synthesis reports under `output_files/`
- `STUDY.md` — C10 GX + A5E fit study notes

## Synth result
- Logic: ~141,256 / 222,400 ALMs (**64%**)
- Placement succeeded; routing OOM on 16 GB VM — needs ≥32 GB for full fit

## License
Requires Altera **SW-AGILEX-5E** (no-cost) for your host NIC. Do **not** commit license `.dat` files. Request one from Altera SSLC for your MAC.

## Build
```bash
cd quartus_a5e
# set LM_LICENSE_FILE to your SW-AGILEX-5E.dat
./run_a5e_docker.sh   # alterafpga/quartuspro-v25.3:agilex5, --net=host
```
