# Home Edge Bootstrap

English | [简体中文](README.zh-CN.md)

## First use: obtain the project, open the guide, keep an entry

**Choose ONE acquisition route below; downloading, cloning and installing are not consecutive requirements.** Reuse a complete project folder or a working desktop entry if you already have one. Obtaining files on your computer, opening the TUI and deploying to a router are separate steps; opening the guide does not automatically install or replace router contents.

| Your situation | Choose | Complete flow |
|---|---|---|
| First use or offline runtime preparation (recommended) | [Release offline package](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/tag/v0.1.8) | One archive for your system + `SHA256SUMS` → verify → extract all → open the entry below → choose **1** and follow the observed-state guidance |
| Runtime already present; project scripts/docs only | [Release source package](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/tag/v0.1.8) | One `-source.zip` or `-source.tar.gz` + `SHA256SUMS` → verify and extract → open the same entry; runtime payloads are not included |
| Git already available; keep a local repository | Git clone | Use the commands below to choose a known location → open the same entry in that clone; no second project download is required |
| Complete extracted folder or clone already present | Reuse that folder | Skip acquisition and continue at “Open and validate the project location” below; keep different copies separate |
| Local desktop entry already created | Reuse the desktop entry | Open `Home Edge Bootstrap` → entry revalidates its registered folder, or asks you to select and validate a replacement → choose **1** to resume |
| This computer cannot reach the download site | Transfer a complete package offline | Download and verify on a connected device → transfer archive and checksum file → verify locally, extract all and open the same entry |

**Public clones and source packages contain no ShellCrash/Mihomo offline payloads.** They can open the guide, run applicable diagnosis or manage an existing runtime. If the target lacks a runtime, choose the offline package and follow preparation guidance; obtaining project source does not install a runtime.

**There is currently no npm, pnpm or npx installation entry, and Node.js is not required.** Choose one compression format. Manifests, SBOMs and third-party complete corresponding source are audit material, not consecutive installation parts. GitHub automatic `Source code` archives are not the contracted release packages; prefer the explicitly named project assets. Package details and verification steps are in the [release notes](docs/RELEASE_NOTES.md).

### Open the same entry for your computer

Release packages, existing folders and desktop entries do not require Git. **The download column is only for the release-package route; with a clone or complete existing folder, use its startup file without downloading again.**

| Operator computer | Download | Open after extraction |
|---|---|---|
| Windows | [Starter ZIP](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.zip) | Double-click `start.cmd` |
| macOS | [Starter tar.gz](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.tar.gz) | Double-click `start.command` |
| Linux | [Starter tar.gz](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.tar.gz) | Open `start.sh`, using Run in Terminal when offered |

Use your browser's download history and Show in folder (often **Ctrl+J** on Windows), then **extract the whole package**. Keep it under Documents or another convenient location; no drive, username or directory is prescribed. Do not run inside a compressed-folder window or download just one script. Choose one package for your system; checksums and copyable verification steps are in the [release notes](docs/RELEASE_NOTES.md).

When downloads are unavailable, obtain and verify the complete package on a device with access to the release page, then transfer it offline. A clone is also valid, but is not an operator prerequisite. These systems describe the operator computer; offline runtime payloads still target the current reference device adapter, not every device architecture.

### Open and validate the project location

In the extracted folder or clone, find the level containing `PROJECT`, `README` and `scripts`, and open the entry above. It resolves its own directory, validates project identity and required launcher files, and shows the actual `project_dir`. It does not depend on terminal cwd or the presence of `.git`. This is a structural check, not a code signature or whole-repository security attestation.

If macOS requests source confirmation, verify the download source and use the system's Open flow. If execution permission was not retained, use Terminal. Linux desktop script associations vary: when Run in Terminal is unavailable, open a terminal, type `sh ` (including the space), drag `start.sh` into it and press Enter. The same fallback works on macOS; neither requires `cd` first.

The menu defaults to Chinese; type **L**, **language** or **9** in the menu to switch to English. For advanced arguments use a full path, such as `& "C:\actual-project-folder\start.cmd" -Language en` on Windows or `sh "/actual-project-folder/start.sh" --lang en` on macOS/Linux. Dragging the file into a terminal inserts its path. On Windows, typing `powershell` into the project folder's Explorer address bar also opens the terminal in that folder.

### Git clone: know the location and start the guide

Use these commands only if you chose cloning. Git must already be available; otherwise choose a release package. The examples store the project in `home-edge-bootstrap` under your current user home directory. Keep that directory, or replace the destination with your chosen full path. Git refuses an existing nonempty destination: reuse the existing project or choose a new folder instead of deleting or overwriting its contents.

Windows PowerShell:

```powershell
$GitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($GitCommand) {
  $ProjectDirectory = Join-Path $env:USERPROFILE "home-edge-bootstrap"
  & $GitCommand.Source clone --branch v0.1.8 --single-branch https://github.com/yiheng8023/home-edge-bootstrap-public.git $ProjectDirectory
  if ($? -and $LASTEXITCODE -eq 0) { & (Join-Path $ProjectDirectory "start.cmd") -Language en }
} else {
  Write-Host "Git was not found; use the release-package route above."
}
```

macOS / Linux:

```sh
project_dir="$HOME/home-edge-bootstrap"
git clone --branch v0.1.8 --single-branch https://github.com/yiheng8023/home-edge-bootstrap-public.git "$project_dir" &&
  sh "$project_dir/start.sh" --lang en
```

The destination shown here is your project location; no prior `cd` is needed. These examples select release tag `v0.1.8` rather than automatically following development changes; later updates are deliberate. An existing computer folder does not prove router installation; the guide probes that separately.

### Keep an entry for later

All three systems offer menu **8: Create or refresh a local desktop launcher**. Alternatively open `create-desktop-shortcut.cmd`, `create-desktop-shortcut.command`, or invoke `create-desktop-shortcut.sh` through `sh`.

The independent entry stores your chosen location and directory-instance identity and rechecks them at startup. A move, deletion, damaged record or replacement directory prompts for a new explicit selection followed by validation. A native folder picker is used when available, otherwise a path prompt; cancellation or EOF executes no project. Multiple clones can coexist: a directory-local entry uses its own copy, and the independent entry uses the explicitly registered copy. There is no disk-wide scan or arbitrary selection. If a Linux desktop requires Allow Launching, check the entry and follow its prompt; headless environments retain the terminal entry.

If the registered target and cached launcher files already match this copy and the desktop entry points to that registered launcher, desktop setup reports `shortcut_state=reused`. Updating another project-owned target, an incomplete registration or changed cached launcher files requires **REPLACE** then **APPLY**. Unowned storage and unrelated desktop files are not overwritable. This updates the local entry, not the router installation.

For absent Git, offline access, missing desktops/tools/permissions or uninstalled optional operations, use [conditions and recovery](docs/LAUNCHER.md). The core entry does not require ASUS or Merlin adapter files; device operations require their implementation and target capabilities. Opening the menu performs no automatic deployment, runtime update or router change; write actions retain explicit confirmation and recovery.

### Help, language and an existing installation

At the main menu, type **H**, **?**, **help**, or **6** for local help: menu actions, prerequisites, confirmations, recovery and documentation paths. Type **L**, **language**, or **9** to switch Chinese/English immediately. The switch keeps the router target and selected session, lasts for this TUI session only, and performs no network access or global setting write. **0** exits.

Choose **1** to start or resume. A fresh read-only probe of the selected router and project path distinguishes `installed`, `partial`, `not_installed` and `unknown`. Existing project content defaults to diagnosis and saved-session reuse. `installed` means recognized project-owned presence, not a healthy runtime or complete network/lifecycle acceptance. ShellCrash/Mihomo alone does not mean this project is installed. Only positively observed absence permits first installation; unknown ownership, foreign content, links or a failed/malformed probe stop deployment for review.

To refresh an owned project, deliberately choose **R**, review the target, plan and `<project-path>.prev` backup, then type **REPLACE** followed by **APPLY** exactly. An older `.prev` backup may be replaced. This uses the project-only deployment scope: it prevents runtime/core asset replacement, but can update project-managed integration and configuration. It is not a complete runtime rollback. The writer rechecks ownership under its lock before applying. Runtime replacement and core replacement remain separate opt-in actions; runtime-only replacement preserves the existing core unless `ReplaceCore` / `BOOTSTRAP_REPLACE_CORE=1` is separately selected.

The guide rechecks current project structure/directory identity and required tool availability at menu/action transitions and around important work. Known degradation stops affected actions and gives recovery guidance while **H**, **L** and **0** remain usable. These are event-driven checks, not a background daemon or detection of every unknown fault. See the launcher contract for the supported recovery paths.

Shortest path: [Quick start](QUICKSTART.md).

Release downloads: [GitHub Releases](https://github.com/yiheng8023/home-edge-bootstrap-public/releases) ·
[what to download](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/tag/v0.1.8) ·
[release contract](docs/PUBLIC_RELEASE.md).

Home Edge Bootstrap is a capability-driven bootstrap, recovery, and resilience framework for home
and small-organization network edges. It coordinates a safe path from an unprepared edge gateway to
an observable, recoverable, self-healing proxy path while keeping human decisions explicit.

The current implemented reference adapter targets ASUS routers running official Asuswrt-Merlin and
uses ShellCrash/ShellClash with a Mihomo-compatible runtime. This is the first implemented adapter,
not a permanent architecture limit and not a claim that the adapter has reached a verified maturity
stage. Windows, macOS, and Linux are supported operator-host families within their declared
capability boundaries.

The framework reuses mature proxy runtimes and their existing management interfaces. It does not reimplement a proxy core or dashboard.
Future device, firmware, and runtime families may join through
separate adapters only after their capability, safety, recovery, evidence, maintenance, migration,
and decommission contracts are defined and verified. No unimplemented adapter is listed as supported.

## Automatic management and manual choices

Subscription refresh and route self-heal have separate authority. Refresh validates node changes, preserves the selected nodes, and cancels when those choices change during preparation; it does not decide which node is best for an application. A latency result or an `[AI]` label is not an application-availability guarantee.

Self-heal keeps a healthy current route. When enabled for writes, it may fail over the explicitly managed main selector after a failed probe or an unmet explicit region constraint. Set `HEAL_GROUP` to the **exact writable selector name** to define that boundary; a missing or non-writable named group stops the run. Automatic main-group discovery excludes names containing Chinese `手动` or the English word `Manual`; explicitly naming such a group deliberately authorizes its automation. Nested switching remains off by default, and role policies have their own enable/matching controls. Those opt-ins can still authorize changes outside the automatically discovered main group. Before every switch or compensating rollback, the helper checks the current selection and membership again; a changed plan is cancelled. The controller has no established compare-and-set API, so this check does not eliminate the short read-to-write or same-value ABA race.

For the current Merlin reference adapter, site overrides live in `/jffs/home-edge-bootstrap-state/policy.local`. Keep nested switching disabled and role mutation disabled if the other groups are to remain under manual control. Local source, the registered desktop entry, deployed kit files, active helpers and loaded runtime rules are separate states: update only the differing layer and verify it. A new README or Git commit alone does not require router reinstallation; project-only refresh preserves runtime/core assets but may change managed integration/configuration. Preview that refresh and keep recovery material before applying it.


## Start here

Before choosing or flashing a router, verify the exact model and hardware revision against the
[official Asuswrt-Merlin supported-model list](https://www.asuswrt-merlin.net/about), confirm that a
current build exists on the [official download page](https://www.asuswrt-merlin.net/download), and
use the [ASUS Download Center](https://www.asus.com/global/support/download-center/) for the
model-specific manual, stock firmware, and recovery tools. ASUS availability alone does not prove
current Asuswrt-Merlin support. Review the [router baseline](docs/ROUTER_BASELINE.md) before making
settings changes, and follow the
[official installation guide](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation). This
project does not download or flash router firmware. If the project website is unreachable, use the
official [SourceForge release area](https://sourceforge.net/projects/asuswrt-merlin/files/) or another
official download endpoint currently listed by the official download page. A third-party community
or support site may exist for a particular country or region and may distribute a modified firmware
family; do not assume that a corresponding site exists elsewhere or that it is an official source.

For all operating systems, relative script examples below assume a terminal opened in the verified
`project_dir`; otherwise use each script's full path. Starting or exiting the guide does not change
the calling terminal's directory. Ordinary use continues through the menu.

Advanced command entry (optional): in File Explorer, open the extracted project folder, click the address bar, type `powershell`, and press Enter. That opens PowerShell in the correct folder. Then:

```powershell
.\start.cmd -Language en
.\start.cmd -Help
```

In an existing terminal, use the full path instead of assuming its working directory:

```powershell
& "C:\path-to-your-extracted-folder\start.cmd" -Language en
```

```sh
sh "/path/to/extracted-folder/start.sh" --lang en
```

Replace the example path with the actual extracted folder, or drag the launcher into the terminal to insert its path. Developers may still clone the repository; cloning is not the operator startup requirement.

On macOS and Linux, local verification requires Python 3. The `python3` command is accepted; `python` is accepted only when it points to Python 3. Python 2 is unsupported.

## Completion standard

A target is usable only when the evidence for that target shows all of the following:

- Required host, SSH, firmware, persistent-storage, shell, and runtime capabilities are present.
- The router baseline has no unresolved action item that the operator has not explicitly accepted.
- A dry-run plan identifies the target, managed paths, backup, and rollback route before any write.
- The runtime has consumed a validated subscription or profile without exposing its credential.
- Health checks can discover and query the runtime rather than relying on a fixed controller port.
- Self-heal remains in dry-run until its route selection and fallback behavior are understood.
- A client-side check confirms the intended topology instead of silently treating an endpoint proxy
  as router-path evidence.
- The final installation gate passes for the declared target and accepted boundaries.

Synthetic fixtures prove script behavior; they do not certify a specific router, firmware build,
provider, or network. See [Compatibility](docs/COMPATIBILITY.md) before applying changes.

## Guided TUI

The zero-dependency TUI is the normal interactive entry point. It is a numbered guide, not a
dashboard: router firmware, ShellCrash, soft routers, and endpoint proxy clients retain their own
management interfaces. The guide delegates to the existing diagnosis, bootstrap, offline-recovery,
rollback, and support-export scripts instead of duplicating their state machines.

The guided sequence is progressive:

1. Inspect local prerequisites and documentation without contacting a router.
2. Declare a target and run read-only capability probes over SSH.
3. Review a `--dry-run` deployment plan, including backup and rollback information.
4. Enter the exact `APPLY` token only after the plan is acceptable.
5. Verify runtime and client topology; enter the exact `ENABLE` token only when live self-heal is intended.
6. Use the exact `ROLLBACK` token only when a prompted rollback is intended.
7. Export a redacted support bundle only after reviewing every generated file.

EOF, interruption, invalid input, or any response other than the required confirmation token cancels
the write-capable action.

## Architecture and product boundary

The framework separates common control contracts from adapter-specific implementation:

- The common layer defines intake, capability checks, plan/apply separation, backup, rollback,
  recovery, secret handling, evidence, and closeout behavior.
- An adapter maps those contracts to a concrete device, firmware, filesystem, service manager, and
  runtime combination.
- Mature third-party runtimes continue to own traffic processing and their operational dashboards.
- A fallback remains operationally independent; success on a fallback is not evidence that the router
  path works.

| Area | Current public scope | Boundary |
| --- | --- | --- |
| Implemented reference adapter | ASUS gateway with official Asuswrt-Merlin | First implementation only; it is not a permanent product boundary or a verified maturity claim |
| Proxy runtime | ShellCrash/ShellClash with a Mihomo-compatible runtime | The project coordinates and verifies the path; it does not replace the runtime or its dashboard |
| Operator host | Windows, macOS, or Linux | Commands and available capabilities differ by host |
| Offline recovery | Source checkout plus separately verified offline release artifacts when available | A source checkout does not imply that runtime payloads are bundled |
| Fallback | An independent soft-router or endpoint fallback | It preserves recovery access but does not certify the router path |
| Automation | Automated where the action is safe, bounded, and verifiable | Firmware flashing, provider purchase, credentials, trust decisions, and final acceptance remain human responsibilities |

See [Architecture](docs/ARCHITECTURE.md), [No-wall bootstrap](docs/NO_WALL_BOOTSTRAP.md), and the
[Threat model](docs/THREAT_MODEL.md).

## Adapter and support model

Adapter maturity and target support classification are separate dimensions:

- Adapter maturity describes implementation ownership and evidence: external integration,
  experimental adapter, community-maintained adapter, or verified adapter.
- Target support classification describes one target evaluated by an adapter: `supported`,
  `supported_needs_manual`, `accepted_modified`, `unknown`, or `unsupported`.

The current Merlin implementation is the implemented reference adapter. That role does not assign it a verified maturity stage.
The public compatibility matrix currently contains policy declarations and synthetic fixture
evidence only; its field-evidence set is intentionally empty, so the listed target paths remain
`unknown` until target-specific evidence establishes another classification.

Future adapters should remain external until they have a named owner, bounded capability, safety,
recovery, evidence, maintenance, migration, and decommission contracts, synthetic fixtures,
rollback behavior, diagnostics that do not expose sensitive information, bilingual operator guidance, and an
evidence path suitable for their support claim. Maintainers decide admission and maturity changes
through review; popularity or similarity to an existing proxy solution is not sufficient evidence.

## Stable state and safe project exit

Replaceable project code lives in `/jffs/home-edge-bootstrap`; retained operator and recovery state
lives in `/jffs/home-edge-bootstrap-state`. Deployment, rollback, and project decommission preserve
the stable state. Decommission is plan-first and removes only reviewed project helpers, exact
registration, validated kit variants, and the default regenerable cache. It does not remove
subscriptions, local policy, recovery backups, Asuswrt-Merlin firmware, or the external
ShellCrash/Mihomo runtime. See [Quick start](QUICKSTART.md) for exact commands. Runtime uninstall and
firmware recovery remain separate maintainer/vendor operations.

## Source checkout and offline recovery

This repository is the project source checkout. It contains scripts, documentation, and synthetic
offline fixtures. It may configure an existing supported runtime, but it does not by itself promise
the runtime payloads needed for a fresh installation.

A separately published offline release may include checksum-bound runtime payloads, third-party
licenses, complete corresponding source, an SPDX SBOM, and a release manifest. Verify the release
checksums before extraction. Artifact availability does not broaden the declared device, firmware,
architecture, or support boundary.

For downloads, start at [GitHub Releases](https://github.com/yiheng8023/home-edge-bootstrap-public/releases).
You need one archive for your operator host plus `SHA256SUMS`, not every file shown by GitHub.
The [release notes](docs/RELEASE_NOTES.md) provide a Windows/macOS/Linux download matrix and commands
that verify only the selected asset. The [public release contract](docs/PUBLIC_RELEASE.md) explains
the source/offline split, manifest, SBOM, complete corresponding-source files, and why GitHub's
automatic **Source code** archives are not installation packages.

This distinction protects the no-wall bootstrap path: before `proxy_state=verified`, required steps
must not depend on the proxy already working. Use the local checkout, LAN management, LAN SSH, files
already present on the target, or a previously verified offline artifact. Internet downloads are
optional preparation sources, not mandatory recovery steps.

## Safety and human boundaries

- Verify the SSH host key yourself; do not disable host-key checking.
- Keep an independent management or recovery path while testing a gateway change.
- Review the dry-run target, paths, backup, and rollback command before `APPLY`.
- Enable live self-heal only after dry-run and fallback behavior are understood; the write requires
  the exact `ENABLE` token.
- A subscription URL is a credential. Never commit it, paste it into an issue, or include it in a
  support archive.
- Review every file in a redacted support bundle before sharing it.
- Do not treat fixture success, brand recognition, or one successful target as a wider compatibility
  claim.

For account, payment, registration, and other identity-sensitive operations, ordinary connectivity
or the lowest-latency exit is not evidence of a stable or suitable egress identity. Automatic route
selection and self-heal may change an exit between attempts. The project can expose and constrain
that continuity boundary, but it does not promise platform acceptance, geographic eligibility, or a
successful transaction.

## Progressive operator path

1. Read [Quick start](QUICKSTART.md) and [Compatibility](docs/COMPATIBILITY.md).
2. Run TUI help and local verification; these paths do not contact a router.
3. Confirm host tools and prepare a separate fallback or management path.
4. Declare the target and run read-only capability and baseline checks.
5. Review the deployment dry-run and explicit rollback route.
6. Apply only after entering `APPLY`; preserve the reported backup.
7. Provide the subscription through the documented path without exposing the credential.
8. Verify runtime, router, and client topology.
9. Enable self-heal only after its dry-run evidence is acceptable.
10. Run the final installation gate and retain the non-secret evidence needed for recovery.

If any step cannot establish its required evidence, stop at that boundary. Do not convert missing
evidence into an acceptance claim.

## Verify locally

The local verifier does not contact a router or the network:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1
```

```sh
sh scripts/verify-local.sh
```

These commands validate the public checkout and synthetic fixtures. They do not replace a target
capability check, a field observation, or the release-specific gates described in
[Release readiness](docs/RELEASE_READINESS.md).

## Support, security, and contribution

- Usage and design questions: [Support](SUPPORT.md)
- Compatibility evidence and future adapter proposals:
  [Structured issue forms](https://github.com/yiheng8023/home-edge-bootstrap-public/issues/new/choose)
- Confidential vulnerability reports: [Security policy](SECURITY.md)
- Focused, reproducible changes: [Contributing](CONTRIBUTING.md)
- Maintainer authority and evidence rules: [Governance](GOVERNANCE.md)
- Third-party licensing: [Third-party notices](THIRD_PARTY_NOTICES.md)
- Reusable project graphics and accessibility text: [Media kit](media/MEDIA_KIT.md)

Community support is best effort. Sponsorship does not create a service-level commitment, warranty,
response priority, release promise, or feature entitlement.

## Sponsor

If Home Edge Bootstrap is useful to you and you would like to support its continued maintenance,
documentation, testing, and community work, voluntary sponsorships of any amount are sincerely
appreciated. Sponsorship is optional and does not purchase support priority, features, release
decisions, or technical influence.

- For CNY sponsorships, scan the WeChat Pay or Alipay code below.
- For cross-border sponsorships or other supported currencies, use the
  [PayPal payment link](https://www.paypal.com/ncp/payment/LNTF8KXGJXMZY). Available currencies,
  payment methods, conversion, and fees are determined by the PayPal checkout page and may vary by
  country or region.

Please verify the displayed recipient before confirming a payment. Thank you for supporting the
project.

<table>
  <tr>
    <td align="center"><strong>WeChat Pay (CNY)</strong><br><img src="docs/assets/sponsoring/wechat-pay.png" alt="WeChat Pay sponsorship QR code" width="280"></td>
    <td align="center"><strong>Alipay (CNY)</strong><br><img src="docs/assets/sponsoring/alipay.png" alt="Alipay sponsorship QR code" width="280"></td>
  </tr>
</table>

See [Sponsoring](SPONSORING.md) for the complete voluntary-sponsorship and governance boundary.

## Repository layout

```text
adapters/    Device and firmware adapters; the current implementation targets Asuswrt-Merlin
bundle/      Offline-runtime contract and release-populated payload location
config/      Portable policy, compatibility, lock, and SBOM data
docs/        Architecture, recovery, compatibility, threat, and release guidance
media/       Reproducible public graphics, source copy, manifests, and accessibility text
scripts/     Guided operation, deployment, recovery, verification, and fixture entry points
```

Project-original work is licensed under Apache-2.0. Bundled or referenced third-party components
retain their own licenses and corresponding-source obligations; see
[Third-party notices](THIRD_PARTY_NOTICES.md).

## Guarded subscription refresh and dashboard defaults

The current source checkout adds opt-in periodic and demand-driven node refresh.
A five-minute check defaults to a daily fetch; three sustained health failures can
request an earlier refresh, subject to uplink, cooldown and backoff checks. Unchanged
nodes do not reload. Changes retain local rules/groups and manual choices, validate
an isolated candidate, obtain synchronous non-forced reload acknowledgement, and
roll back failed network verification. A newly removed manual selection is reported
as a conflict instead of silently replaced.

Supported Yacd-meta initial preferences are latency ascending, unavailable nodes
hidden, and automatic closing of old connections off. Saved browser choices win.
The local panel automatically uses its own router: enter the panel access key once,
then reopen directly in the same browser, without Add or IP selection. Controller
authentication remains enabled; retain site storage and use the same local URL.

The parser is compiled on the operator host, so the router needs no Go installation.
See [Subscription automation](docs/SUBSCRIPTION_AUTOMATION.md) for prerequisites,
activation and limits. This source feature is not retroactively present in the
already published v0.1.4 download archives. Site results and offline fixture results
are distinct; they do not establish broad firmware/provider support.

The v0.1.8 release includes this source and helpers, with Mihomo v1.19.32 in the offline runtime package.
Node-only subscription automation still needs host compilation of yamlbridge through a trusted network
or prepared module cache; no prebuilt parser is included. HTTPS subscription, controller key, local
group filters and explicit site activation are separate prerequisites. See [release notes](docs/RELEASE_NOTES.md).

OpenAI routing requires a consistent service policy for login, chat and dependency domains. Generic latency tests and provider [AI] labels do not establish service availability. Review the [service routing procedure](docs/SERVICE_ROUTING.md), preserve working manual choices, and verify both persistent and loaded rules before treating a repair as complete.
