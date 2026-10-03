# Subscription Automation

English source of truth. See `docs/zh-CN/SUBSCRIPTION_AUTOMATION.md` for the Chinese reading mapping.

## Purpose

Changing proxy providers should be routine: replace the subscription credential, normalize it into a
Mihomo-compatible profile, validate the result, cache it, and apply it only when explicitly allowed.
The process is automatable because most providers eventually describe the same proxy primitives:
Shadowsocks, VMess, VLESS, Trojan, Hysteria2, TUIC, or Clash/Mihomo YAML.

The non-automatable boundary is trust. A subscription URL is a credential. A converter service that
receives it can see that credential. This project therefore defaults to direct download, or to a
converter reachable on localhost or a private LAN. Public converters require an explicit
`SUBSCRIPTION_ALLOW_REMOTE_CONVERTER=1` decision.

## Supported Flow

```text
provider subscription URL
-> optional local/private converter
-> Mihomo/Clash YAML validation
-> cache file
-> optional live config path
-> self-heal verifies the configured reachability probe
```

The legacy cache/full-profile flow remains operator-invoked. An opt-in node-only updater now
shares periodic, demand and manual triggers without importing provider policies.

`/jffs/scripts/home-edge-update-sub.sh` implements the flow on the router. Host-side helpers wrap the
safe common cases:

- `scripts/store-subscription.ps1` / `.sh`: prompt for the provider URL and write it to the router
  without printing the URL.
- `scripts/refresh-subscription.ps1` / `.sh`: run a DRY-RUN refresh by default; update cache only
  when explicitly applied; optionally overwrite a known live profile path and run a tested reload
  command.

## Configuration

Put the provider URL in:

```text
/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local
```

Redeploying the project preserves `SUBSCRIPTION.local`, `cache/`, `backups/`, and local policy
overrides from the previous router-side install directory. Updating project scripts should not
require pasting the subscription URL again.

Use direct mode when the provider already returns Mihomo/Clash YAML:

Windows PowerShell:

```powershell
.\scripts\refresh-subscription.ps1 -Router $Router
.\scripts\refresh-subscription.ps1 -Router $Router -Apply
```

macOS/Linux shell:

```sh
sh scripts/refresh-subscription.sh "$router"
APPLY=1 sh scripts/refresh-subscription.sh "$router"
```

Use converter mode when the provider returns a raw/base64 subscription that Mihomo cannot import
directly:

Windows PowerShell:

```powershell
.\scripts\refresh-subscription.ps1 -Router $Router -ConverterBaseUrl "http://192.168.50.2:25500/sub" -ConverterTarget clash
```

macOS/Linux shell:

```sh
SUBSCRIPTION_CONVERTER_BASE_URL=http://192.168.50.2:25500/sub \
SUBSCRIPTION_CONVERTER_TARGET=clash \
sh scripts/refresh-subscription.sh "$router"
```

Successful DRY-RUN prints `subscription_dry_run=ok`. Apply mode prints
`subscription_cache=updated` and either `subscription_apply=cache_only` or the configured live apply
path. These messages never include the subscription URL.

`subscription_state=cache_ready` proves that the project holds a validated cache; it does not prove
that the active runtime consumes those bytes. Strong closeout requires
`subscription_consumption_state=runtime_profile_matches_cache`, backed by successful reload,
matching cache digest, a runtime-observed active config path and process identity, an attestation
within `SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC` (default `300`) that does not predate that
process, and fresh controller/route evidence.
File equality alone is
`profile_file_matches_cache`. A supported cache-only or manual
ShellCrash import remains an explicit acceptance boundary.

Runtime evidence is accepted only under project-owned `/tmp/home-edge-*` or
`/jffs/home-edge-bootstrap/` paths. Every existing path component and the target must be
symlink-free; rejection happens before subscription fetch, cache, or live-profile mutation.

If you know the live Mihomo/ShellCrash profile path, pass it explicitly. Keep this unset when you
prefer ShellCrash menu import or when the runtime's live path is uncertain:

Windows PowerShell:

```powershell
.\scripts\refresh-subscription.ps1 -Router $Router -Apply -ApplyPath "/path/to/live/config.yaml"
.\scripts\refresh-subscription.ps1 -Router $Router -Apply -ApplyPath "/path/to/live/config.yaml" -ReloadCommand "sh /path/to/reload.sh"
```

macOS/Linux shell:

```sh
APPLY=1 SUBSCRIPTION_APPLY_PATH=/path/to/live/config.yaml sh scripts/refresh-subscription.sh "$router"
APPLY=1 SUBSCRIPTION_APPLY_PATH=/path/to/live/config.yaml SUBSCRIPTION_RELOAD_CMD='sh /path/to/reload.sh' sh scripts/refresh-subscription.sh "$router"
```

Optional knobs:

| Variable | Default | Meaning |
|---|---:|---|
| `SUBSCRIPTION_CONVERTER_BASE_URL` | empty | Converter endpoint such as a self-hosted subconverter `/sub` endpoint |
| `SUBSCRIPTION_CONVERTER_TARGET` | `clash` | Converter target profile format |
| `SUBSCRIPTION_CONVERTER_CONFIG_URL` | empty | Optional remote conversion rules/config URL |
| `SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC` | `300` | Maximum age of a process-bound successful-reload attestation |
| `SUBSCRIPTION_ALLOW_REMOTE_CONVERTER` | `0` | Required before sending the subscription URL to a public converter |
| `SUBSCRIPTION_APPLY_PATH` | empty | Live config path to overwrite after backup; empty means cache only |
| `SUBSCRIPTION_RELOAD_CMD` | empty | Optional local reload command after live overwrite; reload failure triggers best-effort live restore |
| `SUBSCRIPTION_DRY_RUN` | `1` | Download and validate without changing cache/live config |
| `SUBSCRIPTION_FETCH_PROXY` | empty | Optional proxy URL for downloading the subscription, for example a local Mihomo mixed port |
| `SUBSCRIPTION_MIN_BYTES` | `64` | Reject obviously broken responses |

## Safety Gates

- The subscription file must exist and contain a URL.
- Converter mode is blocked for public endpoints unless explicitly allowed.
- The downloaded result must be non-empty and large enough.
- HTML/error pages are rejected.
- Raw/base64 provider feeds are rejected with a converter-specific message.
- The result must look like a Mihomo/Clash YAML profile.
- Existing cache/live files are backed up before replacement.
- Live overwrite stages the new profile first, then moves it into place.
- If a configured reload command fails after live overwrite, the previous live profile is restored
  when a backup exists.
- If any step fails, the previous cache/live config remains in place.

## Research Notes

- Mihomo supports Clash-compatible configuration and proxy-provider style inputs; this is the target
  runtime format for this project.
- `subconverter` is the common conversion layer for raw provider subscriptions to Clash-family
  profiles. It is suitable as a local or private-network dependency when a provider does not return
  Mihomo-compatible YAML.
- Sub-Store can manage multiple subscriptions and transformations, but it is a heavier management
  surface. It is optional; this project only needs a converter endpoint unless provider aggregation
  becomes a real requirement.

## Current Boundary

Provider switching is now automatable after the human supplies a trusted subscription URL and, when
needed, a trusted converter endpoint. Account purchase, CAPTCHA/login, payment, and the decision to
trust a converter remain manual. Runtime restart, subscription import/trust, dashboard installation,
firewall/DNS changes, soft-router changes, and endpoint mutation are not implied by cache refresh.


## Guarded node-only automation

`subscription-auto.sh` is the single entrypoint (`--tick`, `--refresh`, `--status`,
`--check`, `--reconcile`, `--boot`). Site activation requires an existing HTTPS subscription,
a private controller secret, an installed parser runtime, and explicit filters for
node subsets. It currently targets an inline-node ShellCrash/Mihomo profile; provider-based
profiles should use the core's native provider updater. Raw/base64 sources retain the
operator-controlled converter flow and are not sent to a public service by this updater.
Explicit host converter/fetch-proxy/apply-path/reload overrides keep using that legacy
manual flow; they are never silently discarded by automation dispatch.

The parser is built from `tools/yamlbridge` with the maintained stable YAML v3 library
pinned in go.mod/go.sum. Run `sh scripts/build-subscription-parser.sh OUTPUT`, transfer the
ARM64 gzip to the stable runtime directory as `yamlbridge.gz`, and store the SHA256 of
the uncompressed binary in `yamlbridge.sha256`. The router needs no Go installation.
The verified executable is recreated in RAM after reboot.

Configure the site-local stable policy (credentials never belong in this file):

```sh
SUBSCRIPTION_AUTO_ENABLED=1
SUBSCRIPTION_AUTO_INTERVAL_SEC=86400
SUBSCRIPTION_AUTO_COOLDOWN_SEC=3600
SUBSCRIPTION_AUTO_FAILURE_CHECKS=3
SUBSCRIPTION_AUTO_HEALTH_PERCENT=50
SUBSCRIPTION_AUTO_PROXY_FALLBACK=1
```

`subscription-groups.json` maps existing group names to node-name regular expressions;
these are data, never shell commands. Entire-node-list groups need no filter. Fixed
members and existing manual selections cannot disappear silently: conflicting candidates
are refused. Group definitions, service rules, DNS, controller access, listener settings
and dashboard preferences remain owned by the local profile.

One project-owned cron checks every five minutes. Periodic refresh defaults to once per
day and respects `profile-update-interval`. Demand refresh needs three consecutive
observations of zero healthy nodes or a drop below half the prior health reference,
an available uplink, and the cooldown/backoff gates. Failures back off up to a day.
An unchanged normalized node/membership graph updates the observation/cache only;
it does not reload the core. Browser UI defaults are latency ascending, unavailable
nodes hidden, and auto-close old connections off. Existing stored choices win.
The local `/ui/` entry also selects the controller at the page's own origin. First
use asks only for the panel access key; a validated saved connection opens directly
on subsequent visits, without Add or an IP picker. Authentication stays enabled;
the server does not embed its key in a public asset or URL. Credentials remain in
that browser's existing Yacd storage. Incorrect keys can be re-entered, while a
temporary network failure offers retry without discarding the saved key. Explicit
upstream `hostname`/`port`/`secret` links keep their original behavior. Display
preferences and other stored backend records are retained. Use the same URL in a
browser that preserves site storage. The built-in unconfigured `127.0.0.1:9090`
record is removed only when it has an empty key and `addedAt: 0`; configured loopback
records and other backends stay intact. Private sessions, cleared data, and different
IP/domain/protocol origins cannot share a remembered connection.
Controller and mixed proxy ports are read from the active local profile. Subscription
transport failures can retry through that local mixed proxy; certificate verification stays
enabled. HTTP rejection, invalid data and certificate verification failure do not trigger this
fallback. Set `SUBSCRIPTION_AUTO_PROXY_FALLBACK=0` to disable it.

A changed candidate is checked by the live core and an isolated loopback-only core,
with listeners, TUN, iptables, NTP and unrelated download tasks disabled. Publication
checks original profile bytes, source/policy inputs and selector state again. The
runtime uses synchronous PUT /configs acknowledgement without force or connection
DELETE calls. It requires native `profile.store-selected` persistence (not explicitly false),
retains local policies, and saves the latest valid selections without replaying old selection PUTs.
A real route probe is required before acceptance. An independent 120-second guard
restores the original profiles after failure or a stalled parent. Rollback refuses
newer selections that are absent from an original group's membership. Reboot
recovery restores unaccepted persistent profiles before the project starter, then
reconciles the cron. This is a bounded recovery mechanism, not a tested claim of
power-loss durability or seamless migration of existing TCP sessions. Native selection
updates and config reloads do not share an atomic API lock; a manual click overlapping
the core's reload can still race inside Mihomo. The updater adds no stale snapshot PUTs.
RAM-only recovery mutexes and allocation-specific writer leases prevent an orphan
persistent mutex or an expired parent from deleting a successor's lock. Failed recovery
gates the project starter while allowing unrelated user startup hooks to continue.
`--check` validates a changed candidate and probes it without publishing it or updating
the persistent refresh status.

Status is in the stable state's `subscription-auto/status.json`; transaction backups
are capped at three after accepted updates. This node-only evidence is distinct from
the legacy raw-cache-equals-live-profile predicate: provider policy is deliberately
not copied. Public release/support conclusions in older evidence remain historical.

Disable this component with `SUBSCRIPTION_AUTO_ENABLED=0` and `--reconcile`.
The project decommission path removes its own cron/helpers. Private credentials and
needed recovery data follow the existing preservation policy.

After deployment and source binding, activate with `APPLY=1 sh scripts/enable-subscription-auto.sh "$router" SITE_FILTERS.json`. This validates the site-built ARM64 executable and filter mapping before enabling the single registration. The default invocation only shows the plan.

Activation also closes the legacy-cache handoff: it requests
`HOME_EDGE_STATE_RETIRE_SUBSCRIPTION_CACHE=1` from the existing state migrator before enabling
the scheduler. Only an old kit `cache/subscription.yaml` proven byte-identical to the adopted
stable cache is moved into private `backups/subscription/legacy-cache-*/subscription.yaml`.
Later auto refreshes can change the stable cache without a preserved old active source blocking
the next deployment. Divergent copies still stop migration and require reconciliation;
the original bytes remain available as recovery data. Existing installations already carrying
divergent pre-activation copies need one evidence-backed local reconciliation, not repeated
manual cache replacement.
