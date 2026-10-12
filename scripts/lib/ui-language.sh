# Shared UI language selection; protocol keys and confirmation tokens stay literal.
heb_detect_ui_language() {
  if [ -n "${1:-}" ]; then
    case "$1" in zh-CN|en) printf '%s\n' "$1"; return 0 ;; *) return 2 ;; esac
  fi
  case "${HOME_EDGE_LANGUAGE:-}" in zh-CN|en) printf '%s\n' "$HOME_EDGE_LANGUAGE"; return 0 ;; esac
  heb_locale=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}
  case "$heb_locale" in
    '') printf 'zh-CN\n' ;;
    [zZ][hH]*) printf 'zh-CN\n' ;;
    *) printf 'en\n' ;;
  esac
}
heb_ui_text() {
  if [ "${language:-zh-CN}" = en ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
}
