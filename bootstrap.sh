#!/bin/sh
# Device-neutral dispatch. Detection and target conventions belong to adapters.
set -eu

root=$(CDPATH= cd "$(dirname "$0")" && pwd)
[ -f "$root/scripts/lib/ui-language.sh" ] && [ -r "$root/scripts/lib/ui-language.sh" ] || {
  printf 'startup_state=failed\nmissing_component=scripts/lib/ui-language.sh\n' >&2
  printf '%s\n' '请恢复完整项目目录后，从目录中的 start.sh 入口重新开始；未执行适配器。' 'Restore the complete project folder, then restart through its start.sh entry; no adapter was executed.' >&2
  exit 2
}
. "$root/scripts/lib/ui-language.sh"
language=$(heb_detect_ui_language '')
# Consume UI-only language options before dispatch; preserve every device argument.
remaining=$#
while [ "$remaining" -gt 0 ]; do
  option=$1; shift; remaining=$((remaining - 1))
  case "$option" in
    --lang)
      [ "$remaining" -gt 0 ] || { heb_ui_text '--lang 需要 zh-CN 或 en。' '--lang needs zh-CN or en.' >&2; exit 2; }
      if [ -z "$1" ] || ! resolved_language=$(heb_detect_ui_language "$1"); then
        heb_ui_text '语言无效；请使用 --lang zh-CN 或 --lang en。' 'Invalid language; use --lang zh-CN or --lang en.' >&2
        exit 2
      fi
      language=$resolved_language; shift; remaining=$((remaining - 1))
      ;;
    *) set -- "$@" "$option" ;;
  esac
done
adapter="${BOOTSTRAP_ADAPTER:-auto}"

if [ "$adapter" = "auto" ]; then
  matches=''; count=0
  for directory in "$root"/adapters/*; do
    [ -d "$directory" ] && [ ! -L "$directory" ] || continue
    id=${directory##*/}
    case "$id" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
    [ -f "$directory/detect.sh" ] && [ ! -L "$directory/detect.sh" ] || continue
    if sh "$directory/detect.sh"; then matches="$matches $id"; count=$((count + 1)); fi
  done
  if [ "$count" -ne 1 ]; then
    printf 'adapter_state=needs_selection\nadapter_candidates=%s\n' "$matches" >&2
    heb_ui_text '自动探测未找到唯一候选；请使用引导诊断，明确选择已安装且适用于设备的适配器。' 'Automatic detection did not find exactly one candidate. Use guided diagnosis and explicitly choose an installed device adapter.' >&2
    quoted_entry=$(printf '%s' "$root/bootstrap.sh" | sed "s/'/'\\\\''/g")
    heb_ui_text '检查本项目 adapters 目录中的已安装适配器，再使用以下命令（将 <adapter-id> 替换为已确认的标识）：' 'Inspect installed adapters below this project, then use (replace <adapter-id> with the confirmed identifier):' >&2
    printf "BOOTSTRAP_ADAPTER=<adapter-id> sh '%s' --dry-run\n" "$quoted_entry" >&2
    heb_ui_text '确认目标是 ASUSWRT-Merlin 后，当前参考适配器的示例命令：' 'Example for the current reference adapter, after confirming an ASUSWRT-Merlin target:' >&2
    printf "BOOTSTRAP_ADAPTER=merlin sh '%s' --dry-run\n" "$quoted_entry" >&2
    exit 2
  fi
  adapter=${matches# }
fi
case "$adapter" in
  ''|*[!A-Za-z0-9_-]*) heb_ui_text '适配器标识无效；未执行适配器。' 'Invalid adapter identifier; no adapter was executed.' >&2; exit 2 ;;
esac
entry="$root/adapters/$adapter/bootstrap.sh"
[ -d "$root/adapters/$adapter" ] && [ ! -L "$root/adapters/$adapter" ] && [ -f "$entry" ] && [ ! -L "$entry" ] || {
  echo "adapter_state=unavailable: $adapter" >&2
  heb_ui_text '适配器不可用；请检查完整项目目录和已安装适配器，再重新选择。' 'Adapter unavailable; check the complete project folder and installed adapters, then choose again.' >&2
  exit 2
}
printf 'adapter_candidate=%s\n' "$adapter"
# Candidate detection is not firmware acceptance. The adapter owns plan/apply gates.
exec sh "$entry" "$@"
