#!/bin/sh
# Read-only BusyBox-compatible verification of deployed managed bytes.
set -u

install_dir=${HOME_EDGE_INSTALL_DIR:-/jffs/home-edge-bootstrap}
script_dir=${HOME_EDGE_ROUTER_SCRIPT_DIR:-/jffs/scripts}
expected_kind=${HOME_EDGE_EXPECTED_SOURCE_KIND:-unknown}
expected_commit=${HOME_EDGE_EXPECTED_SOURCE_COMMIT:-unknown}
expected_version=${HOME_EDGE_EXPECTED_SOURCE_VERSION:-unknown}
metadata="$install_dir/DEPLOYMENT-PROVENANCE.env"
sums="$install_dir/DEPLOYMENT-CONTENT-SHA256SUMS"

emit() {
  echo "deployment_provenance_state=$1"
  echo "deployment_source_commit=${source_commit:-unavailable}"
  echo "deployment_source_version=${source_version:-unavailable}"
  echo "deployment_source_tree_state=${source_tree_state:-unavailable}"
  echo "deployment_content_id=${content_id:-unavailable}"
}
value() { awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$metadata" 2>/dev/null; }
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else return 127
  fi
}

source_commit=unavailable
source_version=unavailable
content_id=unavailable
[ -s "$metadata" ] && [ -s "$sums" ] || { emit missing; exit 0; }
schema_version=$(value schema_version)
source_kind=$(value source_kind)
source_commit=$(value source_commit)
source_tree_state=$(value source_tree_state)
source_version=$(value source_version)
content_id=$(value content_id)
case "$schema_version:$source_kind:$source_tree_state" in
  1:git:clean|1:git:dirty|1:release:not_applicable|1:non_git:not_applicable) ;;
  *) emit drift; exit 0 ;;
esac
case "$source_commit" in non-git) ;; *[!0-9a-f]*|'') emit drift; exit 0 ;; esac
[ "$source_commit" = non-git ] || [ ${#source_commit} -eq 40 ] || { emit drift; exit 0; }
case "$content_id" in *[!0-9a-f]*|'') emit drift; exit 0 ;; esac
[ ${#content_id} -eq 64 ] || { emit drift; exit 0; }
actual_content_id=$(hash_file "$sums")
hash_status=$?
[ "$hash_status" -ne 127 ] || { emit unavailable; exit 0; }
[ "$actual_content_id" = "$content_id" ] || { emit drift; exit 0; }

while IFS= read -r line || [ -n "$line" ]; do
  expected_hash=${line%%  *}
  path=${line#*  }
  case "$expected_hash" in *[!0-9a-f]*|'') emit drift; exit 0 ;; esac
  case "$path" in ''|/*|..|../*|*/../*|*/..) emit drift; exit 0 ;; esac
  [ ${#expected_hash} -eq 64 ] || { emit drift; exit 0; }
  [ -f "$install_dir/$path" ] || { emit drift; exit 0; }
  [ "$(hash_file "$install_dir/$path")" = "$expected_hash" ] || { emit drift; exit 0; }
done <"$sums"

for mapping in \
  'config/policy.env|home-edge-policy.env' \
  'scripts/self-heal.sh|home-edge-self-heal.sh' \
  'scripts/update-sub.sh|home-edge-update-sub.sh' \
  'scripts/subscription-runtime-evidence.sh|home-edge-subscription-runtime-evidence.sh' \
  'scripts/verify-bundle.sh|home-edge-verify-bundle.sh' \
  'scripts/reconcile-self-heal-registration.sh|home-edge-reconcile-self-heal.sh'
do
  source_path=${mapping%%|*}
  active_name=${mapping#*|}
  [ -f "$install_dir/$source_path" ] && [ -f "$script_dir/$active_name" ] || { emit drift; exit 0; }
  [ "$(hash_file "$install_dir/$source_path")" = "$(hash_file "$script_dir/$active_name")" ] || { emit drift; exit 0; }
done

case "$expected_kind" in
  git)
    [ "$source_kind" = git ] && [ "$source_tree_state" = clean ] && [ "$source_commit" = "$expected_commit" ] || { emit drift; exit 0; }
    ;;
  release)
    [ "$source_kind" = release ] && [ "$source_version" = "$expected_version" ] || { emit drift; exit 0; }
    ;;
  unknown) emit unavailable; exit 0 ;;
  *) emit unavailable; exit 0 ;;
esac
emit match
