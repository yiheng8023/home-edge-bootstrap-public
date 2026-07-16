# Contributing

[简体中文](CONTRIBUTING.zh-CN.md)

Thank you for helping improve Home Edge Bootstrap. Contributions should be focused, reviewable, and safe to reproduce without access to anyone's real network or accounts.

## Before opening a change

1. Search existing issues and pull requests.
2. Describe the user-visible problem and the smallest proposed solution.
3. Keep fixtures synthetic. Never commit subscription URLs, node lists, credentials, public IPs, raw logs, or unreviewed support bundles.
4. Add or update tests before changing behavior, then run the relevant PowerShell and POSIX verification entry points.
5. When behavior or user guidance changes, update the English document and its corresponding Chinese
   document in the same pull request, whether the pair is at the repository root or under `docs/`.

## Adapter proposals

Start the discussion with the repository's structured adapter proposal form so ownership, boundaries,
and verification evidence remain reviewable.

A new adapter or material adapter expansion must identify:

1. the device, firmware, runtime, and filesystem/service-manager boundary;
2. a named maintenance owner;
3. required capabilities and target support classification;
4. fail-closed probes, synthetic fixtures, backup, rollback, and recovery behavior;
5. diagnostics and support evidence that do not expose sensitive information;
6. licensing and third-party source obligations; and
7. bilingual operator guidance.

Keep the implementation external when those conditions are not yet met. Reference-implementation
status, similarity to an existing adapter, or one successful target does not establish verified adapter maturity or wider compatibility.

## Tests

Run the focused tests for the area you changed. Before requesting final review, run both local verification entry points sequentially:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1
sh scripts/verify-local.sh
```

If an entry point is unavailable in your environment, state that limitation and include the checks you did run. Do not replace fixtures that contain no sensitive or live data with real configuration or diagnostic data.

## Developer Certificate of Origin

Every commit must carry a Developer Certificate of Origin sign-off. Add it with `git commit --signoff` or include this trailer using your real name and an email address you are authorized to use:

```text
Signed-off-by: Your Name <your.email@example.com>
```

The name and email in the trailer become public, durable commit metadata. You may use a verified GitHub noreply address when the hosting service accepts it for the signed-off commit; otherwise use an address you are comfortable publishing.

By signing off, you certify that you have the right to submit the contribution under the project's Apache-2.0 license and the Developer Certificate of Origin 1.1.

## Pull requests

Keep pull requests narrow, explain verification evidence, identify user-facing documentation changes, and respond to review. Maintainers may ask for a change to be split when doing so makes security, licensing, or behavior easier to review.

Use the terminology defined in [Compatibility](docs/COMPATIBILITY.md) and
[Governance](GOVERNANCE.md). Code, documentation, repository metadata, release notes, and promotion
must not claim more maturity or support than the submitted evidence establishes.
