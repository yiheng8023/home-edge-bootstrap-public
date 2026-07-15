#!/bin/sh
# Offline deployment provenance tests. Does not contact a router.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-provenance-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "deployment_provenance_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

source_root="$tmp/source"
stage="$tmp/stage"
active="$tmp/active"
mkdir -p "$source_root" "$stage/scripts" "$stage/config" "$active"
printf '%s\n' '#!/bin/sh' 'echo managed' >"$stage/scripts/self-heal.sh"
printf '%s\n' '#!/bin/sh' 'echo update' >"$stage/scripts/update-sub.sh"
printf '%s\n' '#!/bin/sh' 'echo runtime-evidence' >"$stage/scripts/subscription-runtime-evidence.sh"
printf '%s\n' '#!/bin/sh' 'echo verify' >"$stage/scripts/verify-bundle.sh"
printf '%s\n' '#!/bin/sh' 'echo reconcile' >"$stage/scripts/reconcile-self-heal-registration.sh"
printf '%s\n' 'HEAL_DRY_RUN=1' >"$stage/config/policy.env"
printf '%s\n' 'private-marker-must-not-print' >"$stage/README.md"
cp "$stage/scripts/self-heal.sh" "$active/home-edge-self-heal.sh"
cp "$stage/scripts/update-sub.sh" "$active/home-edge-update-sub.sh"
cp "$stage/scripts/subscription-runtime-evidence.sh" "$active/home-edge-subscription-runtime-evidence.sh"
cp "$stage/scripts/verify-bundle.sh" "$active/home-edge-verify-bundle.sh"
cp "$stage/scripts/reconcile-self-heal-registration.sh" "$active/home-edge-reconcile-self-heal.sh"
cp "$stage/config/policy.env" "$active/home-edge-policy.env"

git -C "$source_root" init -q
git -C "$source_root" config user.email fixture@example.invalid
git -C "$source_root" config user.name fixture
git -C "$source_root" config core.autocrlf false
printf '%s\n' source >"$source_root/source.txt"
git -C "$source_root" add source.txt
git -C "$source_root" commit -qm baseline
source_commit=$(git -C "$source_root" rev-parse HEAD)

sh "$repo/scripts/new-deployment-provenance.sh" "$stage" "$source_root"
[ -s "$stage/DEPLOYMENT-PROVENANCE.env" ] || fail "missing provenance metadata"
[ -s "$stage/DEPLOYMENT-CONTENT-SHA256SUMS" ] || fail "missing provenance checksums"
grep -q '^schema_version=1$' "$stage/DEPLOYMENT-PROVENANCE.env" || fail "schema missing"
grep -q '^source_kind=git$' "$stage/DEPLOYMENT-PROVENANCE.env" || fail "git source kind missing"
grep -q "^source_commit=$source_commit$" "$stage/DEPLOYMENT-PROVENANCE.env" || fail "source commit mismatch"
content_id=$(sed -n 's/^content_id=//p' "$stage/DEPLOYMENT-PROVENANCE.env")
[ "$content_id" = "$(sha256sum "$stage/DEPLOYMENT-CONTENT-SHA256SUMS" | awk '{print $1}')" ] || fail "content id does not hash actual checksum bytes"
(cd "$stage" && sha256sum -c DEPLOYMENT-CONTENT-SHA256SUMS >/dev/null) || fail "staged bytes do not match provenance"

match_output=$(HOME_EDGE_INSTALL_DIR="$stage" HOME_EDGE_ROUTER_SCRIPT_DIR="$active" HOME_EDGE_EXPECTED_SOURCE_KIND=git HOME_EDGE_EXPECTED_SOURCE_COMMIT="$source_commit" sh "$repo/scripts/verify-deployment-provenance.sh")
printf '%s\n' "$match_output" | grep -q '^deployment_provenance_state=match$' || fail "matching deployment not reported"
printf '%s\n' "$match_output" | grep -q "^deployment_source_commit=$source_commit$" || fail "safe source commit missing"
printf '%s\n' "$match_output" | grep -q "^deployment_content_id=$content_id$" || fail "safe content id missing"
if printf '%s\n' "$match_output" | grep -q 'private-marker\|README.md\|home-edge-self-heal'; then fail "verification leaked content or managed paths"; fi

unknown_output=$(HOME_EDGE_INSTALL_DIR="$stage" HOME_EDGE_ROUTER_SCRIPT_DIR="$active" HOME_EDGE_EXPECTED_SOURCE_KIND=unknown sh "$repo/scripts/verify-deployment-provenance.sh")
printf '%s\n' "$unknown_output" | grep -q '^deployment_provenance_state=unavailable$' || fail "unbound expected source was reported as a match"

rm -f "$active/home-edge-subscription-runtime-evidence.sh"
missing_helper_output=$(HOME_EDGE_INSTALL_DIR="$stage" HOME_EDGE_ROUTER_SCRIPT_DIR="$active" HOME_EDGE_EXPECTED_SOURCE_KIND=git HOME_EDGE_EXPECTED_SOURCE_COMMIT="$source_commit" sh "$repo/scripts/verify-deployment-provenance.sh")
printf '%s\n' "$missing_helper_output" | grep -q '^deployment_provenance_state=drift$' || fail "missing deployed runtime evidence helper was not reported as drift"
cp "$stage/scripts/subscription-runtime-evidence.sh" "$active/home-edge-subscription-runtime-evidence.sh"

printf '%s\n' '# drift' >>"$active/home-edge-subscription-runtime-evidence.sh"
helper_drift_output=$(HOME_EDGE_INSTALL_DIR="$stage" HOME_EDGE_ROUTER_SCRIPT_DIR="$active" HOME_EDGE_EXPECTED_SOURCE_KIND=git HOME_EDGE_EXPECTED_SOURCE_COMMIT="$source_commit" sh "$repo/scripts/verify-deployment-provenance.sh")
printf '%s\n' "$helper_drift_output" | grep -q '^deployment_provenance_state=drift$' || fail "drifted deployed runtime evidence helper was not reported as drift"
cp "$stage/scripts/subscription-runtime-evidence.sh" "$active/home-edge-subscription-runtime-evidence.sh"

printf '%s\n' '# drift' >>"$active/home-edge-self-heal.sh"
drift_output=$(HOME_EDGE_INSTALL_DIR="$stage" HOME_EDGE_ROUTER_SCRIPT_DIR="$active" HOME_EDGE_EXPECTED_SOURCE_KIND=git HOME_EDGE_EXPECTED_SOURCE_COMMIT="$source_commit" sh "$repo/scripts/verify-deployment-provenance.sh")
printf '%s\n' "$drift_output" | grep -q '^deployment_provenance_state=drift$' || fail "active drift not detected"

rm -f "$stage/DEPLOYMENT-PROVENANCE.env"
missing_output=$(HOME_EDGE_INSTALL_DIR="$stage" HOME_EDGE_ROUTER_SCRIPT_DIR="$active" sh "$repo/scripts/verify-deployment-provenance.sh")
printf '%s\n' "$missing_output" | grep -q '^deployment_provenance_state=missing$' || fail "missing provenance not reported"

echo "deployment_provenance_fixture_tests=ok"
