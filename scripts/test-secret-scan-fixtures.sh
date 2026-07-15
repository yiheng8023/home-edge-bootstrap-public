#!/bin/sh
# Offline fixture tests for the conservative secret scanner.
set -eu
umask 077

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-secret-fixtures.XXXXXX") || exit 1
mkdir -p "$tmp/safe" "$tmp/leak"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "secret_scan_fixture_tests=failed"
  echo "$1"
  exit 1
}

cat >"$tmp/safe/template.txt" <<'EOF'
# Keep it non-secret: subscription URLs, tokens, and provider node lists stay local only.
subscription_url=${SUBSCRIPTION_URL:-}
token=REDACTED
uuid=REDACTED_UUID
proxy_uri=REDACTED_URL
EOF

if ! sh "$repo/scripts/scan-secrets.sh" "$tmp/safe" >"$tmp/safe.out" 2>&1; then
  cat "$tmp/safe.out"
  fail "safe_fixture_flagged"
fi
grep -q 'secret_scan_state=ready' "$tmp/safe.out" || fail "safe_fixture_missing_ready"

printf 'subscription_url=%s%s\n' \
  'https://provider.example/download/' \
  'abcdefghijklmnopqrstuvwxyz' >"$tmp/leak/subscription.txt"
if sh "$repo/scripts/scan-secrets.sh" "$tmp/leak" >"$tmp/leak-sub.out" 2>&1; then
  cat "$tmp/leak-sub.out"
  fail "subscription_fixture_not_flagged"
fi
grep -q 'secret_assignment' "$tmp/leak-sub.out" || fail "subscription_fixture_missing_label"

scheme="vmes"
printf '%s://%s\n' "${scheme}s" 'abcdefghijklmnopqrstuvwxyz0123456789' >"$tmp/leak/proxy.txt"
if sh "$repo/scripts/scan-secrets.sh" "$tmp/leak/proxy.txt" >"$tmp/leak-proxy.out" 2>&1; then
  cat "$tmp/leak-proxy.out"
  fail "proxy_fixture_not_flagged"
fi
grep -q 'proxy_uri' "$tmp/leak-proxy.out" || fail "proxy_fixture_missing_label"

printf -- '-----BEGIN %s PRIVATE KEY-----\n' 'OPENSSH' >"$tmp/leak/private-key.txt"
if sh "$repo/scripts/scan-secrets.sh" "$tmp/leak/private-key.txt" >"$tmp/leak-key.out" 2>&1; then
  cat "$tmp/leak-key.out"
  fail "private_key_fixture_not_flagged"
fi
grep -q 'private_key' "$tmp/leak-key.out" || fail "private_key_fixture_missing_label"

printf 'not-a-real-key\n' >"$tmp/leak/opaque.pem"
if sh "$repo/scripts/scan-secrets.sh" "$tmp/leak/opaque.pem" >"$tmp/leak-pem.out" 2>&1; then
  cat "$tmp/leak-pem.out"
  fail "sensitive_filename_not_flagged"
fi
grep -q 'sensitive_filename' "$tmp/leak-pem.out" || fail "sensitive_filename_missing_label"

echo "secret_scan_fixture_tests=ok"
