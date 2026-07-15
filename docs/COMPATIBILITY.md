# Compatibility policy

[简体中文](zh-CN/COMPATIBILITY.md) · [Home](../README.md)

Compatibility is declared from capabilities and evidence. It is not inferred from a brand name,
model family, adapter maturity, or successful fixture.

## Current implemented reference adapter

The implemented Merlin adapter targets ASUS gateways running official Asuswrt-Merlin with persistent
`/jffs` storage, SSH access, required POSIX utilities, and a supported CPU/runtime combination. The
runtime path uses ShellCrash/ShellClash with a Mihomo-compatible runtime.

This implementation is the project's reference adapter. Reference status identifies the first
implemented architecture path; it does not assign a verified maturity stage and does not extend
support to every ASUS model, Merlin build, runtime release, provider, or network.

## Two independent classifications

Adapter maturity describes implementation ownership and evidence:

- external integration;
- experimental adapter;
- community-maintained adapter; or
- verified adapter.

Target support classification describes one target evaluated by an adapter:

- **`supported`** — all required capabilities and applicable evidence gates are satisfied;
- **`supported_needs_manual`** — the target is suitable, but a named manual action must be completed;
- **`accepted_modified`** — the operator explicitly accepts a compatible modified baseline and its
  provenance/support risk;
- **`unknown`** — evidence is insufficient to determine firmware, architecture, storage, shell,
  runtime, or another required capability; or
- **`unsupported`** — a required capability is absent or conflicts with the adapter boundary.

An adapter does not inherit a wider target-support claim from its maturity label, and one target's
classification does not promote the adapter's maturity.

## Public evidence boundary

Exact machine-readable requirements and classifications are in
[`config/compatibility-matrix.json`](../config/compatibility-matrix.json). Its `field_evidence` array
is intentionally empty, so its listed target paths remain `unknown`. Fixtures are not field
certification: they demonstrate offline script
behavior against synthetic inputs, not observed behavior on a specific router, firmware build,
provider, or network.

Before apply, use the guided capability checks and review every mismatch. A target classification
does not guarantee safety, availability, or success. Keep a soft-router or endpoint fallback
independent; success on a fallback does not validate the router path.

## Future adapters

A new adapter should declare its capability contract, ownership, target-support policy, fixtures,
backup and rollback behavior, diagnostics that do not expose sensitive information, licensing boundary, and bilingual operator
guidance before admission. See [Architecture](ARCHITECTURE.md) and [Governance](../GOVERNANCE.md).
