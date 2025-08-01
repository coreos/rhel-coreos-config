#!/bin/bash
set -xeuo pipefail

# Main script acting as entrypoint for all Prow jobs building RHCOS images

# Global variables
REDIRECTOR_URL="https://rhcos.mirror.openshift.com/art/storage/prod/streams"

# This function is used to update the /etc/passwd file within the COSA container
# at test-time. The need for this comes from the fact that OpenShift will run a
# container with a randomized user ID by default to enhance security. Because
# COSA runs with an unprivileged user ("builder") instead of (container) root,
# this presents special challenges for file and disk permissions. This particular
# pattern was inspired by:
# - https://cloud.redhat.com/blog/jupyter-on-openshift-part-6-running-as-an-assigned-user-id
# - https://cloud.redhat.com/blog/a-guide-to-openshift-and-uids
setup_user() {
    user_id="$(id -u)"
    group_id="$(id -g)"
    # create a homedir we're sure our UID will have access to
    homedir=$(mktemp -d -p /var/tmp)

    grep -v "^prowbuilder" /etc/passwd > /tmp/passwd
    echo "prowbuilder:x:${user_id}:${group_id}::${homedir}:/bin/bash" >> /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd

    # Not strictly required, but nice for debugging.
    id
    whoami
}

# Setup a new build directory with COSA init, selecting the version of RHEL or
# CentOS Stream that we want as a basis for RHCOS/SCOS.
cosa_init() {
    if [[ ${#} -ne 1 ]]; then
        echo "This should have been called with a single 'variant' argument"
        exit 1
    fi
    local -r variant="${1}"
    echo "Using variant: ${variant}"

    if test -d builds; then
        echo "Already in an initialized cosa dir"
        # Pull repos from an in-cluster service of the Openshift CI
        prepare_repos "${variant}"
        return
    fi

    # Always create a writable copy of the source repo
    tmp_src="$(mktemp -d)"
    cp -a /src "${tmp_src}/os"

    # Either use the COSA_DIR prepared for us or create a temporary cosa workdir
    cosa_dir="${COSA_DIR:-$(mktemp -d)}"
    echo "Using $cosa_dir for build"
    cd "$cosa_dir"

    # Setup source tree
    cosa init --transient --variant "${variant}" "${tmp_src}/os"

    # Pull repos from an in-cluster service of the Openshift CI
    prepare_repos "${variant}"
}

# Initialize the .repo files
prepare_repos() {
    if [[ ${#} -ne 1 ]]; then
        echo "This should have been called with a single 'variant' argument"
        exit 1
    fi
    local -r variant="${1}"

    src/config/ci/get-ocp-repo.sh src/config/ocp.repo "${variant}"
}

# Do a cosa build only.
# This is called both as part of the build phase and test phase in Prow thus we
# can not do any kola testing in this function.
# We do not build the QEMU image here as we don't need it in the pure container
# test case.
cosa_build() {
    # Fetch packages
    cosa fetch
    # Only build the ostree image by default
    cosa build ostree
}

# Build QEMU image and run all kola tests
kola_test_qemu() {
    cosa osbuild qemu
    cosa kola run --parallel 2 --output-dir ${ARTIFACT_DIR:-/tmp}/kola --rerun --allow-rerun-success tags=needs-internet
}

# Build metal, metal4k & live images and run kola tests
kola_test_metal() {
    # Build metal + installer now so we can test them
    cosa osbuild metal metal4k live

    # Compress the metal and metal4k images now so we're testing
    # installs with the image format we ship
    cosa compress --artifact=metal --artifact=metal4k

    # Run all testiso scenarios on metal artifact
    kola testiso -S --output-dir ${ARTIFACT_DIR:-/tmp}/kola-testiso  --denylist-test iso-offline-install-iscsi* --denylist-test pxe-offline-install.rootfs-appended.bios
}

# Basic syntaxt validation for manifests
validate() {
    # Create a temporary copy
    workdir="$(mktemp -d)"
    echo "Using $workdir as working directory"

    # for `git config --global` below
    export HOME=${workdir}

    # Figure out if we are running from the COSA image or directly from the Prow src image
    if [[ -d /src/github.com/openshift/os ]]; then
        cd "$workdir"
        git config --global --add safe.directory /src/github.com/openshift/os
        git clone /src/github.com/openshift/os os
    elif [[ -d ./.git ]]; then
        srcdir="${PWD}"
        cd "$workdir"
        git config --global --add safe.directory "${srcdir}/.git"
        git clone "${srcdir}" os
    else
        echo "Could not found source directory"
        exit 1
    fi
    cd os

    # First ensure submodules are initialized
    git submodule update --init --recursive
    # Basic syntax check
    ./fedora-coreos-config/ci/validate

    # Validate shell scripts with ShellCheck
    if [[ -z "$(command -v shellcheck)" ]]; then
        sudo dnf install -y ShellCheck
    fi

    local found_errors="false"
    # Let's start with error, then we can do warning, info, style
    local -r severity="error"

    # Disable -x as it generates too much noise
    set +x

    while IFS= read -r -d '' f; do
        shebang="$(head -1 "${f}")"
        if [[ "${f}" == *.sh ]] || \
            [[ ${shebang} =~ ^#!/.*/bash.* ]] || \
            [[ ${shebang} =~ ^#!/.*/env\ bash ]]; then
            echo "[+] Checking ${f}"
            shellcheck --shell bash --external-sources --severity="${severity}" "${f}" || found_errors="true"
            bash -n "${f}" || found_errors="true"
        fi
    done< <(find . -path "./.git" -prune -o -type f -print0)

    local files_with_whitespace=""
    local files_with_missing_empty_line_at_eof=""

    while IFS= read -r -d '' f; do
        echo "[+] Checking ${f}"

        # Looking for whitespace at end of line
        if grep -Eq " +$" "${f}"; then
            # List of files to ignore
            if \
                [[ "${f}" == "./docs/vsphere-settings.png" ]] || \
                [[ "${f}" == "./fedora-coreos-config/live/isolinux/boot.msg" ]] || \
                [[ "${f}" == "./live/isolinux/boot.msg" ]] \
                ; then
                echo "[+] Checking ${f}: Ignoring whitespace at end of line"
            else
                echo "[+] Checking ${f}: Found whitespace at end of line"
                files_with_whitespace+=" ${f}"
            fi
        fi

        # Looking for missing empty line at end of file
        if [[ -n $(tail -c 1 "${f}") ]]; then
            # List of files to ignore
            if \
                [[ "${f}" == "./docs/vsphere-settings.png" ]] || \
                [[ "${f}" == "./fedora-coreos-config/tests/kola/ignition/resource/authenticated-gs/data/expected/"* ]] ||\
                [[ "${f}" == "./fedora-coreos-config/tests/kola/ignition/resource/authenticated-s3/data/expected/"* ]] ||\
                [[ "${f}" == "./fedora-coreos-config/tests/kola/ignition/resource/remote/data/expected/"* ]] \
                ; then
                echo "[+] Checking ${f}: Ignoring missing empty line at end of file"
            else
                echo "[+] Checking ${f}: Missing empty line at end of file"
                files_with_missing_empty_line_at_eof+=" ${f}"
            fi
        fi
    done< <(find . -path "./.git" -prune -o -type f -print0)

    echo ""
    if [[ "${found_errors}" != "false" ]]; then
        echo "[+] Found errors with ShellCheck"
    else
        echo "[+] No error found with ShellCheck"
    fi

    echo ""
    if [[ -n "${files_with_whitespace}" ]]; then
        echo "[+] Found files with whitespace at the end of line"
        echo "${files_with_whitespace}" | tr ' ' '\n'
    else
        echo "[+] No files with whitespace at the end of line"
    fi

    echo ""
    if [[ -n "${files_with_missing_empty_line_at_eof}" ]]; then
        echo "[+] Found files with missing empty line at end of file"
        echo "${files_with_missing_empty_line_at_eof}" | tr ' ' '\n'
    else
        echo "[+] No files with missing empty line at end of file"
    fi

    if [[ -n "${files_with_whitespace}" ]] || [[ -n "${files_with_missing_empty_line_at_eof}" ]] || [[ "${found_errors}" != "false" ]]; then
        exit 1
    fi

    exit 0
}

main() {
    if [[ "${#}" -lt 1 ]]; then
        echo "This script is expected to be called by Prow with the name of the build phase or test to run"
        exit 1
    fi

    # Record information about cosa + rpm-ostree
    if [[ -d /cosa ]]; then
        jq . < /cosa/coreos-assembler-git.json
    fi
    if [[ $(command -v rpm-ostree) ]]; then
        rpm-ostree --version
    fi

    case "${1}" in
        "validate")
            validate
            ;;
        "init")
            cosa_init "$2"
            ;;
        # this is called by cosa's CI
        "rhcos-cosa-prow-pr-ci")
            setup_user
            cosa_init "rhel-9.6"
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-9-build-test-qemu")
            setup_user
            cosa_init "rhel-9.6"
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-9-build-test-metal")
            setup_user
            cosa_init "rhel-9.6"
            cosa_build
            kola_test_metal
            ;;
        "rhcos-9next-build-test-qemu")
            exit 0
            ;;
        "rhcos-9next-build-test-metal")
            exit 0
            ;;
        "scos-9-build-test-qemu")
            setup_user
            cosa_init "c9s"
            cosa_build
            kola_test_qemu
            ;;
        "scos-9-build-test-metal")
            setup_user
            cosa_init "c9s"
            cosa_build
            kola_test_metal
            ;;
        "scos-10-build-test-qemu")
            setup_user
            cosa_init "c10s"
            cosa_build
            kola_test_qemu
            ;;
        "scos-10-build-test-metal")
            setup_user
            cosa_init "c10s"
            cosa_build
            kola_test_metal
            ;;
        "rhcos-10-build-test-qemu")
            setup_user
            cosa_init "rhel-10.1"
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-10-build-test-metal")
            setup_user
            cosa_init "rhel-10.1"
            cosa_build
            kola_test_metal
            ;;
        *)
            # This case ensures that we exhaustively list the tests that should
            # pass for a PR. To add a new test in openshift/os:
            # 1. Add a new test case here that does nothing and get it merged
            # 2. Add a new test job in openshift/release that calls this test
            # 3. Update your test here and debug it with the CI in the PR
            echo "Unknown test name"
            exit 1
            ;;
    esac
}

main "${@}"
