# Release notes

[简体中文](zh-CN/RELEASE_NOTES.md) · [Home](../README.md)

## v0.1.9 (2026-10-13)

v0.1.9 corrects self-heal authority: a configured HEAL_GROUP must exactly match a writable selector, and automatic main-group discovery excludes manual names. Explicitly naming a manual group authorizes its automation; nested and role switching retain their separate opt-in controls. Fresh graph/selection checks run before PUT; rollback is guarded against intervening changes. The controller has no atomic compare-and-swap (CAS), so these checks reduce the observed race window without eliminating all concurrent-change risk.

Active service-helper provenance is included in project adoption. Merlin detection falls back to an available command locator instead of treating a missing command as a negative installation verdict. PowerShell 5/7 and POSIX deployment use short SSH argv with UTF-8/LF stdin and wrapped base64 transfer, with archive failure checked in its own scope; 16K fixture transport is covered. Source provenance keeps non-Git and missing-Git cases explicit, never borrows an ancestor repository, and deterministically selects the first usable Git. Windows short and long staging paths produce identical relative checksum paths. Windows clone failure does not launch an existing destination.

The reference site separately accepted a project-only refresh of the execution source, preserved runtime/core, selectors and profiles, and observed a later natural cron with no selection change. This is bounded site evidence, not acceptance of every new archive, native GUI, provider, account or network outcome. This version/documentation commit is separate from that earlier site source receipt; documentation bytes need their own adoption reconciliation.

The v0.1.8 tags, draft assets and original notes remain preserved and unpublished because later source gaps were found. v0.1.9 requires its own exact-source CI, concrete archives and publication checks. Mihomo v1.19.32, ShellCrash 1.9.4, GPL/source locks, nine public asset roles and broad-claim blocked scope remain unchanged.

Choose one acquisition route: verify/extract a release package, Git clone, reuse a complete local folder/desktop entry, or transfer one complete package offline. Windows opens start.cmd; macOS opens start.command; Linux runs start.sh through sh, then choose 1 for observed-state guidance. No npm, pnpm or npx installation entry is provided.

Public source packages/clones omit offline runtime payloads; use source with an existing runtime or choose offline when the target lacks one.

Windows: download one complete ZIP, Extract All, then double-click start.cmd. macOS/Linux: choose tar.gz. Download SHA256SUMS to verify the selected package; complete-source audit assets are not extra installation parts.

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.9-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.9-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.9-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.9-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.9-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.9-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.9-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.9-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

Choose one package for your system plus `SHA256SUMS`; verify only the file you downloaded. Manifest, SBOM (public release) and complete-source assets are audit/source-availability material, not extra installation parts. GitHub automatic Source code archives are not the contracted packages.

Choose a source-only package only when the runtime is already present and you need scripts/documentation; choose an offline package for fresh offline runtime preparation.

Save the chosen archive and `SHA256SUMS` in the same folder. Run the verification commands below in a terminal opened in that download folder: on Windows, open the folder in Explorer, type `powershell` in the address bar and press Enter; on macOS/Linux, open Terminal, type `cd ` (with the space), drag the download folder into it and press Enter. Extract only after verification succeeds; the project directory is not needed for this check.

Windows PowerShell, checking only the offline ZIP you downloaded:

```powershell
$File = "home-edge-bootstrap-v0.1.9-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux, checking only the offline `tar.gz` you downloaded:

```sh
file=home-edge-bootstrap-v0.1.9-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```


## v0.1.8 (2026-10-12)

### Acquisition and startup (release-page guidance revision)

Choose one acquisition route: verify/extract a release package, Git clone, reuse a complete local folder/desktop entry, or transfer a complete package offline. Windows opens `start.cmd`; macOS opens `start.command`; Linux runs `start.sh` through `sh`; then choose **1** to start/resume from observed state. No npm, pnpm or npx installation entry is provided.

Public source packages and clones omit offline runtime payloads; use them for scripts with an existing runtime, or choose an offline package when the target lacks one.

This is a release-page documentation revision. Downloaded packages remain bound to the original v0.1.8 commits recorded in their manifests and do not contain the later README rewrite. For complete current paths, see the [English README](https://github.com/yiheng8023/home-edge-bootstrap-public/blob/main/README.md). Existing assets, tags and checksums remain unchanged.

Fix OpenAI service-policy inference: exact `DOMAIN-KEYWORD,openai/chatgpt` anchors now participate alongside dependency-domain rules. Conflicting groups require an explicit `HOME_EDGE_SERVICE_GROUP` instead of silently choosing the media policy. Add the exact `frontend-apps-multi-region.workos.com` dependency from the current official network guidance.

Installation observation preserves and excludes only an empty regular historical `home-edge-policy.local.bak.<14 digits>` from active-file ownership checks. Nonempty unknown backups, other names and links remain protected; a passive backup does not establish installation ownership or replacement permission.

The bilingual runbook distinguishes ordinary latency probes and provider `[AI]` labels from actual service access, and persistent ShellCrash overlays from the currently loaded rules. User selections remain authoritative; no automatic AI-node switching or guarantee of future service availability is introduced.

The guide menu is ordered 1 through 9 with exit last, combines help aliases into one entry, and keeps Language / 语言 plus English / 中文 discoverable in either current language. Windows installation probes also exit with the observer's status before a native pipeline's trailing CRLF can become a false SSH failure.

Affected regression fixtures include keyword/dependency-group conflict, explicit service binding, preservation of unrelated/runtime configuration, rollback, and passive-backup boundaries. A reference site's rule-only hot application separately verified loaded rules and retained selectors/core process; this is not acceptance of every released package, router, OAuth failure or network condition. Runtime pins, licenses, source locks and broad-release `blocked` scope remain unchanged. Earlier release sections, tags and assets remain unchanged.

Windows: download one complete ZIP, Extract All, then double-click start.cmd. macOS/Linux: choose tar.gz. Download SHA256SUMS to verify the selected package; complete-source audit assets are not extra installation parts.

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.8-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.8-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.8-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.8-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.8-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.8-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.8-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.8-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

Choose one package for your system plus `SHA256SUMS`; verify only the file you downloaded. Manifest, SBOM (public release) and complete-source assets are audit/source-availability material, not extra installation parts. GitHub automatic Source code archives are not the contracted packages.

Choose a source-only package only when the runtime is already present and you need scripts/documentation; choose an offline package for fresh offline runtime preparation.

Save the chosen archive and `SHA256SUMS` in the same folder. Run the verification commands below in a terminal opened in that download folder: on Windows, open the folder in Explorer, type `powershell` in the address bar and press Enter; on macOS/Linux, open Terminal, type `cd ` (with the space), drag the download folder into it and press Enter. Extract only after verification succeeds; the project directory is not needed for this check.

Windows PowerShell, checking only the offline ZIP you downloaded:

```powershell
$File = "home-edge-bootstrap-v0.1.8-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux, checking only the offline `tar.gz` you downloaded:

```sh
file=home-edge-bootstrap-v0.1.8-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```


## v0.1.7 (2026-10-12)

Add comprehensive local bilingual help (`H` / `?` / `help` / `6`) and a session-only language switch (`L` / `language` / `9`) that preserves the router target and selected session without network access or global setting writes.

Existing or partial project installations default to fresh read-only diagnosis and saved-session reuse. Installation evidence is bound to the selected router and path; only positive absence permits first installation. Unknown ownership, foreign content, links and malformed probes stop deployment. `installed` means project-owned presence, not complete lifecycle/network health; ShellCrash/Mihomo alone does not prove project installation.

An explicit `R` project refresh reviews a project-only plan and `<project-path>.prev` backup, then requires exact `REPLACE` followed by `APPLY`; an older backup may be replaced. The writer rechecks ownership under its lock. Runtime/core assets are preserved, while project-managed integration/configuration may change. Runtime-only replacement separately preserves the existing core unless core replacement is explicitly selected. This is not complete runtime rollback.

Desktop registration reuses a matching target, cached launcher and desktop pointer; other owned target/cache updates or repairs require `REPLACE` then `APPLY`. Unowned contents are not overwritable. Event-driven checks of current structure, directory identity and tools run at menu/action transitions and around important work; known degradation retains local help/language/exit and provides recovery. There is no background daemon or claim to detect every unknown failure.

Mihomo v1.19.32, ShellCrash 1.9.4, source locks and supply-chain review remain unchanged. yamlbridge remains source-only with the v0.1.5 preparation and explicit activation prerequisites. Common, host and device evidence remain distinct; Merlin is the only implemented real-device reference. No new live-device, shipped-core execution or native GUI field acceptance is claimed; broad claims remain `blocked`. All earlier release sections, tags and assets remain unchanged. Publication does not update an existing installation.

On Windows, download the ZIP below, Extract All, and double-click `start.cmd`. Optionally double-click `create-desktop-shortcut.cmd` to keep a desktop entry. Keep the extracted folder; downloading one script or opening it inside a ZIP is not a complete installation. On macOS/Linux choose tar.gz; if macOS execution permission was not preserved, invoke `sh` with the full path to `start.sh`. Complete-source audit assets are not needed for installation.

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.7-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.7-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.7-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.7-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.7-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.7-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.7-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.7-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

Choose one package for your system plus `SHA256SUMS`; verify only the file you downloaded. Manifest, SBOM (public release) and complete-source assets are audit/source-availability material, not extra installation parts. GitHub automatic Source code archives are not the contracted packages.

Choose a source-only package only when the runtime is already present and you need scripts/documentation; choose an offline package for fresh offline runtime preparation.

Windows PowerShell, checking only the offline ZIP you downloaded:

```powershell
$File = "home-edge-bootstrap-v0.1.7-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux, checking only the offline `tar.gz` you downloaded:

```sh
file=home-edge-bootstrap-v0.1.7-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```

## v0.1.6 (2026-10-12)

Add equal Windows/macOS/Linux directory-local and registered independent entries, with optional desktop integration. macOS uses `start.command`; Linux uses the self-locating `start.sh`. The entries resolve their own package and preserve the existing guide, failure exit codes and confirmation gates. README and Quickstart no longer assume a clone, known folder or prior `cd`.

Mihomo v1.19.32, ShellCrash 1.9.4, source locks and existing security evidence are unchanged. This adds no field acceptance or runtime upgrade; earlier tags/assets remain unchanged and broad release claims remain blocked. Startup performs no network access, automatic update, router change or elevation; Windows execution-policy bypass is confined to the child process. Registration and desktop integration are explicit local actions with path-type and directory-instance checks. Relocation or replacement requires selection; unrelated files are preserved. Missing optional device operations no longer prevent opening the core menu. Device candidate probes live in adapters; neutral dispatch requests selection for unknown or ambiguous candidates. yamlbridge remains source-only with the v0.1.5 activation prerequisites.

On Windows, download the ZIP below, Extract All, and double-click `start.cmd`. Optionally double-click `create-desktop-shortcut.cmd` to keep a desktop entry. Keep the extracted folder; downloading one script or opening it inside a ZIP is not a complete installation. On macOS/Linux choose tar.gz; if macOS execution permission was not preserved, invoke `sh` with the full path to `start.sh`. Complete-source audit assets are not needed for installation.

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.6-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.6-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.6-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.6-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.6-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.6-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.6-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.6-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.5 (2026-10-05)

This limited release brings the current project functions into new versioned archives and replaces
the pinned Mihomo payload with v1.19.32. All earlier tags and downloadable assets remain unchanged.

- Add opt-in guarded node-only subscription updates with periodic, demand and manual triggers,
  local-profile ownership, selection preservation, candidate checks and bounded rollback/reboot recovery.
- Separate stable credentials, cache and recovery state from replaceable project scripts; retire a
  consumed legacy cache only after byte-equality and ownership checks.
- Make the local dashboard use its own controller origin, remember a validated browser connection,
  and preserve stored display choices. Correct host SSH command normalization and fixture temp paths.
- Pin Mihomo v1.19.32 at `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`; keep ShellCrash 1.9.4.
  The downloaded Linux ARM64 binary records Go1.26.8 and `with_gvisor` independently of the
  Go1.26.8 source-preparation toolchain. Complete corresponding source and inventory are refreshed.
- Re-run the ten-case CVE-2025-56499 source regression and removed-guard/explicit-bypass controls
  against the exact v32 complete source. Preserve the v28 proof and logs as historical evidence.

**Runtime change and security scope:** The previous v1.19.28 binary records Go1.26.5, within
the Go1.26 affected range for [GO-2026-6090 / CVE-2026-56862](https://pkg.go.dev/vuln/GO-2026-6090)
(`go1.26.0-0` through versions before `go1.26.6`). The v32 binary's Go1.26.8 identity is outside
that reported range; this version-bound disposition is not a broad vulnerability clearance.
Upstream v1.19.30 notes identify the TLS fix. v1.19.32 changes the default TUN/IP stack to
`mips`/mipstack and includes TCP, UDP and ICMP changes; review local TUN settings before adoption.
This release adds no execution test of the shipped ARM64 binary, live-router upgrade, target
rollback rehearsal or broad firmware/provider compatibility evidence. GitHub asset digests match,
but no maintainer signature or independent reproducible-build attestation is recorded. The broad
release-readiness claim remains blocked; publication verifies the declared source/host/archive scope.

**Subscription prerequisites:** These archives include yamlbridge source and build helpers, without
a prebuilt yamlbridge executable. The opt-in updater requires a host Go compiler, POSIX shell,
gzip/OpenSSL and the pinned YAML module available through a trusted network or prepared module cache.
Build and verify a Linux ARM64 gzip plus the uncompressed binary SHA256, then explicitly activate
the site with deployed helpers, an HTTPS subscription, private controller key, inline-node profile
and local group filters. The router needs no Go installation. This optional preparation is separate
from the two-payload offline runtime package; source/host fixtures do not establish site acceptance.
Publishing does not update or restart an existing installation.

Choose one package plus `SHA256SUMS`. Manifest, SBOM and complete-source assets serve audit and
source availability; GitHub's automatic Source code archives are not the contracted packages.

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.5-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.5-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.5-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.5-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.5-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.5-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.5-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.5-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |


## v0.1.4 (2026-09-06)

This patch release supersedes v0.1.3 for subscription transport security and host verification.
The earlier archives remain unchanged and do not contain these fixes.

- Reject non-HTTPS direct provider subscriptions before fetching. Restrict both initial requests
  and redirects to HTTPS, including the proxy-fetch branch, to prevent plaintext credential exposure.
- Preserve the separate local/private HTTP converter policy; this is not permission to use an
  HTTP provider subscription. Providers must offer an HTTPS subscription endpoint.
- Fail Windows verification immediately when a PowerShell child check fails, with regression
  coverage for failures at different points in the verification chain.
- Correct Windows route selection to compare route metric plus interface metric after
  longest-prefix matching, avoiding false local-proxy/TUN diagnoses.
- Make third-party compliance fixtures use the selected Python interpreter, including hosts
  that provide only Python 3.

Mihomo v1.19.28 and ShellCrash 1.9.4 payloads and source locks are unchanged. This release does not
claim new live-router acceptance or broader compatibility. Existing installations are not
automatically updated by publishing this release.

**Security evidence correction (2026-09-06):** The previous statement that
[CVE-2025-56499](https://github.com/advisories/GHSA-7m6g-3fpv-8gmx) remained unresolved for the pinned
source is superseded. Upstream [PR #2177](https://github.com/MetaCubeX/mihomo/pull/2177), included in
[v1.19.12](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.12), is retained in the locked
v1.19.28 source. Existing isolated source regression evidence supports the fix under the default
path policy: path checks enabled, no additional allowed paths, and a non-CMFA build. Static review
found no path-policy overrides in the shipped startup scripts. This is a source-level disposition,
not a new execution test of the shipped binary or a live-router security acceptance, and it does
not close independent upstream authenticity requirements. Published tags and downloadable archives
remain unchanged and therefore retain the earlier wording; this dated correction updates the
documentation and release-page explanation only.

Choose one package plus `SHA256SUMS`. Source-only packages, where offered, do not include runtime
payloads. The manifest, SBOM and complete-source archives are audit material, not extra installation
steps.

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.4-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.4-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.4-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.4-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/mihomo-v1.19.28-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.4-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.4-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.4-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.4-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.3 (2026-08-01)

This corrective release supersedes v0.1.2 for release-document integrity. Runtime payloads,
component locks, deployment behavior, and the declared compatibility boundary are unchanged. No
new hardware, provider, network, or live-router certification is claimed.

- Render only the exact target version section into each GitHub Release body, so a current Release
  page cannot expose historical download matrices as current guidance.
- Derive fixture versions from the release notes, require English and Chinese current sections to
  agree, reject historical download tags, and require the complete current asset contract.
- Use version-neutral build guidance in the packaged source documentation, make Windows fixture
  cleanup deterministic, and explicitly prefer POSIX `find` during source preparation so Git Bash
  cannot select the incompatible Windows command.

v0.1.2 assets remain immutable and checksum-verifiable. Use v0.1.3 for the corrected release
presentation and validation contract. Choose one package plus `SHA256SUMS`:

| Need | Download | Required with it |
|---|---|---|
| Windows offline package, runtime included | [`home-edge-bootstrap-v0.1.3-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |
| macOS/Linux offline package, runtime included | [`home-edge-bootstrap-v0.1.3-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |
| Windows scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.3-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |
| macOS/Linux scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.3-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |

The remaining assets support audit and corresponding-source availability:

| Asset | Purpose | Required for normal installation |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/RELEASE-MANIFEST.json) | Records the public commit, component locks, sizes, and digests | No |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SBOM.spdx.json) | Release-specific software inventory and license metadata | No |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/mihomo-v1.19.28-source-complete.tar.gz) | Complete corresponding source for Mihomo | No |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/shellcrash-1.9.4-source-complete.tar.gz) | Complete corresponding source for ShellCrash | No |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.3-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.3-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.3-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.3-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.2 (2026-07-31)

This patch release supersedes v0.1.1 for cross-platform host verification and lifecycle migration.
It incorporates the final RT-AX86U Pro field findings without claiming new hardware, provider, or
network certification.

- Make the PowerShell deployment path honor the same temporary `DEPLOY_BUNDLE_DIR` override as the
  POSIX path, and test its runtime plan with a small synthetic bundle rather than expecting a source
  checkout to contain the production runtime.
- Let macOS verification use native `shasum -a 256` through a temporary compatibility command when
  GNU `sha256sum` is absent, without installing packages or modifying the host environment.
- Upgrade GitHub checkout actions to the current Node 24-based major, stream PowerShell verification
  output, and publish bounded failure-tail annotations for diagnosable host-matrix failures.
- Derive release-candidate versions from the pushed tag or explicit manual-dispatch input instead
  of building mislabeled v0.1.0 artifacts.
- Normalize a trailing macOS `TMPDIR` separator across projection, deployment, verification, secret
  scanning, and fixture temporary directories; use portable GNU/BSD file-mode checks in ShellCrash
  data fixtures.
- Migrate one well-formed legacy ShellCrash `services-start` block into the single canonical
  lifecycle block. Malformed, duplicated, reversed, or overlapping markers fail closed without
  rewriting unrelated hook content; decommission recognizes the same legacy surface.
- Verify the migration on a live RT-AX86U Pro after a manual official-firmware update from
  `3006.102.8_0` to `3006.102.8_2`: CrashCore remained available, controller authentication and
  Yacd returned healthy responses, the legacy block was removed, and one startup command remained.
  This is bounded field evidence, not certification of other models, providers, or networks.

v0.1.1 assets remain immutable. You do not need all nine v0.1.2 files. Choose one package and
download `SHA256SUMS` with it:

| Need | Download | Required with it |
|---|---|---|
| Windows offline package, runtime included | [`home-edge-bootstrap-v0.1.2-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |
| macOS/Linux offline package, runtime included | [`home-edge-bootstrap-v0.1.2-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |
| Windows scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.2-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |
| macOS/Linux scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.2-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |

The manifest, SBOM, and complete-source archives are not additional installation parts:

| Asset | Purpose | Required for normal installation |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/RELEASE-MANIFEST.json) | Records the public commit, component locks, sizes, and digests | No |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SBOM.spdx.json) | Release-specific software inventory and license metadata | No |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/mihomo-v1.19.28-source-complete.tar.gz) | Complete corresponding source for Mihomo | No |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/shellcrash-1.9.4-source-complete.tar.gz) | Complete corresponding source for ShellCrash | No |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.2-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.2-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.2-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.2-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.1 (2026-07-31)

Maintenance release incorporating the RT-AX86U Pro field-recovery findings. It does not assign a
verified adapter maturity stage or certify hardware beyond the declared capability boundary.

- Normalize and back up ShellCrash startup tasks that recursively start the service or update the
  core, scripts, or rule data during startup, while preserving unrelated and benign tasks.
- Install a conservative boot helper that respects manual-disable and prior-start-error markers,
  restores a missing compressed Mihomo core from protected state, and avoids duplicate starts.
- Register ShellCrash startup and self-heal reconciliation as separate bounded lifecycle actions.
- Harden Merlin/BusyBox fallbacks, subscription validation, controller-secret file handling, DNS
  and rule-data preparation, deployment staging, and lifecycle evidence.
- Parse ShellCrash `command.env` as constrained data rather than sourcing it during normalization,
  so an unexpected statement cannot execute as router root.
- Detect persistent Windows user proxy variables as active client-topology ownership rather than
  relying on a transient process or listener name.
- Add optional, atomic service-dependency profiles with rollback state and no automatic runtime
  reload, keeping service-specific routing out of generic route recovery. Per-profile block backups
  make interleaved apply/rollback operations composable, and a failed state commit restores the
  prior rules file.
- Add a field-derived `asus-global-account` profile that scopes a direct-route exception to the
  observed `nomos.asus.com` token endpoint rather than widening all ASUS traffic.
- Document arbitrary upstream gateways, double NAT, and the independent IPv6 acceptance boundary.
- Make stable subscription writes atomic and roll back the staged control plane when a following
  runtime deployment fails.
- Protect the POSIX remote-script template with a quoted heredoc so embedded `awk` quotes cannot
  escape the template and recursively invoke deployment. Provenance avoids one shell per staged
  file on Git Bash, canonicalizes platform-specific SHA-256 output while accepting legacy
  star-delimited records, uses a minimal verified runtime payload in failure-path fixtures, and
  includes the service-rule helper in rollback cleanup. A runtime-stage failure now either replays
  the restored prior control plane or removes first-install active scripts and hooks before
  reporting rollback.

A live RT-AX86U Pro recovery exercise verified the running mixed-mode core, controller
authentication, dashboard reachability, explicit-proxy and transparent probes, and a downstream-ASUS
topology behind a separate upstream gateway. Router power-loss/restart recovery was observed after
boot-hook repair. This is bounded site evidence; destructive rollback branches are verified by
deterministic offline fixtures rather than deliberately reinjected into an active network.

### What to download

You do not need all nine files. Choose one package for your operator host and download
`SHA256SUMS` with it:

| Need | Download | Required with it |
|---|---|---|
| Windows offline package, runtime included | [`home-edge-bootstrap-v0.1.1-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |
| macOS/Linux offline package, runtime included | [`home-edge-bootstrap-v0.1.1-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |
| Windows scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.1-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |
| macOS/Linux scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.1-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |

Choose one archive format for one purpose. The manifest, SBOM, and complete-source archives are
audit and source-availability artifacts, not additional installation parts:

| Asset | Purpose | Needed for normal installation? |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/RELEASE-MANIFEST.json) | Records the public commit, component locks, sizes, and digests | No |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SBOM.spdx.json) | Release-specific software inventory and license metadata | No |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/mihomo-v1.19.28-source-complete.tar.gz) | Complete corresponding source for Mihomo | No |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/shellcrash-1.9.4-source-complete.tar.gz) | Complete corresponding source for ShellCrash | No |
| GitHub **Source code (zip)** / **Source code (tar.gz)** | Automatic GitHub snapshots; not contracted packages | No |

The exact non-empty GitHub asset labels are:

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.1-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.1-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.1-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.1-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.0

Initial public release of the Home Edge Bootstrap framework and its current implemented reference
adapter for ASUS gateways running official Asuswrt-Merlin.

Reference-adapter status identifies the first implemented architecture path; it does not assign a
verified adapter maturity stage or certify a wider compatibility range.

### What to download

> **Known v0.1.0 limitation:** the assets remain checksum-verifiable, but the automated fresh
> runtime installation path has not been validated for official Asuswrt-Merlin targets with limited
> JFFS capacity or missing helper commands. Do not treat v0.1.0 as a verified fresh-install path on
> such a target. Review the source/docs, use them with an already working runtime, or wait for a
> superseding release that has passed the live acceptance contract.

You do not need all files listed by GitHub. Choose one archive for your operator host plus
`SHA256SUMS`; the table describes each artifact's intended role, subject to the limitation above:

| Need | Download | Required with it |
|---|---|---|
| Windows offline package | [`home-edge-bootstrap-v0.1.0-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |
| macOS/Linux offline package | [`home-edge-bootstrap-v0.1.0-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |
| Windows scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.0-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |
| macOS/Linux scripts/docs only; runtime already present | [`home-edge-bootstrap-v0.1.0-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |

Choose one archive format for one purpose. You do not need both ZIP and `tar.gz`, and a source
archive is not a substitute for the offline package when runtime payloads are needed.

The remaining assets serve verification, audit, and source-availability needs:

| Asset | Purpose | Needed for normal installation? |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/RELEASE-MANIFEST.json) | Records the public commit, component locks, artifact sizes, and digests | No; optional provenance record |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SBOM.spdx.json) | Release-specific software inventory and license metadata | No; optional audit input |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/mihomo-v1.19.28-source-complete.tar.gz) | Complete corresponding source for the distributed Mihomo payload | No; source review and license compliance |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/shellcrash-1.9.4-source-complete.tar.gz) | Complete corresponding source for the distributed ShellCrash payload | No; source review and license compliance |
| GitHub **Source code (zip)** / **Source code (tar.gz)** | Automatic snapshots generated by GitHub | No; not the contracted source or offline packages |

The complete corresponding-source archives are also embedded in each offline package. Separate
copies are published so source remains directly available without downloading the much larger
offline package.

The exact GitHub asset-label mapping is:

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.0-offline.zip` | `Windows offline package - known v0.1.0 limitation` |
| `home-edge-bootstrap-v0.1.0-offline.tar.gz` | `macOS/Linux offline package - known v0.1.0 limitation` |
| `home-edge-bootstrap-v0.1.0-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.0-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

Publishers retrieve the asset IDs from the release API, review the ID/name mapping, and PATCH only
the `label` field:

```sh
gh api "repos/OWNER/REPOSITORY/releases/tags/v0.1.0" --jq '.assets[] | [.id,.name,.label] | @tsv'
gh api --method PATCH "repos/OWNER/REPOSITORY/releases/assets/ASSET_ID" \
  -f label='Windows offline package - known v0.1.0 limitation'
```

Filenames remain the contractual identities.

Windows PowerShell, checking only the offline ZIP you downloaded:

```powershell
$File = "home-edge-bootstrap-v0.1.0-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux, checking only the offline `tar.gz` you downloaded:

```sh
file=home-edge-bootstrap-v0.1.0-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```

### Included capabilities

- Numbered TUI entry points for Windows PowerShell and POSIX hosts on macOS and Linux.
- Capability-first router guidance, dry-run planning, exact apply confirmation, backup-aware deployment, rollback, self-heal setup, health checks, and redacted support-bundle export.
- Synthetic offline fixtures and local verification for supported host CI environments.
- A capability-driven framework boundary, the current Merlin reference adapter, and an independent
  soft-router or endpoint fallback boundary.
- Separate adapter-maturity and target-support classifications for future community evolution.

### Artifact types

- Source archive or source checkout: scripts, documentation, policy, and fixtures. It may configure an existing runtime but does not by itself promise fresh offline runtime installation.
- Offline recovery archive: the source surface plus reviewed runtime payloads, checksum material,
  third-party licenses, complete corresponding source, and a release-specific SBOM. Verify release
  checksums before use.

### Verification

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1` on Windows or `sh scripts/verify-local.sh` on macOS/Linux. Host CI covers the corresponding PowerShell and POSIX paths; it does not certify router hardware or firmware.

Verify the selected archive against `SHA256SUMS` before extraction. After extraction, verify the
archive's `CONTENT-SHA256SUMS` before running the guide.

### Known limitations

- Compatibility is capability-based and field evidence is not yet published in the policy matrix.
- The current reference adapter has no formally assigned verified maturity stage.
- Fixtures do not certify hardware, firmware, providers, or live networks.
- Runtime payload source, package, and checksum records must be completed and reviewed for each offline release artifact.
- Third-party components remain under their own licenses; see [third-party notices](../THIRD_PARTY_NOTICES.md) and the SPDX document at [`config/sbom.json`](../config/sbom.json).

### GitHub Release body

Do not paste this file directly as a GitHub Release body: GitHub resolves relative links from the tag
root rather than this file's `docs/` directory. Render a tag-aware body first:

```sh
python scripts/render-release-body.py \
  --repository OWNER/REPOSITORY \
  --version v0.1.0 \
  --source docs/RELEASE_NOTES.md \
  --output /path/outside/the/checkout/GITHUB-RELEASE.md
```

The renderer reads its body source from `--source-ref` (default: `--version`) while validating links
against the target tag named by `--version`. Correcting this existing release body from a later
reviewed commit requires an explicit `--source-ref COMMIT_SHA`; a new release should use its new tag
for both values.
