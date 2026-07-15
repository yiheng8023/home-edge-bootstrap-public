#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sut="$repo/scripts/subscription-runtime-evidence.sh"
tmp=$(mktemp -d "/tmp/home-edge-runtime-evidence-test.XXXXXX") || exit 1
cleanup() { case "$tmp" in /tmp/home-edge-runtime-evidence-test.*) rm -rf "$tmp" ;; esac; }
trap cleanup EXIT HUP INT TERM

fail() { echo "subscription_runtime_evidence_fixture_tests=failed" >&2; echo "$*" >&2; exit 1; }
state_from() { sed -n "s/^subscription_consumption_state=//p" "$1" | head -n 1; }
reason_from() { sed -n "s/^subscription_runtime_evidence_state=//p" "$1" | head -n 1; }
make_symlink() {
  target=$1 link=$2
  ln -s "$target" "$link"
  [ -L "$link" ] && return 0
  rm -rf "$link"
  return 1
}

[ -s "$sut" ] || fail "missing subscription runtime evidence classifier"
mkdir -p "$tmp/proc/41"
printf 'mihomo\n' >"$tmp/proc/41/comm"
printf 'mihomo\000-f\000%s\000' "$tmp/live.yaml" >"$tmp/proc/41/cmdline"
{
  printf '41 (mihomo) S'
  field=2
  while [ "$field" -lt 20 ]; do printf ' 0'; field=$((field + 1)); done
  printf ' 9000 0\n'
} >"$tmp/proc/41/stat"
printf 'btime 800\n' >"$tmp/proc/stat"
HOME_EDGE_PROC_ROOT="$tmp/proc" HOME_EDGE_CLK_TCK=100 sh "$sut" observe >"$tmp/observe.out"
grep -q '^runtime_process_identity=mihomo:41:9000$' "$tmp/observe.out" || { cat "$tmp/observe.out" >&2; fail "runtime identity observation missing"; }
grep -q '^runtime_process_start_epoch=890$' "$tmp/observe.out" || fail "runtime process start observation missing"
grep -Fq "runtime_active_config_path=$tmp/live.yaml" "$tmp/observe.out" || fail "runtime active config observation missing"

printf 'proxies:\n  - name: US\n' >"$tmp/cache.yaml"
cp "$tmp/cache.yaml" "$tmp/live.yaml"
digest=$(sha256sum "$tmp/cache.yaml" | awk '{print $1}')

write_evidence() {
  timestamp=$1 path=$2 evidence_digest=$3 identity=$4
  cat >"$tmp/evidence" <<EOF
runtime_subscription_evidence_state=reload_succeeded
runtime_subscription_apply_path=$path
runtime_subscription_cache_sha256=$evidence_digest
runtime_subscription_reload_timestamp=$timestamp
runtime_subscription_process_identity=$identity
EOF
}

run_classify() {
  HOME_EDGE_SUB_CACHE="$tmp/cache.yaml" HOME_EDGE_SUB_APPLY_PATH="$tmp/live.yaml" \
  HOME_EDGE_SUB_EVIDENCE="$classification_evidence" HOME_EDGE_RUNTIME_PROCESS_IDENTITY='mihomo:41:9000' \
  HOME_EDGE_RUNTIME_PROCESS_START_EPOCH=900 HOME_EDGE_EVIDENCE_MAX_AGE_SEC=300 HOME_EDGE_NOW_EPOCH=1000 \
  sh "$sut" classify >"$tmp/$1.out"
}

classification_evidence="$tmp/evidence"
platform_tmp_symlink=0
if [ -L /tmp ]; then
  platform_tmp_symlink=1
elif [ "${HOME_EDGE_FIXTURE_TMP_SYMLINK:-0}" = 1 ]; then
  classification_evidence="/tmp/not-home-edge-simulated-evidence-$$"
  platform_tmp_symlink=1
fi

if [ "$platform_tmp_symlink" = 1 ]; then
  write_evidence 950 "$tmp/live.yaml" "$digest" 'mihomo:41:9000'
  run_classify system_tmp_symlink
  [ "$(state_from "$tmp/system_tmp_symlink.out")" != runtime_profile_matches_cache ] || fail "symlinked system temporary root passed"
  [ "$(reason_from "$tmp/system_tmp_symlink.out")" = missing_or_unsafe ] || fail "symlinked system temporary root failed for the wrong reason"
  echo "subscription_runtime_evidence_semantics=skipped_platform_tmp_symlink"
  echo "subscription_runtime_evidence_fixture_tests=ok"
  exit 0
fi

write_evidence 600 "$tmp/live.yaml" "$digest" 'mihomo:41:9000'
run_classify expired
[ "$(state_from "$tmp/expired.out")" != runtime_profile_matches_cache ] || fail "expired attestation passed"

write_evidence 899 "$tmp/live.yaml" "$digest" 'mihomo:41:9000'
run_classify pre_process
[ "$(state_from "$tmp/pre_process.out")" != runtime_profile_matches_cache ] || fail "pre-process-start attestation passed"

write_evidence 950 "$tmp/other.yaml" "$digest" 'mihomo:41:9000'
run_classify wrong_path
[ "$(state_from "$tmp/wrong_path.out")" != runtime_profile_matches_cache ] || fail "wrong apply path passed"

write_evidence 950 "$tmp/live.yaml" "${digest%?}0" 'mihomo:41:9000'
run_classify wrong_digest
[ "$(state_from "$tmp/wrong_digest.out")" != runtime_profile_matches_cache ] || fail "wrong digest passed"

write_evidence 950 "$tmp/live.yaml" "$digest" 'mihomo:99:9000'
run_classify wrong_identity
[ "$(state_from "$tmp/wrong_identity.out")" != runtime_profile_matches_cache ] || fail "wrong process identity passed"

write_evidence 950 "$tmp/live.yaml" "$digest" 'mihomo:41:9000'
run_classify valid
[ "$(state_from "$tmp/valid.out")" = runtime_profile_matches_cache ] || fail "valid current attestation did not pass"

arbitrary="/tmp/not-home-edge-classifier-evidence-$$"
cp "$tmp/evidence" "$arbitrary"
HOME_EDGE_SUB_CACHE="$tmp/cache.yaml" HOME_EDGE_SUB_APPLY_PATH="$tmp/live.yaml" \
HOME_EDGE_SUB_EVIDENCE="$arbitrary" HOME_EDGE_RUNTIME_PROCESS_IDENTITY='mihomo:41:9000' \
HOME_EDGE_RUNTIME_PROCESS_START_EPOCH=900 HOME_EDGE_EVIDENCE_MAX_AGE_SEC=300 HOME_EDGE_NOW_EPOCH=1000 \
sh "$sut" classify >"$tmp/arbitrary.out"
rm -f "$arbitrary"
[ "$(state_from "$tmp/arbitrary.out")" != runtime_profile_matches_cache ] || fail "classifier accepted non-project-owned evidence path"

mkdir -p "$tmp/outside-parent"
cp "$tmp/evidence" "$tmp/outside-parent/evidence"
if make_symlink "$tmp/outside-parent" "$tmp/evidence-parent-link"; then
  HOME_EDGE_SUB_CACHE="$tmp/cache.yaml" HOME_EDGE_SUB_APPLY_PATH="$tmp/live.yaml" \
  HOME_EDGE_SUB_EVIDENCE="$tmp/evidence-parent-link/evidence" HOME_EDGE_RUNTIME_PROCESS_IDENTITY='mihomo:41:9000' \
  HOME_EDGE_RUNTIME_PROCESS_START_EPOCH=900 HOME_EDGE_EVIDENCE_MAX_AGE_SEC=300 HOME_EDGE_NOW_EPOCH=1000 \
  sh "$sut" classify >"$tmp/parent-link.out"
  [ "$(state_from "$tmp/parent-link.out")" != runtime_profile_matches_cache ] || fail "classifier accepted symlinked evidence parent"
else
  echo "subscription_classifier_parent_symlink_fixture=skipped_platform_no_symlink"
fi

cp "$tmp/evidence" "$tmp/evidence-target"
if make_symlink "$tmp/evidence-target" "$tmp/evidence-link"; then
  HOME_EDGE_SUB_CACHE="$tmp/cache.yaml" HOME_EDGE_SUB_APPLY_PATH="$tmp/live.yaml" \
  HOME_EDGE_SUB_EVIDENCE="$tmp/evidence-link" HOME_EDGE_RUNTIME_PROCESS_IDENTITY='mihomo:41:9000' \
  HOME_EDGE_RUNTIME_PROCESS_START_EPOCH=900 HOME_EDGE_EVIDENCE_MAX_AGE_SEC=300 HOME_EDGE_NOW_EPOCH=1000 \
  sh "$sut" classify >"$tmp/target-link.out"
  [ "$(state_from "$tmp/target-link.out")" != runtime_profile_matches_cache ] || fail "classifier accepted symlinked evidence target"
else
  echo "subscription_classifier_target_symlink_fixture=skipped_platform_no_symlink"
fi

echo "subscription_runtime_evidence_fixture_tests=ok"
