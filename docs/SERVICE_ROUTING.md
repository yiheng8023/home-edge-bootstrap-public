# Service routing and login recovery

[简体中文](zh-CN/SERVICE_ROUTING.md) · [Home](../README.md)

A stored login credential does not prove that its authentication or refresh request can reach the service. If changing a proxy restores access, investigate routing and service responses before clearing credentials. A generic latency test or a provider `[AI]` node label is only a signal; neither guarantees login, streaming or future availability.

Inspect the current policy group and its selected route in the dashboard. Preserve a working manual choice. Check login, chat, static assets and file domains together: different service groups can select different exits. The existing `HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX` and `HEAL_ROLE_ROUTE_TARGET_REGEX` controls choose existing group candidates; they do not rewrite membership or enable the separate semantic service-health path described below.

## Observe through an existing standard proxy

The current host-native `yamlbridge` also has a product-neutral protocol observation adapter. It
uses an existing HTTP/S proxy on an explicit loopback/private IP, without a controller, named node,
core executable, runtime config or router installation. Save a request such as:

```json
{"adapter":"http-proxy-observe","profile":"gemini","proxy_url":"http://127.0.0.1:7890","timeout_sec":15}
```

Run `yamlbridge service-probe request.json report-new.json` (PowerShell:
`.\yamlbridge.exe service-probe request.json report-new.json`) with a current binary built for that
host OS. The report must be a new file. Profiles are `gemini`, `openai` and `anthropic`; the endpoint
must be a literal local/private IP with an explicit port, without URL credentials, query or a custom
path. HTTP/S proxy transport is supported; this adapter does not add SOCKS or client control.

The result is `route_binding=proxy_endpoint_only`, `egress_bound=false`,
`verification_scope=frontend_only` and `account_verified=false`. Even an explicit region rejection
observed there cannot authorize named-node failover: the proxy's effective outbound is unproven and
the adapter has no selection/recovery API. Missing control capabilities stay observation-only;
unknown evidence stays unknown. No runtime replacement or client product is required.

Both this observer and the runtime driver call the same pure `internal/healthpolicy` decision
package. The observer supplies fixed observe mode and observation-only capabilities; its
`policy_action`/`policy_reason` expose that decision, with `egress_unbound` retaining the named-route
evidence gap. Sharing the policy grants no control capability. See the [architecture boundary](ARCHITECTURE.md#product-neutral-service-health-decisions-and-concrete-adapters).

## Current Merlin/Mihomo routing adapter

For the implemented Merlin/ShellCrash reference adapter, the following is a **router SSH terminal** command, after the project helper has been deployed. Replace the group placeholder with the exact existing group confirmed in your dashboard:

```sh
HOME_EDGE_SERVICE_PROFILE=openai \
HOME_EDGE_SERVICE_GROUP='YOUR_EXISTING_SERVICE_GROUP' \
sh /jffs/scripts/home-edge-configure-service-rules.sh
```

This plans a bounded dependency profile. Exact OpenAI/ChatGPT keyword rules participate in group discovery; conflicting dependency and keyword groups require an explicit group. The profile includes service domains such as `openai.com`, `chatgpt.com`, `oaistatic.com`, `oaiusercontent.com`, and exact shared dependency hosts, including `frontend-apps-multi-region.workos.com`.

Setting `HOME_EDGE_SERVICE_RULES_ACTION=apply` writes the persistent ShellCrash overlay and recovery state. It reports `runtime_reload_state=pending`: the running core has not thereby adopted the overlay. An ordinary Mihomo `PUT /configs {}` rereads its bound config and does not run ShellCrash's overlay synthesis. Arrange a separately validated synthesis or rule-only hot application; check the generated configuration, saved/current selections and recovery before reloading. A ShellCrash restart may interrupt traffic and later restore saved choices.

Verify the current controller `/rules`, new connection chains, and the persistent profile independently. Existing connections may keep their original route. Preserve the working node, runtime/core and unrelated configuration; do not replay an old selection snapshot over a later user choice. `status` checks persistent markers and explicitly reports `not_checked` for runtime activation. A routing correction alone does not prove the original OAuth failure's complete cause.

## Semantic service health in the current source

The current source adds an optional service-specific setup and health path for the Merlin/ShellCrash adapter. This describes implemented source behavior, not an assertion that an existing release package or router already contains or runs these helpers. The earlier `configure-service-rules` command remains a bounded overlay-only tool; the new setup below separately validates and applies its managed runtime, overlays and registration with recovery receipts.

Available profiles are listed below. The default `SERVICE_HEALTH_PROFILES=gemini` selects Google/Gemini only; other vendors' existing rules and choices are preserved. Select additional profiles explicitly, with a separately verified current seed for each rather than assuming they use the same route.

| Profile | User-facing selector | Private automatic selector |
|---|---|---|
| Gemini / selected Google endpoints | `Edge-gemini` | `Edge-gemini-Auto` |
| OpenAI / ChatGPT | `Edge-openai` | `Edge-openai-Auto` |
| Anthropic / Claude | `Edge-anthropic` | `Edge-anthropic-Auto` |

These are separate policies, so a Gemini failure does not authorize changing an OpenAI, Anthropic or unrelated selector. The Gemini profile uses exact service endpoints rather than all Google traffic; its shared `accounts.google.com` rule also affects Google sign-in. Its frontend probe does not verify the Gemini API, AI Studio or Antigravity. Existing selector values are checked and preserved during setup. Ambiguous seed discovery stops instead of assigning one common route to every vendor; a deliberate common seed override is a separate operator choice.

To install the extended parser without enabling subscription automation, use the host entry from any working directory. Current project helpers must already be deployed; missing helpers stop with instructions to deploy/refresh that layer first. The host needs SSH/SCP and Go for module verification, tests and a static Linux build for the detected arm64/amd64 router. It does not install Go or download a prebuilt helper automatically:

```sh
sh /path/to/project/scripts/enable-service-health.sh USER@ROUTER
APPLY=1 sh /path/to/project/scripts/enable-service-health.sh USER@ROUTER
```

```powershell
& 'C:\path\to\project\scripts\enable-service-health.ps1' -Router USER@ROUTER
& 'C:\path\to\project\scripts\enable-service-health.ps1' -Router USER@ROUTER -Apply
```

The first command is PLAN: private staging and native verification, without installing protected tools or configuration. Explicit APPLY installs the verified compressed parser and raw SHA256, keeps one owned previous tools generation, then configures only Google/Gemini auto mode. SSH uses strict existing-host trust by default and honors `SSH_OPTS` (PowerShell also accepts `-SshOptions`). An operator-supplied raw binary plus expected digest can replace the Go build: `SERVICE_HEALTH_PREBUILT` and `SERVICE_HEALTH_PREBUILT_SHA256`, or PowerShell `-PrebuiltBinary` and `-ExpectedSha256`. Native hash/capability checks still apply. Unknown remote outcomes retain the private stage for inspection; a failed configuration step retains its recovery receipt and tools backup rather than claiming completion.

Run the following in a **router SSH terminal only after these source helpers and the compiled bridge have been deployed**:

```sh
sh /jffs/scripts/home-edge-configure-service-health.sh --plan
```

Defaults are `SERVICE_HEALTH_GOOGLE_MODE=manual`, `SERVICE_HEALTH_OPENAI_MODE=manual`, `SERVICE_HEALTH_ANTHROPIC_MODE=manual`, and `SERVICE_HEALTH_MODE=observe`. Planning validates the candidate without applying it. To apply that reviewed manual/observe setup:

```sh
SERVICE_HEALTH_CONFIRM=APPLY \
sh /jffs/scripts/home-edge-configure-service-health.sh --apply
```

Enabling Google/Gemini automation requires **both** its outer selector's automatic mode and the health engine's write mode. Preview and apply the same explicit choices:

These mode choices alone are insufficient: the supported loaded-definition binding described below
must also remain valid, otherwise the driver observes only and makes no automatic selection.

```sh
SERVICE_HEALTH_GOOGLE_MODE=auto SERVICE_HEALTH_MODE=auto \
sh /jffs/scripts/home-edge-configure-service-health.sh --plan

SERVICE_HEALTH_GOOGLE_MODE=auto SERVICE_HEALTH_MODE=auto \
SERVICE_HEALTH_CONFIRM=APPLY \
sh /jffs/scripts/home-edge-configure-service-health.sh --apply
```

OpenAI and Anthropic are not selected in this example, so their existing routing is preserved. Their profile selection and mode variables are separate opt-ins. Selecting a concrete node in any outer `Edge-*` selector holds that service manually, even with the health engine in auto mode. Selecting its matching `Edge-*-Auto` branch allows the registered automation to act within that private group. A later user selection or membership/configuration change cancels the prepared action; an old snapshot is not replayed over it. Review the setup receipt and loaded rules independently; a plan, source update or successful file write is not deployment or service acceptance.

```sh
sh /jffs/scripts/home-edge-service-health.sh --check
sh /jffs/scripts/home-edge-service-health.sh --run
sh /jffs/scripts/home-edge-service-health.sh --status
```

`--check` observes and writes a report without switching production selectors. `--run` respects the registered observe/auto mode and each service's manual hold; it does not grant write permission itself. `--status` shows the last report, not a fresh probe. Scheduled checks reuse the existing self-heal cron lifecycle, with a default 600-second interval and no new daemon. Defaults require three consecutive eligible failures, a 1,800-second cooldown and a shared hourly write budget of two, including a reserved rollback write; at most three alternative concrete candidates are tested per service run. These limits do not guarantee two successful repairs per hour.

`SERVICE_HEALTH_PROFILES` selects one or more profiles. A selected service reuses its existing `Edge-*` route when available. Otherwise, use its own `SERVICE_HEALTH_GEMINI_SEED_GROUP`, `SERVICE_HEALTH_OPENAI_SEED_GROUP` or `SERVICE_HEALTH_ANTHROPIC_SEED_GROUP` if discovery is ambiguous. `SERVICE_HEALTH_SEED_GROUP` deliberately overrides the common seed; do not use it to accidentally move unrelated vendors to the same exit.

For later helper maintenance, `TOOLS_ONLY=1 APPLY=1 sh scripts/enable-service-health.sh USER@ROUTER` or PowerShell `-ToolsOnly -Apply` updates verified tools without provisioning/reloading service routes or changing manual selections. Remove APPLY to preview that same scope.

## Probe evidence and compatibility limits

The `mihomo-isolated` adapter is the default for legacy core/config/node probe requests. Each candidate gets an isolated, short-lived copy of the existing Linux core with a private directory and authenticated loopback listener bound to that concrete outbound. This is a Mihomo capability, not a universal proxy-control contract. Probing does not cycle production selectors, refresh subscriptions, share the production cache/controller, start TUN/DNS listeners or change firewall rules. Only supported inline nodes or existing provider-cache nodes and resolvable dialer dependencies are copied. Unknown dependencies fail closed. The preceding `http-proxy-observe` adapter does not launch a core and supplies no named-egress or automatic-control evidence.

The adapter must verify router-originated bypass before attributing a result to a candidate. The current reference check requires the existing nonzero runtime routing mark, no nftables executable, and empty accepting IPv4 `nat`/`mangle` OUTPUT chains. With source IPv6 enabled it also checks the corresponding IPv6 OUTPUT chains, then supplies the verified dual-stack prerequisite. The backend preserves source IPv6 choices; absent or inconsistent mark/IPv6 evidence returns unknown instead of disabling IPv6 or trying new firewall marks. Other interception topologies require a verified adapter.

Automatic control additionally requires the private receipt referenced by `loaded_binding_file`.
The implemented binding is limited to **Mihomo v1.19.34 inline proxy instances**: the controlled
`service-bind-reload` path performs a real, authorized reload and checks source-file/core identity,
canonical `GET /configs`, changed inline instance IDs and subsequent continuity. An instance ID is
not a parameter fingerprint. Missing bindings or source/core/config/instance drift report
`loaded_definition_unverified` or `loaded_definition_changed` and reduce the driver to
observe-only/unknown. A restart or external reload needs an explicitly controlled rebind; the tool
does not reconstruct authority from names, unchanged file bytes or an old receipt. Do not fabricate
a binding file to bypass this gate. `proxy-providers` remain ineligible for this automatic binding;
`rule-providers` are allowed subject to static-target and ownership checks. The generic proxy
observer needs no such receipt because it has no automatic control. The pinned offline core may be
an older version; new helpers do not upgrade it or imply that its auto-control gate passes.

The probe performs a bounded TLS-verified GET and examines the response body. A clear Gemini country rejection can therefore be `region_denied` even with HTTP 200. A request failure before any HTTP response can be `transport_failed`; cancelled work, oversized/incomplete bodies, authentication, browser challenges, HTTP 429, generic policy errors and unrecognized pages stay unknown and do not initiate failover. Unknown breaks the consecutive failure sequence. An eligible repeated failure still requires an independently positive candidate before any switch; post-switch verification and ownership checks bound rollback/recovery, and unresolved writes retain pending state.

Reports declare `verification_scope=frontend_only`. `frontend_available` means a bounded recognized entry structure in the response; it does not prove JavaScript execution, CSS/browser rendering, account eligibility, a successful login, model generation or streaming. Matching entry/rejection markers alongside template, hidden, aria-hidden or inline visibility structures conservatively return unknown; the helper does not implement a browser or a complete CSS visibility model. `account_verified` remains false. Website changes can make the conservative classifier return unknown. Test actual signed-in use on the intended client separately. FlClash and other local clients are not modified: their proxy/TUN/DNS routes can take priority before traffic reaches the router, so router probe evidence does not establish the client's effective route.

FlClash is an example of that priority relationship, not a required product. Protocol fixtures,
pure-policy fixtures and scoped native observations establish different facts; none proves another
router kit is implemented or that every OS/client/runtime combination has passed real-client
acceptance. An observation-capable interface without a safe control adapter remains observation-only.

The default anonymous Gemini probe (`/app?hl=en`) does **not** establish detection of a signed-in account's region rejection. A failing signed-in route and a working route can both return HTTP 200 sign-in pages anonymously, leaving both unknown; switching to the root page is not a verified solution. The explicit visible Chinese rejection `Gemini 目前不支持你所在的地区。敬请期待！` is recognized if returned, but a fixture does not prove the anonymous endpoint will expose it. Hidden JavaScript capability flags or a location-only RPC do not count as frontend or account success. Covering an authentication-dependent failure requires a separately configured and authorized authenticated canary with its own credential, scope and maintenance controls; that canary is not implemented here, and these helpers do not capture browser cookies.

## Automatic management and manual choices

Subscription refresh and route self-heal have separate authority. Refresh validates node changes, preserves the selected nodes, and cancels when those choices change during preparation; it does not decide which node is best for an application. A latency result or an `[AI]` label is not an application-availability guarantee.

Self-heal keeps a healthy current route. When enabled for writes, it may fail over the explicitly managed main selector after a failed probe or an unmet explicit region constraint. Set `HEAL_GROUP` to the **exact writable selector name** to define that boundary; a missing or non-writable named group stops the run. Automatic main-group discovery excludes names containing Chinese `手动` or the English word `Manual`; explicitly naming such a group deliberately authorizes its automation. Nested switching remains off by default, and role policies have their own enable/matching controls. Those opt-ins can still authorize changes outside the automatically discovered main group. Before every switch or compensating rollback, the helper checks the current selection and membership again; a changed plan is cancelled. The controller has no established compare-and-set API, so this check does not eliminate the short read-to-write or same-value ABA race.

For the current Merlin reference adapter, site overrides live in `/jffs/home-edge-bootstrap-state/policy.local`. Keep nested switching disabled and role mutation disabled if the other groups are to remain under manual control. Local source, the registered desktop entry, deployed kit files, active helpers and loaded runtime rules are separate states: update only the differing layer and verify it. A new README or Git commit alone does not require router reinstallation; project-only refresh preserves runtime/core assets but may change managed integration/configuration. Preview that refresh and keep recovery material before applying it.
