#!/bin/sh
# home-edge-bootstrap/registered-launcher/v1
set -eu
launcher_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
startup_missing_component() {
  printf 'startup_state=failed\nmissing_component=%s\n' "$1" >&2
  printf '%s\n' '请恢复完整项目；若注册入口损坏，请从完整项目目录运行 start.sh，再明确修复注册入口。' 'Restore the complete project. If its registered entry is damaged, run start.sh from the complete project folder and explicitly repair the registration.' >&2
  exit 2
}
for required_component in lib/project-location.sh lib/ui-language.sh; do
  [ -f "$launcher_dir/$required_component" ] && [ -r "$launcher_dir/$required_component" ] || startup_missing_component "$required_component"
done
. "$launcher_dir/lib/project-location.sh"
. "$launcher_dir/lib/ui-language.sh"
language=$(heb_detect_ui_language '')
launcher_check() {
  recovery_zh=$1; shift
  if "$@"; then return 0
  else
    recovery_status=$?
    if [ "$language" != en ]; then printf 'repair_hint=%s\n' "$recovery_zh" >&2; fi
    return "$recovery_status"
  fi
}
explicit_repo=''
if [ "${1:-}" = --repo ]; then
  [ "$#" -ge 2 ] || { heb_ui_text '--repo 需要完整项目文件夹路径。' '--repo needs a complete project folder.' >&2; exit 2; }
  explicit_repo=$2; shift 2
fi
# Resolve language before choosing a project. Keep guide arguments intact.
expect_language=0
skip_value=0
show_help=0
for option in "$@"; do
  if [ "$skip_value" = 1 ]; then skip_value=0; continue; fi
  if [ "$expect_language" = 1 ]; then
    if [ -z "$option" ] || ! resolved_language=$(heb_detect_ui_language "$option"); then
      heb_ui_text '语言无效；请使用 --lang zh-CN 或 --lang en。' 'Invalid language; use --lang zh-CN or --lang en.' >&2
      exit 2
    fi
    language=$resolved_language
    expect_language=0
    continue
  fi
  case "$option" in --lang) expect_language=1 ;; --router) skip_value=1 ;; --help|-h) show_help=1 ;; esac
done
[ "$expect_language" = 0 ] || { heb_ui_text '--lang 需要 zh-CN 或 en。' '--lang needs zh-CN or en.' >&2; exit 2; }
if [ "$show_help" = 1 ]; then
  echo 'usage: start.sh [--lang zh-CN|en] [--router user@host] [--no-color] [--help] [--version]'
  echo 'registered entry: launch-tui.sh [--repo <complete-project-folder>] [guide options]'
  heb_ui_text '注册入口会验证保存的项目目录；目录移动后会重新请求选择。' 'Registered entries validate their saved folder and ask again if it moved.'
  heb_ui_text '语言顺序：显式 --lang、HOME_EDGE_LANGUAGE、系统语言；无系统语言时使用中文。帮助不会联系路由器或写入项目。' 'Language priority: explicit --lang, HOME_EDGE_LANGUAGE, host locale; Chinese when unset. Help does not contact routers or write the project.'
  exit 0
fi
registered=0
if [ -f "$launcher_dir/.home-edge-launcher-owned" ]; then
  [ -f "$launcher_dir/lib/host-launcher.sh" ] && [ -r "$launcher_dir/lib/host-launcher.sh" ] || startup_missing_component lib/host-launcher.sh
  . "$launcher_dir/lib/host-launcher.sh"
  launcher_check '注册正在使用，或其锁定记录无法确认；请结束其他入口设置后重试。未执行项目。' home_edge_acquire_launcher_lock "$launcher_dir" || exit 2
  trap 'home_edge_release_launcher_lock' 0
  trap 'exit 2' HUP INT TERM
  launcher_check '注册路径结构不安全或不完整；请检查启动器目录与文件类型，勿替换不属于本项目的内容。' home_edge_registration_paths "$launcher_dir" || exit 2
  [ "$(cat "$launcher_dir/.home-edge-launcher-owned")" = 'home-edge-bootstrap/registered-launcher/v1' ] || { heb_ui_text '启动器所有权标记无效；请核对入口或从完整项目目录修复。' 'Invalid launcher ownership marker; check the entry or repair it from the complete project folder.' >&2; exit 2; }
  registered=1
fi
if [ -n "$explicit_repo" ]; then candidate=$explicit_repo
else
  candidate="$launcher_dir/.."
  if [ "$registered" = 1 ] && [ -f "$launcher_dir/target.txt" ]; then
    if [ "$(sed -n '1p' "$launcher_dir/target.txt")" = 'home-edge-bootstrap/target/v2' ] && [ "$(wc -l <"$launcher_dir/target.txt" | tr -d ' ')" = 3 ]; then
      candidate=$(sed -n '2p' "$launcher_dir/target.txt")
      saved_identity=$(sed -n '3p' "$launcher_dir/target.txt")
    else heb_ui_text '保存的目录记录无效；请选择完整项目文件夹修复。' 'Invalid saved location; select a complete project folder to repair it.' >&2; candidate=''
    fi
  fi
fi
selected_again=0
while :; do
  if project=$(home_edge_project_dir "$candidate"); then
    if [ "$registered" = 1 ]; then
      current_identity=$(launcher_check '无法验证所选项目的目录实例；请检查完整项目目录及其访问权限后重试。' home_edge_directory_identity "$project") || exit 2
      if [ -z "$explicit_repo" ] && [ "$selected_again" = 0 ] && [ "$current_identity" != "${saved_identity:-}" ]; then
        heb_ui_text '保存的路径已指向另一个目录实例；执行前需要明确重新选择。' 'The saved location contains a different directory instance; choose explicitly before execution.' >&2
      else break
      fi
    else break
    fi
  fi
    echo 'project_location_state=needs_selection'
    heb_ui_text '请选择完整克隆或解压的项目文件夹（包含 PROJECT 和 scripts）；粘贴完整路径，按回车取消：' 'Choose the complete cloned or extracted project folder (containing PROJECT and scripts); paste its full path, or press Enter to cancel:'
    picker_used=0
    if [ -t 0 ]; then
      case "$(uname -s)" in
        Darwin)
          if command -v osascript >/dev/null 2>&1; then
            picker_title=$(heb_ui_text '选择包含 PROJECT 和 scripts 的 Home Edge Bootstrap 文件夹' 'Select the Home Edge Bootstrap folder containing PROJECT and scripts')
            if candidate=$(osascript -e 'on run argv' -e 'try' -e 'return POSIX path of (choose folder with prompt (item 1 of argv))' -e 'on error number -128' -e 'return ""' -e 'end try' -e 'end run' "$picker_title"); then picker_used=1
            else heb_ui_text '文件夹选择器不可用；请粘贴路径继续。' 'Folder chooser unavailable; paste the path to continue.' >&2
            fi
          fi
          ;;
        Linux)
          if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
            picker_title=$(heb_ui_text '选择 Home Edge Bootstrap 项目文件夹' 'Select Home Edge Bootstrap project folder')
            if candidate=$(zenity --file-selection --directory --title="$picker_title"); then
              picker_used=1
            else
              picker_status=$?
              if [ "$picker_status" = 1 ]; then heb_ui_text '已取消文件夹选择；未执行项目。' 'Folder selection cancelled; no project was executed.'; exit 2; fi
              heb_ui_text '文件夹选择器失败；请在当前窗口粘贴项目路径。' 'Folder chooser failed; paste the project path in this window instead.' >&2
              candidate=''
            fi
          fi
          ;;
      esac
    fi
    if [ "$picker_used" = 0 ]; then IFS= read -r candidate || { heb_ui_text '输入结束，启动已取消；未执行项目。' 'Input ended; startup cancelled; no project was executed.'; exit 2; }; fi
    [ -n "$candidate" ] || { heb_ui_text '启动已取消；未执行项目。' 'Startup cancelled; no project was executed.'; exit 2; }
    if [ ! -d "$candidate" ]; then
      case "$candidate" in \"*\") candidate=${candidate#\"}; candidate=${candidate%\"} ;; \'*\') candidate=${candidate#\'}; candidate=${candidate%\'} ;; esac
    fi
    selected_again=1
done
if [ "$selected_again" = 1 ] && [ "$registered" = 1 ]; then
  printf 'home-edge-bootstrap/target/v2\n%s\n%s\n' "$project" "$current_identity" | launcher_check '无法保存已选择的项目路径；请检查启动器注册文件的所有权与写入权限后重试。' home_edge_write_registration "$launcher_dir/target.txt" 600
fi
if [ "$registered" = 1 ]; then home_edge_release_launcher_lock; trap - 0 HUP INT TERM; fi
echo 'project_location_state=verified_structure'
printf 'project_dir=%s\n' "$project"
exec sh "$project/scripts/tui.sh" --lang "$language" "$@"
