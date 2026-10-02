#!/bin/sh
# Read-only library embedded by the host audit; never source site evidence files.

core_baseline_sha256() {
  if which openssl >/dev/null 2>&1; then
    cb_hash_line=$(openssl dgst -sha256 "$1" 2>/dev/null) || return 1
    printf '%s\n' "$cb_hash_line" | awk '{print $NF}'
  elif which sha256sum >/dev/null 2>&1; then
    cb_hash_line=$(sha256sum "$1" 2>/dev/null) || return 1
    printf '%s\n' "$cb_hash_line" | awk '{print $1}'
  else
    return 1
  fi
}

core_baseline_field() {
  # Exactly one occurrence. Values are data; no eval, source, or shell expansion.
  awk -v key="$2" '
    { sub(/\r$/, "") }
    index($0, key "=") == 1 { count++; value=substr($0, length(key)+2) }
    END { if (count != 1) exit 1; print value }
  ' "$1" 2>/dev/null
}

core_baseline_version() {
  printf '%s\n' "$1" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9._-]+)?$' || return 1
  case "$1" in v*) printf '%s\n' "$1" ;; *) printf 'v%s\n' "$1" ;; esac
}

core_baseline_digest_valid() {
  [ "${#1}" = 64 ] || return 1
  case "$1" in *[!a-f0-9]*) return 1 ;; esac
}

core_baseline_path_valid() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in /|*[!A-Za-z0-9_./-]*|*'/../'*|*'/..'|*'/./'*|*'/.'|*'//'*) return 1 ;; esac
}

core_baseline_no_links() {
  cb_checked=""
  cb_old_ifs=$IFS; IFS=/; set -f
  for cb_part in $1; do
    [ -n "$cb_part" ] || continue
    cb_checked="$cb_checked/$cb_part"
    if [ -L "$cb_checked" ]; then IFS=$cb_old_ifs; set +f; return 1; fi
  done
  IFS=$cb_old_ifs; set +f
}

core_baseline_emit() {
  printf 'mihomo_version=%s\n' "$cb_actual_version"
  printf 'shellcrash_core_version=%s\n' "$cb_metadata_version"
  printf 'core_baseline_expected_version=%s\n' "$cb_expected_version"
  printf 'core_baseline_runtime_raw_sha256=%s\n' "$cb_raw_hash"
  printf 'core_baseline_native_gzip_sha256=%s\n' "$cb_native_hash"
  printf 'core_baseline_protected_gzip_sha256=%s\n' "$cb_protected_hash"
  printf 'core_baseline_receipt_sha256=%s\n' "$cb_receipt_hash"
  printf 'core_baseline_status_source=%s\n' "$cb_status_source"
  printf 'core_baseline_state=%s\ncore_baseline_reason=%s\n' "$1" "$2"
}

audit_core_baseline() (
  # The optional PID is already observed by the enclosing audit. Path overrides
  # are trusted host/test inputs; ROOT remaps router paths for offline fixtures.
  cb_root=${HOME_EDGE_CORE_AUDIT_ROOT:-}
  cb_proc=${HOME_EDGE_CORE_PROC_ROOT:-/proc}
  cb_record=${HOME_EDGE_CORE_BASELINE_FILE:-/jffs/home-edge-bootstrap-state/runtime-core-baseline.env}
  cb_native=${HOME_EDGE_CORE_NATIVE_GZIP:-/jffs/ShellCrash/CrashCore.gz}
  cb_protected=${HOME_EDGE_CORE_PROTECTED_GZIP:-/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz}
  cb_cfg=${HOME_EDGE_CORE_SHELLCRASH_CONFIG:-/jffs/ShellCrash/configs/ShellCrash.cfg}
  cb_pid=${1:-}
  cb_actual_version=unavailable; cb_metadata_version=unavailable
  cb_expected_version=unrecorded
  cb_raw_hash=unavailable; cb_native_hash=unavailable
  cb_protected_hash=unavailable; cb_receipt_hash=unavailable
  cb_status_source=unavailable
  for cb_path in "$cb_proc" "$cb_record" "$cb_native" "$cb_protected" "$cb_cfg"; do
    core_baseline_path_valid "$cb_path" || { core_baseline_emit invalid unsafe_observation_path; return 0; }
  done
  if [ -n "$cb_root" ]; then
    core_baseline_path_valid "$cb_root" || { core_baseline_emit invalid unsafe_observation_root; return 0; }
  fi
  cb_record="$cb_root$cb_record"; cb_native="$cb_root$cb_native"
  cb_protected="$cb_root$cb_protected"; cb_cfg="$cb_root$cb_cfg"
  if [ -z "$cb_pid" ] && [ -r "$cb_root/tmp/ShellCrash/shellcrash.pid" ]; then
    cb_pid=$(cat "$cb_root/tmp/ShellCrash/shellcrash.pid" 2>/dev/null)
  fi
  cb_runtime_ready=0
  case "$cb_pid" in ''|*[!0-9]*) ;; *)
    cb_exe="$cb_proc/$cb_pid/exe"
    cb_stat="$cb_proc/$cb_pid/stat"
    cb_before=$(cat "$cb_stat" 2>/dev/null) || cb_before=""
    if [ -n "$cb_before" ] && [ -x "$cb_exe" ]; then
      cb_version_output=$("$cb_exe" -v 2>/dev/null) || cb_version_output=""
      cb_version_token=$(printf '%s\n' "$cb_version_output" | awk 'tolower($1)=="mihomo" { for(i=2;i<=NF;i++) if($i ~ /^v[0-9]+\.[0-9]+\.[0-9]+/) { print $i; exit } }')
      cb_actual_version=$(core_baseline_version "$cb_version_token") || cb_actual_version=unavailable
      cb_raw_hash=$(core_baseline_sha256 "$cb_exe") || cb_raw_hash=unavailable
      cb_after=$(cat "$cb_stat" 2>/dev/null) || cb_after=""
      # /proc/stat changes CPU counters; field 22 binds PID reuse independently.
      cb_start_before=$(printf '%s\n' "$cb_before" | sed 's/^.*) //' | awk '{print $20}')
      cb_start_after=$(printf '%s\n' "$cb_after" | sed 's/^.*) //' | awk '{print $20}')
      if [ -n "$cb_start_before" ] && [ "$cb_start_before" = "$cb_start_after" ] &&
         [ "$cb_actual_version" != unavailable ] && core_baseline_digest_valid "$cb_raw_hash"; then
        cb_runtime_ready=1
      else
        cb_actual_version=unavailable; cb_raw_hash=unavailable
      fi
    fi
  ;; esac
  cb_metadata_raw=$(core_baseline_field "$cb_cfg" core_v) || cb_metadata_raw=""
  # ShellCrash writes either plain or uniformly quoted version metadata.
  case "$cb_metadata_raw" in \"*\") cb_metadata_raw=${cb_metadata_raw#\"}; cb_metadata_raw=${cb_metadata_raw%\"} ;; \'*\') cb_metadata_raw=${cb_metadata_raw#\'}; cb_metadata_raw=${cb_metadata_raw%\'} ;; esac
  cb_metadata_version=$(core_baseline_version "$cb_metadata_raw") || cb_metadata_version=unavailable
  cb_native_hash=$(core_baseline_sha256 "$cb_native") || cb_native_hash=unavailable
  cb_protected_hash=$(core_baseline_sha256 "$cb_protected") || cb_protected_hash=unavailable
  if [ ! -e "$cb_record" ] && [ ! -L "$cb_record" ]; then
    core_baseline_emit unrecorded site_record_missing; return 0
  fi
  if ! core_baseline_no_links "$cb_record" || [ ! -f "$cb_record" ] || [ ! -r "$cb_record" ]; then
    core_baseline_emit invalid unsafe_or_unreadable_site_record; return 0
  fi
  cb_record_size=$(wc -c <"$cb_record" 2>/dev/null) || cb_record_size=0
  if [ "$cb_record_size" -gt 8192 ] || ! awk '
    { sub(/\r$/, "") }
    /^$/ || /^#/ { next }
    !/^[a-z_0-9]+=/ { bad=1; next }
    { key=$0; sub(/=.*/, "", key); count[key]++ }
    END {
      if(bad) exit 1
      for(key in count) {
        keys++
        if(key !~ /^(schema_version|core_version|core_raw_sha256|core_gzip_sha256|receipt_path|receipt_sha256)$/ || count[key]!=1) exit 1
      }
      if(keys!=6) exit 1
    }
  ' "$cb_record"; then
    core_baseline_emit invalid malformed_site_record; return 0
  fi
  cb_schema=$(core_baseline_field "$cb_record" schema_version)
  cb_expected_raw=$(core_baseline_field "$cb_record" core_version)
  cb_expected_version=$(core_baseline_version "$cb_expected_raw") || cb_expected_version=invalid
  cb_expected_raw_hash=$(core_baseline_field "$cb_record" core_raw_sha256)
  cb_expected_gzip_hash=$(core_baseline_field "$cb_record" core_gzip_sha256)
  cb_receipt=$(core_baseline_field "$cb_record" receipt_path)
  cb_expected_receipt_hash=$(core_baseline_field "$cb_record" receipt_sha256)
  if [ "$cb_schema" != 1 ] || [ "$cb_expected_version" = invalid ] ||
     ! core_baseline_digest_valid "$cb_expected_raw_hash" || ! core_baseline_digest_valid "$cb_expected_gzip_hash" ||
     ! core_baseline_digest_valid "$cb_expected_receipt_hash" || ! core_baseline_path_valid "$cb_receipt"; then
    core_baseline_emit invalid unsupported_or_invalid_site_record; return 0
  fi
  case "$cb_receipt" in /jffs/?*/result.env) ;; *) core_baseline_emit invalid receipt_path_outside_jffs; return 0 ;; esac
  cb_receipt="$cb_root$cb_receipt"
  if ! core_baseline_no_links "$cb_receipt"; then core_baseline_emit invalid unsafe_receipt_path; return 0; fi
  if [ ! -f "$cb_receipt" ] || [ ! -r "$cb_receipt" ]; then
    core_baseline_emit unavailable receipt_missing_or_unreadable; return 0
  fi
  cb_receipt_hash=$(core_baseline_sha256 "$cb_receipt") || cb_receipt_hash=unavailable
  if [ "$cb_receipt_hash" = unavailable ]; then core_baseline_emit unavailable hashing_unavailable; return 0; fi
  if [ "$cb_receipt_hash" != "$cb_expected_receipt_hash" ]; then core_baseline_emit drift receipt_digest_mismatch; return 0; fi
  cb_receipt_version_raw=$(core_baseline_field "$cb_receipt" version) || cb_receipt_version_raw=""
  cb_receipt_version=$(core_baseline_version "$cb_receipt_version_raw") || cb_receipt_version=invalid
  cb_status_file="${cb_receipt%/*}/status"
  cb_legacy_status_count=$(awk 'index($0,"status=")==1 {count++} END {print count+0}' "$cb_receipt")
  cb_legacy_status=$(core_baseline_field "$cb_receipt" status) || cb_legacy_status=""
  if [ -e "$cb_status_file" ] || [ -L "$cb_status_file" ]; then
    if ! core_baseline_no_links "$cb_status_file"; then core_baseline_emit invalid unsafe_status_path; return 0; fi
    if [ ! -f "$cb_status_file" ] || [ ! -r "$cb_status_file" ]; then
      core_baseline_emit unavailable acceptance_status_unreadable; return 0
    fi
    # The actual transaction layout has a separate file containing verified\n.
    if ! awk '{sub(/\r$/, ""); if(NR!=1 || $0!="verified") bad=1} END {if(bad || NR!=1) exit 1}' "$cb_status_file"; then
      core_baseline_emit invalid receipt_acceptance_not_verified; return 0
    fi
    if [ "$cb_legacy_status_count" -gt 0 ] && { [ "$cb_legacy_status_count" != 1 ] || [ "$cb_legacy_status" != verified ]; }; then
      core_baseline_emit invalid conflicting_acceptance_status; return 0
    fi
    cb_receipt_status=verified; cb_status_source=separate_file
  elif [ "$cb_legacy_status_count" = 1 ]; then
    cb_receipt_status=$cb_legacy_status; cb_status_source=receipt_field
  elif [ "$cb_legacy_status_count" = 0 ]; then
    core_baseline_emit unavailable acceptance_status_missing; return 0
  else
    core_baseline_emit invalid receipt_acceptance_not_verified; return 0
  fi
  cb_receipt_choices=$(core_baseline_field "$cb_receipt" selectors_unchanged) || cb_receipt_choices=""
  cb_receipt_route=$(core_baseline_field "$cb_receipt" route_verified) || cb_receipt_route=""
  if [ "$cb_receipt_version" != "$cb_expected_version" ] || [ "$cb_receipt_status" != verified ] ||
     [ "$cb_receipt_choices" != yes ] || [ "$cb_receipt_route" != yes ]; then
    core_baseline_emit invalid receipt_acceptance_not_verified; return 0
  fi
  if [ "$cb_runtime_ready" != 1 ] || [ "$cb_metadata_version" = unavailable ] ||
     [ "$cb_native_hash" = unavailable ] || [ "$cb_protected_hash" = unavailable ]; then
    core_baseline_emit unavailable observation_incomplete; return 0
  fi
  if [ "$cb_actual_version" != "$cb_expected_version" ]; then core_baseline_emit drift runtime_version_mismatch
  elif [ "$cb_raw_hash" != "$cb_expected_raw_hash" ]; then core_baseline_emit drift runtime_digest_mismatch
  elif [ "$cb_metadata_version" != "$cb_expected_version" ]; then core_baseline_emit drift shellcrash_metadata_mismatch
  elif [ "$cb_native_hash" != "$cb_expected_gzip_hash" ]; then core_baseline_emit drift native_archive_mismatch
  elif [ "$cb_protected_hash" != "$cb_expected_gzip_hash" ]; then core_baseline_emit drift protected_archive_mismatch
  else core_baseline_emit match accepted_site_core_and_receipt_match
  fi
)
