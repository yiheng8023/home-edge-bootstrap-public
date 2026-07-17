#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "/tmp/home-edge-enable-absent-policy-test.XXXXXX") || exit 1
cleanup() { case "$tmp" in /tmp/home-edge-enable-absent-policy-test.*) rm -rf "$tmp" ;; esac; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$tmp/bin"
export HOME_EDGE_WRITE_LOCK_DIR="$tmp/write.lock"

fail() { echo "enable_live_absent_policy_fixture_tests=failed" >&2; echo "$*" >&2; exit 1; }

cat >"$tmp/bin/cru" <<'EOF'
#!/bin/sh
set -eu
state=${CRU_STATE:?}
case "${1:-}" in
  l) cat "$state" ;;
  d) next="$state.next.$$"; grep -Fv "#${2:?}#" "$state" >"$next" || true; mv "$next" "$state" ;;
  a)
    if [ -n "${CRU_CORRUPT_ADD_ONCE_FILE:-}" ] && [ ! -e "$CRU_CORRUPT_ADD_ONCE_FILE" ]; then
      : >"$CRU_CORRUPT_ADD_ONCE_FILE"; printf '%s extra #%s#\n' "${3:?}" "${2:?}" >>"$state"; exit 0
    fi
    printf '%s #%s#\n' "${3:?}" "${2:?}" >>"$state" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$tmp/bin/cru"

prepare_case() {
  root=$1
  mkdir -p "$root/jffs/scripts" "$root/jffs/home-edge-bootstrap-state"
  printf ': "${HEAL_CRON_DRY_RUN:=1}"\n' >"$root/jffs/scripts/home-edge-policy.env"
  : >"$root/cru.state"
  cp "$repo/scripts/reconcile-self-heal-registration.sh" "$root/jffs/scripts/home-edge-reconcile-self-heal.sh"
  cat >"$root/jffs/scripts/home-edge-self-heal-cron.sh" <<'EOF'
#!/bin/sh
[ "${ENABLE_FIXTURE_FAIL:-0}" != 1 ]
EOF
  chmod 755 "$root/jffs/scripts/home-edge-reconcile-self-heal.sh" "$root/jffs/scripts/home-edge-self-heal-cron.sh"
  [ ! -e "$root/jffs/home-edge-bootstrap-state/policy.local" ] || fail "fixture policy unexpectedly exists"
}

wrapper_root="$tmp/wrapper"
prepare_case "$wrapper_root"
if HOME_EDGE_ENABLE_ROOT="$wrapper_root" ENABLE_FIXTURE_FAIL=1 CRU_STATE="$wrapper_root/cru.state" PATH="$tmp/bin:$PATH" sh "$repo/scripts/enable-live-self-heal-router.sh" >/dev/null 2>&1; then
  fail "live wrapper failure should propagate"
fi
[ ! -e "$wrapper_root/jffs/home-edge-bootstrap-state/policy.local" ] || fail "wrapper failure did not restore absent local policy"

verification_root="$tmp/verification"
prepare_case "$verification_root"
if HOME_EDGE_ENABLE_ROOT="$verification_root" CRU_CORRUPT_ADD_ONCE_FILE="$tmp/corrupt.once" CRU_STATE="$verification_root/cru.state" PATH="$tmp/bin:$PATH" sh "$repo/scripts/enable-live-self-heal-router.sh" >/dev/null 2>&1; then
  fail "registration verification failure should propagate"
fi
[ ! -e "$verification_root/jffs/home-edge-bootstrap-state/policy.local" ] || fail "registration failure did not restore absent local policy"

echo "enable_live_absent_policy_fixture_tests=ok"
