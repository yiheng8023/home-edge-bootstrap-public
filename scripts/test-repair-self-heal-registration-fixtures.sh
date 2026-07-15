#!/bin/sh
# Offline tests for host-side lifecycle registration repair. Never contacts a router.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-repair-registration-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "repair_self_heal_registration_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

mkdir -p "$tmp/bin"
cat >"$tmp/bin/ssh" <<'EOF'
#!/bin/sh
cat >"$REPAIR_FIXTURE_REMOTE_SCRIPT"
exit "${REPAIR_FIXTURE_SSH_EXIT:-0}"
EOF
chmod 755 "$tmp/bin/ssh"

PATH="$tmp/bin:$PATH" \
  REPAIR_FIXTURE_REMOTE_SCRIPT="$tmp/success.remote" \
  LOG_PATH="$tmp/success.log" \
  KNOWN_HOSTS_FILE="$tmp/success.known-hosts" \
  sh "$repo/scripts/repair-self-heal-registration.sh" user@router >"$tmp/success.out" 2>"$tmp/success.err" ||
  fail "successful fake SSH repair was rejected"

grep -Fq 'sh "$reconciler" --install' "$tmp/success.remote" ||
  fail "repair did not request idempotent lifecycle installation"

set +e
PATH="$tmp/bin:$PATH" \
  REPAIR_FIXTURE_REMOTE_SCRIPT="$tmp/failure.remote" \
  REPAIR_FIXTURE_SSH_EXIT=23 \
  LOG_PATH="$tmp/failure.log" \
  KNOWN_HOSTS_FILE="$tmp/failure.known-hosts" \
  sh "$repo/scripts/repair-self-heal-registration.sh" user@router >"$tmp/failure.out" 2>"$tmp/failure.err"
status=$?
set -e

[ "$status" -eq 23 ] || fail "SSH failure exit 23 was not preserved (got $status)"

echo "repair_self_heal_registration_fixture_tests=ok"
