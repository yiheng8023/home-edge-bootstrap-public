#!/bin/sh
# Read-only one-screen entrypoint for router-primary/client-fallback diagnosis.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
script_dir="$repo/scripts"
router="${ROUTER:-}"
json=0

case "${DOCTOR_JSON:-0}" in
  1|true|TRUE|yes|YES) json=1 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      json=1
      ;;
    --help|-h)
      echo "usage: sh scripts/doctor.sh [--json] [<ssh-user>@<router-ip>]" >&2
      echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
      exit 2
      ;;
    *)
      if [ -z "$router" ]; then
        router="$1"
      else
        echo "unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
  shift
done

run_or_fixture() {
  name=$1
  shift
  output_var="DOCTOR_FIXTURE_${name}_OUTPUT"
  exit_var="DOCTOR_FIXTURE_${name}_EXIT"
  eval "fixture_output=\${$output_var+x}"
  if [ -n "${fixture_output:-}" ]; then
    eval "printf '%s' \"\${$output_var}\""
    return "$(eval "printf '%s' \"\${$exit_var:-0}\"")"
  fi
  "$@" 2>&1
}

state_from() {
  key=$1
  input=$2
  printf '%s\n' "$input" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}

or_unknown() {
  value=$1
  [ -n "$value" ] && printf '%s\n' "$value" || printf unknown
}

working_directory_state() {
  cwd=$(pwd -P)
  case "$cwd" in
    "$repo")
      printf repo_root
      ;;
    "$repo"/*)
      printf inside_repo
      ;;
    *)
      printf outside_repo
      ;;
  esac
}


json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN { ORS="" } { if (NR > 1) printf "\\n"; gsub(/\r/, "\\r"); gsub(/\t/, "\\t"); gsub(/[[:cntrl:]]/, ""); printf "%s", $0 }'
}

json_pair() {
  key=$1
  value=$2
  suffix=$3
  printf '  "%s": "%s"%s\n' "$key" "$(json_escape "$value")" "$suffix"
}

repository_exit=0
repository_output=$(run_or_fixture REPOSITORY sh "$script_dir/verify-closeout.sh") || repository_exit=$?

working_directory_state_value=$(working_directory_state)
no_wall_exit=0
no_wall_output=$(run_or_fixture NO_WALL sh "$script_dir/check-no-wall-readiness.sh") || no_wall_exit=$?

host_ssh_exit=0
host_ssh_output='host_ssh_check_state=not_checked
router_ssh_state=not_checked'
edge_health_exit=0
edge_health_output='edge_health_state=not_checked
next_action=provide router target and rerun'

if [ -n "$router" ]; then
  host_ssh_output=$(run_or_fixture HOST_SSH sh "$script_dir/check-host-ssh.sh" "$router") || host_ssh_exit=$?
  edge_health_output=$(run_or_fixture EDGE_HEALTH sh "$script_dir/check-edge-health.sh" "$router") || edge_health_exit=$?
fi

repository_state=$(state_from closeout_state "$repository_output")
local_tools_state=$(state_from status "$no_wall_output")
bundle_state=$(state_from bundle_state "$no_wall_output")
host_ssh_check_state=$(state_from host_ssh_check_state "$host_ssh_output")
router_ssh_state=$(state_from router_ssh_state "$host_ssh_output")
ssh_failure_hint=$(state_from ssh_failure_hint "$host_ssh_output")

edge_health_state=$(state_from edge_health_state "$edge_health_output")
proxy_state=$(state_from proxy_state "$edge_health_output")
subscription_state=$(state_from subscription_state "$edge_health_output")
automation_state=$(state_from automation_state "$edge_health_output")
client_topology_mode=$(state_from client_topology_mode "$edge_health_output")
client_runtime_present=$(state_from client_runtime_present "$edge_health_output")
client_conflict_risk=$(state_from client_conflict_risk "$edge_health_output")
edge_next_action=$(state_from next_action "$edge_health_output")

doctor_state=needs_attention
next_action="inspect doctor output"
next_action_command='sh scripts/doctor.sh <ssh-user>@<router-ip>'

if [ "$repository_exit" -ne 0 ] || [ "${repository_state:-}" != ready ]; then
  doctor_state=repository_attention
  next_action="fix repository closeout structure before operating the router"
  next_action_command='sh scripts/verify-closeout.sh'
elif [ "$no_wall_exit" -ne 0 ] || [ "${local_tools_state:-}" != tools_ready ]; then
  doctor_state=host_tools_attention
  next_action="install or repair local tools before router work"
  next_action_command='sh scripts/check-no-wall-readiness.sh'
elif [ -z "$router" ]; then
  doctor_state=local_ready_router_not_checked
  next_action="provide the router SSH target and rerun doctor"
  next_action_command='sh scripts/doctor.sh <ssh-user>@<router-ip>'
elif [ "$host_ssh_exit" -ne 0 ] || [ "${host_ssh_check_state:-}" != ready ]; then
  doctor_state=router_connection_attention
  next_action="fix host SSH or router SSH reachability"
  next_action_command="sh scripts/check-host-ssh.sh \"$router\""
elif [ "${edge_health_state:-}" = router_managed ] && [ "${edge_next_action:-}" = none ]; then
  doctor_state=ready
  next_action=none
  next_action_command=none
else
  doctor_state=router_attention
  if [ -n "${edge_next_action:-}" ]; then
    next_action=$edge_next_action
  else
    next_action="inspect edge health and guide-router output"
  fi
  next_action_command="sh scripts/check-edge-health.sh \"$router\""
fi

router_target_state=missing
[ -n "$router" ] && router_target_state=provided

repository_state_out=$(or_unknown "${repository_state:-}")
working_directory_state_out=$(or_unknown "$working_directory_state_value")
local_tools_state_out=$(or_unknown "${local_tools_state:-}")
bundle_state_out=$(or_unknown "${bundle_state:-}")
host_ssh_check_state_out=$(or_unknown "${host_ssh_check_state:-}")
router_ssh_state_out=$(or_unknown "${router_ssh_state:-}")
ssh_failure_hint_out=$(or_unknown "${ssh_failure_hint:-}")
edge_health_state_out=$(or_unknown "${edge_health_state:-}")
proxy_state_out=$(or_unknown "${proxy_state:-}")
subscription_state_out=$(or_unknown "${subscription_state:-}")
automation_state_out=$(or_unknown "${automation_state:-}")
client_topology_mode_out=$(or_unknown "${client_topology_mode:-}")
client_runtime_present_out=$(or_unknown "${client_runtime_present:-}")
client_conflict_risk_out=$(or_unknown "${client_conflict_risk:-}")

if [ "$json" -eq 1 ]; then
  printf '{\n'
  json_pair doctor_state "$doctor_state" ,
  json_pair repository_state "$repository_state_out" ,
  json_pair working_directory_state "$working_directory_state_out" ,
  json_pair local_tools_state "$local_tools_state_out" ,
  json_pair bundle_state "$bundle_state_out" ,
  json_pair router_target_state "$router_target_state" ,
  json_pair host_ssh_check_state "$host_ssh_check_state_out" ,
  json_pair router_ssh_state "$router_ssh_state_out" ,
  json_pair ssh_failure_hint "$ssh_failure_hint_out" ,
  json_pair edge_health_state "$edge_health_state_out" ,
  json_pair proxy_state "$proxy_state_out" ,
  json_pair subscription_state "$subscription_state_out" ,
  json_pair automation_state "$automation_state_out" ,
  json_pair client_topology_mode "$client_topology_mode_out" ,
  json_pair client_runtime_present "$client_runtime_present_out" ,
  json_pair client_conflict_risk "$client_conflict_risk_out" ,
  json_pair next_action "$next_action" ,
  json_pair next_action_command "$next_action_command" ""
  printf '}\n'
else
  echo "# Home Edge Doctor"
  echo
  echo "This is a read-only entrypoint. It does not deploy, reload, or change router settings."
  echo
  echo "doctor_state=$doctor_state"
  echo "repository_state=$repository_state_out"
  echo "working_directory_state=$working_directory_state_out"
  echo "local_tools_state=$local_tools_state_out"
  echo "bundle_state=$bundle_state_out"
  echo "router_target_state=$router_target_state"
  echo "host_ssh_check_state=$host_ssh_check_state_out"
  echo "router_ssh_state=$router_ssh_state_out"
  echo "ssh_failure_hint=$ssh_failure_hint_out"
  echo "edge_health_state=$edge_health_state_out"
  echo "proxy_state=$proxy_state_out"
  echo "subscription_state=$subscription_state_out"
  echo "automation_state=$automation_state_out"
  echo "client_topology_mode=$client_topology_mode_out"
  echo "client_runtime_present=$client_runtime_present_out"
  echo "client_conflict_risk=$client_conflict_risk_out"
  echo "next_action=$next_action"
  echo "next_action_command=$next_action_command"
fi

case "$doctor_state" in
  repository_attention|host_tools_attention|router_connection_attention)
    exit 1
    ;;
esac
exit 0
