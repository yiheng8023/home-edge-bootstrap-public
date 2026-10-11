#!/bin/sh
# home-edge-bootstrap/registered-launcher/v1
set -eu
launcher_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
. "$launcher_dir/lib/project-location.sh"
explicit_repo=''
if [ "${1:-}" = --repo ]; then
  [ "$#" -ge 2 ] || { echo '--repo needs a complete project folder.' >&2; exit 2; }
  explicit_repo=$2; shift 2
fi
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo 'usage: start.sh [--lang zh-CN|en] [--router user@host] [--no-color] [--help] [--version]'
  echo 'registered entry: launch-tui.sh [--repo <complete-project-folder>] [guide options]'
  echo 'Registered entries validate their saved folder and ask again if it moved.'
  exit 0
fi
registered=0
if [ -f "$launcher_dir/.home-edge-launcher-owned" ]; then
  . "$launcher_dir/lib/host-launcher.sh"
  home_edge_acquire_launcher_lock "$launcher_dir" || exit 2
  trap 'home_edge_release_launcher_lock' 0
  trap 'exit 2' HUP INT TERM
  home_edge_registration_paths "$launcher_dir" || exit 2
  [ "$(cat "$launcher_dir/.home-edge-launcher-owned")" = 'home-edge-bootstrap/registered-launcher/v1' ] || { echo 'Invalid launcher ownership marker.' >&2; exit 2; }
  registered=1
fi
if [ -n "$explicit_repo" ]; then candidate=$explicit_repo
else
  candidate="$launcher_dir/.."
  if [ "$registered" = 1 ] && [ -f "$launcher_dir/target.txt" ]; then
    if [ "$(sed -n '1p' "$launcher_dir/target.txt")" = 'home-edge-bootstrap/target/v2' ] && [ "$(wc -l <"$launcher_dir/target.txt" | tr -d ' ')" = 3 ]; then
      candidate=$(sed -n '2p' "$launcher_dir/target.txt")
      saved_identity=$(sed -n '3p' "$launcher_dir/target.txt")
    else echo 'Invalid saved location; select a complete project folder to repair it.' >&2; candidate=''
    fi
  fi
fi
selected_again=0
while :; do
  if project=$(home_edge_project_dir "$candidate"); then
    if [ "$registered" = 1 ]; then
      current_identity=$(home_edge_directory_identity "$project") || exit 2
      if [ -z "$explicit_repo" ] && [ "$selected_again" = 0 ] && [ "$current_identity" != "${saved_identity:-}" ]; then
        echo 'The saved location contains a different directory instance; choose explicitly before execution.' >&2
      else break
      fi
    else break
    fi
  fi
    echo 'project_location_state=needs_selection'
    echo 'Paste the full cloned or extracted project folder path (containing PROJECT and scripts), or press Enter to cancel:'
    picker_used=0
    if [ -t 0 ]; then
      case "$(uname -s)" in
        Darwin)
          if command -v osascript >/dev/null 2>&1; then
            if candidate=$(osascript -e 'try' -e 'return POSIX path of (choose folder with prompt "Select the Home Edge Bootstrap folder containing PROJECT and scripts")' -e 'on error number -128' -e 'return ""' -e 'end try'); then picker_used=1
            else echo 'Folder chooser unavailable; paste the path to continue.' >&2
            fi
          fi
          ;;
        Linux)
          if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
            if candidate=$(zenity --file-selection --directory --title='Select Home Edge Bootstrap project folder'); then
              picker_used=1
            else
              picker_status=$?
              if [ "$picker_status" = 1 ]; then echo 'Folder selection cancelled; no project was executed.'; exit 2; fi
              echo 'Folder chooser failed; paste the project path in this window instead.' >&2
              candidate=''
            fi
          fi
          ;;
      esac
    fi
    if [ "$picker_used" = 0 ]; then IFS= read -r candidate || exit 2; fi
    [ -n "$candidate" ] || exit 2
    if [ ! -d "$candidate" ]; then
      case "$candidate" in \"*\") candidate=${candidate#\"}; candidate=${candidate%\"} ;; \'*\') candidate=${candidate#\'}; candidate=${candidate%\'} ;; esac
    fi
    selected_again=1
done
if [ "$selected_again" = 1 ] && [ "$registered" = 1 ]; then
  printf 'home-edge-bootstrap/target/v2\n%s\n%s\n' "$project" "$current_identity" | home_edge_write_registration "$launcher_dir/target.txt" 600
fi
if [ "$registered" = 1 ]; then home_edge_release_launcher_lock; trap - 0 HUP INT TERM; fi
echo 'project_location_state=verified_structure'
printf 'project_dir=%s\n' "$project"
exec sh "$project/scripts/tui.sh" "$@"
