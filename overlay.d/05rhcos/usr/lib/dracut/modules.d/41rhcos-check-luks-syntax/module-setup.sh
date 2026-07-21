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

install_unit() {
    local unit="$1"; shift
    local target="${1:-ignition-complete.target}"; shift
    local instantiated="${1:-$unit}"; shift
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    # note we `|| exit 1` here so we error out if e.g. the units are missing
    # see https://github.com/coreos/fedora-coreos-config/issues/799
    systemctl -q --root="$initdir" add-requires "$target" "$instantiated" || exit 1
}

install() {
    inst_script "$moddir/rhcos-fail-boot-for-legacy-luks-config" \
        "/usr/libexec/rhcos-fail-boot-for-legacy-luks-config"

    install_unit rhcos-fail-boot-for-legacy-luks-config.service
}
