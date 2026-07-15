# Quick start

[简体中文](QUICKSTART.zh-CN.md) · [Home](README.md)

This path introduces the framework progressively. The current implemented reference adapter targets
an ASUS gateway running official Asuswrt-Merlin with ShellCrash/ShellClash and a Mihomo-compatible
runtime. It is not a verified-adapter maturity claim.

## 1. Clone the source checkout

```powershell
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
```

The source checkout contains scripts, documentation, and synthetic fixtures. It may not contain the
runtime payloads required for a fresh offline installation.

## 2. Inspect the guide locally

Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Help
```

macOS or Linux:

On macOS and Linux, local verification requires Python 3. The `python3` command is accepted; `python` is accepted only when it points to Python 3. Python 2 is unsupported.

```sh
sh scripts/tui.sh --help
```

Help is local-only and does not contact a router.

## 3. Verify the checkout

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1
```

```sh
sh scripts/verify-local.sh
```

Local verification is offline and fixture-based. It is not field certification for a router,
firmware build, provider, or network.

## 4. Prepare the safety boundary

Before declaring a target:

- Read [Compatibility](docs/COMPATIBILITY.md).
- Keep a separately managed recovery or fallback path.
- Confirm that you can verify the SSH host key.
- Do not place a subscription URL in a command history, issue, or support archive.
- If the runtime is absent, obtain a separately verified offline release artifact rather than making
  the unverified proxy path a prerequisite for its own installation.

## 5. Start a guided target session

Use a generic SSH target such as `router-user@router.lan`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Router router-user@router.lan
```

```sh
sh scripts/tui.sh --router router-user@router.lan
```

After a target is supplied, the guide can run read-only capability probes over SSH. Verify the SSH
host key yourself; do not disable host-key checking.

## 6. Review before writing

The guide prepares a dry-run before deployment. Review the exact target, managed paths, backup,
rollback command, capability mismatches, and accepted boundaries. A write requires the exact
`APPLY` confirmation. EOF, interruption, invalid input, or any other response cancels the action.

## 7. Verify before enabling self-heal

After apply:

1. Confirm the runtime profile and health endpoint.
2. Confirm the intended router/client topology.
3. Retain the reported backup and rollback route.
4. Enable live self-heal only after its dry-run behavior is understood; the write requires the exact
   `ENABLE` confirmation.

If the applied state is unhealthy, use the reported rollback path. A prompted rollback requires the
exact `ROLLBACK` confirmation.

## 8. Close out or request support

Run the final installation gate for the declared target. If diagnosis must be shared, generate a
redacted support bundle and review every file before attaching it. A subscription URL is a credential
and must never appear in an issue or support archive.

Return to the [full README](README.md) for architecture, adapter maturity, no-wall recovery, and
contribution guidance.
