# No-Wall Bootstrap Contract

English source of truth. See `docs/zh-CN/NO_WALL_BOOTSTRAP.md` for the Chinese reading mapping.

This project exists to bring up the proxy path. Therefore every required step before the proxy path
works must be possible without using that proxy path.

## Contract

Before `proxy_state=verified`, required operations may use only:

- the local checkout of this repository;
- local OS tools such as Git, SSH, tar, PowerShell, and, on POSIX systems, gzip;
- the router Web GUI on the LAN;
- SSH to the router on the LAN;
- files already present on the router;
- files already present in `bundle/`;
- a provider subscription URL supplied by the user, if the provider endpoint is directly reachable.

Before `proxy_state=verified`, required operations must not require these sources to be reachable:

- GitHub, SourceForge, the Asuswrt-Merlin website, or any other internet download that may be slow,
  blocked, or temporarily unreachable from the current network;
- public subscription converters;
- package managers or installers that fetch from the internet;
- DNS, geosite, geoip, core, dashboard, or rule downloads that require the proxy path that is not yet
  working.

## Consequences

- Firmware acquisition and flashing happen before this bootstrap when the router is new or still
  runs stock Asuswrt. If official Asuswrt-Merlin is already installed, skip this preparation. From
  a trusted reachable network, select the exact model and hardware revision on the
  [official supported-model list](https://www.asuswrt-merlin.net/about), obtain the matching build
  through the [official download page](https://www.asuswrt-merlin.net/download) or its official
  [SourceForge release area](https://sourceforge.net/projects/asuswrt-merlin/files/), and follow the
  [official installation guide](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation).
  Transfer the verified archive offline if necessary. This project does not download or flash router
  firmware. A third-party community or support site may serve only one country or region and may
  distribute a modified firmware family; do not assume that a corresponding site exists elsewhere
  or that it is an official source.
  If no trusted source is reachable, stop rather than substituting an unverified download.
- `prepare-bundle` is not a required pre-proxy step. It downloads release assets from GitHub. GitHub
  may work directly in mainland China, but it can be slow or temporarily unreachable during sensitive
  periods, so the main no-wall path must not depend on it.
- A fresh no-wall runtime install requires verified files in `bundle/`.
- If `bundle/` is missing, the kit may still configure and supervise an existing ShellCrash/Mihomo
  runtime, but it must not claim that a fresh offline install is possible.
- Public remote converters remain blocked by default. Use direct provider YAML, ShellCrash import, or
  a trusted local/private converter until the user explicitly accepts converter exposure.

## Local Readiness Check

Windows PowerShell:

```powershell
.\scripts\check-no-wall-readiness.ps1
```

macOS/Linux shell:

```sh
sh scripts/check-no-wall-readiness.sh
```

The check does not contact the network. It verifies local tools and, if present, validates the offline
runtime bundle.

## Practical Flow

1. If the router does not already run official Asuswrt-Merlin, complete the official manual download
   and installation preparation above from a trusted reachable network.
2. Use router Web GUI and LAN SSH for initial setup.
3. Run `check-no-wall-readiness`.
4. Run `guide-router`.
5. If ShellCrash/Mihomo already exists, deploy policy/scripts and import the provider profile.
6. If runtime is missing, use `-InstallRuntime` only when `bundle/` is verified.
7. Only after the route is verified should optional online preparation tasks be treated as convenient
   rather than blocking.
