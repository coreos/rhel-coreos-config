#!/bin/bash
## kola:
##   exclusive: false
##   description: Verify that system is correctly detected on s390x
##   architectures: s390x

set -xeuo pipefail

. $KOLA_EXT_DATA/commonlib.sh

level=$(cat /sys/firmware/cpi/system_level)

# https://www.ibm.com/docs/en/linux-on-systems?topic=identification-system-level
# This may look like:
#   on QEMU - 0x070906023a050e00
#   on LPAR - 0x870906023a050e00
if is_rhcos && [[ ! "${level}" =~ ^0x.7 ]]; then
    fatal "RHCOS system detection failed: expected 0x.7... but got ${level}"
fi
