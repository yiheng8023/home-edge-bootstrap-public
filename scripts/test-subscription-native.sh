#!/bin/sh
# Isolated real Mihomo startup and native selection persistence, no traffic redirection.
set -eu
umask 077
core=${1:?usage: test-subscription-native.sh CORE_BIN}
port=${SUBSCRIPTION_NATIVE_TEST_PORT:-19998}
case "$port" in ''|*[!0-9]*) exit 2;; esac
work="/tmp/home-edge-native-test.$$"
[ ! -e "$work" ] && [ ! -L "$work" ] || exit 1
mkdir "$work"
pid=""
cleanup() {
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
api="http://127.0.0.1:$port"
printf '%s\n' 'header = "Authorization: Bearer <REDACTED>"' >"$work/auth"
call() { curl --config "$work/auth" --noproxy '*' -fsS --connect-timeout 1 --max-time 5 "$@"; }
! call "$api/version" >/dev/null 2>&1 || { echo native_test=port_in_use; exit 1; }
cat >"$work/config.yaml" <<EOF
external-controller: 127.0.0.1:$port
secret: "<REDACTED>"
mixed-port: 0
port: 0
socks-port: 0
redir-port: 0
tproxy-port: 0
allow-lan: false
dns: {enable: false}
tun: {enable: false}
iptables: {enable: false}
geo-auto-update: false
log-level: silent
proxy-groups:
  - name: NativeFixture
    type: select
    proxies: [DIRECT, REJECT]
rules: ["MATCH,DIRECT"]
EOF
"$core" -d "$work" -f "$work/config.yaml" >"$work/core.log" 2>&1 & pid=$!
ready=0
for n in 1 2 3 4 5; do if call "$api/version" >/dev/null 2>&1; then ready=1; break; fi; sleep 1; done
[ "$ready" = 1 ] || { echo native_test=start_failed; cat "$work/core.log"; exit 1; }
for choice in REJECT DIRECT; do
  call -X PUT -H 'Content-Type: application/json' --data "{\"name\":\"$choice\"}" "$api/proxies/NativeFixture" >/dev/null
  ack=$(call -X PUT -H 'Content-Type: application/json' --data '{}' -o "$work/response" -w '%{http_code}' "$api/configs")
  [ "$ack" = 204 ]
  actual=$(call "$api/proxies/NativeFixture" | jq -r .now)
  [ "$actual" = "$choice" ] || { echo native_test=selection_not_persisted; exit 1; }
done
[ -s "$work/cache.db" ]
echo native_start_and_selection_reload=pass
