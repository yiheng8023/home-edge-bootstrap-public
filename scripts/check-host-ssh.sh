#!/bin/sh
# Read-only host SSH readiness check. It does not print keys or store passwords.
set -u

router="${1:-${ROUTER:-}}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
timeout_sec="${HOST_SSH_TIMEOUT_SEC:-5}"

print_kv() {
  key="$1"
  value="$2"
  [ -n "$value" ] || value=unknown
  printf '%s=%s\n' "$key" "$value"
}

default_key_state() {
  [ -n "${HOST_SSH_FIXTURE_DEFAULT_KEY_STATE:-}" ] && { printf '%s\n' "$HOST_SSH_FIXTURE_DEFAULT_KEY_STATE"; return; }
  for name in id_ed25519 id_ecdsa id_rsa; do
    [ -s "${HOME:-}/.ssh/$name" ] && { printf present; return; }
  done
  printf missing
}

agent_state() {
  [ -n "${HOST_SSH_FIXTURE_AGENT_STATE:-}" ] && { printf '%s\n' "$HOST_SSH_FIXTURE_AGENT_STATE"; return; }
  command -v ssh-add >/dev/null 2>&1 || { printf ssh_add_missing; return; }
  output=$(ssh-add -l 2>&1)
  code=$?
  [ "$code" -eq 0 ] && { printf identities_loaded; return; }
  printf '%s\n' "$output" | grep -Eiq 'no identities|The agent has no identities' && { printf no_identities; return; }
  printf '%s\n' "$output" | grep -Eiq 'Could not open|Error connecting|No such file' && { printf agent_unavailable; return; }
  printf unknown
}

failure_hint() {
  text="$1"
  printf '%s\n' "$text" | grep -Eiq 'Permission denied' && { printf auth_failed_or_identity_not_loaded; return; }
  printf '%s\n' "$text" | grep -Eiq 'Connection timed out|Operation timed out|No route to host|Network is unreachable' && { printf router_unreachable; return; }
  printf '%s\n' "$text" | grep -Eiq 'Connection refused' && { printf router_ssh_disabled_or_wrong_port; return; }
  printf '%s\n' "$text" | grep -Eiq 'Could not resolve hostname' && { printf router_name_unresolved; return; }
  printf inspect_ssh_error
}

ssh_client_state=present
command -v ssh >/dev/null 2>&1 || ssh_client_state=missing
ssh_agent_state=$(agent_state)
default_key_state_value=$(default_key_state)
router_target_state=missing
[ -n "$router" ] && router_target_state=provided
router_ssh_state=skipped_no_router
ssh_failure_hint=""

if [ "$ssh_client_state" = "missing" ]; then
  router_ssh_state=skipped_no_ssh_client
  ssh_failure_hint=install_openssh
elif [ -n "${HOST_SSH_FIXTURE_ROUTER_SSH_STATE:-}" ]; then
  router_ssh_state=$HOST_SSH_FIXTURE_ROUTER_SSH_STATE
  ssh_failure_hint="${HOST_SSH_FIXTURE_FAILURE_HINT:-}"
elif [ -n "$router" ]; then
  mkdir -p "$(dirname "$known_hosts_file")"
  output=$(ssh \
    -o BatchMode=yes \
    -o ConnectTimeout="$timeout_sec" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$known_hosts_file" \
    -- "$router" 'echo router-ssh-ok' 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && printf '%s\n' "$output" | grep -q 'router-ssh-ok'; then
    router_ssh_state=ok
  else
    router_ssh_state=failed
    ssh_failure_hint=$(failure_hint "$output")
  fi
fi

host_ssh_check_state=ready
if [ "$ssh_client_state" = "missing" ]; then
  host_ssh_check_state=missing_ssh_client
elif [ "$router_ssh_state" = "failed" ]; then
  host_ssh_check_state=router_ssh_failed
elif [ "$router_ssh_state" = "skipped_no_router" ]; then
  host_ssh_check_state=host_only_ready
fi

echo "# Host SSH Check"
echo
print_kv host_ssh_check_state "$host_ssh_check_state"
print_kv ssh_client_state "$ssh_client_state"
print_kv ssh_agent_state "$ssh_agent_state"
print_kv default_key_state "$default_key_state_value"
print_kv router_target_state "$router_target_state"
print_kv router_ssh_state "$router_ssh_state"
print_kv ssh_failure_hint "$ssh_failure_hint"
