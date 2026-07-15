#!/bin/sh
# Offline behavior tests for check-host-ssh.sh.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

fail() {
  echo "host_ssh_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

state_from() {
  key="$1"
  input="$2"
  printf '%s\n' "$input" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}

run_case() {
  name="$1"
  router_state="$2"
  failure_hint="$3"
  expected="$4"

  output=$(
    HOST_SSH_FIXTURE_AGENT_STATE=identities_loaded \
    HOST_SSH_FIXTURE_DEFAULT_KEY_STATE=present \
    HOST_SSH_FIXTURE_ROUTER_SSH_STATE="$router_state" \
    HOST_SSH_FIXTURE_FAILURE_HINT="$failure_hint" \
    sh "$repo/scripts/check-host-ssh.sh" user@192.168.50.1
  )

  state=$(state_from host_ssh_check_state "$output")
  [ "$state" = "$expected" ] || fail "$name expected host_ssh_check_state=$expected got=$state"
}

run_case router_ok ok "" ready
run_case auth_failed failed auth_failed_or_identity_not_loaded router_ssh_failed

echo "host_ssh_fixture_tests=ok"
