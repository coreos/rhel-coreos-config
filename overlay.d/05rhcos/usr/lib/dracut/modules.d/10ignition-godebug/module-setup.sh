#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

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
    echo systemd
}

install() {
    inst_simple "$moddir/10-default-env-godebug.conf" \
        "/etc/systemd/system.conf.d/10-default-env-godebug.conf"
}
