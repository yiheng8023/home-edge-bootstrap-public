#!/bin/sh
# Zero-dependency numbered guide for macOS, Linux, and Git Bash.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
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
  printf 'usage: %s [--lang zh-CN|en] [--router <ssh-user>@<router-ip>] [--no-color] [--help] [--version]\n' "${usage_command:-$(command_line sh "$repo/scripts/tui.sh")}"
  printf '\n'
  if [ "$language" = en ]; then
    while IFS= read -r help_line || [ -n "$help_line" ]; do printf '%s\n' "$help_line"; done <<'EOF'
Home Edge local help
Help and language switching only change this screen; no router, network, program launch, or project write.

Menu guide:
1. Start or resume: choose a saved session or enter user@router. Diagnosis and planning run before any confirmed change.
   First installation: review compatibility and prerequisites, then the deployment plan. Already installed: inspect diagnosis/session state first; do not assume reinstall or overwrite is required.
2. Diagnosis: run the doctor. Read-only checks may contact a configured router; review reported findings.
3. Session: read saved local state and next-action hints. Saved commands are displayed as data, never executed by this choice.
4. Offline bundle: verify the runtime bundle and readiness before deployment.
5. Support: export a redacted local support bundle; review its contents before sharing.
6 / H / ? / help: show this local help at any time from the main menu.
7. Decommission: show the project removal plan, then require DECOMMISSION before applying it.
8. Desktop: explicitly create or refresh a local launcher; this writes local launcher files.
9 / L / language: toggle Chinese and English immediately for this session, keeping the router and selected session.
R. Explicitly refresh owned project content: review a fresh installation probe and plan, then type REPLACE followed by APPLY. Runtime/core assets are preserved; project-managed policy, integration and configuration may change per plan. The current tree is backed up to <project-path>.prev; an older backup may be replaced.
0. Exit. End of input (EOF) exits; at a confirmation prompt, EOF or any other token cancels that operation. Ctrl+C interrupts.

Safety: review the exact command, target, expected effect, session/log destinations and rollback path before confirming.
Deployment requires exact APPLY; project refresh additionally requires REPLACE first; live self-heal requires exact ENABLE; project removal requires exact DECOMMISSION.
Tokens are case-sensitive and accept no extra spaces. Help/language/Enter do not authorize these operations.
If an operation is unavailable, keep using local help and check compatibility before adding an adapter.

Project location: use the complete cloned or extracted folder containing PROJECT, README.md and scripts; do not select a ZIP or single script.
The paths below bind to this running project. Open/read them yourself; help does not open programs.
EOF
    docs_dir="$repo/docs"; readme="$repo/README.md"
  else
    while IFS= read -r help_line || [ -n "$help_line" ]; do printf '%s\n' "$help_line"; done <<'EOF'
Home Edge 本地帮助
帮助和语言切换只改变当前界面；不会联系路由器、联网、打开程序或写入项目。

菜单说明：
1. 开始或接续：选择已有会话或输入 user@router。先诊断和审查计划，再确认修改。
   首次安装：先核对兼容性与前置条件，再审查部署计划。已经安装：先查看诊断和会话状态；不要默认需要重装或覆盖。
2. 只读诊断：运行 doctor。只读检查可能联系已配置路由器，请审查发现的问题。
3. 会话状态：读取本地保存的状态和下一步提示；记录中的命令仅作为数据展示，此选项不会执行它们。
4. 离线 bundle：部署前验证运行时包与就绪情况。
5. 支持包：导出本地脱敏支持包；分享前请审查内容。
6 / H / ? / help：在主菜单随时查看此本地帮助。
7. 项目退出：先显示项目移除计划，输入 DECOMMISSION 后才会执行。
8. 桌面入口：明确创建或更新本机启动入口，会写入本机启动文件。
9 / L / language：立即切换本次会话的中英文，保留路由器和所选会话。
R. 明确刷新本项目管理的内容：先审查最新安装探测与计划，再先输入 REPLACE 后输入 APPLY。运行时/核心资产保留；本项目管理的策略、集成与配置可能按计划变化。当前项目树备份至 <项目路径>.prev，旧备份可能被替换。
0. 退出。输入结束（EOF）会退出；确认提示处的 EOF 或其他令牌取消该操作。Ctrl+C 中断。

安全约束：确认前审查精确命令、目标、预期影响、会话和日志位置以及回退路径。
部署必须精确输入 APPLY；刷新本项目还必须先输入 REPLACE；真实自愈必须精确输入 ENABLE；项目移除必须精确输入 DECOMMISSION。
令牌区分大小写且不接受多余空格。帮助、切换语言或回车都不授权这些操作。
如操作尚不可用，可继续查看本地帮助，并在添加适配器前核对兼容性。

项目目录：请选择完整克隆或解压后的文件夹，其中应包含 PROJECT、README.md 和 scripts；不要选择 ZIP 或单个脚本。
下面路径绑定当前运行的项目。请自行打开或阅读；帮助不会打开程序。
EOF
    docs_dir="$repo/docs/zh-CN"; readme="$repo/README.zh-CN.md"
  fi
  printf 'project_dir=%s\nreadme=%s\n' "$repo" "$readme"
  for name in LAUNCHER.md COMPATIBILITY.md RUNBOOK.md NO_WALL_BOOTSTRAP.md; do
    printf 'doc=%s/%s\n' "$docs_dir" "$name"
  done
}
switch_language() {
  if [ "$language" = en ]; then language=zh-CN; else language=en; fi
  printf 'language=%s\n' "$language"
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

. "$repo/scripts/lib/project-location.sh"
if [ ! -f "$repo/scripts/lib/host-launcher.sh" ]; then echo 'startup_state=failed'; echo 'missing_component=scripts/lib/host-launcher.sh'; exit 2; fi
. "$repo/scripts/lib/host-launcher.sh"

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
repo_identity=$(home_edge_directory_identity "$repo") || { echo 'startup_state=failed'; echo 'repair_hint=Restore the complete project folder and required local tools, then restart.'; exit 2; }
home_edge_project_dir "$repo" >/dev/null || { echo 'startup_state=invalid_project'; exit 2; }
usage_command=$(command_line sh "$repo/scripts/tui.sh")

guide_tools_available() {
  # A shell can cache the path of an executable after its file disappears.
  hash -r
  for guide_tool in sh mktemp tee sed awk grep cat rm tr stat uname; do
    if ! command -v "$guide_tool" >/dev/null 2>&1; then
      last_action_status=2
      echo 'capability_state=unavailable'
      printf 'missing_prerequisite=%s\n' "$guide_tool"
      echo 'repair_hint=Restore the required local tool, then restart or retry. Local help, language and exit remain available.'
      return 2
    fi
  done
  return 0
}
current_project() {
  guide_tools_available || return 2
  if [ ! -f "$repo/scripts/lib/host-launcher.sh" ] || ! home_edge_project_dir "$repo" >/dev/null 2>&1; then
    last_action_status=2
    echo 'condition_state=project_degraded'
    echo 'repair_hint=Restore the complete original project folder and restart this guide from that folder.'
    return 2
  fi
  current_identity=$(home_edge_directory_identity "$repo") || {
    last_action_status=2; echo 'condition_state=project_degraded'; echo 'repair_hint=Restore the required local tools and restart this guide.'; return 2;
  }
  if [ "$current_identity" != "$repo_identity" ]; then
    last_action_status=2
    echo 'condition_state=project_degraded'
    echo 'repair_hint=The project directory was replaced; restart from the complete original project folder.'
    return 2
  fi
  return 0
}

show_menu() {
  if [ "$language" = en ]; then
    while IFS= read -r menu_line || [ -n "$menu_line" ]; do printf '%s\n' "$menu_line"; done <<'EOF'
# Home Edge Guide
1. Start or resume guided bootstrap
2. Run read-only diagnosis
3. View current bootstrap session state
4. Verify offline runtime bundle
5. Export a redacted support bundle
6. Show help and safety boundaries
7. Review project decommission
8. Create or refresh a local desktop launcher
9 / L / language. Switch language (current: English)
H / ? / help. Local help
R. Reinstall / refresh this project only (requires REPLACE then APPLY)
Local project located; router installation is checked only after choosing a target and an operation.
0. Exit without changes
EOF
    printf 'Select: '
  else
    while IFS= read -r menu_line || [ -n "$menu_line" ]; do printf '%s\n' "$menu_line"; done <<'EOF'
# Home Edge 引导器
1. 开始或接续引导式配置
2. 运行只读诊断
3. 查看当前 bootstrap 会话状态
4. 验证离线运行时 bundle
5. 导出脱敏支持包
6. 查看帮助与安全边界
7. 审查项目退出
8. 创建或更新本机桌面启动入口
9 / L / language. 切换语言（当前：中文）
H / ? / help. 本地帮助
R. 重新安装 / 刷新本项目（需先 REPLACE 再 APPLY）
已定位本地项目；路由器安装状态需选择目标和操作后才检查。
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
  tmp_base=${TMPDIR:-/tmp}
  if command -v cygpath >/dev/null 2>&1; then tmp_base=$(cygpath -u "$tmp_base"); fi
  [ "$tmp_base" = / ] || tmp_base=${tmp_base%/}
  session_index_file=$(mktemp "$tmp_base/home-edge-tui-sessions.XXXXXX") || return 1
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
  current_project || return 2
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    last_action_status=2
    echo 'capability_state=unavailable'
    printf 'missing_component=%s\n' "$1"
    echo 'Restore or update the complete project folder, then restart this guide. Local help, language switching and exit remain available.'
    return 2
  fi
  return 0
}
run_child() {
  action=$1; write_started=$2; shift 2
  guide_tools_available || return 2
  if ! command -v "${1:-}" >/dev/null 2>&1; then
    last_action_status=2; echo 'capability_state=unavailable'; printf 'missing_prerequisite=%s\n' "${1:-unknown}"; echo 'Restore the required local tool, then retry.'; return 2
  fi
  expect_script=0
  for token do
    if [ "$expect_script" -eq 1 ]; then operation_available "$token" || return 2; break; fi
    [ "$token" != sh ] || expect_script=1
  done
  resume_command=$(command_line "$@")
  tmp_base=${TMPDIR:-/tmp}
  if command -v cygpath >/dev/null 2>&1; then tmp_base=$(cygpath -u "$tmp_base"); fi
  [ "$tmp_base" = / ] || tmp_base=${tmp_base%/}
  capture_file=$(mktemp "$tmp_base/home-edge-tui-output.XXXXXX") || return 1
  status_file=$(mktemp "$tmp_base/home-edge-tui-status.XXXXXX") || { cleanup_temp; return 1; }
  ( "$@"; printf '%s\n' "$?" >"$status_file" ) 2>&1 | tee "$capture_file"
  capture_status=$?
  if [ "$capture_status" -ne 0 ] || ! guide_tools_available; then
    last_action_status=2
    echo "failed_action=$action"
    echo 'child_result_state=capture_unavailable'
    [ "$write_started" != true ] || echo 'write_action_started=true'
    cleanup_temp
    return 2
  fi
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
  if [ "$mode" = display ]; then command_line env BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_REPLACE_RUNTIME=0 BOOTSTRAP_REPLACE_CORE=0 INCLUDE_BUNDLE=0 BOOTSTRAP_REPLACE_PROJECT=0 BOOTSTRAP_PROJECT_CONFIRMATION= sh "$repo/scripts/run-bootstrap.sh" "$@"
  else run_child "$action" "$write_started" env BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_REPLACE_RUNTIME=0 BOOTSTRAP_REPLACE_CORE=0 INCLUDE_BUNDLE=0 BOOTSTRAP_REPLACE_PROJECT=0 BOOTSTRAP_PROJECT_CONFIRMATION= sh "$repo/scripts/run-bootstrap.sh" "$@"
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

probe_field() {
  printf '%s\n' "$child_output" | tr -d '\r' | awk -F= -v wanted="project_install_$1" '
    $1 == wanted { count++; value=substr($0, index($0, "=") + 1) }
    END { if (count != 1) exit 2; print value }'
}
probe_installation() {
  run_child project_installation_probe false sh "$repo/scripts/check-project-installation.sh" "$router" || { echo 'attention_state=project_installation_unknown'; return 1; }
  probe_schema=$(probe_field schema) && probe_router=$(probe_field router) && probe_state=$(probe_field state) && probe_reason=$(probe_field reason) && probe_path=$(probe_field path) && probe_allowed=$(probe_field replace_allowed) || {
    last_action_status=2; echo 'attention_state=invalid_installation_probe'; return 1;
  }
  valid_probe=1
  [ "$probe_schema" = 1 ] && [ "$probe_router" = "$router" ] || valid_probe=0
  case "$probe_state" in installed|not_installed|partial|unknown) ;; *) valid_probe=0 ;; esac
  case "$probe_allowed" in 0|1) ;; *) valid_probe=0 ;; esac
  printf '%s\n' "$probe_reason" | grep -Eq '^[a-z0-9_]+$' || valid_probe=0
  printf '%s\n' "$probe_path" | grep -Eq '^/jffs/[A-Za-z0-9_.-]+$' || valid_probe=0
  case "$probe_path" in /jffs/.|/jffs/..) valid_probe=0 ;; esac
  case "$probe_state:$probe_allowed" in unknown:1|not_installed:1) valid_probe=0 ;; esac
  [ "$valid_probe" -eq 1 ] || { last_action_status=2; echo 'attention_state=invalid_installation_probe'; return 1; }
  [ "$probe_state" != unknown ] || { last_action_status=1; echo 'attention_state=project_installation_unknown'; return 1; }
  return 0
}
show_existing_installation() {
  if [ "$language" = en ]; then echo "Existing or partial project content was found. Continue with diagnosis and saved session state. To refresh owned project content, explicitly choose R; runtime/core assets are preserved, while project-managed policy, integration and configuration may change per plan."
  else echo '发现已有或不完整的项目内容。默认继续诊断并查看会话状态；如需刷新本项目内容，请明确选择 R。运行时/核心资产保留；本项目管理的策略、集成与配置可能按计划变化。'
  fi
}
confirm_project_refresh() {
  printf 'project_refresh_path=%s\nproject_backup_path=%s.prev\n' "$probe_path" "$probe_path"
  if [ "$language" = en ]; then
    echo "Refresh replaces this project's managed content. The current project tree is backed up at the path above; an older .prev backup may be replaced. Runtime/core assets are preserved; project-managed policy, integration and configuration may change per plan. Review the plan and backup contents."
    printf 'Type REPLACE to choose this project refresh; anything else cancels: '
  else
    echo '刷新会替换本项目管理的内容。当前项目树备份至上述路径，旧 .prev 备份可能被替换。运行时/核心资产保留；本项目管理的策略、集成与配置可能按计划变化。请审查计划与备份内容。'
    printf '输入 REPLACE 明确选择刷新本项目，其他输入取消: '
  fi
  if ! IFS= read -r confirmation || [ "$confirmation" != REPLACE ]; then
    if [ "$language" = en ]; then echo 'Action cancelled.'; else echo '操作已取消。'; fi
    return 1
  fi
  if [ "$language" = en ]; then printf 'Type APPLY to apply the reviewed project refresh; anything else cancels: '
  else printf '即将执行部署。输入 APPLY 确认，其他输入取消: '
  fi
  if ! IFS= read -r confirmation || [ "$confirmation" != APPLY ]; then
    if [ "$language" = en ]; then echo 'Action cancelled.'; else echo '操作已取消。'; fi
    return 1
  fi
  return 0
}
project_deploy_command() {
  # Override only this child environment; inherited runtime replacement flags never widen R.
  set -- env REMOTE_DIR="$probe_path" APPLY="$1" BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_REPLACE_RUNTIME=0 BOOTSTRAP_REPLACE_CORE=0 INCLUDE_BUNDLE=0 BOOTSTRAP_REPLACE_PROJECT="$2" BOOTSTRAP_PROJECT_CONFIRMATION="$3" sh "$repo/scripts/deploy-merlin.sh" "$router" --project-only
  if [ "$deploy_mode" = display ]; then command_line "$@"
  else run_child "$deploy_action" "$deploy_write" "$@"
  fi
}
refresh_project() {
  last_action_status=0
  operation_available "$repo/scripts/deploy-merlin.sh" || return 0
  operation_available "$repo/scripts/check-project-installation.sh" || return 0
  ensure_router || return 0
  probe_installation || return 0
  if [ "$probe_state" = not_installed ]; then
    if [ "$language" = en ]; then echo 'Project is not installed on this target. Choose 1 for first installation.'
    else echo '此目标尚未安装本项目。请选择 1 进行首次安装。'; fi
    return 0
  fi
  [ "$probe_allowed" = 1 ] || { echo 'attention_state=project_refresh_not_allowed'; return 0; }
  deploy_mode=run; deploy_action=project_refresh_plan; deploy_write=false
  project_deploy_command 0 0 '' || return 0
  if [ "$(output_value deploy_state)" != plan ] || [ "$(output_value router)" != "$router" ] || [ "$(output_value remote_dir)" != "$probe_path" ] || [ "$(output_value runtime_assets_effect)" != preserve ] || [ "$(output_value integration_effect)" != project_managed_configuration_may_change ]; then echo 'attention_state=invalid_project_refresh_plan'; return 0; fi
  deploy_mode=display
  refresh_exact=$(project_deploy_command 1 1 REPLACE)
  show_write_disclosure refresh_project_managed_content_preserve_runtime_core_assets "$refresh_exact"
  confirm_project_refresh || return 0
  planned_probe_router=$probe_router; planned_probe_path=$probe_path; planned_probe_state=$probe_state
  probe_installation || return 0
  if [ "$probe_router" != "$planned_probe_router" ] || [ "$probe_path" != "$planned_probe_path" ] || [ "$probe_state" != "$planned_probe_state" ] || [ "$probe_allowed" != 1 ]; then echo 'attention_state=installation_probe_changed'; return 0; fi
  deploy_mode=run; deploy_action=project_refresh_apply; deploy_write=true
  project_deploy_command 1 1 REPLACE || return 0
  if [ "$(output_value deploy_state)" != applied ]; then last_action_status=2; echo 'attention_state=project_refresh_result_unconfirmed'; echo 'health_state=not_checked'; return 0; fi
  echo 'project_refresh_state=applied'
  if run_doctor; then echo 'health_state=doctor_reported'; else echo 'health_state=not_checked'; fi
}

start_or_resume() {
  last_action_status=0
  operation_available "$repo/scripts/run-bootstrap.sh" || return 0
  operation_available "$repo/scripts/doctor.sh" || return 0
  ensure_router || return 0
  probe_installation || return 0
  [ "$probe_state" = not_installed ] || show_existing_installation
  run_doctor || return 0
  run_bootstrap_child bootstrap_read_only "" false || return 0
  bootstrap_state=$(output_value bootstrap_state)
  next_code=$(output_value next_action_code)
  if [ -z "$bootstrap_state" ]; then echo "attention_state=malformed_child_state"; return 0; fi
  if [ "$bootstrap_state" = pass ]; then return 0; fi
  case "$next_code" in
    deploy_plan)
      if [ "$probe_state" != not_installed ]; then show_existing_installation; return 0; fi
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
      if [ "$probe_state" = partial ] || { [ "$probe_state" = installed ] && [ "$probe_allowed" != 1 ]; }; then echo "attention_state=installation_requires_review"; return 0; fi
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
show_safety_help() { usage; }
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
  menu_ready=1
  current_project || menu_ready=0
  show_menu
  if ! IFS= read -r choice; then printf '\n'; exit "$last_action_status"; fi
  case "$choice" in 0|6|H|h|\?|help|HELP|9|L|l|language|LANGUAGE) ;; *)
    if [ "$menu_ready" -ne 1 ] || ! current_project; then continue; fi ;;
  esac
  case "$choice" in
    0) exit "$last_action_status" ;;
    1) start_or_resume ;;
    R|r) refresh_project ;;
    2) run_doctor || true ;;
    3) show_session ;;
    4) verify_bundle ;;
    5) export_support ;;
    6|H|h|\?|help|HELP) show_safety_help ;;
    9|L|l|language|LANGUAGE) switch_language ;;
    7) review_decommission ;;
    8) run_child create_local_launcher true sh "$repo/scripts/create-desktop-shortcut.sh" || true ;;
    *) if [ "$language" = en ]; then echo "Invalid selection."; else echo "无效选择。"; fi ;;
  esac
  echo
done
