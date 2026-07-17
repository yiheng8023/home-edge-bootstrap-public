#!/bin/sh
# Offline fake-SSH tests for the POSIX decommission host wrapper.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
wrapper="$repo/scripts/decommission-merlin.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-decommission-host-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fakebin="$tmp/bin"
ssh_log="$tmp/ssh.log"
payload="$tmp/payload.tgz"
mkdir -p "$fakebin"
: >"$ssh_log"

fail() {
  echo "decommission_host_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

cat >"$fakebin/ssh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${DECOMMISSION_SSH_LOG:?}"
cat >"${DECOMMISSION_SSH_PAYLOAD:?}"
echo 'decommission_state=plan_ready'
exit "${DECOMMISSION_SSH_EXIT:-0}"
EOF
chmod 755 "$fakebin/ssh"

[ -f "$wrapper" ] || fail "missing POSIX decommission wrapper"

DECOMMISSION_SSH_LOG="$ssh_log" DECOMMISSION_SSH_PAYLOAD="$payload" PATH="$fakebin:$PATH" \
  sh "$wrapper" user@192.168.50.1 --known-hosts-file "$tmp/known_hosts" >"$tmp/plan.out"
grep -Fq 'DECOMMISSION_APPLY=0' "$ssh_log" || fail "POSIX plan did not stream apply=0"
grep -Fq 'user@192.168.50.1' "$ssh_log" || fail "POSIX plan omitted router target"
[ -s "$payload" ] || fail "POSIX plan omitted tar payload"
tar -tzf "$payload" | tr -d '\r' | sort >"$tmp/archive.list"
printf '%s\n' decommission-router-state.sh migrate-router-state.sh | sort >"$tmp/archive.expected"
cmp "$tmp/archive.expected" "$tmp/archive.list" >/dev/null || fail "POSIX payload contained files outside the two-script allowlist"

calls_before=$(wc -l <"$ssh_log" | tr -d ' ')
set +e
DECOMMISSION_SSH_LOG="$ssh_log" DECOMMISSION_SSH_PAYLOAD="$payload" PATH="$fakebin:$PATH" \
  sh "$wrapper" user@192.168.50.1 --apply --confirm WRONG >"$tmp/wrong.out" 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail "POSIX wrong confirmation did not exit 2"
calls_after=$(wc -l <"$ssh_log" | tr -d ' ')
[ "$calls_after" -eq "$calls_before" ] || fail "POSIX wrong confirmation contacted SSH"

: >"$ssh_log"
DECOMMISSION_SSH_LOG="$ssh_log" DECOMMISSION_SSH_PAYLOAD="$payload" PATH="$fakebin:$PATH" \
  sh "$wrapper" user@192.168.50.1 --apply --confirm DECOMMISSION --known-hosts-file "$tmp/known_hosts" >"$tmp/apply.out"
grep -Fq 'DECOMMISSION_APPLY=1' "$ssh_log" || fail "POSIX apply did not stream apply=1"
grep -Fq 'DECOMMISSION_CONFIRMATION=DECOMMISSION' "$ssh_log" || fail "POSIX apply omitted exact confirmation"

: >"$ssh_log"
set +e
DECOMMISSION_SSH_LOG="$ssh_log" DECOMMISSION_SSH_PAYLOAD="$payload" PATH="$fakebin:$PATH" \
  sh "$wrapper" 'user@router;unsafe' >"$tmp/invalid.out" 2>&1
invalid_status=$?
set -e
[ "$invalid_status" -eq 2 ] || fail "POSIX invalid router did not exit 2"
[ ! -s "$ssh_log" ] || fail "POSIX invalid router contacted SSH"

echo "decommission_host_fixture_tests=ok"
