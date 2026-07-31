# Release notes

[简体中文](zh-CN/RELEASE_NOTES.md) · [Home](../README.md)

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
