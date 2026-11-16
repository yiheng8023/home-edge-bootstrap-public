#!/bin/sh
# Offline adapter tests: mock controller/core/parser processes at their boundary;
# yamlbridge's actual transformation and collisions are tested in Go.
set -eu
umask 077
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/home-edge-service-setup-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/bin" "$tmp/state" "$tmp/runtime" "$tmp/yamls"
if [ -n "${SERVICE_HEALTH_FIXTURE_JQ:-}" ]; then
  cp "$SERVICE_HEALTH_FIXTURE_JQ" "$tmp/bin/jq"
  chmod 700 "$tmp/bin/jq"
fi
PATH=$tmp/bin:$PATH
export PATH
which jq >/dev/null 2>&1 || { echo 'fixture requires jq' >&2; exit 1; }
fail() { echo "service_health_setup_fixture_tests=failed: $*" >&2; exit 1; }
export FIXTURE_ROOT=$tmp
cat >"$tmp/bin/pidof" <<'EOF'
#!/bin/sh
[ "${MOCK_CORE_STOPPED:-0}" != 1 ] || exit 1
printf '%s\n' 314
EOF
cat >"$tmp/bin/CrashCore" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FIXTURE_ROOT/core.calls"
case "$*" in *' -t') exit "${MOCK_CORE_TEST_FAIL:-0}" ;; *) exit 91 ;; esac
EOF
cat >"$tmp/bin/readlink" <<'EOF'
#!/bin/sh
[ "${MOCK_CORE_STOPPED:-0}" != 1 ] || exit 1
[ "${MOCK_WRONG_EXE:-0}" != 1 ] || { printf '/unrelated/core\n'; exit; }
printf '%s\n' "$FIXTURE_ROOT/bin/CrashCore"
EOF
cat >"$tmp/bin/which" <<'EOF'
#!/bin/sh
if [ "$1" = sha256sum ] && [ "${MOCK_HASH_FALLBACK:-0}" = 1 ]; then exit 1; fi
command -v "$1"
EOF
cat >"$tmp/bin/yamlbridge" <<'EOF'
#!/bin/sh
case "$1" in
 core-test)
   [ "${MOCK_CORE_TEST_FAIL:-0}" = 0 ] || exit 1
   printf '{}\n' >"$3"; exit 0 ;;
 decode)
   if [ "${MOCK_PROVIDER_UNSUPPORTED:-0}" = 1 ]; then printf '{"proxies":[{"name":"TokyoPro"}],"proxy-providers":{"live":{}}}\n'
   else printf '{"proxies":[{"name":"TokyoPro"}]}\n'; fi >"$3"; exit 0 ;;
 service-bind-reload)
   [ ! -e "$3" ] || exit 89
   printf 'BIND\n' >>"$FIXTURE_ROOT/api.calls"
   if [ "${MOCK_LATER_EDIT:-0}" = 1 ]; then printf '# later user edit\n' >"$FIXTURE_ROOT/yamls/rules.yaml"; fi
   [ "${MOCK_RELOAD_FAIL:-0}" != 1 ] || exit 22
   cp "$FIXTURE_ROOT/graph.after.json" "$FIXTURE_ROOT/graph.json"
   [ "${MOCK_BIND_POST_FAIL:-0}" != 1 ] || exit 23
   printf '{"kind":"mihomo-inline-loaded-binding/v1","runtime_sha256":"fixture"}\n' >"$3"; exit 0 ;;
 service-bind-check) printf '{"binding_preflight":"passed"}\n' >"$3"; exit 0 ;;
 service-health-validate) cp "$2" "$3"; exit 0 ;;
 service-setup) ;;
 *) exit 90 ;;
esac
if [ -n "${SERVICE_HEALTH_FIXTURE_YAMLBRIDGE:-}" ]; then exec "$SERVICE_HEALTH_FIXTURE_YAMLBRIDGE" "$@"; fi
[ ! -e "$3" ] || exit 89
mkdir "$3"
runtime=$(jq -er .runtime_config "$2")
cat "$runtime" >"$3/runtime.yaml"
printf '# derived fixture\n' >>"$3/runtime.yaml"
printf '# fixture groups\n- {name: Edge-gemini, type: select, proxies: [TokyoPro]}\n' >"$3/groups.yaml"
printf '# fixture bounded rule\nDOMAIN,gemini.google.com,Edge-gemini\n' >"$3/rules.yaml"
printf '{}\n' >"$3/manifest.json"
EOF
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/sh
method=GET
version=0
while [ "$#" -gt 0 ]; do
  case "$1" in -X) method=$2; shift ;; */version) version=1 ;; esac
  shift
done
[ "$version" -eq 0 ] || { printf '{"version":"%s"}\n' "${MOCK_VERSION:-1.19.34}"; exit; }
printf '%s\n' "$method" >>"$FIXTURE_ROOT/api.calls"
if [ "$method" = PUT ]; then
  if [ "${MOCK_LATER_EDIT:-0}" = 1 ]; then printf '# later user edit\n' >"$FIXTURE_ROOT/yamls/rules.yaml"; fi
  [ "${MOCK_RELOAD_FAIL:-0}" != 1 ] || exit 22
  cp "$FIXTURE_ROOT/graph.after.json" "$FIXTURE_ROOT/graph.json"
else
  count=$(wc -l <"$FIXTURE_ROOT/api.calls" | tr -d ' ')
  if [ "${MOCK_FRESH_DRIFT:-0}" = 1 ] && [ "$count" -gt 1 ]; then
    jq '.proxies.Manual.now="Backup"' "$FIXTURE_ROOT/graph.json"
  else cat "$FIXTURE_ROOT/graph.json"; fi
fi
EOF
chmod 700 "$tmp/bin/pidof" "$tmp/bin/readlink" "$tmp/bin/which" "$tmp/bin/CrashCore" "$tmp/bin/yamlbridge" "$tmp/bin/curl"
export SERVICE_HEALTH_STATE_ROOT=$tmp/state
export SERVICE_HEALTH_RUNTIME_CONFIG=$tmp/runtime/config.yaml
export SERVICE_HEALTH_RUNTIME_DIR=$tmp/runtime
export SERVICE_HEALTH_GROUPS_FILE=$tmp/yamls/proxy-groups.yaml
export SERVICE_HEALTH_RULES_FILE=$tmp/yamls/rules.yaml
export SERVICE_HEALTH_CORE_PATH=$tmp/bin/CrashCore
export SERVICE_HEALTH_YAMLBRIDGE=$tmp/bin/yamlbridge
export SERVICE_HEALTH_SECRET_FILE=$tmp/state/CONTROLLER_SECRET.local
export HOME_EDGE_WRITE_LOCK_DIR=$tmp/write.lock
export HOME_EDGE_SECURE_TEMP_HELPER=$repo/scripts/home-edge-secure-temp.sh
export SERVICE_HEALTH_API=http://127.0.0.1:9999
export SERVICE_HEALTH_GOOGLE_MODE=auto
export SERVICE_HEALTH_MODE=auto
printf 'fixture-private-token\n' >"$SERVICE_HEALTH_SECRET_FILE"
reset_sources() {
  printf 'proxies: [{name: TokyoPro, type: http, server: localhost, port: 9}]\nproxy-groups: []\nrules: ["MATCH,DIRECT"]\n' >"$SERVICE_HEALTH_RUNTIME_CONFIG"
  printf '# existing groups\n[]\n' >"$SERVICE_HEALTH_GROUPS_FILE"
  printf '# existing rules\nDOMAIN,example.com,DIRECT\n' >"$SERVICE_HEALTH_RULES_FILE"
  rm -f "$tmp/state/service-health.json" "$tmp/state/service-health.loaded.json" "$tmp/api.calls" "$tmp/core.calls"
  jq -n '{proxies:({"人工智能":{type:"Selector",now:"Manual",all:["Manual"]},GLOBAL:{type:"Selector",now:"Manual",all:["Manual","TokyoPro","Backup"]},Manual:{type:"Selector",now:"TokyoPro",all:["TokyoPro","Backup"]},TokyoPro:{type:"Http",id:"before-instance"},Backup:{type:"Http"}} + (reduce range(1;12) as $n ({}; .["Old-"+($n|tostring)]={type:"Selector",now:"Backup",all:["TokyoPro","Backup"]})))}' >"$tmp/graph.json"
  jq '.proxies += {"Edge-gemini":{type:"Selector",now:"Edge-gemini-Auto",all:["Edge-gemini-Auto","TokyoPro","Backup"]},"Edge-gemini-Auto":{type:"Selector",now:"TokyoPro",all:["TokyoPro","Backup"]}} | .proxies.GLOBAL.all += ["Edge-gemini","Edge-gemini-Auto"]' "$tmp/graph.json" >"$tmp/graph.after.json"
  sha256sum "$SERVICE_HEALTH_RUNTIME_CONFIG" "$SERVICE_HEALTH_GROUPS_FILE" "$SERVICE_HEALTH_RULES_FILE" >"$tmp/before.sha"
}
run_setup() { sh "$repo/scripts/configure-service-health.sh" "$@"; }
unchanged_sources() { sha256sum -c "$tmp/before.sha" >/dev/null 2>&1; }
reset_sources
run_setup --plan >"$tmp/plan.out" || fail 'plan failed'
grep -q '^service_health_setup_state=planned$' "$tmp/plan.out" || fail 'missing planned state'
unchanged_sources || fail 'plan changed sources'
[ ! -e "$tmp/state/service-health.json" ] && [ ! -e "$tmp/state/service-health-setup.pending" ] || fail 'plan installed state'
! grep -q '^PUT$' "$tmp/api.calls" || fail 'plan called controller mutation'
MOCK_HASH_FALLBACK=1 run_setup --plan >"$tmp/hash-fallback.out" || fail 'openssl SHA-256 fallback failed'
if MOCK_WRONG_EXE=1 run_setup --plan >"$tmp/wrong-exe.out" 2>&1; then fail 'pidof accepted unrelated executable'; fi
if MOCK_CORE_TEST_FAIL=1 run_setup --plan >"$tmp/core-fail.out" 2>&1; then fail 'failed bounded core validation accepted'; fi
SERVICE_HEALTH_MODE=observe SERVICE_HEALTH_GOOGLE_MODE=manual run_setup --plan >"$tmp/manual-plan.out" || fail 'manual observe plan failed'
grep -q '^gemini_initial_mode=manual$' "$tmp/manual-plan.out" || fail 'manual plan mode lost'
MOCK_VERSION=1.19.33 run_setup --plan >"$tmp/version-plan.out" || fail 'unsupported version observation plan rejected'
grep -q '^repair_capability=observe_only$' "$tmp/version-plan.out" || fail 'unsupported version claimed repair capability'
if run_setup --apply >"$tmp/without-token.out" 2>&1; then fail 'apply accepted missing opt-in'; fi
unchanged_sources || fail 'missing-token apply wrote sources'
mkdir "$tmp/write.lock"
if SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/lock.out" 2>&1; then fail 'active global lock ignored'; fi
rmdir "$tmp/write.lock"
reset_sources
if MOCK_FRESH_DRIFT=1 SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/drift.out" 2>&1; then fail 'fresh graph drift accepted'; fi
unchanged_sources || fail 'fresh drift changed sources'
[ ! -e "$tmp/state/service-health-setup.pending" ] || fail 'fresh drift created journal'
reset_sources
SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/apply.out" || fail 'apply failed'
grep -q '^service_health_setup_state=accepted$' "$tmp/apply.out" || fail 'missing accepted state'
[ ! -e "$tmp/state/service-health-setup.pending" ] && [ -f "$tmp/state/service-health-setup.previous/receipt.json" ] || fail 'accepted backup not retained'
jq -e '.mode=="auto" and (.services|length)==1 and .services[0].selector=="Edge-gemini" and (.loaded_binding_file|endswith("service-health.loaded.json"))' "$tmp/state/service-health.json" >/dev/null || fail 'health registration wrong'
jq -e '.status=="accepted" and (.files|length)==5 and any(.files[];.role=="binding" and (.proposed_sha256|test("^[0-9a-f]{64}$")))' "$tmp/state/service-health-setup.previous/receipt.json" >/dev/null || fail 'accepted receipt wrong'
[ -f "$tmp/state/service-health.loaded.json" ] || fail 'verified binding not installed'
[ "$(jq '[.proxies[]|select(.type=="Selector")]|length' "$tmp/graph.json")" -eq 16 ] || fail 'expected fourteen old plus two selected selectors'
[ "$(grep -c '^BIND$' "$tmp/api.calls")" -eq 1 ] && ! grep -q '^PUT$' "$tmp/api.calls" || fail 'supported apply did not use exactly one binding reload'
run_setup --status | grep -q '^service_health_setup_state=configured$' || fail 'status missing configuration'
reset_sources
MOCK_PROVIDER_UNSUPPORTED=1 SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/observe-only.out" || fail 'unsupported provider observe installation failed'
jq -e '.mode=="observe"' "$tmp/state/service-health.json" >/dev/null || fail 'unsupported provider did not force observation'
[ ! -e "$tmp/state/service-health.loaded.json" ] || fail 'unsupported provider fabricated binding'
! grep -q '^BIND$' "$tmp/api.calls" && [ "$(grep -c '^PUT$' "$tmp/api.calls")" -eq 1 ] || fail 'observe-only reload count wrong'
reset_sources
for graph in "$tmp/graph.json" "$tmp/graph.after.json"; do
  jq '.proxies += {"Edge-openai":{type:"Selector",now:"Backup",all:["Backup","Edge-openai-Auto"]},"Edge-openai-Auto":{type:"Selector",now:"Backup",all:["TokyoPro","Backup"]}} | .proxies.GLOBAL.all += ["Edge-openai","Edge-openai-Auto"]' "$graph" >"$tmp/graph.preserve.json"
  mv "$tmp/graph.preserve.json" "$graph"
done
printf '{"schema_version":1,"mode":"observe","services":[{"name":"openai","selector":"Edge-openai","auto_selector":"Edge-openai-Auto"}]}\n' >"$tmp/state/service-health.json"
(unset SERVICE_HEALTH_MODE; SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply) >"$tmp/preserve-service.out" || fail 'existing unselected service preservation failed'
jq -e '.mode=="observe" and [.services[].name]==["gemini","openai"]' "$tmp/state/service-health.json" >/dev/null || fail 'existing health service or global mode lost'
jq -e '.proxies["Edge-openai"].now=="Backup" and .proxies["Edge-openai-Auto"].now=="Backup"' "$tmp/graph.json" >/dev/null || fail 'unselected existing service was reselected'
reset_sources
if SERVICE_HEALTH_PROFILES=gemini,gemini run_setup --plan >"$tmp/duplicate-profile.out" 2>&1; then fail 'duplicate service profiles accepted'; fi
jq '.proxies.GLOBAL.all += ["unrelated-new-member"]' "$tmp/graph.after.json" >"$tmp/graph.bad.json"
mv "$tmp/graph.bad.json" "$tmp/graph.after.json"
if SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/global-member.out" 2>&1; then fail 'unrelated GLOBAL member accepted'; fi
unchanged_sources || fail 'unexpected GLOBAL member did not restore configuration'
MOCK_CORE_STOPPED=1 run_setup --recover >"$tmp/global-member-recover.out" || fail 'GLOBAL member recovery failed'
reset_sources
jq '.proxies.GLOBAL.now="Backup"' "$tmp/graph.after.json" >"$tmp/graph.bad.json"
mv "$tmp/graph.bad.json" "$tmp/graph.after.json"
printf '{"previous":"private-binding"}\n' >"$tmp/state/service-health.loaded.json"
if SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/global-change.out" 2>&1; then fail 'GLOBAL selection drift accepted'; fi
unchanged_sources || fail 'GLOBAL verification failure did not restore configuration'
jq -e '.previous=="private-binding"' "$tmp/state/service-health.loaded.json" >/dev/null || fail 'failed verification lost prior binding'
MOCK_CORE_STOPPED=1 run_setup --recover >"$tmp/global-recover.out" || fail 'GLOBAL failure preboot recovery failed'
reset_sources
if MOCK_BIND_POST_FAIL=1 SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/binding-post-fail.out" 2>&1; then fail 'unverified reload binding accepted'; fi
unchanged_sources || fail 'post-reload failure did not restore owned configuration'
[ -f "$tmp/state/service-health-setup.pending/receipt.json" ] && [ ! -e "$tmp/state/service-health.loaded.json" ] || fail 'post-reload failure lost pending or fabricated binding'
MOCK_CORE_STOPPED=1 run_setup --recover >"$tmp/binding-recover.out" || fail 'post-reload failure preboot recovery failed'
reset_sources
if MOCK_RELOAD_FAIL=1 SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/reload-fail.out" 2>&1; then fail 'reload failure accepted'; fi
unchanged_sources || fail 'failed reload did not restore owned sources'
[ -f "$tmp/state/service-health-setup.pending/receipt.json" ] || fail 'failed reload lost pending responsibility'
if run_setup --recover >"$tmp/live-recover.out" 2>&1; then fail 'live file-only recovery cleared runtime responsibility'; fi
MOCK_CORE_STOPPED=1 run_setup --recover >"$tmp/recover.out" || fail 'pre-boot recovery failed'
[ ! -e "$tmp/state/service-health-setup.pending" ] || fail 'recovered journal remained'
reset_sources
if MOCK_RELOAD_FAIL=1 MOCK_LATER_EDIT=1 SERVICE_HEALTH_CONFIRM=APPLY run_setup --apply >"$tmp/later-edit.out" 2>&1; then fail 'later-edit failure accepted'; fi
grep -q '^# later user edit$' "$SERVICE_HEALTH_RULES_FILE" || fail 'rollback overwrote later user edit'
if MOCK_CORE_STOPPED=1 run_setup --recover >"$tmp/unresolved.out" 2>&1; then fail 'recovery overwrote later user edit'; fi
grep -q '^# later user edit$' "$SERVICE_HEALTH_RULES_FILE" || fail 'recovery changed later edit'
[ -f "$tmp/state/service-health-setup.pending/receipt.json" ] || fail 'unresolved receipt disappeared'
if grep -l 'fixture-private-token' "$tmp"/*.out >/dev/null 2>&1; then fail 'controller secret leaked to output'; fi
echo 'service_health_setup_fixture_tests=ok'
