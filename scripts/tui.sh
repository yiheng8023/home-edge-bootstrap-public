#!/bin/sh
# Zero-dependency numbered guide for macOS, Linux, and Git Bash.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$repo/scripts/lib/project-location.sh"
language=zh-CN
router=""
selected_session_dir=""
selected_state_file=""
no_color=0
show_help=0
show_version=0
last_action_status=0
capture_file=""
status_file=""
session_index_file=""

cleanup_temp() {
  [ -z "$capture_file" ] || rm -f "$capture_file"
  [ -z "$status_file" ] || rm -f "$status_file"
  [ -z "$session_index_file" ] || rm -f "$session_index_file"
  capture_file=""
  status_file=""
  session_index_file=""
}
signal_exit() {
  code=$1
  cleanup_temp
  trap - 0 HUP INT TERM
  exit "$code"
}
trap cleanup_temp 0
trap 'signal_exit 129' HUP
trap 'signal_exit 130' INT
trap 'signal_exit 143' TERM

usage() {
  printf 'usage: %s [--lang zh-CN|en] [--router <ssh-user>@<router-ip>] [--no-color] [--help] [--version]\n' "$(command_line sh "$repo/scripts/tui.sh")"
  cat <<'EOF'

Numbered guide over the existing Home Edge bootstrap scripts. Help and version
do not contact a router or the Internet.
EOF
}

quote_argument() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
command_line() {
  separator=''
  for argument do
    printf '%s' "$separator"
    quote_argument "$argument"
    separator=' '
  done
}

version() {
  value=development
  if [ -f "$repo/VERSION" ]; then
    candidate=$(sed -n '1p' "$repo/VERSION" | tr -d '\r')
    [ -z "$candidate" ] || value=$candidate
  fi
  printf 'home-edge-bootstrap %s\n' "$value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lang) shift; [ "$#" -gt 0 ] || { echo "--lang requires a value" >&2; exit 2; }; language=$1 ;;
    --router) shift; [ "$#" -gt 0 ] || { echo "--router requires a value" >&2; exit 2; }; router=$1 ;;
    --no-color) no_color=1 ;;
    --help|-h) show_help=1 ;;
    --version) show_version=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$language" in zh-CN|en) ;; *) echo "unsupported language: $language" >&2; exit 2 ;; esac

valid_router() {
  case "$1" in
    [A-Za-z0-9_.-]*@[A-Za-z0-9]* ) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_.-]+@[A-Za-z0-9][A-Za-z0-9.-]*$' || return 1
  case "$1" in *@*..*|*@.*|*@*.) return 1 ;; esac
  return 0
}
if [ -n "$router" ] && ! valid_router "$router"; then
  echo "invalid router target: $router" >&2
  exit 2
fi

[ "$show_help" -eq 0 ] || { usage; exit 0; }
[ "$show_version" -eq 0 ] || { version; exit 0; }

startup_check() {
  for command in sh mktemp tee sed awk grep cat rm tr; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "startup_state=failed"
      echo "missing_prerequisite=$command"
      return 2
    }
  done
  return 0
}
startup_check || exit $?

show_menu() {
  if [ "$language" = en ]; then
    cat <<'EOF'
# Home Edge Guide
1. Start or resume guided bootstrap
2. Run read-only diagnosis
3. View current bootstrap session state
4. Verify offline runtime bundle
5. Export a redacted support bundle
6. Show help and safety boundaries
7. Review project decommission
8. Create or refresh a local desktop launcher
0. Exit without changes
EOF
    printf 'Select: '
  else
    cat <<'EOF'
# Home Edge 引导器
1. 开始或接续引导式配置
2. 运行只读诊断
3. 查看当前 bootstrap 会话状态
4. 验证离线运行时 bundle
5. 导出脱敏支持包
6. 查看帮助与安全边界
7. 审查项目退出
8. 创建或更新本机桌面启动入口
0. 不做修改并退出
EOF
    printf '请选择: '
  fi
}

state_value_env() {
  awk -F= -v wanted="$2" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$1"
}
state_value_json() {
  sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | sed -n '1p'
}
clear_state() {
  state_bootstrap=""; state_phase=""; state_router=""; state_next_code=""
  state_next_command=""; state_session_dir=""; state_log_dir=""; state_log_path=""; state_updated=""
}
load_state() {
  file=$1
  clear_state
  [ -f "$file" ] || return 1
  case "$file" in
    *.json)
      grep -Eq '^[[:space:]]*\{' "$file" || return 1
      grep -Eq '\}[[:space:]]*$' "$file" || return 1
      getter=state_value_json
      ;;
    *.env) getter=state_value_env ;;
    *) return 1 ;;
  esac
  state_bootstrap=$($getter "$file" bootstrap_state)
  state_phase=$($getter "$file" phase)
  state_router=$($getter "$file" router)
  state_next_code=$($getter "$file" next_action_code)
  state_next_command=$($getter "$file" next_action_command)
  state_session_dir=$($getter "$file" session_dir)
  state_log_dir=$($getter "$file" log_dir)
  state_log_path=$($getter "$file" log_path)
  state_updated=$($getter "$file" updated_at)
  [ -n "$state_bootstrap" ] && [ -n "$state_router" ]
}
known_next_code() {
  case "$1" in
    ''|none|enable_router_prereqs|resolve_action_findings|review_baseline_findings|deploy_plan|store_or_import_subscription|store_subscription_for_managed_switching|inspect_self_heal_dry_run|enable_live_self_heal|monitor_live_managed|inspect_audit_log|manual_prerequisite_setup|step_failed|inspect_logs|resume|installation_closeout_*) return 0 ;;
    *) return 1 ;;
  esac
}

session_count=0
list_sessions() {
  session_count=0
  session_index_file=$(mktemp "${TMPDIR:-/tmp}/home-edge-tui-sessions.XXXXXX") || return 1
  root="$repo/logs/bootstrap"
  [ -d "$root" ] || return 0
  for dir in "$root"/*; do
    [ -d "$dir" ] || continue
    if [ -f "$dir/state.env" ]; then state_file="$dir/state.env"
    elif [ -f "$dir/state.json" ]; then state_file="$dir/state.json"
    else continue
    fi
    session_count=$((session_count + 1))
    if load_state "$state_file"; then display_router=$state_router; display_state=$state_bootstrap
    else display_router='<unknown>'; display_state=malformed
    fi
    printf '%s|%s|%s\n' "$session_count" "$dir" "$state_file" >>"$session_index_file"
    printf 'existing_session=%s router=%s bootstrap_state=%s session_dir=%s\n' "$session_count" "$display_router" "$display_state" "$dir"
  done
  return 0
}

ensure_router() {
  [ -z "$router" ] || return 0
  list_sessions || return 1
  if [ "$session_count" -gt 0 ]; then
    if [ "$language" = en ]; then printf 'Select an existing session number, or press Enter to type a router target: '
    else printf '选择现有会话编号，或直接回车后输入路由器目标: '
    fi
    if ! IFS= read -r selection; then return 1; fi
    if [ -n "$selection" ]; then
      case "$selection" in *[!0-9]*|0) echo "attention_state=invalid_session_selection"; return 1 ;; esac
      record=$(awk -F'|' -v wanted="$selection" '$1 == wanted { print; exit }' "$session_index_file")
      [ -n "$record" ] || { echo "attention_state=invalid_session_selection"; return 1; }
      selected_session_dir=$(printf '%s\n' "$record" | awk -F'|' '{print $2}')
      selected_state_file=$(printf '%s\n' "$record" | awk -F'|' '{print $3}')
      session_leaf=${selected_session_dir##*/}
      case "$session_leaf" in ''|*[!A-Za-z0-9_.-]*) echo "attention_state=malformed_session_state"; return 1 ;; esac
      if ! load_state "$selected_state_file" || ! valid_router "$state_router"; then
        echo "attention_state=malformed_session_state"
        return 1
      fi
      router=$state_router
      return 0
    fi
  fi
  if [ "$language" = en ]; then printf 'Enter router SSH target (user@ip): '
  else printf '请输入路由器 SSH 目标（user@ip）: '
  fi
  if ! IFS= read -r router; then return 1; fi
  if ! valid_router "$router"; then
    if [ "$language" = en ]; then echo "Invalid router target."; else echo "路由器目标格式无效。"; fi
    router=""
    return 1
  fi
  return 0
}

operation_available() {
  if [ ! -f "$1" ]; then
    last_action_status=2
    echo 'capability_state=unavailable'
    printf 'missing_component=%s\n' "$1"
    echo 'This operation is not installed. The menu and local launcher remain available; consult the compatibility guide before adding a device adapter.'
    return 2
  fi
  return 0
}
run_child() {
  action=$1; write_started=$2; shift 2
  if [ "${1:-}" = sh ]; then operation_available "${2:-}" || return 2; fi
  resume_command=$(command_line "$@")
  tmp_base=${TMPDIR:-/tmp}; [ "$tmp_base" = / ] || tmp_base=${tmp_base%/}
  capture_file=$(mktemp "$tmp_base/home-edge-tui-output.XXXXXX") || return 1
  status_file=$(mktemp "$tmp_base/home-edge-tui-status.XXXXXX") || { cleanup_temp; return 1; }
  ( "$@"; printf '%s\n' "$?" >"$status_file" ) 2>&1 | tee "$capture_file"
  child_status=$(sed -n '1p' "$status_file")
  case "$child_status" in ''|*[!0-9]*) child_status=1 ;; esac
  child_output=$(cat "$capture_file")
  rm -f "$capture_file" "$status_file"; capture_file=""; status_file=""
  last_action_status=$child_status
  if [ "$child_status" -ne 0 ]; then
    echo "failed_action=$action"
    echo "child_exit_code=$child_status"
    echo "safe_resume_command=$resume_command"
    [ "$write_started" = true ] && echo "write_action_started=true"
  fi
  return "$child_status"
}

run_doctor() {
  if [ -n "$router" ]; then run_child doctor false sh "$repo/scripts/doctor.sh" --json "$router"
  else run_child doctor false sh "$repo/scripts/doctor.sh" --json
  fi
}
bootstrap_resume() {
  bootstrap_operation display '' "$1" false
}
run_bootstrap_child() {
  bootstrap_operation run "$1" "$2" "$3"
}
bootstrap_operation() {
  mode=$1; action=$2; flags=$3; write_started=$4
  set -- --no-pause
  [ -z "$flags" ] || set -- "$@" "$flags"
  if [ -n "$selected_session_dir" ]; then
    set -- "$@" --session-dir "$selected_session_dir"
  fi
  set -- "$@" "$router"
  if [ "$mode" = display ]; then command_line sh "$repo/scripts/run-bootstrap.sh" "$@"
  else run_child "$action" "$write_started" sh "$repo/scripts/run-bootstrap.sh" "$@"
  fi
}
output_value() { printf '%s\n' "$child_output" | awk -F= -v wanted="$1" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }'; }
show_write_disclosure() {
  effect=$1; command=$2
  session_destination=$(output_value session_dir); log_destination=$(output_value log_path)
  [ -n "$session_destination" ] || session_destination=${selected_session_dir:-unknown}
  [ -n "$log_destination" ] || log_destination=unknown
  echo "exact_command=$command"
  echo "expected_effect=$effect"
  printf 'rollback_path=%s\n' "$(command_line sh "$repo/scripts/rollback-merlin.sh" "$router")"
  echo "session_destination=$session_destination"
  echo "log_destination=$log_destination"
}

start_or_resume() {
  last_action_status=0
  operation_available "$repo/scripts/run-bootstrap.sh" || return 0
  operation_available "$repo/scripts/doctor.sh" || return 0
  ensure_router || return 0
  run_doctor || return 0
  run_bootstrap_child bootstrap_read_only "" false || return 0
  bootstrap_state=$(output_value bootstrap_state)
  next_code=$(output_value next_action_code)
  if [ -z "$bootstrap_state" ]; then echo "attention_state=malformed_child_state"; return 0; fi
  if [ "$bootstrap_state" = pass ]; then return 0; fi
  case "$next_code" in
    deploy_plan)
      exact=$(bootstrap_resume --apply-deploy)
      show_write_disclosure apply_reviewed_deployment_plan "$exact"
      if [ "$language" = en ]; then printf 'Deployment is ready. Type APPLY to confirm; anything else cancels: '
      else printf '即将执行部署。输入 APPLY 确认，其他输入取消: '
      fi
      if ! IFS= read -r confirmation || [ "$confirmation" != APPLY ]; then
        if [ "$language" = en ]; then echo "Action cancelled."; else echo "操作已取消。"; fi
        return 0
      fi
      run_bootstrap_child apply_deploy --apply-deploy true || return 0
      ;;
    enable_live_self_heal)
      exact=$(bootstrap_resume --enable-live-self-heal)
      show_write_disclosure enable_live_self_heal "$exact"
      if [ "$language" = en ]; then printf 'Live self-heal is ready. Type ENABLE to confirm; anything else cancels: '
      else printf '即将开启真实自愈。输入 ENABLE 确认，其他输入取消: '
      fi
      if ! IFS= read -r confirmation || [ "$confirmation" != ENABLE ]; then
        if [ "$language" = en ]; then echo "Action cancelled."; else echo "操作已取消。"; fi
        return 0
      fi
      run_bootstrap_child enable_live_self_heal --enable-live-self-heal true || return 0
      ;;
    *)
      if ! known_next_code "$next_code"; then echo "attention_state=unknown_next_action"; fi
      printf '%s\n' "$child_output" | awk -F= '$1 == "next_action_command" || $1 == "session_dir" || $1 == "log_path" { print }'
      ;;
  esac
}

show_session() {
  last_action_status=0
  ensure_router || return 0
  state_path=$selected_state_file
  if [ -z "$state_path" ]; then
    router_id=$(printf '%s' "$router" | sed 's/[^A-Za-z0-9_.-]/_/g')
    state_dir="$repo/logs/bootstrap/$router_id"
    if [ -f "$state_dir/state.env" ]; then state_path="$state_dir/state.env"
    elif [ -f "$state_dir/state.json" ]; then state_path="$state_dir/state.json"
    fi
  fi
  if [ -z "$state_path" ] || [ ! -f "$state_path" ]; then
    if [ "$language" = en ]; then echo "Session state not found."; else echo "未找到会话状态。"; fi
    return 0
  fi
  if ! load_state "$state_path" || ! valid_router "$state_router"; then echo "attention_state=malformed_session_state"; return 0; fi
  for pair in "bootstrap_state=$state_bootstrap" "phase=$state_phase" "router=$state_router" "next_action_code=$state_next_code" "next_action_command=$state_next_command" "session_dir=$state_session_dir" "log_dir=$state_log_dir" "log_path=$state_log_path" "updated_at=$state_updated"; do
    case "$pair" in *=) ;; *) printf '%s\n' "$pair" ;; esac
  done
  known_next_code "$state_next_code" || echo "attention_state=unknown_session_state"
}

verify_bundle() { run_child verify_offline_bundle false sh "$repo/scripts/check-no-wall-readiness.sh" || return 0; }
export_support() {
  if [ -n "$router" ]; then run_child export_support_bundle false sh "$repo/scripts/export-support-bundle.sh" "$router" || return 0
  else run_child export_support_bundle false sh "$repo/scripts/export-support-bundle.sh" || return 0
  fi
}
show_safety_help() {
  last_action_status=0; usage
  if [ "$language" = en ]; then echo "Read-only actions may run directly. Deploy, live self-heal, and decommission apply require their exact confirmation tokens."
  else echo "帮助与安全边界：只读操作可直接运行；部署、真实自愈和项目退出执行必须输入各自的精确确认令牌。"
  fi
}
review_decommission() {
  last_action_status=0
  operation_available "$repo/scripts/decommission-merlin.sh" || return 0
  ensure_router || return 0
  run_child decommission_plan false sh "$repo/scripts/decommission-merlin.sh" "$router" || return 0
  apply_resume=$(command_line sh "$repo/scripts/decommission-merlin.sh" --apply --confirm DECOMMISSION "$router")
  printf 'exact_command=%s\nexpected_effect=apply_reviewed_decommission_plan\n' "$apply_resume"
  if [ "$language" = en ]; then
    printf 'The project decommission plan is shown above. Type DECOMMISSION to confirm; anything else cancels: '
  else
    printf '项目退出计划已显示。输入 DECOMMISSION 确认，其他输入取消: '
  fi
  if ! IFS= read -r confirmation || [ "$confirmation" != DECOMMISSION ]; then
    if [ "$language" = en ]; then echo "Action cancelled."; else echo "操作已取消。"; fi
    return 0
  fi
  run_child decommission_apply true sh "$repo/scripts/decommission-merlin.sh" --apply --confirm DECOMMISSION "$router" || return 0
}

while :; do
  if ! home_edge_project_dir "$repo" >/dev/null; then echo 'startup_state=invalid_project'; exit 2; fi
  show_menu
  if ! IFS= read -r choice; then printf '\n'; exit "$last_action_status"; fi
  case "$choice" in
    0) exit "$last_action_status" ;;
    1) start_or_resume ;;
    2) run_doctor || true ;;
    3) show_session ;;
    4) verify_bundle ;;
    5) export_support ;;
    6) show_safety_help ;;
    7) review_decommission ;;
    8) run_child create_local_launcher true sh "$repo/scripts/create-desktop-shortcut.sh" || true ;;
    *) if [ "$language" = en ]; then echo "Invalid selection."; else echo "无效选择。"; fi ;;
  esac
  echo
done
