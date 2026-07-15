#!/bin/sh
# Build non-secret deployment provenance from the exact staged bytes.
set -eu

stage_root=${1:-}
source_root=${2:-}
[ -d "$stage_root" ] || { echo "new-deployment-provenance: stage root is required" >&2; exit 2; }
[ -d "$source_root" ] || { echo "new-deployment-provenance: source root is required" >&2; exit 2; }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "new-deployment-provenance: SHA-256 tool unavailable" >&2; return 1
  fi
}

source_kind=non_git
source_commit=non-git
source_tree_state=not_applicable
source_version=unversioned
if git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_kind=git
  source_commit=$(git -C "$source_root" rev-parse HEAD)
  source_tree_state=clean
  [ -z "$(git -C "$source_root" status --porcelain --untracked-files=no)" ] || source_tree_state=dirty
elif [ -s "$source_root/VERSION" ]; then
  source_kind=release
  source_version=$(sed -n '1p' "$source_root/VERSION" | tr -d '\r')
  printf '%s\n' "$source_version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || {
    source_kind=non_git
    source_version=unversioned
  }
fi

sums="$stage_root/DEPLOYMENT-CONTENT-SHA256SUMS"
metadata="$stage_root/DEPLOYMENT-PROVENANCE.env"
find_cmd=find
[ ! -x /usr/bin/find ] || find_cmd=/usr/bin/find
sort_cmd=sort
[ ! -x /usr/bin/sort ] || sort_cmd=/usr/bin/sort
rm -f "$sums" "$metadata"
tmp_sums="$stage_root/.deployment-content-sums.tmp"
: >"$tmp_sums"
(
  cd "$stage_root"
  "$find_cmd" . -type f ! -name DEPLOYMENT-PROVENANCE.env ! -name DEPLOYMENT-CONTENT-SHA256SUMS ! -name .deployment-content-sums.tmp -print |
    sed 's#^\./##' | LC_ALL=C "$sort_cmd" | while IFS= read -r path; do
      hash=$(hash_file "$path") || exit 1
      printf '%s  %s\n' "$hash" "$path"
    done
) >"$tmp_sums"
mv "$tmp_sums" "$sums"
content_id=$(hash_file "$sums")
managed_file_count=$(wc -l <"$sums" | tr -d ' ')

cat >"$metadata" <<EOF
schema_version=1
source_kind=$source_kind
source_commit=$source_commit
source_tree_state=$source_tree_state
source_version=$source_version
content_id=$content_id
managed_file_count=$managed_file_count
EOF
