#!/bin/bash
## kola:
##   distros: "rhcos"
##   tags: needs-internet
##   platforms: qemu
##   numaNodes: true
##   minMemory: 2048
##   architectures: "!s390x"
##   description: Verify that numad detects nodes and tracks processes

set -euo pipefail

# shellcheck disable=SC1091
. "$KOLA_EXT_DATA/commonlib.sh"

if [[ $(systemctl show numad -p ActiveState) != "ActiveState=active" ]]; then
    fatal "numad did not activate"
fi

if ! lscpu | grep -Eq "NUMA node\(s\):\s*2"; then
    fatal "expected to find exactly 2 numa nodes"
fi

# run a process and check that the daemon is actively monitoring it
podman run --privileged \
       --name pod-stress-ng --pid=host \
       ghcr.io/colinianking/stress-ng \
       -A --vm 1 --vm-bytes 50% \
       --timeout 20s

logfile="/var/log/numad.log"
pattern='MBs_total\s+[0-9]+, MBs_free\s+[0-9]+, CPUs_total\s+[0-9]+, CPUs_free\s+[0-9]+'

for node in 0 1; do
    if ! grep -Eq "Node ${node}: ${pattern}" "$logfile"; then
        fatal "Numad didn't detect Node ${node}"
    fi
done

# Check that the stress test was being monitored by numad
if ! grep -q "stress-ng-vm" /var/log/numad.log; then
    fatal "Numad is not monitoring the stress test"
fi

ok "Numad working as expected"
