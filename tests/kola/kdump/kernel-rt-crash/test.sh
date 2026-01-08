#!/bin/bash
## kola:
##   tags: "needs-internet skip-base-checks"
##   timeoutMin: 15
##   # We've seen some OOM when 1024M is used in similar tests:
##   # https://github.com/coreos/fedora-coreos-tracker/issues/1506
##   minMemory: 2048
##   architectures: x86_64
##   description: Verify kdump successfuly generates vmcore even after
##       replacing the kernel with kernel-rt.

set -euo pipefail

. $KOLA_EXT_DATA/commonlib.sh

# Execute a command verbosely, i.e. echoing its arguments to stderr
runv () {
    ( set -x ; "${@}" )
}

basearch=$(arch)

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
# first boot : install kernel-rt
"")

    # in prow there isn't any repos in the image, so we use the centos stream repos
    if [ -z "$(ls -A /etc/yum.repos.d/)" ]; then
       if match_maj_ver "9"; then
        repo_name=c9s.repo
        if [ ! -e /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official ]; then
            runv curl -sSLf https://centos.org/keys/RPM-GPG-KEY-CentOS-Official-SHA256 -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official
        fi
        elif match_maj_ver "10"; then
            repo_name=c10s.repo
            if [ ! -e /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256 ]; then
                runv curl -sSLf https://centos.org/keys/RPM-GPG-KEY-CentOS-Official-SHA256 -o /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256
            fi
        else
            fatal "Unhandled major RHEL/SCOS VERSION"
        fi

        runv cp "$KOLA_EXT_DATA/$repo_name" /etc/yum.repos.d/cs.repo
    fi
    # Enable nfv and rt repos
    runv sed -i '/\[nfv\]/,/^ *\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/*.repo
    runv sed -i '/\[rt\]/,/^ *\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/*.repo
    runv sed -i '/\[extras\-common\]/,/^ *\[/ s/enabled=1/enabled=0/' /etc/yum.repos.d/*.repo
    kernel_pkgs=("kernel-rt-core" "kernel-rt-modules" "kernel-rt-modules-extra" "kernel-rt-modules-core")
    args=()
    for x in ${kernel_pkgs}; do
        args+=(--install "${x}")
    done
    runv rpm-ostree override remove kernel{,-core,-modules,-modules-extra,-modules-core} "${args[@]}"
    # enable kdump and reboot
    # we don't enable kdump for the first boot to avoid building the initramfs twice
    systemctl enable kdump.service
    runv /tmp/autopkgtest-reboot 1
    ;;
# first reboot : confirm we have kernel-rt and kdump is active
1)
    case $(uname -r) in
        *".${basearch}+rt") echo "ok kernel-rt" ;;
        *)
           runv uname -r
           runv rpm -q kernel-rt
           fatal "Failed to apply rt kernel override"
        ;;
    esac

    # use 240s for this since kdump can take a while to build its initramfs,
    # especially if the system is loaded
    if ! is_service_active kdump.service 240; then
      fatal "kdump.service failed to start"
    fi
    # Verify that the crashkernel reserved memory is large enough
    output=$(kdumpctl estimate)
    if grep -q "WARNING: Current crashkernel size is lower than recommended size" <<< "$output"; then
      fatal "The reserved crashkernel size is lower than recommended."
    fi

    kdump_path="/var/lib/kdump/initramfs-$(uname -r)kdump.img"

    if [[ ! -f "${kdump_path}" ]]; then
      fatal "kdump initrd not found at path ${kdump_path}"
    fi

    /tmp/autopkgtest-reboot-prepare 2

    # Now we can crash the kernel
    echo "Triggering sysrq"
    sync
    # Give I/O a moment to settle after sync before crashing.
    # We've seen this test hang forever in prow without this.
    # https://github.com/coreos/rhel-coreos-config/issues/132
    sleep 1
    echo 1 > /proc/sys/kernel/sysrq
    # This one will trigger kdump, which will write the kernel core, then reboot.
    echo c > /proc/sysrq-trigger
    # We shouldn't reach this point
    sleep 5
    fatal "failed to invoke sysrq"
    ;;
# second reboot : check for the memory dump
2)
    kcore=$(find /var/crash -type f -name vmcore)
    if test -z "${kcore}"; then
        fatal "No kcore found in /var/crash"
    fi
    info=$(file "${kcore}")
    if ! [[ "${info}" =~ 'vmcore: Kdump'.*'system Linux' ]]; then
        fatal "vmcore does not appear to be a Kdump?"
    fi
    ;;
*)
    fatal "Unhandled reboot mark ${AUTOPKGTEST_REBOOT_MARK:-}"
    ;;
esac

echo ok
