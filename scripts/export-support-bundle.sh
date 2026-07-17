#!/bin/sh
# Export a redacted support bundle for diagnosis. Router collection is optional.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
router="${1:-${ROUTER:-}}"
output_dir="${OUTPUT_DIR:-/tmp/home-edge-support-bundles}"
stamp="$(date +%Y%m%d-%H%M%S)-$$"
work_dir="$output_dir/home-edge-support-$stamp"
archive="$work_dir.tar.gz"

mkdir -p "$work_dir"

redact() {
  awk '
    /-----BEGIN [^-]+ PRIVATE KEY-----/ {
      if (!in_private_key) print "REDACTED_PRIVATE_KEY"
      in_private_key = 1
      next
    }
    in_private_key {
      if ($0 ~ /-----END [^-]+ PRIVATE KEY-----/) in_private_key = 0
      next
    }
    { print }
  ' | sed -E \
    -e 's#([Rr][Uu][Nn][Aa][Ss] [Uu][Ss][Ee][Rr]|[Uu][Ss][Ee][Rr][Nn][Aa][Mm][Ee])[[:space:]]*[:=][[:space:]]*.*#\1=REDACTED#g' \
    -e 's#([Mm][Aa][Cc][Hh][Ii][Nn][Ee])[[:space:]]*:[[:space:]]*[^(\r\n]+#\1: REDACTED #g' \
    -e 's#C:\\Users\\[^\\[:space:]]+#C:\\Users\\REDACTED#g' \
    -e 's#^([bcdlps-][rwxStTs-]{9}[[:space:]]+[0-9]+[[:space:]]+)[^[:space:]]+([[:space:]]+[^[:space:]]+[[:space:]]+)#\1REDACTED_USER\2#g' \
    -e 's#git@[A-Za-z0-9._-]+:[^[:space:]"'"'"'<>]+#git@REDACTED_GIT_REMOTE#g' \
    -e 's#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}#REDACTED_EMAIL#g' \
    -e 's#[A-Za-z0-9._%+-]+@((10|127)(\.[0-9]{1,3}){3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})#REDACTED_USER@REDACTED_LAN_IP#g' \
    -e 's#((10|127)(\.[0-9]{1,3}){3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})#REDACTED_LAN_IP#g' \
    -e 's#(https?|ss|ssr|vmess|vless|trojan|hysteria2?)://[^[:space:]"'"'"'<>]+#\1://REDACTED_URL#g' \
    -e 's#([Ss][Uu][Bb][Ss][Cc][Rr][Ii][Pp][Tt][Ii][Oo][Nn](_[Uu][Rr][Ll])?|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]|[Aa][Pp][Ii][-_ ]?[Kk][Ee][Yy]|[Uu][Uu][Ii][Dd]|[Uu][Ss][Ee][Rr][Nn][Aa][Mm][Ee])[[:space:]]*[:=][[:space:]]*[^[:space:]]+#\1=REDACTED#g' \
    -e 's#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#REDACTED_UUID#g' \
    -e 's#[A-Za-z0-9+/=_-]{48,}#REDACTED_TOKEN#g'
}

capture() {
  name=$1
  shift
  if output=$("$@" 2>&1); then
    printf '%s\n' "$output" | redact > "$work_dir/$name"
  else
    status=$?
    {
      printf '%s\n' "$output"
      echo
      echo "capture_failed=$name"
      echo "exit_code=$status"
    } | redact > "$work_dir/$name"
  fi
}

{
  echo "# Home Edge Support Bundle"
  echo "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo=$repo"
  if [ -n "$router" ]; then
    echo "router_supplied=true"
  else
    echo "router_supplied=false"
  fi
  echo
  echo "This bundle is intended for diagnosis. It excludes subscription files, node lists,"
  echo "runtime caches, private keys, and bundle binaries. Captured text is redacted before"
  echo "it is written."
} | redact > "$work_dir/manifest.txt"

capture git-status.txt git -C "$repo" status --short --branch
capture git-head.txt sh -c "cd '$repo' && git rev-parse HEAD && git remote -v"
capture tracked-files.txt sh -c "cd '$repo' && git ls-files | grep -Ev '(^|/)(bundle|cache|backups)/|SUBSCRIPTION|subscription.*[.](yaml|txt|local)$|[.](key|pem|log)$'"
capture closeout.txt sh "$repo/scripts/verify-closeout.sh"
capture no-wall-readiness.txt sh "$repo/scripts/check-no-wall-readiness.sh"
capture doctor.txt sh "$repo/scripts/doctor.sh" "$router"
capture host-ssh.txt sh "$repo/scripts/check-host-ssh.sh" "$router"
capture client-topology.txt sh "$repo/scripts/check-client-topology.sh" "$router"

if [ -n "$router" ]; then
  capture edge-health.txt sh "$repo/scripts/check-edge-health.sh" "$router"
  capture router-status.txt env NO_LOG=1 sh "$repo/scripts/check-router-status.sh" "$router"
else
  echo "edge_health_state=skipped_no_router" > "$work_dir/edge-health.txt"
  echo "router_status=skipped_no_router" > "$work_dir/router-status.txt"
fi

status_value() {
  sed -n "s/^$1=//p" "$work_dir/router-status.txt" 2>/dev/null | head -n 1
}
stable_schema=$(status_value stable_state_schema)
case "$stable_schema" in 1|missing|invalid) ;; *) stable_schema=unavailable ;; esac
stable_subscription=$(status_value stable_subscription_state)
case "$stable_subscription" in present|absent|unavailable) ;; *) stable_subscription=unavailable ;; esac
stable_policy=$(status_value stable_policy_state)
case "$stable_policy" in present|absent|unavailable) ;; *) stable_policy=unavailable ;; esac
compatibility_bridge=$(status_value compatibility_bridge_state)
case "$compatibility_bridge" in present|absent|drift) ;; *) compatibility_bridge=unavailable ;; esac
{
  echo "stable_state_root=/jffs/home-edge-bootstrap-state"
  echo "stable_state_schema=$stable_schema"
  echo "stable_subscription_state=$stable_subscription"
  echo "stable_policy_state=$stable_policy"
  echo "compatibility_bridge_state=$compatibility_bridge"
} >"$work_dir/lifecycle-state.txt"

tar -czf "$archive" -C "$output_dir" "$(basename "$work_dir")"

echo "# Support Bundle"
echo "support_bundle_state=ready"
echo "support_bundle_dir=$work_dir"
echo "support_bundle_archive=$archive"
