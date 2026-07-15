# Public Release Contract

English is normative. See [`zh-CN/PUBLIC_RELEASE.md`](zh-CN/PUBLIC_RELEASE.md) for the Simplified
Chinese reading mapping.

## Purpose

The public release separates project source from a complete offline recovery package. Both archive
formats are generated from one clean public Git commit and verified by the same offline contract.
Runtime payloads, GPL license copies, and complete corresponding source never enter public Git
history; they appear only in the verified offline release and as separate corresponding-source
assets.

Release verification proves archive integrity and declared local contracts only. It does not
guarantee provider availability, sensitive-operation acceptance, account, payment, registration,
financial, or regional-verification outcomes. A reachable low-latency route, a country label, or an
automatically selected node is not evidence of stable egress identity.

## Exact Release Surface

A release contains exactly these nine files for `v0.1.0`:

- `home-edge-bootstrap-v0.1.0-source.zip`
- `home-edge-bootstrap-v0.1.0-source.tar.gz`
- `home-edge-bootstrap-v0.1.0-offline.zip`
- `home-edge-bootstrap-v0.1.0-offline.tar.gz`
- `mihomo-v1.19.28-source-complete.tar.gz`
- `shellcrash-1.9.4-source-complete.tar.gz`
- `SBOM.spdx.json`
- `RELEASE-MANIFEST.json`
- `SHA256SUMS`

`SHA256SUMS` covers the other eight distributed files. It cannot contain a checksum for itself.
`RELEASE-MANIFEST.json` records the public commit, deterministic build time, support limitation,
component locks, artifact sizes, and artifact hashes. `SBOM.spdx.json` is release-specific and is
separate from the source-checkout SBOM in `config/sbom.json`.

## Source And Offline Separation

The source archives contain only committed paths selected by
`config/public-release-files.txt`, plus `VERSION`, `PUBLIC-COMMIT`, and
`CONTENT-SHA256SUMS`. They exclude runtime payloads, complete corresponding-source archives,
licenses copied from GPL components, Git history, release output, caches, logs, local policy, and
credentials.

The offline archives start from the same verified project source and additionally contain:

- `bundle/mihomo-linux-arm64`, `bundle/ShellCrash.tar.gz`, their manifest, and checksums;
- GPL-3.0-only license copies under `third-party/licenses/`;
- complete corresponding source under `third-party/sources/`.

ZIP and tar archives must have one safe package root, no traversal or link entries, identical file
lists, identical bytes, and a complete valid `CONTENT-SHA256SUMS`.

## Build And Verify

Prepare verified third-party material outside the Git checkout with
`scripts/prepare-public-sources.ps1` or `.sh`. Then build into an absent output directory:

```powershell
.\scripts\build-public-release.ps1 `
  -Repo (Get-Location) `
  -Version v0.1.0 `
  -PreparedDir C:\path\to\verified-prepared-material `
  -Output C:\path\to\dist
```

```sh
sh scripts/build-public-release.sh \
  --repo . \
  --version v0.1.0 \
  --prepared-dir /path/to/verified-prepared-material \
  --output /path/to/dist
```

Verify without contacting a router or network:

```powershell
.\scripts\verify-public-release.ps1 -Repo (Get-Location) -Version v0.1.0 -Dist C:\path\to\dist
```

```sh
sh scripts/verify-public-release.sh --repo . --version v0.1.0 --dist /path/to/dist
```

The stable success marker is `public_release_state=ready`. A failed build leaves no partial output.
Building or verifying does not create a Git tag, publish a GitHub Release, change repository
visibility, or contact a router.

## Sensitive Egress Limitation

Routine self-heal optimizes availability and bounded recovery. It is not a sensitive-egress
assurance mechanism. Until a separately verified continuity capability exists, operators should not
interpret route health as proof of a stable effective leaf, ASN class, reputation, DNS path, account
risk posture, or platform acceptance. Public release readiness does not upgrade this limitation.
