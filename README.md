# RHEL CoreOS and CentOS Stream CoreOS config

This repository is the "config" repository used to build RHEL CoreOS and CentOS
Stream CoreOS using [coreos-assembler].

The main output is a bootable container image containing _only RHEL/CentOS
Stream content_ (i.e., no OpenShift components). This container image is then
used as the base image to build the [OpenShift node image].

## Variants

To support building both a RHEL-based and a CentOS Stream-based CoreOS, the
coreos-assembler concept of [variants] is used. The following variants are
supported:

- RHEL-based variants: `rhel-9.8`, `rhel-10.1`
- CentOS Stream-based variants: `c9s`, `c10s`

The default variant is `rhel-9.8`.

## Reporting issues

The issue tracker for this repository is only used to track the development
work related to RHEL CoreOS.

**Please report OKD or CentOS Stream CoreOS issues in the [OKD issue tracker].**

**Please see this [FAQ entry for Red Hat support](https://github.com/openshift/os/blob/master/docs/faq.md#q-where-should-i-report-issues-with-openshift-container-platform-or-red-hat-coreos).**

## Frequently Asked Questions

A lot of common questions are answered in the [FAQ].

## Building and developing CentOS Stream CoreOS

See the [SCOS development doc](docs/development-scos.md).

## Building and developing RHEL CoreOS

See the [RHCOS development doc](docs/development-rhcos.md).

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[OpenShift node image]: https://github.com/openshift/os
[OKD issue tracker]: https://github.com/openshift/okd/issues
[variants]: https://github.com/coreos/coreos-assembler/blob/065cd2d20e379642cc3a69e498d20708e2243b21/src/cmd-init#L45-L48
[FAQ]: https://github.com/openshift/os/blob/master/docs/faq.md
