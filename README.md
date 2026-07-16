# Home Edge Bootstrap

English | [简体中文](README.zh-CN.md)

Shortest path: [Quick start](QUICKSTART.md).

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
separate adapters after their capability, safety, recovery, evidence, and maintenance contracts are
defined and verified.

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

Clone the repository and open the numbered guided interface:

```powershell
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1
```

```sh
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
sh scripts/tui.sh
```

Use a generic target such as `router-user@router.lan`. The help path is local-only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Help
```

```sh
sh scripts/tui.sh --help
```

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

Future adapters should remain external until they have a named owner, a bounded capability contract,
synthetic fixtures, rollback behavior, diagnostics that do not expose sensitive information, bilingual operator guidance, and an
evidence path suitable for their support claim. Maintainers decide admission and maturity changes
through review; popularity or similarity to an existing proxy solution is not sufficient evidence.

## Source checkout and offline recovery

This repository is the project source checkout. It contains scripts, documentation, and synthetic
offline fixtures. It may configure an existing supported runtime, but it does not by itself promise
the runtime payloads needed for a fresh installation.

A separately published offline release may include checksum-bound runtime payloads, third-party
licenses, complete corresponding source, an SPDX SBOM, and a release manifest. Verify the release
checksums before extraction. Artifact availability does not broaden the declared device, firmware,
architecture, or support boundary.

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
