#!/bin/sh
# Attest and classify subscription runtime evidence without exposing credentials.
set -eu
umask 077

action=${1:-classify}
cache=${HOME_EDGE_SUB_CACHE:-}
apply_path=${HOME_EDGE_SUB_APPLY_PATH:-}
evidence=${HOME_EDGE_SUB_EVIDENCE:-/tmp/home-edge-subscription-runtime.evidence}
runtime_identity=${HOME_EDGE_RUNTIME_PROCESS_IDENTITY:-unknown}
runtime_start=${HOME_EDGE_RUNTIME_PROCESS_START_EPOCH:-unknown}
max_age=${HOME_EDGE_EVIDENCE_MAX_AGE_SEC:-300}
now=${HOME_EDGE_NOW_EPOCH:-$(date +%s)}

die() { echo "subscription-runtime-evidence: ERROR: $*" >&2; exit 1; }
value_from() { sed -n "s/^$1=//p" "$evidence" 2>/dev/null | head -n 1; }
file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else return 1
  fi
}
validate_number() { case "$2" in ""|*[!0-9]*) die "$1 must be a non-negative integer" ;; esac; }

evidence_path_is_safe() {
  case "$evidence" in /tmp/home-edge-*|/jffs/home-edge-bootstrap/?*) ;; *) return 1 ;; esac
  case "$evidence" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*) return 1 ;; esac
  current=""
  relative=${evidence#/}
  old_ifs=$IFS; IFS=/; set -- $relative; IFS=$old_ifs
  for segment in "$@"; do current="$current/$segment"; [ ! -L "$current" ] || return 1; done
  return 0
}
validate_evidence_path() {
  evidence_path_is_safe || die "evidence path is unsafe or not project-owned"
}

case "$action" in
  observe)
    proc_root=${HOME_EDGE_PROC_ROOT:-/proc}
    case "$proc_root" in /proc|/tmp/home-edge-*) ;; *) die "unsafe proc observation root" ;; esac
    clk_tck=${HOME_EDGE_CLK_TCK:-$(getconf CLK_TCK 2>/dev/null || echo 100)}
    validate_number HOME_EDGE_CLK_TCK "$clk_tck"
    [ "$clk_tck" -gt 0 ] || die "HOME_EDGE_CLK_TCK must be positive"
    btime=$(awk '$1 == "btime" { print $2; exit }' "$proc_root/stat" 2>/dev/null || true)
    case "$btime" in ""|*[!0-9]*) btime=unknown ;; esac
    observed=0
    for process_dir in "$proc_root"/[0-9]*; do
      [ -d "$process_dir" ] || continue
      name=$(sed -n '1p' "$process_dir/comm" 2>/dev/null || true)
      case "$name" in mihomo|clash|CrashCore|sing-box) ;; *) continue ;; esac
      pid=${process_dir##*/}
      start_ticks=$(sed 's/^.*) //' "$process_dir/stat" 2>/dev/null | awk '{print $20}' | head -n 1)
      case "$start_ticks" in ""|*[!0-9]*) continue ;; esac
      config_path=$(tr '\000' '\n' <"$process_dir/cmdline" 2>/dev/null | awk 'take { print; exit } $0 == "-f" || $0 == "--config" { take=1; next } /^--config=\// { sub(/^--config=/, ""); print; exit } /^-f\// { sub(/^-f/, ""); print; exit }')
      case "$config_path" in /*) ;; *) config_path=unknown ;; esac
      if [ "$btime" = unknown ]; then start_epoch=unknown; else start_epoch=$((btime + start_ticks / clk_tck)); fi
      echo "runtime_process_identity=$name:$pid:$start_ticks"
      echo "runtime_process_start_epoch=$start_epoch"
      echo "runtime_active_config_path=$config_path"
      observed=1
      break
    done
    if [ "$observed" = 0 ]; then
      echo "runtime_process_identity=unknown"
      echo "runtime_process_start_epoch=unknown"
      echo "runtime_active_config_path=unknown"
    fi
    ;;
  attest)
    validate_evidence_path
    [ -s "$cache" ] || die "cache is unavailable"
    [ -n "$apply_path" ] && [ "$apply_path" != "$cache" ] || die "apply path is invalid"
    case "$runtime_identity" in ""|unknown) die "runtime process identity is unavailable" ;; esac
    validate_number HOME_EDGE_RUNTIME_PROCESS_START_EPOCH "$runtime_start"
    validate_number HOME_EDGE_NOW_EPOCH "$now"
    [ "$now" -ge "$runtime_start" ] || die "reload timestamp predates runtime process"
    digest=$(file_sha256 "$cache") || die "cache digest is unavailable"
    parent=$(dirname "$evidence")
    mkdir -p "$parent" || die "cannot prepare evidence directory"
    tmp=$(mktemp "${evidence}.tmp.XXXXXX") || die "cannot stage evidence"
    {
      echo "runtime_subscription_evidence_state=reload_succeeded"
      echo "runtime_subscription_apply_path=$apply_path"
      echo "runtime_subscription_cache_sha256=$digest"
      echo "runtime_subscription_reload_timestamp=$now"
      echo "runtime_subscription_process_identity=$runtime_identity"
    } >"$tmp" || { rm -f "$tmp"; die "cannot write evidence"; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$evidence" || { rm -f "$tmp"; die "cannot activate evidence"; }
    echo "subscription_runtime_evidence=reload_succeeded"
    ;;
  classify)
    state=profile_file_matches_cache
    [ -s "$cache" ] && [ -s "$apply_path" ] && [ "$cache" != "$apply_path" ] || { echo "subscription_consumption_state=$state"; exit 0; }
    command -v cmp >/dev/null 2>&1 && cmp -s "$cache" "$apply_path" || { echo "subscription_consumption_state=live_profile_differs_from_cache"; exit 0; }
    evidence_path_is_safe && [ -f "$evidence" ] || { echo "subscription_consumption_state=$state"; echo "subscription_runtime_evidence_state=missing_or_unsafe"; exit 0; }
    validate_number HOME_EDGE_EVIDENCE_MAX_AGE_SEC "$max_age"
    validate_number HOME_EDGE_NOW_EPOCH "$now"
    validate_number HOME_EDGE_RUNTIME_PROCESS_START_EPOCH "$runtime_start"
    evidence_state=$(value_from runtime_subscription_evidence_state)
    evidence_path=$(value_from runtime_subscription_apply_path)
    evidence_digest=$(value_from runtime_subscription_cache_sha256)
    evidence_timestamp=$(value_from runtime_subscription_reload_timestamp)
    evidence_identity=$(value_from runtime_subscription_process_identity)
    case "$evidence_timestamp" in ""|*[!0-9]*) echo "subscription_consumption_state=$state"; echo "subscription_runtime_evidence_state=invalid_timestamp"; exit 0 ;; esac
    age=$((now - evidence_timestamp))
    reason=valid
    [ "$evidence_state" = reload_succeeded ] || reason=invalid_state
    [ "$evidence_path" = "$apply_path" ] || reason=wrong_path
    digest=$(file_sha256 "$cache" 2>/dev/null || true)
    [ -n "$digest" ] && [ "$evidence_digest" = "$digest" ] || reason=wrong_digest
    [ "$runtime_identity" != unknown ] && [ "$evidence_identity" = "$runtime_identity" ] || reason=wrong_process_identity
    [ "$age" -ge 0 ] && [ "$age" -le "$max_age" ] || reason=expired
    [ "$evidence_timestamp" -ge "$runtime_start" ] || reason=pre_process_start
    if [ "$reason" = valid ]; then state=runtime_profile_matches_cache; fi
    echo "subscription_consumption_state=$state"
    echo "subscription_runtime_evidence_state=$reason"
    ;;
  *) die "usage: subscription-runtime-evidence.sh observe|attest|classify" ;;
esac
