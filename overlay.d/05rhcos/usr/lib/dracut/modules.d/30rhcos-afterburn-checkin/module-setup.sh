# RHCOS specific initramfs checkin for Azure. Linked to
# initrd.target much like what we do for ignition
#
# Context: this is for installer UX considerations. The provision
# success check masks issues with Ignition configs because it runs
# after Ignition (which may never conclude). Terraform will also
# report that nothing is progressing (as it is waiting for the checkin
# even though things are. Kube will do the actual health handling
# for the machine.

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
    echo network systemd
}

install() {
    local unit=rhcos-afterburn-checkin.service
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    # note we `|| exit 1` here so we error out if e.g. the units are missing
    # see https://github.com/coreos/fedora-coreos-config/issues/799
    systemctl -q --root="$initdir" add-requires ignition-files.service "$unit" || exit 1
}
