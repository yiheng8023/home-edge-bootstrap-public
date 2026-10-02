#!/bin/sh
# Activate an already deployed node updater with a site parser and filter mapping.
set -eu
router=${1:?usage: enable-subscription-auto.sh USER@ROUTER FILTERS_JSON}
filters=${2:?site filter mapping required}
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
[ -f "$filters" ] || { echo 'subscription_enable=filter_file_missing' >&2; exit 1; }
if [ "${APPLY:-0}" != 1 ]; then
  echo subscription_enable=plan
  echo 'required=deployed helpers, configured HTTPS subscription, controller key, compiled parser, site filters'
  exit 0
fi
build=${SUBSCRIPTION_PARSER_BUILD_DIR:-$repo/.tmp/subscription-parser}
[ -s "$build/yamlbridge-linux-arm64.gz" ] || sh "$repo/scripts/build-subscription-parser.sh" "$build"
digest=$(openssl dgst -sha256 "$build/yamlbridge-linux-arm64" | awk '{print $NF}')
opts=${SSH_OPTS:-'-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes'}
token="$$-$(date +%s)"
stage="/tmp/home-edge-subscription-enable.$token"
stage_owned=0
cleanup_host() {
  if [ "$stage_owned" = 1 ]; then
    ssh $opts -- "$router" "test ! -L '$stage' && test \"\$(cat '$stage/owner' 2>/dev/null)\" = '$token' && rm -rf '$stage'" >/dev/null 2>&1 || true
  fi
}
trap cleanup_host EXIT
trap 'exit 130' HUP INT TERM
ssh $opts -- "$router" "set -eu; umask 077; test ! -e '$stage'; mkdir '$stage'; printf '%s\\n' '$token' >'$stage/owner'"
stage_owned=1
scp -O $opts -- "$build/yamlbridge-linux-arm64.gz" "$router:$stage/parser.gz"
scp -O $opts -- "$filters" "$router:$stage/filters.json"
{
  printf "digest='%s'\n" "$digest"
  printf "stage='%s'\n" "$stage"
  printf "token='%s'\n" "$token"
  cat <<'EOF'
set -eu
umask 077
state=/jffs/home-edge-bootstrap-state
lock=/tmp/home-edge-bootstrap-write.lock
mkdir "$lock"
echo $$ >"$lock/pid"; echo subscription-enable >"$lock/operation"; date +%s >"$lock/started_at"
cleanup() { if [ "$(cat "$lock/pid" 2>/dev/null || true)" = "$$" ] && [ "$(cat "$lock/operation" 2>/dev/null || true)" = subscription-enable ]; then rm -f "$lock/pid" "$lock/operation" "$lock/started_at"; rmdir "$lock" 2>/dev/null || true; fi; }
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
test -s "$state/SUBSCRIPTION.local"
jq -e 'type=="object" and all(.[];type=="string")' "$stage/filters.json" >/dev/null
gzip -dc "$stage/parser.gz" >"$stage/parser"
[ "$(openssl dgst -sha256 "$stage/parser" | awk '{print $NF}')" = "$digest" ]
chmod 700 "$stage/parser"
printf 'probe: true\n' >"$stage/probe.yaml"
"$stage/parser" decode "$stage/probe.yaml" "$stage/probe.json"
jq -e '.probe==true' "$stage/probe.json" >/dev/null
mkdir -p "$state/runtime"
cp "$stage/parser.gz" "$state/runtime/yamlbridge.gz.new"
printf '%s\n' "$digest" >"$state/runtime/yamlbridge.sha256.new"
chmod 600 "$state/runtime/yamlbridge.gz.new" "$state/runtime/yamlbridge.sha256.new"
mv "$state/runtime/yamlbridge.gz.new" "$state/runtime/yamlbridge.gz"
mv "$state/runtime/yamlbridge.sha256.new" "$state/runtime/yamlbridge.sha256"
cp "$stage/filters.json" "$state/subscription-groups.json"
chmod 600 "$state/subscription-groups.json"
policy="$state/policy.local"
[ -f "$policy" ] || : >"$policy"
cp "$policy" "$stage/policy-before"
sed '/^SUBSCRIPTION_AUTO_ENABLED=/d' "$policy" >"$policy.new"
printf 'SUBSCRIPTION_AUTO_ENABLED=1\n' >>"$policy.new"
chmod 600 "$policy.new"; mv "$policy.new" "$policy"
if ! /jffs/scripts/home-edge-subscription-auto.sh --reconcile; then
  cp "$stage/policy-before" "$policy"
  /jffs/scripts/home-edge-subscription-auto.sh --reconcile || true
  exit 1
fi
cleanup; trap - EXIT HUP INT TERM
[ "$(cd "$stage" && pwd -P)" = "$stage" ] && [ ! -L "$stage" ] && [ "$(cat "$stage/owner")" = "$token" ]
rm -rf "$stage"
echo subscription_enable=ready
EOF
} | ssh $opts -- "$router" 'tr -d "\r" | sh -s'
