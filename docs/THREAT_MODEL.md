# Threat Model

English source of truth. See `docs/zh-CN/THREAT_MODEL.md` for the Chinese reading mapping.

This project manages a home edge router. Its safety posture is based on bounded automation,
credential minimization, local verification, and explicit manual trust decisions.

## Protected Assets

- Router administrator access.
- SSH keys and authorized keys.
- Wi-Fi credentials, WAN/ISP details, VPN peer keys, and regulatory settings.
- Provider subscription URLs and provider node lists.
- Mihomo external-controller secret, if configured.
- Offline runtime bundle integrity.
- Router traffic path and client reachability.

## Trust Boundaries

| Boundary | Project Position |
| --- | --- |
| Local host to router SSH | Requires an already-authorized SSH identity or password. Scripts must not collect or store router passwords. |
| Router LAN | Assumes the operator is on the trusted LAN. WAN exposure remains out of scope except for audit warnings. |
| Provider subscription URL | Treated as a credential. It must stay out of Git, chat, logs, and public converters unless explicitly accepted. |
| Subscription converter | Localhost/private LAN is allowed by default. Public converters require `SUBSCRIPTION_ALLOW_REMOTE_CONVERTER=1`. |
| Offline bundle | Local hashes verify checkout integrity. Upstream authenticity is handled by the supply-chain policy, not by local hashes alone. |
| ShellCrash/Mihomo runtime | Treated as third-party runtime code. This project stages and verifies local payloads but does not become upstream maintainer. |
| Modified Merlin firmware | Allowed only as an explicit compatibility decision. Official Asuswrt-Merlin remains the preferred support target. |

## Threats And Controls

| Threat | Control |
| --- | --- |
| Subscription credential leaks to Git | `.gitignore`, helper scripts that do not print URLs, and subscription fixture tests that check stdout redaction. |
| Public converter sees subscription URL | Remote converters blocked by default; explicit allow flag required. |
| Router settings drift after manual changes | Read-only router audit and guided state loop must be rerun after manual intervention. |
| Wrong Mihomo API port assumption | API discovery checks config and common local ports; status output reports the actual port. |
| Provider/UI label drift | Route selection uses Mihomo API state, role-oriented group matching, optional candidate/region expressions, latency probes, and fixture tests. |
| Route flap or repeated switching | Self-heal switch journal and per-hour circuit breaker. |
| Sensitive-operation egress identity drift | Route health is not treated as identity proof. The current release documents the negative contract only; a future bounded lease must bind runtime owner, effective leaf, observed exit/network class, DNS path, policy generation, and expiry, then invalidate on ambiguity or drift. |
| Broken deployment overwrites working kit | Remote staging uses a temporary directory and keeps a previous deployment directory. |
| Deployed scripts silently drift from the reviewed source | Each applied deployment carries source identity and managed-file hashes; read-only router status verifies the installed kit and active script copies. |
| Bad update or runtime replacement | Rollback scripts can restore the previous kit and optionally restore a backed-up runtime. |
| Broken subscription response | Size, HTML/error-page, raw/base64, and YAML-shape validation before cache/apply. |
| Host environment ambiguity | Local verification checks required command availability and runs cross-platform fixture tests. |

## Non-Goals

- The project does not bypass firmware flashing, provider purchase, account setup, first router
  credentials, regional radio rules, or subscription converter trust decisions.
- The project does not make public converter use safe. It only blocks it by default and makes the
  decision explicit.
- The project does not certify third-party firmware or runtime code. It records provenance and local
  integrity and keeps rollback available.
- The project does not guarantee account, payment, registration, financial, or regional-verification
  outcomes, and it does not treat a country label or reachable low-latency route as stable identity.
- The project does not make a compromised router trustworthy. If compromise is suspected, rebuild
  from known-good firmware and credentials before using this automation.

## Operator Rules

1. Run no-wall readiness before assuming the repository can recover a fresh runtime without proxy.
2. Run router audit after any manual router setting change.
3. Keep `SUBSCRIPTION.local`, node lists, keys, and logs with secrets out of Git and chat.
4. Use dry-run mode before applying deployment, subscription refresh, live self-heal, or rollback.
5. Treat any public converter, firmware mirror, or third-party runtime replacement as a manual trust
   decision.
