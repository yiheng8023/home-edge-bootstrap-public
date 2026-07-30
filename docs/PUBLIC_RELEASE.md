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

A versioned release contains exactly nine contracted files. For `v0.1.1`, they are:

- `home-edge-bootstrap-v0.1.1-source.zip`
- `home-edge-bootstrap-v0.1.1-source.tar.gz`
- `home-edge-bootstrap-v0.1.1-offline.zip`
- `home-edge-bootstrap-v0.1.1-offline.tar.gz`
- `mihomo-v1.19.28-source-complete.tar.gz`
- `shellcrash-1.9.4-source-complete.tar.gz`
- `SBOM.spdx.json`
- `RELEASE-MANIFEST.json`
- `SHA256SUMS`

`SHA256SUMS` covers the other eight distributed files. It cannot contain a checksum for itself.
`RELEASE-MANIFEST.json` records the public commit, deterministic build time, support limitation,
component locks, artifact sizes, and artifact hashes. `SBOM.spdx.json` is release-specific and is
separate from the source-checkout SBOM in `config/sbom.json`.

Publishers preserve contractual filenames and apply the exact human-readable asset labels in
`docs/RELEASE_NOTES.md`. Every uploaded asset must have a non-empty label before publication.

Ordinary users do not download all nine files. The minimum download is one archive plus
`SHA256SUMS`; use the corresponding source archive only when the runtime is already present and only
scripts or documentation are needed. The manifest, SBOM, and separate complete-source archives are
audit and source-availability artifacts, not additional installation parts. GitHub's automatic
**Source code** archives are outside this exact release surface and are not substitutes for the
contracted archives. Version-specific known limitations in `docs/RELEASE_NOTES.md` override the
general intended role of an artifact.

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

Before creating or editing a GitHub Release, render `docs/RELEASE_NOTES.md` with
`scripts/render-release-body.py` for the target repository and version. This converts repository
links to tag-pinned URLs; using the documentation file directly as the Release body can produce
links that resolve from the wrong directory.

The renderer's `--source-ref` selects the reviewed commit/tag containing the Release body, while
`--version` selects the release tag against which repository links are validated. They are normally
the same new tag. A correction to an existing body must explicitly name a later reviewed
`--source-ref`; it must not imply that old assets contain later fixes.

## v0.1.1 Acceptance Contract

v0.1.1 publication is gated on all of the following:

- Create a new tag and new versioned assets; never replace v0.1.0 assets or describe them as fixed.
- Preserve the nine contractual asset roles, verify `SHA256SUMS`, the release manifest, SPDX SBOM,
  licenses, and complete corresponding source, and give every uploaded asset its exact non-empty
  label.
- Render the Release body from the reviewed v0.1.1 tag and verify every tag-pinned link.
- Record supported live official Asuswrt-Merlin evidence for the running core, boot survival,
  controller/UI reachability, transparent and explicit-proxy paths, client checks, and installation
  closeout.
- Verify helper-command fallbacks, temporary runtime staging outside persistent JFFS,
  interrupted-install cleanup, and rollback against the exact tagged implementation. Destructive
  failure branches may use deterministic offline fault injection instead of deliberately disrupting
  an active live network, but the evidence type must be disclosed.
- Record the exact source commit, field evidence, and offline verification boundary. Host CI or
  fixtures alone do not substitute for the live runtime evidence above.

The release notes record the resulting evidence and its limits; this contract does not certify
additional hardware, providers, routes, accounts, or regional outcomes.

## Sensitive Egress Limitation

Routine self-heal optimizes availability and bounded recovery. It is not a sensitive-egress
assurance mechanism. Until a separately verified continuity capability exists, operators should not
interpret route health as proof of a stable effective leaf, ASN class, reputation, DNS path, account
risk posture, or platform acceptance. Public release readiness does not upgrade this limitation.
