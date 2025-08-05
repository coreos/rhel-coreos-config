# Building and developing Red Hat Enterprise Linux CoreOS

## Background

RHEL CoreOS (RHCOS) is a derivative of Red Hat Enterprise Linux (RHEL), CentOS
Strema CoreOS (SCOS) and Fedora CoreOS (FCOS). The tool to build RHCOS, SCOS
and FCOS is [coreos-assembler]. The process detailled here is thus very similar
to the one described in [Building Fedora CoreOS] or [Building and developing
CentOS Stream CoreOS](development-scos.md) but requires access to Red Hat
internal resources.

## Build process

Note that this documentation applies only to RHCOS versions starting with 4.19
and later. For version from 4.9 to 4.18, see the documentation from
[openshift/os (4.18 branch)](https://github.com/openshift/os/blob/release-4.18/docs/development-rhcos.md).
For versions older than 4.9, see the internal documentation.

- Make sure you're meeting the [prerequisites].

- Make sure that you have setup the Red Hat internal CA on your system and that
  you are connected to the Red Hat VPN.

- Setup a `cosa` alias, following the [upstream documentation][cosa-alias].
  - Note: If you encounter DNS resolution issues with COSA when on the Red Hat
    VPN, you should try adding `--net=host` to the podman invocation.

- Create and use a dedicated directory:
  ```
  $ mkdir rhcos
  $ cd rhcos
  ```
  If you're going to work on RHCOS based on different versions of RHEL, using a
  dedicated directory for each RHEL version is recommended:
  ```
  $ mkdir rhcos-rhel-10.1
  $ cd rhcos-rhel-10.1
  ```

- Make sure that you have setup the latest internal Red Hat root certificates
  on your host system. See the internal documentation.

- Make sure that you have the latest `cosa` alias from the
  [documentation][cosa-alias]. Then ask COSA to use those certificates:
  ```
  $ export COREOS_ASSEMBLER_ADD_CERTS='y'
  ```

- Get the following value from the internal documentation:
  ```
  $ export RHCOS_REPO="..."
  ```

- Clone the config repo (`coreos/rhel-coreos-config`), passing as argument the
  internal Git repo which includes the RPM repo configs and optionaly the
  specific branch:
  ```
  # Main developement branch, default version
  $ cosa init --yumrepos "${RHCOS_REPO}" https://github.com/coreos/rhel-coreos-config.git

  # Main developement branch, selecting a specific variant
  $ cosa init --yumrepos "${RHCOS_REPO}" --variant rhel-10.1 https://github.com/coreos/rhel-coreos-config.git

  # Specific develepment branch, selecting a specific variant
  $ cosa init --yumrepos "${RHCOS_REPO}" --variant rhel-10.1 --branch foobar https://github.com/coreos/rhel-coreos-config.git
  ```

- Fetch packages and build RHCOS ostree container and QEMU image:
  ```
  $ cosa fetch
  $ cosa build
  ```

## Building RHCOS images for other platforms than QEMU

- You can build images for platforms that are supported in COSA using the
  [`buildextend` commands][buildextend]:
  ```
  $ cosa osbuild aws
  $ cosa osbuild openstack
  ```

## Running RHCOS locally for testing

- You may then run an ephemeral virtual machine using QEMU with:
  ```
  $ cosa run
  ```

## Testing RHCOS with kola

- You may then run tests on the image built with [`kola`][kola]:
  ```
  # Run basic QEMU scenarios
  $ cosa kola run basic*
  # Run all kola tests (internal & external)
  $ cosa kola run --parallel 2
  ```

## Overriding packages for testing

- If you need to override a file or a package for local testing, you can place
  those into the `override/rootfs` or `override/rpm` directory before building
  the image. See the [Using overrides] section from the [COSA
  documentation][coreos-assembler].

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[Building Fedora CoreOS]: https://coreos.github.io/coreos-assembler/building-fcos/
[prerequisites]: https://coreos.github.io/coreos-assembler/building-fcos/#getting-started---prerequisites
[cosa-alias]: https://coreos.github.io/coreos-assembler/building-fcos/#define-a-bash-alias-to-run-cosa
[buildextend]: https://coreos.github.io/coreos-assembler/cosa/#buildextend-commands
[kola]: https://coreos.github.io/coreos-assembler/kola/
[Using overrides]: https://coreos.github.io/coreos-assembler/working/#using-overrides
