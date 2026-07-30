#!/bin/sh
# Project-scoped secure temporary path allocator for constrained Merlin shells.
#
# Source this file, then call:
#   home_edge_secure_temp TEMPLATE
#   home_edge_secure_temp -d TEMPLATE
#
# TEMPLATE must end in XXXXXX. The function prints the created path.

home_edge_secure_temp() {
  home_edge_temp_kind=file
  if [ "${1:-}" = -d ]; then
    home_edge_temp_kind=directory
    shift
  fi
  home_edge_temp_template=${1:-}
  [ "$#" -eq 1 ] || return 2
  case "$home_edge_temp_template" in
    *XXXXXX) home_edge_temp_prefix=${home_edge_temp_template%XXXXXX} ;;
    *) return 2 ;;
  esac
  [ -n "$home_edge_temp_prefix" ] || return 2

  home_edge_temp_attempt=0
  while [ "$home_edge_temp_attempt" -lt 32 ]; do
    home_edge_temp_attempt=$((home_edge_temp_attempt + 1))
    home_edge_temp_suffix=""
    if which openssl >/dev/null 2>&1; then
      home_edge_temp_suffix=$(openssl rand -hex 8 2>/dev/null | tr -d '\r\n' || true)
    fi
    if [ -z "$home_edge_temp_suffix" ] &&
      which base64 >/dev/null 2>&1 &&
      [ -r /dev/urandom ]; then
      home_edge_temp_suffix=$(
        head -c 12 /dev/urandom 2>/dev/null |
          base64 2>/dev/null |
          tr -dc 'A-Za-z0-9' |
          cut -c1-16
      ) || home_edge_temp_suffix=""
    fi
    case "$home_edge_temp_suffix" in
      ''|*[!0-9A-Za-z]*) continue ;;
    esac
    home_edge_temp_path=$home_edge_temp_prefix$home_edge_temp_suffix
    if [ "$home_edge_temp_kind" = directory ]; then
      if (umask 077; mkdir "$home_edge_temp_path") 2>/dev/null; then
        printf '%s\n' "$home_edge_temp_path"
        return 0
      fi
    elif (umask 077; set -C; : >"$home_edge_temp_path") 2>/dev/null; then
      printf '%s\n' "$home_edge_temp_path"
      return 0
    fi
  done
  return 1
}
