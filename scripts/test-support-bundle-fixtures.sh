#!/bin/sh
# Offline behavior tests for redacted support bundle export.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp="${TMPDIR:-/tmp}/home-edge-support-fixture.$$"
find_cmd=find
if [ -x /usr/bin/find ]; then
  find_cmd=/usr/bin/find
fi
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/git" <<'EOF'
#!/bin/sh
printf -- '-----BEGIN %s PRIVATE KEY-----\n' 'OPENSSH'
printf '%s\n' 'fixture-private-key-material'
printf -- '-----END %s PRIVATE KEY-----\n' 'OPENSSH'
EOF
chmod +x "$fake_bin/git"

fail() {
  echo "support_bundle_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

output=$(
  CLIENT_TOPOLOGY_FIXTURE_OS=linux \
  CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY=192.168.50.1 \
  CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE=unknown \
  CLIENT_TOPOLOGY_FIXTURE_TUN_STATE=unknown \
  CLIENT_TOPOLOGY_FIXTURE_DNS_STATE=unknown \
  CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE=ok:204 \
  HOST_SSH_FIXTURE_AGENT_STATE=identities_loaded \
  HOST_SSH_FIXTURE_DEFAULT_KEY_STATE=present \
  HOST_SSH_FIXTURE_ROUTER_SSH_STATE=ok \
  PATH="$fake_bin:$PATH" \
  OUTPUT_DIR="$tmp" \
  sh "$repo/scripts/export-support-bundle.sh"
)

bundle_dir=$(printf '%s\n' "$output" | awk -F= '$1 == "support_bundle_dir" { print $2; exit }')
[ -n "$bundle_dir" ] && [ -d "$bundle_dir" ] || fail "support bundle directory was not created"

for name in manifest.txt closeout.txt no-wall-readiness.txt doctor.txt host-ssh.txt client-topology.txt edge-health.txt router-status.txt; do
  [ -f "$bundle_dir/$name" ] || fail "missing support bundle file: $name"
done

if "$find_cmd" "$bundle_dir" -type f \( -name '*.raw' -o -name '*.raw.log' \) | grep -q .; then
  fail "raw support files were left behind"
fi

grep -q '^client_runtime_present=unknown$' "$bundle_dir/client-topology.txt" || fail "support bundle did not preserve unknown client runtime evidence"
grep -R -q '^REDACTED_PRIVATE_KEY$' "$bundle_dir" || fail "support bundle did not redact the private key block"
private_begin=$(printf -- '-----BEGIN %s PRIVATE KEY-----' 'OPENSSH')
private_end=$(printf -- '-----END %s PRIVATE KEY-----' 'OPENSSH')
if grep -R -F -q -e "$private_begin" -e 'fixture-private-key-material' -e "$private_end" "$bundle_dir"; then
  fail "support bundle retained private key material"
fi

sh "$repo/scripts/scan-secrets.sh" "$bundle_dir" >/dev/null

echo "support_bundle_fixture_tests=ok"
