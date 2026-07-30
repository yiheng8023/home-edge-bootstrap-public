# Compatibility policy

[简体中文](zh-CN/COMPATIBILITY.md) · [Home](../README.md)

Compatibility is declared from capabilities and evidence. It is not inferred from a brand name,
model family, adapter maturity, or successful fixture.

## Current implemented reference adapter

The implemented Merlin adapter targets ASUS gateways running official Asuswrt-Merlin with persistent
`/jffs` storage, SSH access, the declared POSIX capabilities, and a supported CPU/runtime
combination. Supported firmware may expose a compact BusyBox userland rather than GNU or modern
BusyBox options. The deployer installs its managed secure temporary-path helper and accepts OpenSSL
when `base64` is absent; a firmware-provided `mktemp` is not a fresh-install prerequisite. The
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

## Upstream gateway and dual-stack boundary

The Merlin adapter manages the ASUS gateway only. An ISP device, Huawei gateway, or another router
may sit upstream when managed clients still use the ASUS LAN gateway and DNS path, the ASUS WAN side
has a usable address/default route/DNS/MTU, and direct upstream reachability is verified first.
Double NAT, inbound forwarding, DDNS, and upstream policy remain outside this adapter.

Changing the upstream is a new acceptance event: recheck WAN state, direct reachability, transparent
routing, DNS, and the client's effective gateway. IPv6 is independent of IPv4. Either disable IPv6
during acceptance or separately verify its default route, DNS, interception, and egress policy.

## Optional service-dependency profiles

Applications can depend on more domains than their main website. The project provides
`scripts/configure-shellcrash-service-rules.sh`; its default action is `plan`. An explicit `apply`
atomically manages one reviewed profile and records rollback state without automatically restarting
or reloading ShellCrash. It requires one existing service policy group and does not print that group
in logs. The built-in OpenAI profile follows OpenAI's published network recommendations but does not
promise coverage of every future dependency. The field-derived `asus-global-account` profile is
deliberately narrower: it routes only `nomos.asus.com` through an explicitly selected policy
(normally `DIRECT`) when the account page and OAuth callback succeed but token exchange is closed on
the default route. It does not route all ASUS traffic, change an account region, or certify every
Armoury Crate/account workflow. Other services belong in separate reviewed profiles, not in the
generic route-recovery policy.

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
