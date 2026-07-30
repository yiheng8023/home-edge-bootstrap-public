#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-dns-test.XXXXXX") || exit 1
trap 'case "$tmp" in */home-edge-dns-test.*) rm -rf "$tmp" ;; esac' EXIT HUP INT TERM

fail() {
  echo "shellcrash_dns_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

shellcrash="$tmp/ShellCrash"
state="$tmp/state"
runtime="$tmp/runtime.yaml"
validator="$tmp/mihomo"
validator_args="$tmp/mihomo.args"
mkdir -p "$shellcrash/yamls" "$shellcrash/ruleset" "$state"

cat >"$runtime" <<'EOF'
mixed-port: 7890
external-controller: :9999
secret: REDACTED
experimental: {ignore-resolve-fail: true, interface-name: en0}
dns:
  enable: true
  listen: :1053
  use-hosts: true
  ipv6: false
  default-nameserver:
    - 223.5.5.5
    - 2400:3200::1
  direct-nameserver: [ 127.0.0.1 ]
  enhanced-mode: fake-ip
  fake-ip-range: 28.0.0.0/8
  fake-ip-filter:
    - '*'
    - "rule-set:cn"
  respect-rules: true
  nameserver-policy:
    'rule-set:cn':
      - 127.0.0.1
  proxy-server-nameserver:
    - 223.5.5.5
    - 2400:3200::1
  nameserver:
    - 1.1.1.1
    - 8.8.8.8
  fallback:
    - tls://1.1.1.1
  fallback-filter:
    geoip: true
proxies:
  - name: fixture
    type: http
rules:
  - MATCH,fixture
EOF

cat >"$validator" <<'EOF'
#!/bin/sh
[ -z "${DNS_VALIDATOR_ARGS_LOG:-}" ] || printf '%s\n' "$@" >"$DNS_VALIDATOR_ARGS_LOG"
exit "${DNS_VALIDATOR_STATUS:-0}"
EOF
chmod 755 "$validator"

run_dns() {
  HOME_EDGE_SHELLCRASH_DIR="$shellcrash" \
  HOME_EDGE_STATE_ROOT="$state" \
  HOME_EDGE_DNS_RUNTIME_CONFIG="$runtime" \
  HOME_EDGE_DNS_MIHOMO_BIN="$validator" \
  HOME_EDGE_DNS_MIHOMO_DATA_DIR="$shellcrash" \
  DNS_VALIDATOR_ARGS_LOG="$validator_args" \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  "$@" sh "$repo/scripts/configure-shellcrash-dns.sh"
}

plan_output=$(run_dns env HOME_EDGE_DNS_ACTION=plan)
printf '%s\n' "$plan_output" | grep -q '^dns_candidate_validation=ok$' ||
  fail "DNS plan did not validate"
printf '%s\n' "$plan_output" | grep -q '^dns_override_state=planned$' ||
  fail "DNS plan marker missing"
[ ! -e "$shellcrash/yamls/user.yaml" ] || fail "DNS plan changed user.yaml"
[ "$(sed -n '1p' "$validator_args")" = "-d" ] ||
  fail "DNS semantic validator did not receive -d"
[ "$(sed -n '2p' "$validator_args")" = "$shellcrash" ] ||
  fail "DNS semantic validator received the wrong data directory"

apply_output=$(run_dns env HOME_EDGE_DNS_ACTION=apply)
printf '%s\n' "$apply_output" | grep -q '^dns_override_state=applied$' ||
  fail "DNS apply marker missing"
user_yaml="$shellcrash/yamls/user.yaml"
[ -s "$user_yaml" ] || fail "DNS apply did not create user.yaml"
grep -Fxq '# BEGIN home-edge-bootstrap shellcrash-user-dns/v1' "$user_yaml" ||
  fail "DNS override begin marker missing"
grep -Fxq '# END home-edge-bootstrap shellcrash-user-dns/v1' "$user_yaml" ||
  fail "DNS override end marker missing"
! grep -q 'interface-name:' "$user_yaml" || fail "DNS override retained fixed interface binding"
! grep -q 'nameserver-policy:' "$user_yaml" || fail "DNS override retained CN resolver policy"
! grep -Eq '^  (fallback|fallback-filter):' "$user_yaml" ||
  fail "DNS override retained fallback resolvers"
grep -Fq 'https://1.1.1.1/dns-query' "$user_yaml" ||
  fail "DNS override did not install secure resolvers"
grep -Fqx '  default-nameserver: [ "https://223.5.5.5/dns-query", "https://1.12.12.12/dns-query" ]' "$user_yaml" ||
  fail "DNS override did not install encrypted local bootstrap resolvers"
grep -Fqx '  direct-nameserver: [ "https://223.5.5.5/dns-query", "https://1.12.12.12/dns-query" ]' "$user_yaml" ||
  fail "DNS override did not replace the loop-prone direct resolver"
grep -Fqx '  proxy-server-nameserver: [ "https://223.5.5.5/dns-query", "https://1.12.12.12/dns-query" ]' "$user_yaml" ||
  fail "DNS override did not install encrypted node bootstrap resolvers"
! grep -q '127\.0\.0\.1' "$user_yaml" ||
  fail "DNS override retained a loop-prone localhost resolver"
grep -q '^  direct-nameserver-follow-policy: false$' "$user_yaml" ||
  fail "DNS override did not preserve direct resolver separation"
grep -q '^    - \"rule-set:cn\"$' "$user_yaml" ||
  fail "DNS override did not preserve the generated fake-IP filter"
! grep -q '^secret:' "$user_yaml" || fail "DNS override copied a controller secret"

status_output=$(run_dns env HOME_EDGE_DNS_ACTION=status)
printf '%s\n' "$status_output" | grep -q '^dns_override_state=applied$' ||
  fail "DNS status did not recognize the installed override"

rollback_output=$(run_dns env HOME_EDGE_DNS_ACTION=rollback)
printf '%s\n' "$rollback_output" | grep -q '^dns_override_state=rolled_back$' ||
  fail "DNS rollback marker missing"
[ ! -e "$user_yaml" ] || fail "DNS rollback did not restore the originally absent user.yaml"

cat >"$user_yaml" <<'EOF'
profile:
  store-selected: true
  store-fake-ip: true
experimental:
  quic-go-disable-gso: true
dns:
  enable: false
  nameserver:
    - 8.8.8.8
EOF
cp "$user_yaml" "$tmp/unmanaged-user.before"
apply_existing_output=$(run_dns env HOME_EDGE_DNS_ACTION=apply)
printf '%s\n' "$apply_existing_output" | grep -q '^dns_override_state=applied$' ||
  fail "DNS apply did not compose with an existing user.yaml"
grep -q '^profile:$' "$user_yaml" || fail "DNS apply removed the existing profile section"
grep -q '^  store-selected: true$' "$user_yaml" || fail "DNS apply changed the existing profile section"
grep -q '^experimental:$' "$user_yaml" || fail "DNS apply removed an unrelated experimental section"
grep -q '^  quic-go-disable-gso: true$' "$user_yaml" ||
  fail "DNS apply changed an unrelated experimental option"
[ "$(grep -c '^dns:' "$user_yaml")" -eq 1 ] || fail "DNS apply left duplicate top-level DNS sections"
! grep -q '8.8.8.8' "$user_yaml" || fail "DNS apply retained an unmanaged plaintext upstream"

rollback_existing_output=$(run_dns env HOME_EDGE_DNS_ACTION=rollback)
printf '%s\n' "$rollback_existing_output" | grep -q '^dns_override_state=rolled_back$' ||
  fail "DNS rollback did not report the existing-file rollback"
cmp -s "$user_yaml" "$tmp/unmanaged-user.before" ||
  fail "DNS rollback did not restore the exact pre-existing user.yaml"

cp "$user_yaml" "$tmp/validator-rejection.before"
if run_dns env HOME_EDGE_DNS_ACTION=apply DNS_VALIDATOR_STATUS=1 \
  >"$tmp/validator-rejection.out" 2>"$tmp/validator-rejection.err"; then
  fail "DNS apply accepted a Mihomo-rejected candidate"
fi
grep -q 'Mihomo rejected the DNS override' "$tmp/validator-rejection.err" ||
  fail "Mihomo semantic rejection message missing"
cmp -s "$user_yaml" "$tmp/validator-rejection.before" ||
  fail "Mihomo semantic rejection changed user.yaml"

if [ -e /dev/full ]; then
  cp "$user_yaml" "$tmp/state-commit.before"
  if run_dns env HOME_EDGE_DNS_ACTION=apply HOME_EDGE_DNS_STATE_FILE=/dev/full \
    >"$tmp/state-commit.out" 2>"$tmp/state-commit.err"; then
    fail "DNS apply accepted a failed state commit"
  fi
  grep -q 'cannot commit DNS state; restored prior user.yaml' "$tmp/state-commit.err" ||
    fail "DNS state-commit rollback message missing"
  cmp -s "$user_yaml" "$tmp/state-commit.before" ||
    fail "DNS state-commit failure did not restore prior user.yaml"
fi

echo "shellcrash_dns_fixture_tests=ok"
