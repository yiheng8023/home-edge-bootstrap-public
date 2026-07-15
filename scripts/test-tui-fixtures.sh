#!/bin/sh
# Offline contract tests for the POSIX guided TUI.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
find_cmd=$(command -v find) || exit 1
[ ! -x /usr/bin/find ] || find_cmd=/usr/bin/find
tmp_base=${TMPDIR:-/tmp}
[ "$tmp_base" = "/" ] || tmp_base=${tmp_base%/}
tmp=$(mktemp -d "$tmp_base/home-edge-tui-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "tui_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

tui="$repo/scripts/tui.sh"
[ -f "$tui" ] || fail "missing POSIX TUI entrypoint"

fake_repo="$tmp/repo"
mkdir -p "$fake_repo/scripts"
cp "$tui" "$fake_repo/scripts/tui.sh"
cat >"$fake_repo/scripts/doctor.sh" <<'EOF'
#!/bin/sh
printf 'doctor %s\n' "$*" >>"$TUI_FIXTURE_CALL_LOG"
echo '{"doctor_state":"ready","next_action_code":"monitor_live_managed"}'
exit "${DOCTOR_STUB_EXIT:-0}"
EOF
cat >"$fake_repo/scripts/run-bootstrap.sh" <<'EOF'
#!/bin/sh
printf 'run-bootstrap %s\n' "$*" >>"$TUI_FIXTURE_CALL_LOG"
if [ "${BOOTSTRAP_STUB_MALFORMED:-0}" = 1 ]; then
  echo 'not-machine-readable-state'
  exit 0
fi
echo 'bootstrap_state=waiting_manual'
echo "next_action_code=${BOOTSTRAP_STUB_ACTION:-monitor_live_managed}"
echo 'next_action_command=resume-command'
echo 'session_dir=/fixture/session'
echo 'log_path=/fixture/bootstrap.log'
case " $* " in
  *' --apply-deploy '*|*' --enable-live-self-heal '*) exit "${BOOTSTRAP_STUB_WRITE_EXIT:-0}" ;;
esac
exit "${BOOTSTRAP_STUB_EXIT:-0}"
EOF
cat >"$fake_repo/scripts/check-no-wall-readiness.sh" <<'EOF'
#!/bin/sh
printf 'check-no-wall %s\n' "$*" >>"$TUI_FIXTURE_CALL_LOG"
echo 'bundle_state=verified'
EOF
cat >"$fake_repo/scripts/export-support-bundle.sh" <<'EOF'
#!/bin/sh
printf 'support-bundle %s\n' "$*" >>"$TUI_FIXTURE_CALL_LOG"
echo 'support_bundle_state=ready'
EOF
chmod +x "$fake_repo/scripts/"*.sh

mv "$fake_repo/scripts/export-support-bundle.sh" "$fake_repo/scripts/export-support-bundle.sh.missing"
sh "$fake_repo/scripts/tui.sh" --help >/dev/null || fail "help should bypass startup prerequisites"
sh "$fake_repo/scripts/tui.sh" --version >/dev/null || fail "version should bypass startup prerequisites"
set +e
printf '0\n' | sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/startup-missing.out" 2>&1
startup_missing_status=$?
set -e
[ "$startup_missing_status" -eq 2 ] || fail "missing startup prerequisite should exit 2"
grep -Fq 'startup_state=failed' "$tmp/startup-missing.out" || fail "missing startup prerequisite was not reported"
mv "$fake_repo/scripts/export-support-bundle.sh.missing" "$fake_repo/scripts/export-support-bundle.sh"

printf '0\n' | sh "$fake_repo/scripts/tui.sh" --no-color >"$tmp/default.out"
printf '0\n' | sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/en.out"
sh "$fake_repo/scripts/tui.sh" --help >"$tmp/help.out"
sh "$fake_repo/scripts/tui.sh" --version >"$tmp/version.out"

grep -Fq '1. 开始或接续引导式配置' "$tmp/default.out" || fail "default menu is not Chinese"
grep -Fq '1. Start or resume guided bootstrap' "$tmp/en.out" || fail "English menu missing"
for number in 1 2 3 4 5 6 0; do
  grep -Eq "^$number\\. " "$tmp/default.out" || fail "default menu missing action $number"
  grep -Eq "^$number\\. " "$tmp/en.out" || fail "English menu missing action $number"
done
grep -Fq 'usage:' "$tmp/help.out" || fail "help output missing usage"
grep -Fxq 'home-edge-bootstrap development' "$tmp/version.out" || fail "development version output mismatch"

set +e
sh "$fake_repo/scripts/tui.sh" --lang invalid </dev/null >"$tmp/invalid.out" 2>"$tmp/invalid.err"
invalid_status=$?
set -e
[ "$invalid_status" -eq 2 ] || fail "invalid language should exit 2"

: >"$tmp/router-injection-calls.log"
set +e
env TUI_FIXTURE_CALL_LOG="$tmp/router-injection-calls.log" sh "$fake_repo/scripts/tui.sh" --lang en --router 'user@router;echo-INJECTED' </dev/null >"$tmp/router-injection.out" 2>&1
router_injection_status=$?
set -e
[ "$router_injection_status" -eq 2 ] || fail "unsafe router target should exit 2"
[ ! -s "$tmp/router-injection-calls.log" ] || fail "unsafe router target dispatched a child"

if LC_ALL=C grep "$(printf '\033')" "$tmp/default.out" "$tmp/en.out" >/dev/null 2>&1; then
  fail "no-color output contains ANSI escapes"
fi

call_log="$tmp/calls.log"
: >"$call_log"
printf '2\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/doctor.out"
grep -Fxq 'doctor --json' "$call_log" || fail "diagnosis did not dispatch doctor --json"

: >"$call_log"
printf '4\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/bundle.out"
grep -Fxq 'check-no-wall ' "$call_log" || fail "bundle verification dispatch mismatch"

: >"$call_log"
printf '5\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/support.out"
grep -Fxq 'support-bundle ' "$call_log" || fail "support bundle dispatch mismatch"

: >"$call_log"
printf '9\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/invalid-choice.out"
[ ! -s "$call_log" ] || fail "invalid choice dispatched a child"

: >"$call_log"
printf '0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/exit.out"
[ ! -s "$call_log" ] || fail "exit dispatched a child"

: >"$call_log"
env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color </dev/null >"$tmp/eof.out"
[ ! -s "$call_log" ] || fail "EOF dispatched a child"

: >"$call_log"
printf '1\nWRONG\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/apply-cancel.out"
grep -Eq '^run-bootstrap --no-pause user@192\.168\.50\.1$' "$call_log" || fail "bootstrap read-only pass missing"
if grep -q -- '--apply-deploy' "$call_log"; then fail "wrong token enabled deploy"; fi

for wrong_token in apply 'APPLY ' yes; do
  : >"$call_log"
  printf '1\n%s\n0\n' "$wrong_token" | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/apply-semantic-cancel.out"
  if grep -q -- '--apply-deploy' "$call_log"; then fail "non-exact token enabled deploy: $wrong_token"; fi
done

: >"$call_log"
printf '1\nAPPLY\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/apply.out"
grep -Eq '^run-bootstrap --no-pause user@192\.168\.50\.1$' "$call_log" || fail "bootstrap read-only pass missing before deploy"
grep -Eq '^run-bootstrap --no-pause --apply-deploy user@192\.168\.50\.1$' "$call_log" || fail "APPLY token did not enable deploy"
grep -Fq 'expected_effect=apply_reviewed_deployment_plan' "$tmp/apply.out" || fail "deploy effect was not disclosed"
grep -Fq 'rollback_path=sh scripts/rollback-merlin.sh' "$tmp/apply.out" || fail "deploy rollback path was not disclosed"
grep -Fq 'session_destination=/fixture/session' "$tmp/apply.out" || fail "session destination was not disclosed"
grep -Fq 'log_destination=/fixture/bootstrap.log' "$tmp/apply.out" || fail "log destination was not disclosed"

: >"$call_log"
printf '1\nENABLE\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=enable_live_self_heal sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/enable.out"
grep -Eq '^run-bootstrap --no-pause --enable-live-self-heal user@192\.168\.50\.1$' "$call_log" || fail "ENABLE token did not enable live self-heal"

: >"$call_log"
set +e
printf '1\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_EXIT=17 sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/child-error.out"
child_error_status=$?
set -e
grep -Fq 'child_exit_code=17' "$tmp/child-error.out" || fail "child exit code was not preserved"
[ "$child_error_status" -eq 17 ] || fail "TUI process did not exit with the last child failure"
grep -Fq 'failed_action=bootstrap_read_only' "$tmp/child-error.out" || fail "failed action was not reported"
grep -Fq 'safe_resume_command=sh scripts/run-bootstrap.sh' "$tmp/child-error.out" || fail "safe resume command was not reported"

: >"$call_log"
set +e
printf '1\nAPPLY\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan BOOTSTRAP_STUB_WRITE_EXIT=19 sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/write-error.out"
write_error_status=$?
set -e
[ "$write_error_status" -eq 19 ] || fail "write failure was not returned by TUI"
grep -Fq 'failed_action=apply_deploy' "$tmp/write-error.out" || fail "write failure action missing"
grep -Fq 'write_action_started=true' "$tmp/write-error.out" || fail "write start was not reported"

: >"$call_log"
printf '1\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=unexpected_action sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/unknown-child.out"
grep -Fq 'attention_state=unknown_next_action' "$tmp/unknown-child.out" || fail "unknown child state was not conservative"
if grep -Eq -- '--apply-deploy|--enable-live-self-heal' "$call_log"; then fail "unknown child state unlocked a write action"; fi

: >"$call_log"
printf '1\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_MALFORMED=1 sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/malformed-child.out"
grep -Fq 'attention_state=malformed_child_state' "$tmp/malformed-child.out" || fail "malformed child state was not conservative"

session_env="$fake_repo/logs/bootstrap/01-env"
session_json="$fake_repo/logs/bootstrap/02-json"
session_unknown="$fake_repo/logs/bootstrap/03-unknown"
session_bad="$fake_repo/logs/bootstrap/04-bad"
session_unsafe="$fake_repo/logs/bootstrap/05-bad;name"
mkdir -p "$session_env" "$session_json" "$session_unknown" "$session_bad" "$session_unsafe"
cat >"$session_env/state.env" <<'EOF'
bootstrap_state=waiting_manual
router=env-user@192.168.50.2
next_action_code=deploy_plan
next_action_command=resume-command
session_dir=/fixture/env-session
log_dir=/fixture/logs
log_path=/fixture/env.log
EOF
malicious_marker="$tmp/state-was-executed"
printf 'updated_at=$(touch %s)\n' "$malicious_marker" >>"$session_env/state.env"
cat >"$session_json/state.json" <<'EOF'
{
  "bootstrap_state": "waiting_manual",
  "router": "json-user@192.168.50.3",
  "next_action_code": "monitor_live_managed",
  "next_action_command": "json-resume-command",
  "session_dir": "/fixture/json-session",
  "log_path": "/fixture/json.log"
}
EOF
cat >"$session_unknown/state.env" <<'EOF'
bootstrap_state=waiting_manual
router=unknown-user@192.168.50.4
next_action_code=future_action
next_action_command=future-command
EOF
printf '%s\n' '{not-json' >"$session_bad/state.json"
cat >"$session_unsafe/state.env" <<'EOF'
bootstrap_state=waiting_manual
router=unsafe-session@192.168.50.5
next_action_code=deploy_plan
EOF

: >"$call_log"
printf '3\n1\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-env.out"
grep -Fq 'existing_session=1' "$tmp/session-env.out" || fail "existing sessions were not listed"
grep -Fq 'router=env-user@192.168.50.2' "$tmp/session-env.out" || fail "state.env router was not read"
grep -Fq 'log_path=/fixture/env.log' "$tmp/session-env.out" || fail "state.env log path was not preserved"
[ ! -e "$malicious_marker" ] || fail "state.env content was executed"
[ ! -s "$call_log" ] || fail "session display dispatched a child"

: >"$call_log"
printf '3\n2\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-json.out"
grep -Fq 'router=json-user@192.168.50.3' "$tmp/session-json.out" || fail "state.json router was not read"
grep -Fq 'next_action_command=json-resume-command' "$tmp/session-json.out" || fail "state.json resume command was not preserved"

: >"$call_log"
runtime_tmp="$tmp/runtime-tmp"
mkdir -p "$runtime_tmp"
printf '1\n2\nWRONG\n0\n' | env TMPDIR="$runtime_tmp" TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-resume.out"
grep -Eq 'run-bootstrap --no-pause --session-dir .*/02-json json-user@192\.168\.50\.3' "$call_log" || fail "selected session did not infer router and preserve session directory"
grep -Fq "exact_command=sh scripts/run-bootstrap.sh --no-pause --apply-deploy --session-dir 'logs/bootstrap/02-json' json-user@192.168.50.3" "$tmp/session-resume.out" || fail "copyable selected-session command was not safely repository-relative"
if "$find_cmd" "$runtime_tmp" -type f -name 'home-edge-tui-*' | grep -q .; then fail "TUI temporary capture files were not cleaned"; fi

: >"$call_log"
printf '3\n3\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-unknown.out"
grep -Fq 'attention_state=unknown_session_state' "$tmp/session-unknown.out" || fail "unknown session state was not conservative"

: >"$call_log"
printf '3\n4\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-bad.out"
grep -Fq 'attention_state=malformed_session_state' "$tmp/session-bad.out" || fail "malformed session state was not conservative"
[ ! -s "$call_log" ] || fail "malformed session dispatched a child"

: >"$call_log"
printf '1\n5\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-unsafe.out"
grep -Fq 'attention_state=malformed_session_state' "$tmp/session-unsafe.out" || fail "unsafe session directory was accepted"
[ ! -s "$call_log" ] || fail "unsafe session directory dispatched a child"

: >"$call_log"
printf '1\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/apply-eof.out"
if grep -q -- '--apply-deploy' "$call_log"; then fail "EOF enabled deploy"; fi

if command -v mkfifo >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  : >"$call_log"
  fifo="$tmp/interrupt.input"
  mkfifo "$fifo"
  (printf '1\n'; sleep 5) >"$fifo" & writer=$!
  set +e
  timeout --preserve-status -s INT 2 env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 <"$fifo" >"$tmp/interrupt.out" 2>&1
  interrupt_status=$?
  set -e
  kill "$writer" 2>/dev/null || true
  wait "$writer" 2>/dev/null || true
  [ "$interrupt_status" -ne 0 ] || fail "INT should exit nonzero"
  if grep -q -- '--apply-deploy' "$call_log"; then fail "INT enabled deploy"; fi
fi

echo "tui_fixture_tests=ok"
