# Public release readiness

[简体中文](zh-CN/RELEASE_READINESS.md) · [Home](../README.md)

This document defines the evidence that can be checked from this source tree. It is not a release approval or a claim about a live router.

## Source-tree checks

- PowerShell 5 parsing and POSIX `sh -n` syntax checks pass.
- Synthetic offline fixture suites pass without contacting a router or network.
- The compatibility policy parses, uses `home-edge-public-compatibility/v1`, and keeps `field_evidence` empty.
- The compatibility policy keeps adapter maturity independent from target support and records the
  Merlin implementation as an implemented reference without an assigned verified maturity stage.
- Secret scanning, license presence, SPDX 2.3 structure, bilingual document links, and public closeout structure pass.
- The stable local verifier result is `local_verification_state=ready`.

## Offline artifact checks

An offline recovery artifact needs separate checksum verification, complete runtime package/source
data, third-party license materials, archive-content review, host-platform execution evidence, and a
release-specific SBOM and manifest. Those checks apply to the concrete artifact, not to source-tree
readiness alone.

## Claim boundary

Source-tree readiness does not certify router models, firmware, providers, live-network behavior, security outcomes, uninterrupted availability, or deployment success. No support service level is offered. A release decision requires review of the concrete source commit and any concrete offline artifact.
