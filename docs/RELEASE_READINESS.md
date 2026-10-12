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

## v0.1.9 limited distribution contract

Require the exact new source commit across Linux, macOS, Windows and subscription-behavior CI, then verify the concrete public nine-asset set and bilingual release links. Retain all prior host, installation ownership, twice-confirmed refresh, entry metadata, source-only parser, licensing and locked-runtime gates.

Also verify exact HEAL_GROUP authority, manual-name exclusion from automatic main-group discovery, explicit manual-group authorization and separate nested/role opt-in boundaries, fresh pre-PUT observations and guarded rollback; disclose the controller's lack of atomic CAS. Verify active service-helper provenance, missing-command detector fallback, short-argv UTF-8/LF deployment transport including native PowerShell 5/7 and 16K cases, archive failure scope, and non-Git/missing-Git/first-Git provenance boundaries. Preserve the user's current selectors, profiles and core during separately authorized project-only adoption.

The v0.1.8 tags/drafts remain unpublished historical candidates. This new source/host/archive contract does not certify all devices, providers or GUI fields, does not upgrade broad blocked claims, and does not turn a version-only documentation commit into a new site/core deployment receipt. Preserve existing runtime/source locks and all older assets.

## Claim boundary

For v0.1.8, also verify exact OpenAI keyword/dependency-group conflict rejection, explicit service-rule binding, the bounded empty historical-backup exception, native Windows SSH stdin framing, and the ordered menu's always-discoverable bilingual language entry. Persistent service rules and current runtime activation require separate observations; a provider [AI] label or ordinary latency probe is not a service-availability verdict.

For v0.1.8, exact-commit host/fixture and concrete archive verification must additionally cover bilingual local help/session language switching, fresh target-bound project observation, default diagnosis/reuse, project-only refresh with `REPLACE` then `APPLY`, lock-time ownership rechecks, safe desktop reuse/update and event-driven directory/tool degradation. Project-only scope preserves runtime/core assets but may update managed integration/configuration. These gates do not establish exhaustive fault detection or complete runtime rollback.

For v0.1.8, limited source/host/archive distribution additionally requires three-host guide entries,
validated local location recovery and the concrete ZIP/tar entry metadata. The v0.1.5 exact-commit
subscription-behavior gate and source-only yamlbridge preparation/activation prerequisites remain.
Mihomo v1.19.32 and ShellCrash 1.9.4 are unchanged. Broad claims stay `blocked`; no new device,
runtime or native GUI field acceptance is assigned by this release.

Source-tree readiness does not certify router models, firmware, providers, live-network behavior, security outcomes, uninterrupted availability, or deployment success. No support service level is offered. A release decision requires review of the concrete source commit and any concrete offline artifact.

For v0.1.5, the exact-commit subscription-behavior job is an additional gate. yamlbridge is shipped as source only; host compiler/module preparation and explicit site activation remain separate. New Mihomo v1.19.32 bytes require matching complete source, inventory and binary build metadata; no new field acceptance is claimed.
