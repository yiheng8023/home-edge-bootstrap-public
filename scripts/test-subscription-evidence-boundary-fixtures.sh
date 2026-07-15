#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_base=${TMPDIR:-/tmp}
[ "$tmp_base" = / ] || tmp_base=${tmp_base%/}
tmp=$(mktemp -d "$tmp_base/home-edge-evidence-boundary-test.XXXXXX") || exit 1
arbitrary="/tmp/not-home-edge-runtime-evidence-$$"
owned="/tmp/home-edge-evidence-boundary-$$"
trap 'rm -rf "$tmp" "$owned"; rm -f "$arbitrary"' EXIT HUP INT TERM
mkdir -p "$tmp/bin" "$tmp/cache" "$tmp/backups" "$tmp/apply" "$owned/target"

fail() { echo "subscription_evidence_boundary_fixture_tests=failed" >&2; echo "$*" >&2; exit 1; }

make_symlink() {
  target=$1 link=$2
  ln -s "$target" "$link"
  [ -L "$link" ] && return 0
  rm -rf "$link"
  return 1
}

cat >"$tmp/bin/curl" <<'EOF'
#!/bin/sh
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o|--output) shift; output=${1:?} ;; esac
  shift || break
done
[ -n "$output" ] || exit 2
cat >"$output" <<'YAML'
mixed-port: 7890
proxies:
  - name: United States
    type: ss
    server: 127.0.0.1
    port: 443
YAML
EOF
cat >"$tmp/bin/mihomo" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$tmp/bin/curl" "$tmp/bin/mihomo"
printf 'https://provider.invalid/subscription\n' >"$tmp/SUBSCRIPTION.local"
printf 'arbitrary-sentinel\n' >"$arbitrary"

run_update() {
  evidence=$1
  PATH="$tmp/bin:$PATH" CURL_BIN="$tmp/bin/curl" SUBSCRIPTION_MIHOMO_BIN="$tmp/bin/mihomo" \
  SUBSCRIPTION_FILE="$tmp/SUBSCRIPTION.local" SUBSCRIPTION_CACHE="$tmp/cache/subscription.yaml" \
  SUBSCRIPTION_BACKUP_DIR="$tmp/backups" SUBSCRIPTION_APPLY_PATH="$tmp/apply/live.yaml" \
  SUBSCRIPTION_APPLY_ROOT="$tmp/apply" SUBSCRIPTION_RUNTIME_EVIDENCE="$evidence" \
  SUBSCRIPTION_RELOAD_CMD=true SUBSCRIPTION_DRY_RUN=0 SUBSCRIPTION_MIN_BYTES=1 \
  SUBSCRIPTION_LOCK_DIR="$tmp/write.lock" SUBSCRIPTION_LOG="$tmp/update.log" \
  sh "$repo/scripts/update-sub.sh" >"$tmp/run.out" 2>"$tmp/run.err"
}

if run_update "$arbitrary"; then fail "arbitrary evidence path was accepted"; fi
grep -q 'SUBSCRIPTION_RUNTIME_EVIDENCE' "$tmp/run.err" || { cat "$tmp/run.err" >&2; fail "arbitrary evidence path failed for the wrong reason"; }
[ "$(cat "$arbitrary")" = arbitrary-sentinel ] || fail "arbitrary evidence file was mutated"

if make_symlink "$owned/target" "$owned/link"; then
  if run_update "$owned/link/runtime.evidence"; then fail "symlinked evidence parent was accepted"; fi
  grep -qi 'symlink' "$tmp/run.err" || { cat "$tmp/run.err" >&2; fail "symlinked evidence parent failed for the wrong reason"; }
  [ ! -e "$owned/target/runtime.evidence" ] || fail "symlinked evidence parent was traversed"
else
  echo "subscription_evidence_parent_symlink_fixture=skipped_platform_no_symlink"
fi

printf 'target-sentinel\n' >"$owned/target-file"
if make_symlink "$owned/target-file" "$owned/runtime.evidence"; then
  if run_update "$owned/runtime.evidence"; then fail "symlinked evidence target was accepted"; fi
  grep -qi 'symlink' "$tmp/run.err" || { cat "$tmp/run.err" >&2; fail "symlinked evidence target failed for the wrong reason"; }
  [ "$(cat "$owned/target-file")" = target-sentinel ] || fail "symlinked evidence target was mutated"
else
  echo "subscription_evidence_target_symlink_fixture=skipped_platform_no_symlink"
fi

echo "subscription_evidence_boundary_fixture_tests=ok"
