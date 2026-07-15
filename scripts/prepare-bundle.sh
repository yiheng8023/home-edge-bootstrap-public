#!/bin/sh
# Prepare the offline runtime bundle on macOS/Linux/Git Bash.
set -eu

mihomo_version="${MIHOMO_VERSION:-v1.19.28}"
shellcrash_version="${SHELLCRASH_VERSION:-1.9.4}"
force="${FORCE:-0}"
keep_compressed_source="${KEEP_COMPRESSED_SOURCE:-0}"
skip_verify="${SKIP_VERIFY:-0}"

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd "$script_dir/.." && pwd)
bundle_dir="${BUNDLE_DIR:-$repo_root/bundle}"

mihomo_asset="mihomo-linux-arm64-$mihomo_version.gz"
shellcrash_asset="ShellCrash.tar.gz"
mihomo_url="https://github.com/MetaCubeX/mihomo/releases/download/$mihomo_version/$mihomo_asset"
shellcrash_url="https://github.com/juewuy/ShellCrash/releases/download/$shellcrash_version/$shellcrash_asset"

mihomo_gz="$bundle_dir/$mihomo_asset"
mihomo_out="$bundle_dir/mihomo-linux-arm64"
shellcrash_out="$bundle_dir/$shellcrash_asset"
manifest_out="$bundle_dir/MANIFEST.json"
sha_out="$bundle_dir/SHA256SUMS"
sbom_out="$repo_root/config/sbom.json"

log() { echo "prepare-bundle: $*"; }
die() { echo "prepare-bundle: ERROR: $*" >&2; exit 1; }

mkdir -p "$bundle_dir"

download_file() {
  url="$1"
  dest="$2"
  if [ -s "$dest" ] && [ "$force" != "1" ]; then
    log "keeping existing $dest"
    return 0
  fi

  log "downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
  else
    die "curl or wget is required to download bundle assets"
  fi
}

hash_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    die "sha256sum or shasum is required"
  fi
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

download_file "$mihomo_url" "$mihomo_gz"
download_file "$shellcrash_url" "$shellcrash_out"

if [ -s "$mihomo_out" ] && [ "$force" != "1" ]; then
  log "keeping existing $mihomo_out"
else
  log "expanding $mihomo_gz -> $mihomo_out"
  gzip -dc "$mihomo_gz" > "$mihomo_out"
  chmod 755 "$mihomo_out" 2>/dev/null || true
fi

mihomo_hash=$(hash_file "$mihomo_out")
mihomo_gz_hash=$(hash_file "$mihomo_gz")
shellcrash_hash=$(hash_file "$shellcrash_out")

{
  printf '%s  %s\n' "$mihomo_hash" "mihomo-linux-arm64"
  printf '%s  %s\n' "$shellcrash_hash" "ShellCrash.tar.gz"
} > "$sha_out"

generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
mihomo_size=$(file_size "$mihomo_out")
shellcrash_size=$(file_size "$shellcrash_out")

cat > "$manifest_out" <<EOF
{
  "schema": 1,
  "generatedAt": "$generated_at",
  "sourcePolicy": "Pinned GitHub release assets; verify SHA256SUMS before offline use.",
  "payloads": [
    {
      "id": "mihomo-linux-arm64",
      "path": "mihomo-linux-arm64",
      "version": "$mihomo_version",
      "sourceRepository": "MetaCubeX/mihomo",
      "sourceAsset": "$mihomo_asset",
      "sourceUrl": "$mihomo_url",
      "sourceSha256": "$mihomo_gz_hash",
      "sha256": "$mihomo_hash",
      "sizeBytes": $mihomo_size
    },
    {
      "id": "shellcrash",
      "path": "ShellCrash.tar.gz",
      "version": "$shellcrash_version",
      "sourceRepository": "juewuy/ShellCrash",
      "sourceAsset": "$shellcrash_asset",
      "sourceUrl": "$shellcrash_url",
      "sha256": "$shellcrash_hash",
      "sizeBytes": $shellcrash_size
    }
  ]
}
EOF

cat > "$sbom_out" <<EOF
{
  "schema_version": 1,
  "format": "home-edge-sbom",
  "generated_at": "$generated_at",
  "scope": "offline-router-runtime-bundle",
  "authority_boundary": "Local hashes prove checkout integrity only; upstream authenticity requires upstream release/signature/checksum review when available.",
  "components": [
    {
      "id": "mihomo-linux-arm64",
      "name": "mihomo",
      "type": "runtime-binary",
      "version": "$mihomo_version",
      "target_arch": "linux-arm64",
      "source_repository": "MetaCubeX/mihomo",
      "source_asset": "$mihomo_asset",
      "source_url": "$mihomo_url",
      "source_sha256": "$mihomo_gz_hash",
      "bundle_path": "bundle/mihomo-linux-arm64",
      "bundle_sha256": "$mihomo_hash",
      "bundle_size_bytes": $mihomo_size,
      "license": "upstream-reviewed-required",
      "upstream_authenticity": "not_attested_by_this_repo",
      "replacement_policy": "Replace only through scripts/prepare-bundle with reviewed release notes, regenerated MANIFEST/SHA256SUMS/SBOM, and passing local verification."
    },
    {
      "id": "shellcrash",
      "name": "ShellCrash",
      "type": "router-runtime-manager-archive",
      "version": "$shellcrash_version",
      "target_arch": "router-shell",
      "source_repository": "juewuy/ShellCrash",
      "source_asset": "$shellcrash_asset",
      "source_url": "$shellcrash_url",
      "source_sha256": "$shellcrash_hash",
      "bundle_path": "bundle/ShellCrash.tar.gz",
      "bundle_sha256": "$shellcrash_hash",
      "bundle_size_bytes": $shellcrash_size,
      "license": "upstream-reviewed-required",
      "upstream_authenticity": "not_attested_by_this_repo",
      "replacement_policy": "Replace only through scripts/prepare-bundle with reviewed release notes, regenerated MANIFEST/SHA256SUMS/SBOM, and passing local verification."
    }
  ]
}
EOF

if [ "$keep_compressed_source" != "1" ]; then
  rm -f "$mihomo_gz"
fi

if [ "$skip_verify" != "1" ]; then
  sh "$script_dir/verify-bundle.sh" "$bundle_dir"
fi

log "Bundle ready: $bundle_dir"
log "Binaries are git-ignored by default; use git add -f only when you intentionally want clone-and-go offline restore."
