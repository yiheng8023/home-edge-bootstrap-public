#!/bin/sh
# Portable bounded retry for test/build-owned temporary trees.

home_edge_remove_tree_with_retry() {
  target=${1:-}
  case "$target" in
    ''|/|.|..) echo "remove-tree: ERROR: unsafe temporary tree: $target" >&2; return 2 ;;
  esac
  [ ! -e "$target" ] && return 0

  attempt=0
  while [ "$attempt" -lt 10 ]; do
    chmod -R u+w "$target" 2>/dev/null || true
    rm -rf "$target" 2>/dev/null || true
    [ ! -e "$target" ] && return 0
    attempt=$((attempt + 1))
    sleep 1
  done

  echo "remove-tree: ERROR: failed to remove temporary tree after bounded retries: $target" >&2
  return 1
}
