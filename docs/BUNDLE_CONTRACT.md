# Offline Bundle Contract

English source of truth. See `docs/zh-CN/BUNDLE_CONTRACT.md` for the Chinese reading mapping.

`bundle/` is intentionally ignored by default because it may contain large, architecture-specific
binaries. The contract is still stable so a future router can be restored without needing proxy access.

## Expected Files

| File | Required For | Notes |
|---|---|---|
| `bundle/mihomo-linux-arm64` | aarch64 Linux router; verify the target Merlin model architecture | Mihomo kernel binary |
| `bundle/ShellCrash.tar.gz` | Fresh ShellCrash install | Offline ShellCrash snapshot |
| `bundle/SHA256SUMS` | Offline verification | SHA256 digests checked before use |
| `bundle/MANIFEST.json` | Provenance | Source release, asset, URL, size, and digest metadata |

## Prepare And Verify

First check whether the current checkout already has a verified bundle. This check does not contact
the network.

Windows PowerShell:

```powershell
.\scripts\check-no-wall-readiness.ps1
```

macOS/Linux shell:

```sh
sh scripts/check-no-wall-readiness.sh
```

Prepare the bundle only on a machine that has trusted reachable network access, or after another
proxy path already works. This step downloads release assets and is not required before the first
proxy path is established.

Windows PowerShell:

```powershell
.\scripts\prepare-bundle.ps1
```

macOS/Linux shell:

```sh
sh scripts/prepare-bundle.sh
```

Verify it without network access:

```sh
sh scripts/verify-bundle.sh
```

If the kit must be clone-and-go for a fresh router, intentionally vendor the payloads:

```sh
git add -f bundle/mihomo-linux-arm64 bundle/ShellCrash.tar.gz
git add bundle/MANIFEST.json bundle/SHA256SUMS
```

## Rules

- Do not put subscription URLs, provider node lists, passwords, or API secrets in `bundle/`.
- Add binaries intentionally with `git add -f bundle/<file>` only when you want a clone-and-go kit.
- Keep architecture-specific payloads named explicitly; do not let `bootstrap.sh` guess a binary.
- If payloads are missing, adapters should degrade to "configure existing ShellCrash" rather than
  pretending a full offline install is possible.
- Do not require GitHub or any other internet download to be reachable before the proxy path is
  verified.
- Runtime installation is opt-in: set `BOOTSTRAP_INSTALL_RUNTIME=1`. Existing ShellCrash directories
  are not replaced unless `BOOTSTRAP_REPLACE_RUNTIME=1` is also set.

## Current State

The repository supports configuring and supervising an already installed ShellCrash/Mihomo runtime by
default. When the expected bundle files exist and `BOOTSTRAP_INSTALL_RUNTIME=1` is set, the Merlin
adapter can install ShellCrash from `ShellCrash.tar.gz`, stage the bundled Mihomo binary as
`CrashCore.gz`, and continue with the normal policy/self-heal setup. Subscription import remains a
manual credential step.
