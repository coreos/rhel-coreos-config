#!/bin/bash

check() {
    # If we are in a kdump environment return 255, so this module is only
    # included if some other module depends on it
    # See: https://github.com/coreos/fedora-coreos-tracker/issues/1832
    #
    # This module requires integration with the rest of the initramfs, so don't include it by default.
    if [[ $IN_KDUMP == 1 ]]; then
        return 255
    fi
}

depends() {
    echo fips ignition
}

install() {
    inst_multiple \
        jq \
        tee \
        chroot \
        sync \
        bwrap \
        env

    inst_script "$moddir/rhcos-fips.sh" \
        "/usr/sbin/rhcos-fips"
    inst_script "$moddir/coreos-dummy-ignition-files-run.sh" \
        "/usr/sbin/coreos-dummy-ignition-files-run"
    inst_simple "$moddir/rhcos-fips.service" \
        "$systemdsystemunitdir/rhcos-fips.service"
    inst_simple "$moddir/rhcos-fips-finish.service" \
        "$systemdsystemunitdir/rhcos-fips-finish.service"
    inst_simple "$moddir/rhcos-fips-dracut-boot-fix.service" \
        "$systemdsystemunitdir/rhcos-fips-dracut-boot-fix.service"

    # Unconditionally include /etc/system-fips in the initrd. This has no
    # practical effect if fips=1 isn't also enabled. OTOH, it is a *requirement*
    # for a true FIPS boot: https://bugzilla.redhat.com/show_bug.cgi?id=1778940
    echo "# RHCOS FIPS mode installation complete" > "$initdir/etc/system-fips"

    # note we `|| exit 1` here so we error out if e.g. the units are missing
    # see https://github.com/coreos/fedora-coreos-config/issues/799
    # We don't support reconfiguring the bootloader for FIPS in diskless cases
    systemctl -q --root="$initdir" add-requires ignition-diskful.target rhcos-fips.service || exit 1
    systemctl -q --root="$initdir" add-requires initrd.target rhcos-fips-finish.service || exit 1
}
