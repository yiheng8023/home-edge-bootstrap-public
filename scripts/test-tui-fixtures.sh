#!/bin/sh
# Offline contract tests for the POSIX guided TUI.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
find_cmd=$(command -v find) || exit 1
[ ! -x /usr/bin/find ] || find_cmd=/usr/bin/find
tmp_base=${TMPDIR:-/tmp}
if command -v cygpath >/dev/null 2>&1; then tmp_base=$(cygpath -u "$tmp_base"); fi
[ "$tmp_base" = "/" ] || tmp_base=${tmp_base%/}
tmp=$(mktemp -d "$tmp_base/home-edge-tui-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "tui_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

snapshot_project() {
  "$find_cmd" "$fake_repo" -type d -print
  "$find_cmd" "$fake_repo" -type f -exec cksum {} \;
}

tui="$repo/scripts/tui.sh"
[ -f "$tui" ] || fail "missing POSIX TUI entrypoint"

fake_repo="$tmp/portable copy & test"
mkdir -p "$fake_repo/scripts"
cp "$tui" "$fake_repo/scripts/tui.sh"
cp "$repo/start.sh" "$repo/start.command" "$fake_repo/"
mkdir -p "$fake_repo/scripts/lib" "$fake_repo/config" "$fake_repo/adapters/merlin"
cp "$repo/PROJECT" "$fake_repo/PROJECT"
echo fixture >"$fake_repo/README.md"
cp "$repo/scripts/lib/project-location.sh" "$fake_repo/scripts/lib/"
cp "$repo/scripts/lib/host-launcher.sh" "$fake_repo/scripts/lib/"
cp "$repo/scripts/launch-tui.sh" "$fake_repo/scripts/"
touch "$fake_repo/bootstrap.sh" "$fake_repo/config/policy.env" "$fake_repo/adapters/merlin/bootstrap.sh"
cat >"$fake_repo/scripts/create-desktop-shortcut.sh" <<'EOF'
#!/bin/sh
echo desktop-shortcut >>"$TUI_FIXTURE_CALL_LOG"
EOF
cat >"$fake_repo/scripts/doctor.sh" <<'EOF'
#!/bin/sh
printf 'doctor %s\n' "$*" >>"$TUI_FIXTURE_CALL_LOG"
if [ "${DOCTOR_STUB_REMOVE_PROJECT:-0}" = 1 ]; then rm "$(dirname "$0")/../PROJECT"; fi
if [ "${DOCTOR_STUB_REMOVE_BOOTSTRAP:-0}" = 1 ]; then rm "$(dirname "$0")/run-bootstrap.sh"; fi
if [ -n "${DOCTOR_STUB_REMOVE_TOOL:-}" ]; then rm "$DOCTOR_STUB_REMOVE_TOOL"; fi
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
cat >"$fake_repo/scripts/decommission-merlin.sh" <<'EOF'
#!/bin/sh
printf 'decommission-merlin %s\n' "$*" >>"$TUI_FIXTURE_CALL_LOG"
echo 'decommission_state=plan_ready'
EOF
cat >"$fake_repo/scripts/check-project-installation.sh" <<'EOF'
#!/bin/sh
printf 'project-probe %s\n' "$1" >>"$TUI_FIXTURE_CALL_LOG"
state=${PROJECT_STUB_STATE:-not_installed}
allowed=${PROJECT_STUB_ALLOWED:-}
[ -n "$allowed" ] || { case "$state" in installed|partial) allowed=1 ;; *) allowed=0 ;; esac; }
if [ "${PROJECT_STUB_CHANGE_ON_SECOND:-0}" = 1 ] && [ "$(grep -c '^project-probe ' "$TUI_FIXTURE_CALL_LOG")" -ge 2 ]; then PROJECT_STUB_PATH=/jffs/changed; fi
for pair in "schema=${PROJECT_STUB_SCHEMA:-1}" "router=${PROJECT_STUB_ROUTER:-$1}" "state=$state" 'reason=fixture_observation' "path=${PROJECT_STUB_PATH:-/jffs/home-edge-bootstrap}" "replace_allowed=$allowed"; do
  key=${pair%%=*}
  [ "$key" = "${PROJECT_STUB_OMIT:-}" ] || printf 'project_install_%s\n' "$pair"
  [ "$key" != "${PROJECT_STUB_DUPLICATE:-}" ] || printf 'project_install_%s\n' "$pair"
done
exit "${PROJECT_STUB_EXIT:-0}"
EOF
cat >"$fake_repo/scripts/deploy-merlin.sh" <<'EOF'
#!/bin/sh
printf 'deploy-merlin apply=%s replace_project=%s confirmation=%s router=%s path=%s\n' "$APPLY" "$BOOTSTRAP_REPLACE_PROJECT" "$BOOTSTRAP_PROJECT_CONFIRMATION" "$1" "$REMOTE_DIR" >>"$TUI_FIXTURE_CALL_LOG"
printf 'deploy-scope runtime=%s replace_runtime=%s replace_core=%s include_bundle=%s\n' "$BOOTSTRAP_INSTALL_RUNTIME" "$BOOTSTRAP_REPLACE_RUNTIME" "$BOOTSTRAP_REPLACE_CORE" "$INCLUDE_BUNDLE" >>"$TUI_FIXTURE_CALL_LOG"
if [ "$APPLY" = 1 ]; then echo deploy_state=applied; else echo deploy_state=plan; fi
printf 'router=%s\nremote_dir=%s\n' "$1" "$REMOTE_DIR"
if [ "$APPLY" != 1 ]; then echo 'runtime_assets_effect=preserve'; echo 'integration_effect=project_managed_configuration_may_change'; fi
EOF
chmod +x "$fake_repo/scripts/"*.sh

mv "$fake_repo/scripts/export-support-bundle.sh" "$fake_repo/scripts/export-support-bundle.sh.missing"
sh "$fake_repo/scripts/tui.sh" --help >/dev/null || fail "help should bypass startup prerequisites"
sh "$fake_repo/scripts/tui.sh" --version >/dev/null || fail "version should bypass startup prerequisites"
set +e
printf '0\n' | sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/startup-missing.out" 2>&1
startup_missing_status=$?
set -e
[ "$startup_missing_status" -eq 0 ] || fail "missing optional operation prevented menu startup"
set +e
printf '5\n0\n' | sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/unavailable.out" 2>&1
unavailable_status=$?
set -e
[ "$unavailable_status" -eq 2 ] || fail "missing selected capability did not return failure"
grep -Fq 'capability_state=unavailable' "$tmp/unavailable.out" || fail "missing selected capability was not explained"
mv "$fake_repo/scripts/export-support-bundle.sh.missing" "$fake_repo/scripts/export-support-bundle.sh"

printf '0\n' | sh "$fake_repo/scripts/tui.sh" --no-color >"$tmp/default.out"
printf '0\n' | sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/en.out"
sh "$fake_repo/scripts/tui.sh" --help >"$tmp/help.out"
(
  cd "$tmp"
  sh "$fake_repo/start.sh" --help >"$tmp/launcher-help.out"
  sh "$fake_repo/start.command" --version >"$tmp/launcher-version.out"
)
grep -Fq 'usage:' "$tmp/launcher-help.out" || fail "launcher requires caller to cd to package"
grep -Fxq 'home-edge-bootstrap development' "$tmp/launcher-version.out" || fail "macOS launcher did not resolve its own package"
sh "$fake_repo/scripts/tui.sh" --version >"$tmp/version.out"

grep -Fq '1. 开始或接续引导式配置' "$tmp/default.out" || fail "default menu is not Chinese"
grep -Fq '1. Start or resume guided bootstrap' "$tmp/en.out" || fail "English menu missing"
grep -Fq '7. 审查项目退出' "$tmp/default.out" || fail "Chinese decommission menu missing"
grep -Fq '7. Review project decommission' "$tmp/en.out" || fail "English decommission menu missing"
for number in 1 2 3 4 5 6 7 8 0; do
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
snapshot_project | LC_ALL=C sort >"$tmp/local-before.snapshot"
for alias in H '?' help 6; do
  : >"$call_log"
  printf '%s\n0\n' "$alias" | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/local-help.out"
  for expected in 'Home Edge local help' "project_dir=$fake_repo" "doc=$fake_repo/docs/RUNBOOK.md" 'First installation:' 'Already installed:' APPLY ENABLE DECOMMISSION EOF 'H / ? / help. Local help' '9 / L / language.'; do
    grep -Fq "$expected" "$tmp/local-help.out" || fail "local help missing $expected ($alias)"
  done
  [ ! -s "$call_log" ] || fail "help dispatched a child: $alias"
done
sh "$fake_repo/scripts/tui.sh" --lang en --help >"$tmp/cli-en-help.out"
grep -Fq 'Home Edge local help' "$tmp/cli-en-help.out" || fail "CLI English help missing"
grep -Fq 'Home Edge 本地帮助' "$tmp/help.out" || fail "CLI Chinese help missing"
for alias in L language 9; do
  : >"$call_log"
  printf '%s\nH\n%s\n?\n0\n' "$alias" "$alias" | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --no-color >"$tmp/language-toggle.out"
  for expected in 'language=en' 'language=zh-CN' 'Home Edge local help' 'Home Edge 本地帮助' '1. Start or resume guided bootstrap' '1. 开始或接续引导式配置'; do
    grep -Fq "$expected" "$tmp/language-toggle.out" || fail "toggle did not localize menu/help: $alias ($expected)"
  done
  [ ! -s "$call_log" ] || fail "language/help dispatched a child: $alias"
done
printf 'L\nhelp\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/english-to-chinese.out"
grep -Fq 'Home Edge 本地帮助' "$tmp/english-to-chinese.out" || fail "English-to-Chinese toggle/EOF failed"
printf 'invalid-choice\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/local-invalid.out"
grep -Fq 'Invalid selection.' "$tmp/local-invalid.out" || fail "invalid choice/EOF was not handled"
[ ! -s "$call_log" ] || fail "local choice dispatched a child"
snapshot_project | LC_ALL=C sort >"$tmp/local-after.snapshot"
cmp -s "$tmp/local-before.snapshot" "$tmp/local-after.snapshot" || fail "local help/language changed fixture project"

: >"$call_log"
printf '2\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/doctor.out"
grep -Fxq 'doctor --json' "$call_log" || fail "diagnosis did not dispatch doctor --json"
printf '8\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/desktop-choice.out"
grep -Fxq desktop-shortcut "$call_log" || fail "desktop setup was not delegated from the menu"

: >"$call_log"
printf '4\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/bundle.out"
grep -Fxq 'check-no-wall ' "$call_log" || fail "bundle verification dispatch mismatch"

: >"$call_log"
printf '5\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/support.out"
grep -Fxq 'support-bundle ' "$call_log" || fail "support bundle dispatch mismatch"

: >"$call_log"
printf '7\nWRONG\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/decommission-cancel.out"
grep -Eq '^decommission-merlin user@192\.168\.50\.1$' "$call_log" || fail "TUI omitted read-only decommission plan"
if grep -q -- '--apply' "$call_log"; then fail "wrong token enabled decommission"; fi

: >"$call_log"
printf '7\nDECOMMISSION\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/decommission-apply.out"
grep -Eq '^decommission-merlin user@192\.168\.50\.1$' "$call_log" || fail "TUI omitted decommission plan before apply"
grep -Eq '^decommission-merlin --apply --confirm DECOMMISSION user@192\.168\.50\.1$' "$call_log" || fail "exact token did not enable decommission"

: >"$call_log"
printf '7\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/decommission-eof.out"
grep -Eq '^decommission-merlin user@192\.168\.50\.1$' "$call_log" || fail "decommission EOF omitted read-only plan"
if grep -q -- '--apply' "$call_log"; then fail "EOF enabled decommission"; fi

: >"$call_log"
printf 'invalid-choice\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/invalid-choice.out"
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
grep -Fq "rollback_path='sh' '$fake_repo/scripts/rollback-merlin.sh' 'user@192.168.50.1'" "$tmp/apply.out" || fail "deploy rollback path did not bind its project and target"
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
grep -Fq "'sh' '$fake_repo/scripts/run-bootstrap.sh' '--no-pause' 'user@192.168.50.1'" "$tmp/child-error.out" || fail "safe resume command did not bind its project and target"

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

snapshot_project | LC_ALL=C sort >"$tmp/session-before.snapshot"
: >"$call_log"
printf '3\n2\nL\nH\n3\n9\nhelp\n3\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/switch-session.out"
[ "$(grep -c 'next_action_command=json-resume-command' "$tmp/switch-session.out")" -eq 3 ] || fail "language/help lost selected state"
[ "$(grep -c 'existing_session=2' "$tmp/switch-session.out")" -eq 1 ] || fail "language/help lost selected router/session"
[ ! -s "$call_log" ] || fail "language/help/session display dispatched a child"
snapshot_project | LC_ALL=C sort >"$tmp/session-after.snapshot"
cmp -s "$tmp/session-before.snapshot" "$tmp/session-after.snapshot" || fail "language/help/session changed fixture project"
printf 'L\nH\n9\n2\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --no-color --router user@192.168.50.1 >"$tmp/router-toggle.out"
grep -Fxq 'doctor --json user@192.168.50.1' "$call_log" || fail "language/help lost CLI router"

: >"$call_log"
runtime_tmp="$tmp/runtime-tmp"
mkdir -p "$runtime_tmp"
printf '3\n2\nL\nH\n9\n1\nWRONG\n0\n' | env TMPDIR="$runtime_tmp" TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --no-color >"$tmp/session-resume.out"
grep -Eq 'run-bootstrap --no-pause --session-dir .*/02-json json-user@192\.168\.50\.3' "$call_log" || fail "selected session did not infer router and preserve session directory"
grep -Fq "'sh' '$fake_repo/scripts/run-bootstrap.sh' '--no-pause' '--apply-deploy' '--session-dir' '$session_json' 'json-user@192.168.50.3'" "$tmp/session-resume.out" || fail "selected-session command did not bind its project, session and router"
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

# Installation observation and explicit project refresh are entirely stubbed.
: >"$call_log"
printf '1\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE=installed BOOTSTRAP_STUB_ACTION=deploy_plan sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/existing.out"
grep -Fq 'explicitly choose R' "$tmp/existing.out" || fail "existing default did not explain continuation"
if grep -Eq -- '--apply-deploy|deploy-merlin' "$call_log"; then fail "already installed default silently redeployed"; fi
for state in installed partial; do
  for inputs in 'R|WRONG|0' 'R|replace|0' 'R|REPLACE |0' 'R|REPLACE|WRONG|0' 'R|REPLACE|apply|0' 'R|REPLACE|APPLY |0' 'R' 'R|REPLACE'; do
    : >"$call_log"
    printf '%s\n' "$inputs" | tr '|' '\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE="$state" sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/refresh-cancel.out"
    if grep -Fq 'deploy-merlin apply=1' "$call_log"; then fail "refresh cancellation/EOF allowed a write ($state)"; fi
    grep -Fq 'project-probe user@192.168.50.1' "$call_log" || fail "refresh did not probe ($state)"
    grep -Fq 'deploy-merlin apply=0' "$call_log" || fail "refresh did not plan ($state)"
  done
  : >"$call_log"
  printf 'R\nREPLACE\nAPPLY\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE="$state" BOOTSTRAP_INSTALL_RUNTIME=1 BOOTSTRAP_REPLACE_RUNTIME=1 BOOTSTRAP_REPLACE_CORE=1 INCLUDE_BUNDLE=1 sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/refresh-apply.out"
  grep -Fxq 'deploy-merlin apply=1 replace_project=1 confirmation=REPLACE router=user@192.168.50.1 path=/jffs/home-edge-bootstrap' "$call_log" || fail "double confirmation did not refresh owned project ($state)"
  [ "$(grep -Fc 'deploy-scope runtime=0 replace_runtime=0 replace_core=0 include_bundle=0' "$call_log")" -eq 2 ] || fail "refresh inherited broader runtime scope ($state)"
  grep -Fq 'project_backup_path=/jffs/home-edge-bootstrap.prev' "$tmp/refresh-apply.out" || fail "refresh backup disclosure missing"
done
for bad_probe in PROJECT_STUB_STATE=unknown PROJECT_STUB_EXIT=1 PROJECT_STUB_SCHEMA=2 PROJECT_STUB_ROUTER=other@192.168.50.1 PROJECT_STUB_PATH=/jffs/../wrong PROJECT_STUB_STATE=unrecognized PROJECT_STUB_STATE=INSTALLED PROJECT_STUB_PATH=/JFFS/wrong PROJECT_STUB_ALLOWED=2 PROJECT_STUB_ALLOWED=0; do
  : >"$call_log"
  set +e
  printf 'R\nREPLACE\nAPPLY\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE=partial "$bad_probe" sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/blocked-refresh.out"
  set -e
  if grep -Eq 'deploy-merlin|run-bootstrap' "$call_log"; then fail "unknown/foreign installation enabled deployment ($bad_probe)"; fi
done
for key in schema router state reason path replace_allowed; do
  for format in PROJECT_STUB_DUPLICATE PROJECT_STUB_OMIT; do
    : >"$call_log"
    set +e
    printf 'R\nREPLACE\nAPPLY\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE=installed "$format=$key" sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/malformed-probe.out"
    set -e
    grep -Fq 'attention_state=invalid_installation_probe' "$tmp/malformed-probe.out" || fail "missing/duplicate critical probe field accepted: $key"
    if grep -q deploy-merlin "$call_log"; then fail "malformed probe enabled deployment: $key"; fi
  done
done
: >"$call_log"
printf 'R\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/not-installed-refresh.out"
grep -Fq 'Choose 1 for first installation' "$tmp/not-installed-refresh.out" || fail "R did not direct missing project to first installation"
if grep -q deploy-merlin "$call_log"; then fail "R interpreted missing project as replacement"; fi
for state in unknown partial installed; do
  : >"$call_log"
  set +e
  printf '1\nENABLE\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE="$state" PROJECT_STUB_ALLOWED=0 BOOTSTRAP_STUB_ACTION=enable_live_self_heal sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/unsafe-enable.out"
  set -e
  if grep -Eq -- '--enable-live-self-heal|--apply-deploy' "$call_log"; then fail "unknown/foreign/partial installation enabled write ($state)"; fi
done
: >"$call_log"
set +e
printf '1\nH\nL\n' | env TUI_FIXTURE_CALL_LOG="$call_log" BOOTSTRAP_STUB_EXIT=17 sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/failure-then-help.out"
help_after_failure_status=$?
set -e
[ "$help_after_failure_status" -eq 17 ] || fail "help/language erased the preceding child failure"
mv "$fake_repo/scripts/check-project-installation.sh" "$fake_repo/scripts/check-project-installation.sh.missing"
: >"$call_log"
set +e
printf '1\nH\nL\nR\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/missing-probe.out"
set -e
grep -Fq 'capability_state=unavailable' "$tmp/missing-probe.out" || fail "missing probe was not explained"
grep -Fq 'Home Edge local help' "$tmp/missing-probe.out" || fail "missing probe blocked local help"
[ ! -s "$call_log" ] || fail "missing probe dispatched an operation"
mv "$fake_repo/scripts/check-project-installation.sh.missing" "$fake_repo/scripts/check-project-installation.sh"

: >"$call_log"
printf 'R\nREPLACE\nAPPLY\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" PROJECT_STUB_STATE=installed PROJECT_STUB_CHANGE_ON_SECOND=1 sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/changed-probe.out"
grep -Fq 'attention_state=installation_probe_changed' "$tmp/changed-probe.out" || fail "changed refresh target path was accepted"
if grep -q 'deploy-merlin apply=1' "$call_log"; then fail "changed target path reached fake deploy apply"; fi

: >"$call_log"
set +e
printf '2\n1\nH\nL\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" DOCTOR_STUB_REMOVE_PROJECT=1 sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/removed-project.out"
set -e
grep -Fq 'condition_state=project_degraded' "$tmp/removed-project.out" || fail "removed PROJECT did not degrade current condition"
grep -Fq 'Home Edge local help' "$tmp/removed-project.out" || fail "removed PROJECT blocked loaded help"
grep -Fq 'language=zh-CN' "$tmp/removed-project.out" || fail "removed PROJECT blocked language switch"
if grep -q 'run-bootstrap ' "$call_log"; then fail "removed PROJECT reached bootstrap"; fi
cp "$repo/PROJECT" "$fake_repo/PROJECT"

cp "$fake_repo/scripts/run-bootstrap.sh" "$fake_repo/scripts/run-bootstrap.sh.saved"
: >"$call_log"
set +e
printf '1\nH\nL\n0\n' | env TUI_FIXTURE_CALL_LOG="$call_log" DOCTOR_STUB_REMOVE_BOOTSTRAP=1 sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/removed-operation.out"
set -e
grep -Fq 'capability_state=unavailable' "$tmp/removed-operation.out" || fail "removed child operation was not reported"
grep -Fq 'Home Edge local help' "$tmp/removed-operation.out" || fail "removed child operation blocked help"
if grep -q 'run-bootstrap ' "$call_log"; then fail "removed child operation was invoked"; fi
mv "$fake_repo/scripts/run-bootstrap.sh.saved" "$fake_repo/scripts/run-bootstrap.sh"

# Native private PATH only: removal cannot reveal another system copy or touch it.
case "$(uname -s)" in
  Linux|Darwin)
    tool_bin="$tmp/private-tools"
    mkdir "$tool_bin"
    for missing_tool in tee cat; do
      for fixture_tool in sh mktemp tee sed awk grep cat rm tr stat uname dirname env; do
        ln -s "$(command -v "$fixture_tool")" "$tool_bin/$fixture_tool"
      done
      : >"$call_log"
      set +e
      printf '2\n8\nH\nL\n0\n' | env PATH="$tool_bin" TUI_FIXTURE_CALL_LOG="$call_log" DOCTOR_STUB_REMOVE_TOOL="$tool_bin/$missing_tool" \
        /bin/sh "$fake_repo/scripts/tui.sh" --lang en --router user@192.168.50.1 >"$tmp/missing-$missing_tool.out" 2>"$tmp/missing-$missing_tool.err"
      missing_tool_status=$?
      set -e
      [ "$missing_tool_status" -eq 2 ] || fail "tool degradation did not retain failure status: $missing_tool"
      if ! grep -Fq "missing_prerequisite=$missing_tool" "$tmp/missing-$missing_tool.out"; then
        cat "$tmp/missing-$missing_tool.out" "$tmp/missing-$missing_tool.err" >&2
        fail "removed capture tool was not detected: $missing_tool"
      fi
      grep -Fq 'child_result_state=capture_unavailable' "$tmp/missing-$missing_tool.out" || fail "tool loss concealed child result uncertainty"
      grep -Fq 'Home Edge local help' "$tmp/missing-$missing_tool.out" || fail "removed tool blocked loaded help"
      grep -Fq 'language=zh-CN' "$tmp/missing-$missing_tool.out" || fail "removed tool blocked language switch"
      if grep -q 'desktop-shortcut' "$call_log"; then fail "tool degradation reached a write child: $missing_tool"; fi
      rm -f "$tool_bin"/*
    done
    ;;
esac
echo "tui_fixture_installation_guard_tests=ok"

echo "tui_fixture_tests=ok"
