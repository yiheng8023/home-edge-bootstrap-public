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

For v0.1.7, exact-commit host/fixture and concrete archive verification must additionally cover bilingual local help/session language switching, fresh target-bound project observation, default diagnosis/reuse, project-only refresh with `REPLACE` then `APPLY`, lock-time ownership rechecks, safe desktop reuse/update and event-driven directory/tool degradation. Project-only scope preserves runtime/core assets but may update managed integration/configuration. These gates do not establish exhaustive fault detection or complete runtime rollback.

For v0.1.7, limited source/host/archive distribution additionally requires three-host guide entries,
validated local location recovery and the concrete ZIP/tar entry metadata. The v0.1.5 exact-commit
subscription-behavior gate and source-only yamlbridge preparation/activation prerequisites remain.
Mihomo v1.19.32 and ShellCrash 1.9.4 are unchanged. Broad claims stay `blocked`; no new device,
runtime or native GUI field acceptance is assigned by this release.

Source-tree readiness does not certify router models, firmware, providers, live-network behavior, security outcomes, uninterrupted availability, or deployment success. No support service level is offered. A release decision requires review of the concrete source commit and any concrete offline artifact.

For v0.1.5, the exact-commit subscription-behavior job is an additional gate. yamlbridge is shipped as source only; host compiler/module preparation and explicit site activation remain separate. New Mihomo v1.19.32 bytes require matching complete source, inventory and binary build metadata; no new field acceptance is claimed.
