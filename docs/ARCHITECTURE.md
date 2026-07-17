# Architecture

English source of truth. See `docs/zh-CN/ARCHITECTURE.md` for the Chinese reading mapping.

The goal is not a single-router note. This repository is a capability-driven edge-proxy lifecycle
coordinator, not an initialization-only script. It can re-enter from observed state after reboot or
drift. Keep the valuable policy in Mihomo/Clash-compatible artifacts,
and isolate firmware-specific work in thin adapters. The first implemented reference
adapter targets official Asuswrt-Merlin on supported ASUS routers; it does not pin the project to one
router model, firmware family, provider, runtime, UI template, controller port, or proxy-group naming
convention.

## Layers

| Layer | Artifact | Portability | Notes |
|---|---|---|---|
| Policy | `config/policy.env`, `config/mihomo-overlay.yaml` | High | Region-neutral by default; provider-name tolerant with optional site-local candidate and region constraints |
| Runtime scripts | `scripts/self-heal.sh`, `scripts/update-sub.sh` | High | BusyBox/POSIX shell; avoid desktop-only assumptions |
| Adapter | `adapters/merlin/` | Medium | Asuswrt-Merlin paths, cron, `/jffs`, ShellCrash conventions |
| Offline payload | `bundle/` | Medium | Kernel/plugin binaries are architecture and platform specific |
| Physical setup | none | Manual | Flashing firmware, enabling SSH, and initial credentials remain human steps |

### Merlin lifecycle ownership

| Class | Surface | Upgrade / rollback | Project decommission |
|---|---|---|---|
| Replaceable kit | `/jffs/home-edge-bootstrap` and validated project transaction variants | Replace atomically; a prior kit may be restored | Remove |
| Project helpers | Fixed `home-edge-*` helper allowlist under `/jffs/scripts` | Replace or reapply from the restored kit | Remove only the allowlist |
| Shared registration | Exact managed `services-start` block and cron name `home_edge_selfheal` | Reconcile exact project entries | Remove exact entries only |
| Operator state | Subscription and local policy under `/jffs/home-edge-bootstrap-state` | Preserve | Preserve |
| Recovery state | Subscription/runtime backups and lifecycle evidence under the stable root | Preserve; consume only through explicit recovery | Preserve and report |
| Regenerable state | Default subscription cache under the stable root | Regenerate | Remove |
| External runtime | `/jffs/ShellCrash`, Mihomo core, and runtime-owned configuration | Touch only through a separate authorized runtime operation | Do not touch |
| Firmware/unrelated state | Asuswrt-Merlin, unrelated scripts, jobs, services, and user files | Not owned | Do not touch |

The fixed delete boundary is reviewed adapter code. Provenance may corroborate ownership, but target
metadata cannot provide arbitrary paths to remove.

Runtime presence, controller authentication, dashboard configuration, dashboard reachability,
subscription credential/cache, live subscription consumption, route verification, scheduler
registration, boot-hook registration, and endpoint topology are separate evidence dimensions. No
single healthy dimension upgrades another one.

## Sensitive Egress Assurance

Sensitive Egress Assurance is a separate capability class from ordinary availability and recovery.
Its core invariant is **Sensitive Egress Identity Continuity**: a bounded sensitive-operation window
must retain the same observable path owner and effective leaf, or invalidate the window before the
operation proceeds. Reachability, low latency, a regional label, and a healthy top-level selector do
not prove that invariant.

An eventual assurance implementation must treat the identity as an evidence tuple rather than a
provider or node name. At minimum, that tuple needs the owning runtime plane, effective leaf, egress
address family and observed exit, network/ASN classification, DNS path, policy generation, and
observation time. It must use a bounded lease, suppress automatic switching inside that lease, detect
drift, and fail closed for the sensitive workflow without taking down unrelated connectivity. The
lease cannot authorize or perform an account, payment, registration, financial, or regional-
verification action.

The current self-heal path optimizes availability and bounded recovery. It is not a sensitive-egress
assurance implementation, and current route-health evidence must not be presented as one. This
release defines the problem and negative contract only; a future implementation requires separate
fixtures, privacy review, operator controls, expiry behavior, and end-to-end topology evidence.

## Adapter Contract

The following contract governs future adapter admission and the progressive isolation of the current
reference implementation. The framework should own the common control flow; an adapter owns
target-specific integration. An adapter does not inherit support merely because its target can run a
similar proxy core. Each adapter must:

- detect capabilities and report uncertainty instead of relying only on product names;
- expose read-only diagnosis and plan behavior before any apply path;
- require explicit confirmation for writes and preserve the nearest safe state on failure;
- back up managed state and provide an executable rollback path;
- expose health, provenance, and recovery evidence without leaking credentials;
- keep target-specific paths, service management, firewall, DNS, and runtime conventions inside the
  adapter boundary;
- provide a versioned, idempotent migration path that preserves divergent operator state and fails
  closed on conflicts;
- provide a plan-first decommission path with a fixed ownership boundary and retained-state report;
- provide offline fixtures, a declared compatibility surface, and a named maintenance owner.

Future device, firmware, and runtime work enters only through these capability, safety, recovery,
evidence, maintenance, migration, and decommission contracts. An unimplemented adapter is not a
supported target and must not appear as one in operator guidance.

The framework reuses mature proxy runtimes and device management interfaces. It does not require an
adapter to reimplement a proxy core, firmware dashboard, or client UI.

Automatic repair is limited to project-owned files, managed hook blocks, cron registration, caches,
and bounded selector policy. Runtime restart, dashboard installation, subscription trust/import,
firewall/DNS, soft-router configuration, and endpoint mutation remain adapter-gated or human-gated
unless a future adapter proves a safe, rollback-capable transaction.

The current Merlin implementation predates complete adapter isolation. Common files including
`config/policy.env`, `scripts/self-heal.sh`, and `scripts/update-sub.sh` still contain
Merlin/JFFS/ShellCrash defaults. Those defaults are part of the current reference surface, not
portable framework contracts, and another adapter must not inherit them implicitly. Moving them
behind adapter-supplied configuration is required before a second adapter shares the common apply
path.

The current Merlin adapter installs a marker-bounded block in `services-start`. That block invokes
the project-owned reconciler, which restores exactly one `home_edge_selfheal` cron registration and
preserves `HEAL_CRON_DRY_RUN`. It does not restart the runtime, import a subscription, install a
dashboard, or mutate firewall/DNS. Future soft-router work is a separate adapter admission effort,
not an extension of this Merlin transaction.

The Merlin lifecycle contract is canonical to `/jffs/scripts`. When an alternate JFFS root is used
for an offline fixture, `BOOTSTRAP_SCRIPT_DIR` must still equal `BOOTSTRAP_JFFS_DIR/scripts`.
Deployments that predate the reconciler are upgrade candidates and must rerun the adapter; the
registration repair helper is only for an already-deployed reconciler whose hook or cron has drifted.

## Adapter Lifecycle

Adapter maturity stage is distinct from a target support classification. Maturity describes the
repository governance and evidence of an adapter implementation; target support classifications such
as `supported`, `unknown`, and `unsupported` describe one target evaluated by that adapter. The
current Merlin implementation is the project reference implementation, but no `verified` maturity
stage is claimed under this lifecycle while its formal admission records and broader release/evidence
gates remain incomplete.

| Stage | Meaning | Repository posture |
|---|---|---|
| External integration | A related project applies or is inspired by the framework contracts | Link or document interoperability; no in-repository support claim |
| Experimental adapter | A bounded implementation exists, but evidence or ownership is incomplete | Isolated namespace, explicit experimental label, no default apply path |
| Community adapter | A maintainer, fixtures, documentation, and a declared compatibility range exist | Community-maintained support claim limited to its evidence |
| Verified adapter | The full safety, rollback, privacy, portability, and release gates pass for its declared range | Eligible for first-class guided workflow and release support |

Different licensing, maintenance, or release cadence may make an external integration safer than a
merge. Admission is based on evidence and sustainable ownership, not on popularity or architectural
similarity alone.

## Operating Rule

Before the router can proxy traffic, it cannot rely on proxy-only downloads. Anything required to
recover a working edge proxy must either be in `bundle/`, already present on the router, or reachable
directly from the local network.

GitHub may be reachable directly on some mainland China networks, but availability can be slow,
network-dependent, or temporarily interrupted. Therefore GitHub-hosted release assets are acceptable
as optional preparation sources, but they are not allowed to be required inputs for the pre-proxy
path. The local `check-no-wall-readiness` scripts verify what is already available without contacting
the network.

## Target Flow

1. Prepare the router manually only as far as required: firmware, LAN access, SSH.
2. Copy this kit to the router.
3. Run the adapter in plan mode.
4. Run the adapter in apply mode only after the plan looks right.
5. Verify the configured probe target and at least one operator-relevant external target.
6. Enable and verify the self-heal scheduler plus its reboot recovery hook after DRY-RUN evidence is
   accepted. Subscription refresh remains an explicit operator action; the current implementation
   does not schedule it.

## Runtime Discovery Model

A provider profile may expose a group chain such as:

```text
main selector -> optional regional or policy group -> reachable concrete route
```

The concrete labels are not part of the project contract. The scripts auto-discover the Mihomo
controller, infer the main selectable proxy group by role/name heuristics, and allow explicit
overrides through `HEAL_GROUP`, `HEAL_GROUP_MATCH_REGEX`, and `CLASH_API` when a profile is unusual.
