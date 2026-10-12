#!/bin/sh
# Offline behavior tests for the ShellCrash service-rule manager.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_parent=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${tmp_parent%/}/home-edge-service-rules-test.XXXXXX") || exit 1
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT HUP INT TERM

fail() {
  echo "shellcrash_service_rules_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

shellcrash="$tmp/ShellCrash"
state="$tmp/state"
mkdir -p "$shellcrash/yamls" "$state"
rules="$shellcrash/yamls/rules.yaml"
runtime="$tmp/runtime.yaml"
cat >"$rules" <<'EOF'
  - DOMAIN-SUFFIX,openai.com,Service Policy
  - MATCH,DIRECT
EOF
cat >"$runtime" <<'EOF'
rules:
  - DOMAIN-SUFFIX,openai.com,Service Policy
  - MATCH,DIRECT
EOF
original_hash=$(sha256sum "$rules" | awk '{print $1}')

run_rules() {
  HOME_EDGE_SERVICE_RULES_ACTION="$1" \
  HOME_EDGE_SHELLCRASH_DIR="$shellcrash" \
  HOME_EDGE_SERVICE_RUNTIME_CONFIG="$runtime" \
  HOME_EDGE_STATE_ROOT="$state" \
  sh "$repo/scripts/configure-shellcrash-service-rules.sh"
}

plan=$(run_rules plan)
printf '%s\n' "$plan" | grep -q '^service_rules_state=planned$' || fail "plan state missing"
printf '%s\n' "$plan" | grep -q '^service_profile=openai$' || fail "profile marker missing"
printf '%s\n' "$plan" | grep -q '^runtime_reload_state=not_requested$' || fail "plan unexpectedly requests reload"
if printf '%s\n' "$plan" | grep -Fq 'Service Policy'; then
  fail "plan output exposed the service policy group"
fi

apply=$(run_rules apply)
printf '%s\n' "$apply" | grep -q '^service_rules_state=applied$' || fail "apply state missing"
grep -Fqx '# BEGIN home-edge-bootstrap service-rules/openai/v1' "$rules" || fail "managed block begin missing"
grep -Fqx '# END home-edge-bootstrap service-rules/openai/v1' "$rules" || fail "managed block end missing"
grep -Fq 'DOMAIN-SUFFIX,chatgpt.com,Service Policy' "$rules" || fail "ChatGPT route missing"
grep -Fq 'DOMAIN-SUFFIX,oaistatic.com,Service Policy' "$rules" || fail "static asset route missing"
grep -Fq 'DOMAIN,challenges.cloudflare.com,Service Policy' "$rules" || fail "shared dependency route missing"
[ "$(grep -Fc 'DOMAIN-SUFFIX,openai.com,Service Policy' "$rules")" -eq 1 ] ||
  fail "existing service rule was duplicated"
if printf '%s\n' "$apply" | grep -Fq 'Service Policy'; then
  fail "apply output exposed the service policy group"
fi

status=$(run_rules status)
printf '%s\n' "$status" | grep -q '^service_rules_state=applied$' || fail "status did not observe managed rules"

rollback=$(run_rules rollback)
printf '%s\n' "$rollback" | grep -q '^service_rules_state=rolled_back$' || fail "rollback state missing"
restored_hash=$(sha256sum "$rules" | awk '{print $1}')
[ "$restored_hash" = "$original_hash" ] || fail "rollback did not restore the original rules"

run_asus_rules() {
  HOME_EDGE_SERVICE_RULES_ACTION="$1" \
  HOME_EDGE_SERVICE_PROFILE=asus-global-account \
  HOME_EDGE_SERVICE_GROUP=DIRECT \
  HOME_EDGE_SHELLCRASH_DIR="$shellcrash" \
  HOME_EDGE_SERVICE_RUNTIME_CONFIG="$runtime" \
  HOME_EDGE_STATE_ROOT="$state" \
  sh "$repo/scripts/configure-shellcrash-service-rules.sh"
}

asus_plan=$(run_asus_rules plan)
printf '%s\n' "$asus_plan" | grep -q '^service_rules_state=planned$' ||
  fail "ASUS account plan state missing"
printf '%s\n' "$asus_plan" | grep -q '^service_profile=asus-global-account$' ||
  fail "ASUS account profile marker missing"
if printf '%s\n' "$asus_plan" | grep -Fq 'DIRECT'; then
  fail "ASUS account plan exposed the service policy group"
fi

asus_apply=$(run_asus_rules apply)
printf '%s\n' "$asus_apply" | grep -q '^service_rules_state=applied$' ||
  fail "ASUS account apply state missing"
grep -Fqx '# BEGIN home-edge-bootstrap service-rules/asus-global-account/v1' "$rules" ||
  fail "ASUS account managed block begin missing"
grep -Fqx '  - DOMAIN,nomos.asus.com,DIRECT' "$rules" ||
  fail "ASUS account token route missing"
if grep -Fq 'DOMAIN-SUFFIX,asus.com,DIRECT' "$rules"; then
  fail "ASUS account profile widened to all ASUS domains"
fi
if printf '%s\n' "$asus_apply" | grep -Fq 'DIRECT'; then
  fail "ASUS account apply exposed the service policy group"
fi

asus_rollback=$(run_asus_rules rollback)
printf '%s\n' "$asus_rollback" | grep -q '^service_rules_state=rolled_back$' ||
  fail "ASUS account rollback state missing"
restored_hash=$(sha256sum "$rules" | awk '{print $1}')
[ "$restored_hash" = "$original_hash" ] ||
  fail "ASUS account rollback did not restore the original rules"

run_rules apply >/dev/null
run_asus_rules apply >/dev/null
run_rules rollback >/dev/null
grep -Fqx '# BEGIN home-edge-bootstrap service-rules/asus-global-account/v1' "$rules" ||
  fail "rolling back an earlier profile removed a later managed profile"
if grep -Fqx '# BEGIN home-edge-bootstrap service-rules/openai/v1' "$rules"; then
  fail "OpenAI managed profile remained after interleaved rollback"
fi
run_asus_rules rollback >/dev/null
restored_hash=$(sha256sum "$rules" | awk '{print $1}')
[ "$restored_hash" = "$original_hash" ] ||
  fail "interleaved profile rollback did not preserve the original rules"

missing_state_file="$state/missing/state.env"
if HOME_EDGE_SERVICE_RULES_ACTION=apply \
  HOME_EDGE_SERVICE_GROUP='Service Policy' \
  HOME_EDGE_SHELLCRASH_DIR="$shellcrash" \
  HOME_EDGE_SERVICE_RUNTIME_CONFIG="$runtime" \
  HOME_EDGE_STATE_ROOT="$state" \
  HOME_EDGE_SERVICE_RULES_STATE_FILE="$missing_state_file" \
  sh "$repo/scripts/configure-shellcrash-service-rules.sh" >"$tmp/state-failure.out" 2>"$tmp/state-failure.err"; then
  fail "service-rules apply succeeded with an uncommittable state path"
fi
restored_hash=$(sha256sum "$rules" | awk '{print $1}')
[ "$restored_hash" = "$original_hash" ] ||
  fail "state commit failure did not restore the original rules"
if grep -Fq '# BEGIN home-edge-bootstrap service-rules/' "$rules"; then
  fail "state commit failure left a managed rules block"
fi

cat >"$runtime" <<'EOF'
rules:
  - DOMAIN-SUFFIX,openai.com,First Policy
  - DOMAIN-SUFFIX,chatgpt.com,Second Policy
EOF
if run_rules plan >"$tmp/ambiguous.out" 2>"$tmp/ambiguous.err"; then
  fail "ambiguous policy groups should fail closed"
fi
if grep -Eq 'First Policy|Second Policy' "$tmp/ambiguous.out" "$tmp/ambiguous.err"; then
  fail "ambiguous-group failure exposed policy names"
fi

cat >"$runtime" <<'EOF'
rules:
  -   DOMAIN-KEYWORD,openai,AI Policy
  - DOMAIN-KEYWORD,chatgpt,AI Policy
  - DOMAIN-SUFFIX,oaistatic.com,Media Policy
  - DOMAIN-SUFFIX,oaiusercontent.com,Media Policy
EOF
mixed_runtime_hash=$(sha256sum "$runtime" | awk '{print $1}')
if run_rules plan >"$tmp/mixed.out" 2>"$tmp/mixed.err"; then
  fail "keyword AI and suffix media groups should fail closed"
fi
if grep -Eq 'AI Policy|Media Policy' "$tmp/mixed.out" "$tmp/mixed.err"; then
  fail "mixed-group failure exposed policy names"
fi
[ "$(sha256sum "$rules" | awk '{print $1}')" = "$original_hash" ] ||
  fail "mixed-group plan failure changed persistent rules"
[ ! -e "$state/lifecycle/service-rules-openai.env" ] ||
  fail "mixed-group plan failure created service-rules state"

cat >"$rules" <<'EOF'
  - DOMAIN-SUFFIX,oaistatic.com,Media Policy
  - DOMAIN-SUFFIX,oaiusercontent.com,Media Policy
  - DOMAIN-SUFFIX,example.com,DIRECT
  - MATCH,DIRECT
EOF
mixed_rules_hash=$(sha256sum "$rules" | awk '{print $1}')
explicit_apply=$(HOME_EDGE_SERVICE_GROUP='AI Policy' run_rules apply)
printf '%s\n' "$explicit_apply" | grep -q '^runtime_reload_state=pending$' ||
  fail "explicit service group apply crossed the reload boundary"
for domain in oaistatic.com oaiusercontent.com; do
  grep -Fqx "  - DOMAIN-SUFFIX,$domain,AI Policy" "$rules" ||
    fail "explicit service group route missing for $domain"
  grep -Fqx "  - DOMAIN-SUFFIX,$domain,Media Policy" "$rules" ||
    fail "explicit service group apply changed an existing media rule"
  ai_line=$(grep -Fn "  - DOMAIN-SUFFIX,$domain,AI Policy" "$rules" | cut -d: -f1)
  media_line=$(grep -Fn "  - DOMAIN-SUFFIX,$domain,Media Policy" "$rules" | cut -d: -f1)
  [ "$ai_line" -lt "$media_line" ] || fail "service route does not precede media fallback"
done
grep -Fqx '  - DOMAIN,frontend-apps-multi-region.workos.com,AI Policy' "$rules" ||
  fail "WorkOS frontend route missing from applied profile"
grep -Fqx '  - DOMAIN-SUFFIX,example.com,DIRECT' "$rules" ||
  fail "explicit service group apply changed an unrelated rule"
[ "$(sha256sum "$runtime" | awk '{print $1}')" = "$mixed_runtime_hash" ] ||
  fail "service group apply changed the active runtime config"
run_rules rollback >/dev/null
[ "$(sha256sum "$rules" | awk '{print $1}')" = "$mixed_rules_hash" ] ||
  fail "explicit service group rollback changed original rules"

cat >"$runtime" <<'EOF'
rules:
  -   DOMAIN-KEYWORD,openai,AI Policy
  - DOMAIN-KEYWORD,chatgpt,AI Policy
EOF
keyword_plan=$(run_rules plan)
printf '%s\n' "$keyword_plan" | grep -q '^service_rules_state=planned$' ||
  fail "matching keyword groups were not discovered"
for unsupported in \
  'DOMAIN-KEYWORD,openai-api' \
  'DOMAIN-KEYWORD,chatgpt-extra' \
  'DOMAIN-SUFFIX,openai' \
  'DOMAIN,chatgpt'; do
  printf 'rules:\n  - %s,Other Policy\n' "$unsupported" >"$runtime"
  if run_rules plan >"$tmp/unsupported.out" 2>"$tmp/unsupported.err"; then
    fail "group discovery widened the keyword anchor to $unsupported"
  fi
done

source="$repo/scripts/configure-shellcrash-service-rules.sh"
for expected in \
  'DOMAIN-SUFFIX,chatgpt.com' \
  'DOMAIN-SUFFIX,openai.com' \
  'DOMAIN-SUFFIX,oaistatic.com' \
  'DOMAIN-SUFFIX,oaiusercontent.com' \
  'DOMAIN-SUFFIX,oaistatsig.com' \
  'DOMAIN,challenges.cloudflare.com' \
  'DOMAIN,cdn.workos.com' \
  'DOMAIN,js.stripe.com' \
  'DOMAIN,nomos.asus.com' \
  'runtime_reload_state=pending'; do
  grep -Fq "$expected" "$source" || fail "service profile contract is missing $expected"
done
grep -Fq 'network-recommendations-for-chatgpt-errors-on-web-and-apps' "$source" ||
  fail "service profile source reference missing"
grep -Fq 'https://account.asus.com/' "$source" ||
  fail "ASUS account profile source reference missing"

echo "shellcrash_service_rules_fixture_tests=ok"
