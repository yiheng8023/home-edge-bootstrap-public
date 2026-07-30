#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_base=${TMPDIR:-/tmp}
[ "$tmp_base" = / ] || tmp_base=${tmp_base%/}
tmp=$(mktemp -d "$tmp_base/home-edge-evidence-boundary-test.XXXXXX") || exit 1
arbitrary="/tmp/not-home-edge-runtime-evidence-$$"
owned="/tmp/home-edge-evidence-boundary-$$"
tty_writer=""
tty_reader=""
cleanup() {
  [ -z "$tty_reader" ] || kill "$tty_reader" 2>/dev/null || true
  [ -z "$tty_writer" ] || kill "$tty_writer" 2>/dev/null || true
  rm -rf "$tmp" "$owned"
  rm -f "$arbitrary"
}
trap cleanup EXIT HUP INT TERM
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

if command -v mkfifo >/dev/null 2>&1; then
  store_sut="$repo/scripts/store-subscription.sh"
  cat >"$tmp/bin/stty" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${STTY_FIXTURE_LOG:?}"
case "${1:-}" in -g) printf '%s\n' original-state ;; esac
EOF
  cat >"$tmp/bin/ssh" <<'EOF'
#!/bin/sh
echo "store-subscription fixture unexpectedly reached ssh" >&2
exit 99
EOF
  chmod 755 "$tmp/bin/stty" "$tmp/bin/ssh"
  tty_fifo="$tmp/subscription-input.fifo"
  tty_log="$tmp/stty.log"
  mkfifo "$tty_fifo"
  (sleep 60) >"$tty_fifo" &
  tty_writer=$!
  HOME_EDGE_STDIN_IS_TTY=1 STTY_FIXTURE_LOG="$tty_log" PATH="$tmp/bin:$PATH" \
    sh "$store_sut" user@router.invalid <"$tty_fifo" >"$tmp/store.out" 2>"$tmp/store.err" &
  tty_reader=$!
  attempt=0
  while [ "$attempt" -lt 100 ] && ! grep -Fxq -- '-echo' "$tty_log" 2>/dev/null; do
    attempt=$((attempt + 1))
    sleep 0.05
  done
  grep -Fxq -- '-echo' "$tty_log" || fail "interactive subscription fixture did not disable terminal echo"
  kill -TERM "$tty_reader"
  if wait "$tty_reader"; then
    fail "terminated interactive subscription prompt returned success"
  fi
  tty_reader=""
  kill "$tty_writer" 2>/dev/null || true
  wait "$tty_writer" 2>/dev/null || true
  tty_writer=""
  grep -Fxq original-state "$tty_log" ||
    fail "terminated interactive subscription prompt did not restore terminal state"
else
  echo "subscription_tty_restore_fixture=skipped_no_mkfifo"
fi

echo "subscription_evidence_boundary_fixture_tests=ok"
