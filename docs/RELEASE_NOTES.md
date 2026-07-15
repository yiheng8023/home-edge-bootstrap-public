# Release notes

[简体中文](zh-CN/RELEASE_NOTES.md) · [Home](../README.md)

## v0.1.0

Initial public release of the Home Edge Bootstrap framework and its current implemented reference
adapter for ASUS gateways running official Asuswrt-Merlin.

Reference-adapter status identifies the first implemented architecture path; it does not assign a
verified adapter maturity stage or certify a wider compatibility range.

### Included capabilities

- Numbered TUI entry points for Windows PowerShell and POSIX hosts on macOS and Linux.
- Capability-first router guidance, dry-run planning, exact apply confirmation, backup-aware deployment, rollback, self-heal setup, health checks, and redacted support-bundle export.
- Synthetic offline fixtures and local verification for supported host CI environments.
- A capability-driven framework boundary, the current Merlin reference adapter, and an independent
  soft-router or endpoint fallback boundary.
- Separate adapter-maturity and target-support classifications for future community evolution.

### Artifact types

- Source archive or source checkout: scripts, documentation, policy, and fixtures. It may configure an existing runtime but does not by itself promise fresh offline runtime installation.
- Offline recovery archive: the source surface plus reviewed runtime payloads, checksum material,
  third-party licenses, complete corresponding source, and a release-specific SBOM. Verify release
  checksums before use.

### Verification

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1` on Windows or `sh scripts/verify-local.sh` on macOS/Linux. Host CI covers the corresponding PowerShell and POSIX paths; it does not certify router hardware or firmware.

### Known limitations

- Compatibility is capability-based and field evidence is not yet published in the policy matrix.
- The current reference adapter has no formally assigned verified maturity stage.
- Fixtures do not certify hardware, firmware, providers, or live networks.
- Runtime payload source, package, and checksum records must be completed and reviewed for each offline release artifact.
- Third-party components remain under their own licenses; see [third-party notices](../THIRD_PARTY_NOTICES.md) and the SPDX document at [`config/sbom.json`](../config/sbom.json).
