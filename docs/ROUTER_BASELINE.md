# Router Baseline And State Machine

English source of truth. See `docs/zh-CN/ROUTER_BASELINE.md` for the Chinese reading mapping.

The router baseline is not a blind "apply everything" profile. It is a state-guided loop:

```text
read-only audit
-> detect current state
-> identify the smallest required human action
-> rerun read-only audit
-> generate or apply only allowlisted automation
-> verify
-> repeat until the route is usable and observable
```

## State Model

| State Area | Values | Meaning |
|---|---|---|
| `device_state` | `unreachable`, `lan_reachable`, `web_initialized`, `ssh_reachable` | How far the local computer can reach the router |
| `firmware_state` | `official_merlin`, `merlin_compatible_modified`, `stock_asuswrt`, `unsupported`, `unknown` | What firmware family the audit can infer |
| `admin_state` | `web_only`, `ssh_reachable`, `jffs_scripts_ready` | Whether router-side automation can safely run |
| `baseline_state` | `risky`, `needs_review`, `reviewed`, `reviewed_with_monitoring` | Whether router security and compatibility settings need attention |
| `core_baseline_state` | `match`, `drift`, `unrecorded`, `invalid`, `unavailable` | Whether the observed core and evidence agree with the site-accepted core record; independent of security posture |
| `proxy_state` | `absent`, `policy_deployed`, `api_reachable`, `self_heal_installed`, `verified` | How far the proxy path has progressed |
| `subscription_state` | `missing`, `credential_stored`, `cache_ready`, `runtime_imported` | Whether provider switching can be driven by this project; `runtime_imported` means the current runtime may be healthy but the subscription credential/cache is outside project management |
| `automation_state` | `audit_only`, `dry_run_ready`, `apply_ready`, `live_managed` | What the project is allowed to do next |

The scripts must treat old state as stale after any manual action. If the user changes a router
setting in the web UI, rerun the audit before making the next decision.

## Baseline Recommendations

Recommended defaults:

- Before choosing or flashing a router, verify the exact model and hardware revision against the
  [official Asuswrt-Merlin supported-model list](https://www.asuswrt-merlin.net/about), then confirm
  that a current build exists on the [official download page](https://www.asuswrt-merlin.net/download).
  Use the [ASUS Download Center](https://www.asus.com/global/support/download-center/) for the
  model-specific ASUS manual, stock firmware, and recovery tools. ASUS availability alone does not
  establish current Asuswrt-Merlin support. Follow the
  [official installation guide](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation) rather
  than a repository-local flashing tutorial. If the project website is unreachable, use the official
  [SourceForge release area](https://sourceforge.net/projects/asuswrt-merlin/files/) linked by the
  download page. A third-party support site may serve only one country or region; do not assume that
  a corresponding site exists elsewhere or that it is an official source.
- On the current ASUS manual-update page, selecting a firmware file can immediately begin the upload
  and reboot without a separate apply button. Treat file selection as the write boundary: export the
  router settings and JFFS backup first, verify the exact model and published digest, keep LAN access,
  and expect a temporary outage before choosing the file.
- Keep JFFS custom scripts/configs enabled after SSH is available.
- Keep router administration LAN-side; do not expose the web UI to WAN.
- Disable WPS.
- Disable PPTP server unless a specific legacy client still requires it.
- Keep WAN ping response disabled unless there is a temporary diagnostic reason.
- Keep WireGuard instead of PPTP for VPN server use when VPN access is needed.
- Keep IPv6 disabled for the simple proxy/leak-control profile unless IPv6 firewall, DNS, and proxy
  behavior have been reviewed.

Review rather than blindly change:

- UPnP can stay enabled when gaming, communication apps, downloaders, or household devices need it.
  Treat it as a monitored compatibility setting and inspect active mappings.
- QoS can stay enabled when it improves household traffic. Retest if throughput or acceleration
  becomes a problem.
- Wi-Fi channel width and channel selection depend on the model, radio generation, region, nearby
  networks, and client devices. Do not force one universal channel plan.
- WPA3 transition mode is optional. Use it only when all important clients behave well.
- AiProtection, DNSSEC, DNS-over-TLS, and IPv6 are policy choices with compatibility and privacy
  trade-offs; do not silently enable them.

Human-only or explicit-confirmation items:

- Firmware flashing and downgrade.
- First admin password and account setup.
- WAN mode, PPPoE, VLAN/IPTV, static IP, and ISP-specific settings.
- Wi-Fi SSID, password, regulatory region, and transmit power.
- VPN peer keys, port-forwarding rules, DDNS, and remote-access exposure.
- Provider subscription URL and subscription converter trust.

## Read-Only Audit

For the guided loop, use:

Windows PowerShell:

```powershell
.\scripts\guide-router.ps1 -Router <user>@<router-lan-ip> -NoPause
```

macOS/Linux shell:

```sh
sh scripts/guide-router.sh <user>@<router-lan-ip>
```

The guide runs the audit, summarizes the state, prints `next_action_code`, and prints the next safe
command. Use JSON output when another tool needs to consume the state machine:

```powershell
.\scripts\guide-router.ps1 -Router <user>@<router-lan-ip> -Json
```

```sh
sh scripts/guide-router.sh --json <user>@<router-lan-ip>
```

Windows PowerShell:

```powershell
.\scripts\audit-router-baseline.ps1 -Router <user>@<router-lan-ip> -NoPause
```

macOS/Linux shell:

```sh
sh scripts/audit-router-baseline.sh <user>@<router-lan-ip>
```

The audit is read-only. It does not print Wi-Fi passwords, SSH authorized keys, provider
subscription URLs, or VPN private keys. It reports:

- detected router and firmware state;
- SSH and JFFS readiness;
- WPS, PPTP, UPnP, WAN ping, IPv6, WireGuard, and QoS posture;
- relevant listening ports;
- active UPnP mappings;
- proxy deployment, Mihomo API, cron, and recent self-heal state;
- the active executable version and agreement with the site-accepted core/evidence record;
- the next safe action.

## Site-Accepted Core Record

A locally authorized core replacement needs its own acceptance record. The audit does not compare
ShellCrash `core_v` with the repository release manifest; an accepted site version does not rewrite
the historical v0.1.4 release baseline (`v1.19.28`). `core_baseline_state` changes neither
`baseline_state` nor the risk counters, and never triggers a replacement or downgrade.

Both host wrappers embed `scripts/audit-core-baseline.sh` into the existing SSH payload. No new
router helper deployment is required. `mihomo_version` is read from the active `/proc/PID/exe -v`,
not from the word `authenticated`; controller authentication remains a separate observation.
The audit hashes that executable, native `/jffs/ShellCrash/CrashCore.gz`, protected
`/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz`, and the original router receipt.
It also compares the executable version with ShellCrash `core_v` and the accepted version.
PID start time is checked around executable observation; an incomplete observation stays unknown.

The authorized site owner creates this private record only after checking the original update
receipt and acceptance evidence:

```text
/jffs/home-edge-bootstrap-state/runtime-core-baseline.env
```

Schema version 1 has exactly these six unquoted fields (replace the digest placeholders):

```text
schema_version=1
core_version=v1.19.32
core_raw_sha256=<64 lowercase hexadecimal characters>
core_gzip_sha256=<64 lowercase hexadecimal characters>
receipt_path=/jffs/.home-core-update-YYYYMMDD/result.env
receipt_sha256=<64 lowercase hexadecimal characters>
```

`core_raw_sha256` binds the uncompressed binary. `core_gzip_sha256` binds the exact archive bytes
expected at both native and protected paths. `receipt_sha256` binds the original receipt bytes,
without newline normalization or rewriting. The receipt must have exactly one each of
`version=<accepted version>`, `selectors_unchanged=yes`, and `route_verified=yes`. The same directory's
`status` file must contain exactly one line, `verified`. Historical receipts with a unique
`status=verified` field are also supported when the separate file is absent; conflicting status
sources are rejected. The six-field site schema does not change. Other receipt fields remain data
covered by its full-file digest. This records prior acceptance;
it does not re-prove the current route, upstream provenance, or power-loss durability.

The parser never sources either file. Duplicate/unknown record fields, unsafe paths, unsupported
schema values, and symbolic links in the record/receipt/status path are rejected. Blank lines and comments
are allowed in the record; hash values remain strict. A local downloaded gzip archive does not prove
that a host-side `result.env` exists; this audit reads the named original router receipt only.

| State | Meaning |
|---|---|
| `match` | Runtime version/raw digest, normalized `core_v`, both archive digests, and the verified receipt agree with the accepted record |
| `drift` | An observed version, metadata value, artifact digest, or receipt digest differs from that record |
| `unrecorded` | No site record exists; no release-manifest comparison or downgrade is inferred |
| `invalid` | The record/path/schema, acceptance status, or receipt acceptance fields are invalid |
| `unavailable` | A required runtime, metadata, hashing capability, archive, or receipt observation cannot be obtained |

The output includes `core_baseline_reason`, `core_baseline_expected_version`, `core_baseline_status_source`,
`shellcrash_core_version`, and observed raw/native/protected/receipt SHA-256 fields. It does not print
receipt contents, subscription nodes, or keys. Version comparison normalizes an optional leading
`v`; quoted native `core_v` values are accepted. A mismatch is a request to reconcile evidence,
not permission to overwrite the current core or edit an original receipt.
Hash-tool discovery uses `which`, including on BusyBox shells without a `command` builtin.

Offline fixtures use `HOME_EDGE_CORE_AUDIT_ROOT` to remap router paths and
`HOME_EDGE_CORE_PROC_ROOT` for a synthetic process tree. Additional trusted test overrides are
`HOME_EDGE_CORE_BASELINE_FILE`, `HOME_EDGE_CORE_NATIVE_GZIP`, `HOME_EDGE_CORE_PROTECTED_GZIP`, and
`HOME_EDGE_CORE_SHELLCRASH_CONFIG`; production defaults above remain unchanged. Run:

```sh
sh scripts/test-core-baseline-fixtures.sh
```

## Automation Boundary

Automation may proceed when the current state proves that the next step is safe and reversible.

Safe to automate after SSH/JFFS:

- deploy repository-owned scripts and policy files;
- install or update self-heal cron;
- run DRY-RUN self-heal;
- verify Mihomo API and the configured reachability probe;
- cache and validate provider subscriptions when the URL is already present on the router;
- apply explicitly allowlisted low-risk settings after a backup.

Do not automate without explicit confirmation:

- firmware flashing;
- WAN and ISP settings;
- Wi-Fi identity and credentials;
- router admin credentials;
- VPN keys and peer exposure;
- disabling UPnP when household compatibility is unknown;
- replacing an existing ShellCrash runtime.

## Target End State

```text
router_initialized=yes
ssh_ready=yes
jffs_ready=yes
baseline_reviewed=yes
provider_subscription_present=yes
mihomo_api_reachable=yes
main_selector_verified=yes
self_heal_installed=yes
self_heal_live_after_dry_run=yes
rollback_available=yes
```

If any manual intervention happens, start the loop again with a read-only audit.
