# Quick start

[简体中文](QUICKSTART.zh-CN.md) · [Home](README.md)

This is the shortest executable path through Home Edge Bootstrap. The current implemented reference
adapter targets an ASUS gateway running official Asuswrt-Merlin with ShellCrash/ShellClash and a
Mihomo-compatible runtime. That does not assign it a verified maturity stage.

Help and operator preflight normally take seconds to a few minutes. Firmware installation, runtime
preparation, deployment, and recovery vary by device, network, and offline-transfer needs; there is
no fixed completion-time promise. The full local verification suite is optional for a first read-only
probe and may take several minutes or substantially longer.

## 1. Clone and inspect locally

```powershell
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Help
```

```sh
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
sh scripts/tui.sh --help
```

Expected help starts with a `usage:` line. Help is local-only and does not contact a router.

On macOS and Linux, local verification requires Python 3. The `python3` command is accepted; `python` is accepted only when it points to Python 3. Python 2 is unsupported.

Run the short operator preflight:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\doctor.ps1
```

```sh
sh scripts/doctor.sh
```

For a healthy host-only run, the expected terminal marker is
`doctor_state=local_ready_router_not_checked`. After supplying a router, use the reported doctor
state and next action; host readiness is not router verification. Fix a reported required tool
before touching the router. For an optional deep, offline,
fixture-based checkout check, run `scripts\verify-local.ps1` or `sh scripts/verify-local.sh`.
Success ends with `local_verification_state=ready`; a failure names the first gate to inspect. These
fixtures are not field certification for a router, firmware build, provider, or network.

## 2. Prepare the router and recovery boundary

Before declaring a target:

- Read [Compatibility](docs/COMPATIBILITY.md) and the [router baseline](docs/ROUTER_BASELINE.md).
- Keep an independent soft-router or endpoint fallback and the vendor recovery route.
- Finish the router's first login, enable LAN SSH and JFFS custom scripts/configs, and keep management on the intended LAN.
- Never place a subscription URL in command history, an issue, or a support archive; it is a credential.
- If the runtime is absent, obtain a separately verified offline release artifact instead of making an unverified proxy path a prerequisite for its own installation.

Verify the exact model and hardware revision against the
[official Asuswrt-Merlin supported-model list](https://www.asuswrt-merlin.net/about), confirm a
current build on the [official download page](https://www.asuswrt-merlin.net/download), and use the
[ASUS Download Center](https://www.asus.com/global/support/download-center/) for model-specific
manuals, stock firmware, and recovery tools. ASUS availability alone does not prove current Merlin
support. Follow the [official installation guide](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation).
This project does not download or flash router firmware.

If the official site is unreachable before the proxy works, use the official
[SourceForge release area](https://sourceforge.net/projects/asuswrt-merlin/files/) or another official
endpoint currently listed by the download page. A third-party community or support site may be
country- or region-specific and may distribute modified firmware; do not assume it is official or
available elsewhere. If no trusted source is reachable, obtain and verify the archive on another
trusted network and transfer it offline, or stop.

## 3. Set the actual target and verify SSH identity

Replace the entire target with the router's configured SSH account and actual LAN IP. The placeholder
below is neither an account created by this project nor an IP-discovery mechanism:

```powershell
$Router = "<router-admin-user>@192.168.50.1"
```

```sh
router="<router-admin-user>@192.168.50.1"
```

Each variable exists only in the current shell. Reset `$Router` or `router` after opening a new
PowerShell, Terminal, or SSH window.

Before the first probe, obtain the router's SSH host-key fingerprint through an independent trusted
channel, such as a local console, firmware-provided display, or trusted operator record. Interfaces
vary; stop if no trustworthy fingerprint is available. `ssh-keyscan -t ed25519 192.168.50.1` may
collect the network-presented key for comparison, but by itself it does not verify identity. Stop on
a mismatch. Never delete the saved key or disable host-key checking merely to continue.

## 4. Start a resumable, read-first session

The numbered `tui` is a menu and orientation entry; `run-bootstrap` is the resumable execution loop.
Either may start the workflow, but never run two write-capable sessions against the same router.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-bootstrap.ps1 -Router $Router -NoPause
```

```sh
sh scripts/run-bootstrap.sh --no-pause "$router"
```

The loop stores `state.env`, logs, and a dedicated `known_hosts` record below
`logs/bootstrap/<router-id>/`. Keep this target session until closeout. Expected terminal or pause
markers are:

- `bootstrap_state=waiting_prerequisite`: fix the named host/router prerequisite, then rerun the same command.
- `bootstrap_state=waiting_manual`: read both `next_action_code` and `next_action_command`, complete
  the named manual action, then rerun the same bootstrap command.
- `bootstrap_state=pass`: final installation closeout passed.
- `bootstrap_state=accepted_boundary`: reviewed manual exceptions remain; this is weaker than a full pass.

The loop prints both next-action fields when operator work is needed. It begins with read-only capability probes and prepares
`--dry-run` behavior before write-capable actions.

## 5. Review every write and retain rollback

Review the exact target, managed paths, capability mismatches, accepted boundaries, backup, and
rollback command. A deployment write requires the exact `APPLY` confirmation. Live self-heal
requires `ENABLE`; a prompted rollback requires `ROLLBACK`. EOF, interruption, invalid input, or any
other response cancels the action.

The current project kit is `/jffs/home-edge-bootstrap`; when an older kit exists, deployment keeps it
at `/jffs/home-edge-bootstrap.prev` and reports `rollback_available=0|1` plus the exact rollback
command. Runtime-configuration backups are separate and default to
`/jffs/home-edge-bootstrap-state/backups/runtime`. Do not enable self-heal while apply health is failing.

### Project decommission is a separate lifecycle operation

Run the plan first, then apply only after reviewing the exact remove/retain sets:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\decommission-merlin.ps1 -Router $Router -NoPause
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\decommission-merlin.ps1 -Router $Router -Apply -Confirmation DECOMMISSION -NoPause
```

```sh
sh scripts/decommission-merlin.sh "$router"
sh scripts/decommission-merlin.sh "$router" --apply --confirm DECOMMISSION
```

Decommission removes project helpers, exact project registration, validated kit variants, and the
default regenerable cache. It preserves `/jffs/home-edge-bootstrap-state`, operator subscription and
policy files, recovery backups, Asuswrt-Merlin firmware, and the external ShellCrash/Mihomo runtime.
Rollback restores a prior project kit; decommission retires project control surfaces; runtime
uninstall follows the runtime maintainer; firmware recovery follows the
[ASUS Download Center](https://www.asus.com/global/support/download-center/) and
[official Asuswrt-Merlin guidance](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation).
This project does not substitute a generic firmware flashing tutorial.

## 6. Run the final gate

From a client that uses the router:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-client-topology.ps1 -Router $Router
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-installation-closeout.ps1 -Router $Router -RunClientCheck
```

```sh
sh scripts/check-client-topology.sh "$router"
sh scripts/check-installation-closeout.sh "$router" --run-client-check
```

A pure router-primary pass reports `client_topology_mode=router_primary` and
`installation_closeout_state=pass`. A local proxy/TUN can produce `client_runtime_present`; accept it
only when fallback or hybrid mode is deliberate.

## 7. Export support evidence only when needed

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\export-support-bundle.ps1 -Router $Router
```

```sh
sh scripts/export-support-bundle.sh "$router"
```

Success reports `support_bundle_state=ready` and `support_bundle_archive=<path>`. The default archive
root is `C:\tmp\home-edge-support-bundles` on Windows and `/tmp/home-edge-support-bundles` on
macOS/Linux. The bundle is redacted, but you must review every file before attaching it.

## Glossary

- **Target**: the router account and address being inspected or changed.
- **Capability**: an observed ability needed by a step, such as SSH, JFFS, or a runtime endpoint.
- **Managed path**: a path the framework is allowed to create, replace, back up, or remove.
- **Target session**: resumable state and evidence under `logs/bootstrap/<router-id>/`.
- **Support classification**: the declared evidence level for a target; it does not certify every device.
- **Accepted boundary**: an explicit reviewed manual exception; it is not a strong pass.

## Quick troubleshooting

| Symptom | First action |
|---|---|
| Missing Python 3 or another local tool | Install the named tool and rerun `doctor` |
| SSH unreachable or authentication failed | Check the actual LAN IP, configured SSH account, LAN SSH setting, and reachability |
| Host fingerprint unavailable or mismatched | Stop and verify through an independent trusted channel; do not bypass checking |
| JFFS missing | Enable custom scripts/configs, reboot if firmware requires it, and rerun the same session |
| Runtime unhealthy after apply | Do not enable self-heal; use the reported rollback and inspect the session log |
| Self-heal registration incomplete | Run status first, then repair only project-owned lifecycle entries |

Return to the [full README](README.md) for detailed diagnosis, architecture, adapter maturity,
no-wall recovery, and contribution guidance.
