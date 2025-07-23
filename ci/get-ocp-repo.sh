#!/bin/bash
set -euo pipefail

# This script is used when running within the OpenShift CI clusters to fetch
# the RHEL and OCP yum repo files from an in-cluster service that mirrors the
# content.

urls=(
    # theoretically that's the only ones we need
    "http://base-4-19-rhel96.ocp.svc.cluster.local"
    "http://base-4-20-rhel10.ocp.svc.cluster.local"
    # XXX: but also currently add 9.4 repos for crun-wasm when building extensions
    # https://github.com/openshift/os/issues/1680
    # https://github.com/openshift/os/pull/1682
    # https://issues.redhat.com/browse/COS-3075
    "http://base-4-19-rhel94.ocp.svc.cluster.local"
)

dest=$1; shift
variant=$1; shift

rm -f "$dest"
for url in "${urls[@]}"; do
    curl --fail -L "$url" >> "$dest"
done
# ART team does not set the Y stream in RHEL10 repo definition, so we have to add it back to be consistent
# with our pipeline.
# https://github.com/openshift/release/blob/master/core-services/release-controller/_repos/ocp-4.20-rhel10.repo
if [[ "$variant" == rhel-10* ]]; then
    sed -i "/^name =/s/rhel-10/$variant/;/^\[.*\]$/s/rhel-10/$variant/" "$dest"
fi
