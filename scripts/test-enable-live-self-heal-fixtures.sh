#!/bin/sh
# Offline transaction tests for enable-live-self-heal-router.sh.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "/tmp/home-edge-enable-live-test.XXXXXX") || exit 1
cleanup() { case "$tmp" in /tmp/home-edge-enable-live-test.*) rm -rf "$tmp" ;; esac; }
trap cleanup EXIT HUP INT TERM
export HOME_EDGE_WRITE_LOCK_DIR="$tmp/write.lock"

fail() {
  echo "enable_live_self_heal_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/cru" <<'EOF'
#!/bin/sh
set -eu
state=${CRU_STATE:?}
case "${1:-}" in
  l) cat "$state" ;;
  d)
    next="$state.next.$$"
    grep -Fv "#${2:?}#" "$state" >"$next" || true
    mv "$next" "$state"
    ;;
  a)
    [ "${CRU_FAIL_ADD:-0}" != "1" ] || exit 19
    if [ -n "${CRU_CORRUPT_ADD_ONCE_FILE:-}" ] && [ ! -e "$CRU_CORRUPT_ADD_ONCE_FILE" ]; then
      : >"$CRU_CORRUPT_ADD_ONCE_FILE"
      printf '%s extra #%s#\n' "${3:?}" "${2:?}" >>"$state"
      exit 0
    fi
    printf '%s #%s#\n' "${3:?}" "${2:?}" >>"$state"
    ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$fakebin/cru"

prepare_case() {
  root=$1
  mkdir -p "$root/jffs/scripts"
  printf ': "${HEAL_CRON_DRY_RUN:=1}"\n' >"$root/jffs/scripts/home-edge-policy.env"
  printf 'HEAL_CRON_DRY_RUN=1\nSITE_VALUE=preserved\n' >"$root/jffs/scripts/home-edge-policy.local"
  : >"$root/cru.state"
  cp "$repo/scripts/reconcile-self-heal-registration.sh" "$root/jffs/scripts/home-edge-reconcile-self-heal.sh"
  cat >"$root/jffs/scripts/home-edge-self-heal-cron.sh" <<'EOF'
#!/bin/sh
[ "${ENABLE_FIXTURE_FAIL:-0}" = "1" ] && exit 17
exit 0
EOF
  chmod 755 "$root/jffs/scripts/home-edge-self-heal-cron.sh" "$root/jffs/scripts/home-edge-reconcile-self-heal.sh"
}

success_root="$tmp/success"
prepare_case "$success_root"
success_output=$(
  HOME_EDGE_ENABLE_ROOT="$success_root" \
  CRU_STATE="$success_root/cru.state" PATH="$fakebin:$PATH" \
  sh "$repo/scripts/enable-live-self-heal-router.sh"
)
printf '%s\n' "$success_output" | grep -q 'enable_live_state=enabled' || fail "success state missing"
grep -q '^HEAL_CRON_DRY_RUN=0$' "$success_root/jffs/scripts/home-edge-policy.local" || fail "live policy was not enabled"
grep -q '^SITE_VALUE=preserved$' "$success_root/jffs/scripts/home-edge-policy.local" || fail "site-local settings were not preserved"
ls "$success_root/jffs/scripts/home-edge-policy.local.bak."* >/dev/null 2>&1 || fail "success backup missing"
printf '%s\n' "$success_output" | grep -q '^self_heal_registration_state=ready$' || fail "success did not verify scheduler registration"
printf '%s\n' "$success_output" | grep -q '^self_heal_boot_hook_state=ready$' || fail "success did not verify boot registration"
[ "$(grep -c '#home_edge_selfheal#' "$success_root/cru.state")" -eq 1 ] || fail "success did not leave exactly one cron job"

failure_root="$tmp/failure"
prepare_case "$failure_root"
cat >"$failure_root/jffs/scripts/services-start" <<'EOF'
#!/bin/sh
echo exact-prior-user-hook
EOF
chmod 711 "$failure_root/jffs/scripts/services-start"
printf '%s\n' '17 4 * * * sh /jffs/scripts/home-edge-self-heal-cron.sh #home_edge_selfheal#' >"$failure_root/cru.state"
cp -p "$failure_root/jffs/scripts/services-start" "$tmp/failure-hook.before"
cp "$failure_root/cru.state" "$tmp/failure-cron.before"
if HOME_EDGE_ENABLE_ROOT="$failure_root" ENABLE_FIXTURE_FAIL=1 CRU_STATE="$failure_root/cru.state" PATH="$fakebin:$PATH" \
  sh "$repo/scripts/enable-live-self-heal-router.sh" >"$tmp/failure.out" 2>"$tmp/failure.err"; then
  fail "initial live run failure should propagate"
fi
grep -q 'enable_live_state=rolled_back' "$tmp/failure.out" || fail "rollback state missing"
grep -q '^HEAL_CRON_DRY_RUN=1$' "$failure_root/jffs/scripts/home-edge-policy.local" || fail "dry-run policy was not restored"
grep -q '^SITE_VALUE=preserved$' "$failure_root/jffs/scripts/home-edge-policy.local" || fail "site-local settings were not restored"
cmp -s "$failure_root/jffs/scripts/services-start" "$tmp/failure-hook.before" || fail "live wrapper failure did not exactly restore services-start"
cmp -s "$failure_root/cru.state" "$tmp/failure-cron.before" || fail "live wrapper failure did not exactly restore cron"

registration_failure_root="$tmp/registration-failure"
prepare_case "$registration_failure_root"
if HOME_EDGE_ENABLE_ROOT="$registration_failure_root" CRU_FAIL_ADD=1 CRU_STATE="$registration_failure_root/cru.state" PATH="$fakebin:$PATH" \
  sh "$repo/scripts/enable-live-self-heal-router.sh" >"$tmp/registration-failure.out" 2>"$tmp/registration-failure.err"; then
  fail "scheduler registration failure should propagate"
fi
grep -q 'enable_live_state=rolled_back' "$tmp/registration-failure.out" || fail "scheduler failure rollback state missing"
grep -q '^HEAL_CRON_DRY_RUN=1$' "$registration_failure_root/jffs/scripts/home-edge-policy.local" || fail "scheduler failure did not restore dry-run policy"

verification_failure_root="$tmp/registration-verification-failure"
prepare_case "$verification_failure_root"
cat >"$verification_failure_root/jffs/scripts/services-start" <<'EOF'
#!/bin/sh
echo verification-prior-hook
EOF
printf '%s\n' '11 3 * * * sh /jffs/scripts/home-edge-self-heal-cron.sh #home_edge_selfheal#' >"$verification_failure_root/cru.state"
cp -p "$verification_failure_root/jffs/scripts/services-start" "$tmp/verification-hook.before"
cp "$verification_failure_root/cru.state" "$tmp/verification-cron.before"
if HOME_EDGE_ENABLE_ROOT="$verification_failure_root" CRU_CORRUPT_ADD_ONCE_FILE="$tmp/corrupt-add.once" CRU_STATE="$verification_failure_root/cru.state" PATH="$fakebin:$PATH" \
  sh "$repo/scripts/enable-live-self-heal-router.sh" >"$tmp/registration-verification-failure.out" 2>"$tmp/registration-verification-failure.err"; then
  fail "scheduler registration verification failure should propagate"
fi
cmp -s "$verification_failure_root/jffs/scripts/services-start" "$tmp/verification-hook.before" || fail "registration verification failure did not restore hook"
cmp -s "$verification_failure_root/cru.state" "$tmp/verification-cron.before" || fail "registration verification failure did not restore cron"

interrupt_root="$tmp/atomic"
prepare_case "$interrupt_root"
HOME_EDGE_ENABLE_ROOT="$interrupt_root" CRU_STATE="$interrupt_root/cru.state" PATH="$fakebin:$PATH" sh "$repo/scripts/enable-live-self-heal-router.sh" >/dev/null
[ ! -e "$interrupt_root/jffs/scripts/home-edge-policy.local.tmp.$$" ] || fail "temporary policy residue remains"

echo "enable_live_self_heal_fixture_tests=ok"
