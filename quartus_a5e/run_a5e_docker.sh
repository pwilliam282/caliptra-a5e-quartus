#!/bin/bash
# Quartus Pro 25.3 + SW-AGILEX-5E fixed license. --net=host REQUIRED (FlexLM host-ID = NIC).
set -euo pipefail
export PATH=/workspace/docker-bin:$PATH
cd "$(dirname "$0")"
LIC_HOST=/workspace/altera_license/SW-AGILEX-5E.dat
docker run --rm --net=host \
  -e HOME=/home/box \
  -e LM_LICENSE_FILE=/licenses/SW-AGILEX-5E.dat \
  -e ALTERA_LICENSE_FILE=/licenses/SW-AGILEX-5E.dat \
  -v /workspace:/workspace \
  -v /home/box:/home/box \
  -v "$LIC_HOST":/licenses/SW-AGILEX-5E.dat:ro \
  -w "$PWD" \
  alterafpga/quartuspro-v25.3:agilex5 \
  bash -lc 'quartus_syn --parallel=8 caliptra_a5e && quartus_fit --parallel=8 caliptra_a5e' \
  > flow.log 2>&1
echo "rc=$?"
