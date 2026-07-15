#!/bin/sh
# Public source-tree verification. All invoked checks are local and fixture-based.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sbom_path="$repo/config/sbom.json"
sbom_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sbom) [ "$#" -ge 2 ] || { echo 'missing --sbom value' >&2; exit 2; }; sbom_path=$2; shift 2 ;;
    --sbom-only) sbom_only=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

py=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'; then
    py=$candidate
    break
  fi
done
[ -n "$py" ] || { echo 'local_verification_error=python3_required_python2_unsupported' >&2; exit 1; }

verify_sbom() {
  "$py" - "$1" <<'PY'
import json
import pathlib
import sys

sbom = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if (sbom.get("spdxVersion"), sbom.get("dataLicense"), sbom.get("SPDXID")) != ("SPDX-2.3", "CC0-1.0", "SPDXRef-DOCUMENT"):
    raise SystemExit("invalid SPDX document identity")
if len(sbom.get("packages", [])) != 3:
    raise SystemExit("invalid SPDX package structure")
actual_relationships = sorted([
    (r.get("spdxElementId"), r.get("relationshipType"), r.get("relatedSpdxElement"))
    for r in sbom.get("relationships", [])
])
expected_relationships = sorted([
    ("SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-Package-Source"),
    ("SPDXRef-Package-Mihomo", "OPTIONAL_COMPONENT_OF", "SPDXRef-Package-Source"),
    ("SPDXRef-Package-ShellCrash", "OPTIONAL_COMPONENT_OF", "SPDXRef-Package-Source"),
])
if actual_relationships != expected_relationships:
    raise SystemExit("invalid SPDX relationship triples")
PY
}

if [ "$sbom_only" -eq 1 ]; then
  verify_sbom "$sbom_path"
  echo 'sbom_structure_state=ready'
  exit 0
fi

echo '# Public Local Verification'
echo 'verification_network_boundary=local_only'

for script in "$repo"/scripts/*.sh; do [ -f "$script" ] && sh -n "$script"; done
sh -n "$repo/bootstrap.sh"
echo 'sh_syntax=ok'

if command -v pwsh >/dev/null 2>&1; then
  HOME_EDGE_PUBLIC_REPO="$repo" pwsh -NoProfile -Command '$root=$env:HOME_EDGE_PUBLIC_REPO; Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.ps1" | ForEach-Object { $t=$null; $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e)|Out-Null; if($e.Count){throw "PowerShell parse failed: $($_.Name)"} }; Write-Host "ps1_parse=ok"'
elif command -v powershell >/dev/null 2>&1; then
  HOME_EDGE_PUBLIC_REPO="$repo" powershell -NoProfile -ExecutionPolicy Bypass -Command '$root=$env:HOME_EDGE_PUBLIC_REPO; Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.ps1" | ForEach-Object { $t=$null; $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e)|Out-Null; if($e.Count){throw "PowerShell parse failed: $($_.Name)"} }; Write-Host "ps1_parse=ok"'
else
  echo 'ps1_parse=skipped_no_powershell'
fi

echo 'python3_runtime_state=ready'

for fixture in \
  test-host-ssh-fixtures.sh \
  test-self-heal-fixtures.sh \
  test-enable-live-self-heal-fixtures.sh \
  test-merlin-adapter-fixtures.sh \
  test-bundle-fixtures.sh \
  test-rollback-fixtures.sh \
  test-subscription-fixtures.sh \
  test-client-topology-fixtures.sh \
  test-installation-closeout-client-fixtures.sh \
  test-edge-health-fixtures.sh \
  test-doctor-fixtures.sh \
  test-router-status-fixtures.sh \
  test-run-bootstrap-fixtures.sh \
  test-tui-fixtures.sh \
  test-guide-router-fixtures.sh \
  test-deployment-provenance-fixtures.sh \
  test-deploy-fixtures.sh \
  test-secret-scan-fixtures.sh \
  test-support-bundle-fixtures.sh \
  test-third-party-compliance-fixtures.sh \
  test-public-release-fixtures.sh
do
  [ -f "$repo/scripts/$fixture" ] || { echo "missing required POSIX fixture: $fixture" >&2; exit 1; }
  sh "$repo/scripts/$fixture"
done

sh "$repo/scripts/verify-compatibility-matrix.sh"
sh "$repo/scripts/scan-secrets.sh" "$repo"
sh "$repo/scripts/verify-media-kit.sh" --root "$repo"

for file in LICENSE NOTICE THIRD_PARTY_NOTICES.md; do [ -f "$repo/$file" ] || { echo "missing license material: $file" >&2; exit 1; }; done
grep -Fq 'Apache License' "$repo/LICENSE"
grep -Fq 'Version 2.0' "$repo/LICENSE"
for fact in Mihomo ShellCrash GPL-3.0-only; do grep -Fq "$fact" "$repo/THIRD_PARTY_NOTICES.md"; done
echo 'license_material_state=ready'

verify_sbom "$sbom_path"

"$py" - "$repo" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
required = [
    ".github/workflows/verify.yml", ".github/workflows/release-candidate.yml",
    "README.md", "README.zh-CN.md", "QUICKSTART.md", "QUICKSTART.zh-CN.md",
    "docs/COMPATIBILITY.md", "docs/zh-CN/COMPATIBILITY.md", "docs/RELEASE_NOTES.md", "docs/zh-CN/RELEASE_NOTES.md",
    "docs/RELEASE_READINESS.md", "docs/zh-CN/RELEASE_READINESS.md", "docs/PUBLIC_RELEASE.md", "docs/zh-CN/PUBLIC_RELEASE.md",
    "config/compatibility-matrix.json", "config/sbom.json", "config/third-party-lock.json", "config/public-release-files.txt",
]
for rel in required:
    if not (root / rel).is_file(): raise SystemExit(f"missing public closeout path: {rel}")
language_navigation = {
    "README.md": "English | [简体中文](README.zh-CN.md)",
    "README.zh-CN.md": "[English](README.md) | 简体中文",
}
for rel, expected in language_navigation.items():
    lines = (root / rel).read_text(encoding="utf-8").splitlines()
    if len(lines) < 3 or lines[2] != expected:
        raise SystemExit(f"invalid README language navigation: {rel}")
official_references = (
    "https://www.asuswrt-merlin.net/about",
    "https://www.asuswrt-merlin.net/download",
    "https://www.asus.com/global/support/download-center/",
    "https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation",
    "https://sourceforge.net/projects/asuswrt-merlin/files/",
)
router_references = {
    "README.md": "docs/ROUTER_BASELINE.md",
    "README.zh-CN.md": "docs/zh-CN/ROUTER_BASELINE.md",
    "QUICKSTART.md": "docs/ROUTER_BASELINE.md",
    "QUICKSTART.zh-CN.md": "docs/zh-CN/ROUTER_BASELINE.md",
}
for rel, baseline in router_references.items():
    text = (root / rel).read_text(encoding="utf-8")
    for expected in (*official_references, baseline):
        if expected not in text:
            raise SystemExit(f"missing router reference in {rel}: {expected}")
for rel in ("docs/ROUTER_BASELINE.md", "docs/zh-CN/ROUTER_BASELINE.md"):
    text = (root / rel).read_text(encoding="utf-8")
    for expected in official_references:
        if expected not in text:
            raise SystemExit(f"missing official router reference in {rel}: {expected}")
prebootstrap_references = (
    "https://www.asuswrt-merlin.net/about",
    "https://www.asuswrt-merlin.net/download",
    "https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation",
    "https://sourceforge.net/projects/asuswrt-merlin/files/",
)
for rel in ("docs/NO_WALL_BOOTSTRAP.md", "docs/zh-CN/NO_WALL_BOOTSTRAP.md"):
    text = (root / rel).read_text(encoding="utf-8")
    for expected in prebootstrap_references:
        if expected not in text:
            raise SystemExit(f"missing pre-bootstrap firmware reference in {rel}: {expected}")
link_re = re.compile(r"\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)")
for doc in root.rglob("*.md"):
    for target in link_re.findall(doc.read_text(encoding="utf-8")):
        if re.match(r"^(?:https?://|mailto:|#)", target): continue
        if not (doc.parent / target).exists(): raise SystemExit(f"broken documentation link: {doc} -> {target}")
if (root / ".github/FUNDING.yml").exists():
    raise SystemExit("unexpected funding configuration")
sponsorship_refs = (
    "https://www.paypal.com/ncp/payment/LNTF8KXGJXMZY",
    "docs/assets/sponsoring/wechat-pay.png",
    "docs/assets/sponsoring/alipay.png",
)
for rel in ("README.md", "README.zh-CN.md"):
    text = (root / rel).read_text(encoding="utf-8")
    for expected in sponsorship_refs:
        if expected not in text:
            raise SystemExit(f"missing sponsorship reference in {rel}: {expected}")
expected_assets = {
    "docs/assets/sponsoring/wechat-pay.png": "d8c213f1539cad6c9fd23099736aecd06c722129af24f77fe9f26563bbb9a05e",
    "docs/assets/sponsoring/alipay.png": "491ee27d52797818f1cca756560bc239cf6150fe3327b0fd31728f7ce53327cd",
}
for rel, expected in expected_assets.items():
    path = root / rel
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit(f"invalid sponsorship asset: {rel}")
PY
echo 'readme_language_navigation_state=ready'
echo 'router_reference_discoverability_state=ready'
echo 'sponsorship_surface_state=ready'
echo 'sbom_structure_state=ready'
echo 'release_fixture_state=ready'
echo 'public_media_kit_state=ready'
echo 'public_closeout_structure_state=ready'
echo 'local_verification_state=ready'
