#!/bin/sh
# Conservative offline secret scanner for repository and support-bundle text.
set -eu
umask 077

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
find_cmd=find
if [ -x /usr/bin/find ]; then
  find_cmd=/usr/bin/find
fi
checked=0
skipped=0
scan_tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-secret-scan.XXXXXX") || {
  echo "secret_scan_state=failed" >&2
  echo "secret_scan_error=cannot_allocate_temporary_directory" >&2
  exit 1
}
findings_file="$scan_tmp/findings"
files_file="$scan_tmp/files"
: >"$findings_file"
: >"$files_file"

cleanup() {
  rm -rf "$scan_tmp"
}
trap cleanup EXIT HUP INT TERM

add_finding() {
  rel=$1
  line=$2
  label=$3
  printf 'secret_finding=%s:%s:%s\n' "$rel" "$line" "$label" >>"$findings_file"
}

display_path() {
  path=$1
  case "$path" in
    "$repo"/*) printf '%s\n' "${path#"$repo"/}" ;;
    *) printf '%s\n' "$path" ;;
  esac | sed 's#\\#/#g'
}

should_skip_file() {
  rel=$1
  size=$2
  case "$rel" in
    .git/*|*/.git/*|cache/*|*/cache/*|backups/*|*/backups/*|node_modules/*|*/node_modules/*) return 0 ;;
  esac
  case "$rel" in
    *.zip|*.gz|*.tgz|*.tar|*.bin|*.exe|*.dll|*.so|*.dylib|*.png|*.jpg|*.jpeg|*.webp|*.ico|*.pdf) return 0 ;;
  esac
  if [ "$size" -gt 2097152 ]; then
    return 0
  fi
  return 1
}

collect_default_files() {
  git -C "$repo" ls-files --cached --others --exclude-standard | while IFS= read -r rel; do
    [ -f "$repo/$rel" ] && printf '%s\n' "$repo/$rel"
  done
}

collect_scan_path_files() {
  for item in "$@"; do
    if [ -f "$item" ]; then
      printf '%s\n' "$item"
    elif [ -d "$item" ]; then
      "$find_cmd" "$item" -type f
    else
      printf 'missing_scan_path=%s\n' "$item" >>"$findings_file"
    fi
  done
}

scan_file_patterns() {
  file=$1
  rel=$2
  awk -v rel="$rel" '
    function add(label) {
      printf "secret_finding=%s:%d:%s\n", rel, NR, label
    }
    function value_after_assignment(line, value) {
      value = line
      sub(/^.*[:=][[:space:]]*/, "", value)
      gsub(/^["\\]+|["\\]+$/, "", value)
      return value
    }
    {
      lower = tolower($0)
      if ($0 ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) {
        add("private_key")
      }
      if (lower ~ /(vmess|vless|trojan|hysteria2?|ssr?):\/\/[^[:space:]"<>]+/) {
        proxy = $0
        sub(/^.*(vmess|vless|trojan|hysteria2?|ssr?):\/\//, "", proxy)
        if (length(proxy) >= 8) {
          add("proxy_uri")
        }
      }
      if (lower ~ /(^|[^a-z0-9_-])(subscription(_url)?|password|passwd|token|secret|authorization|api[-_ ]?key)[[:space:]]*[:=]/) {
        value = value_after_assignment($0)
        value_lower = tolower(value)
        if (length(value) >= 12 && value !~ /\$/ && value !~ /^</ && value_lower !~ /^(redacted|redacted_|example|dummy)/) {
          add("secret_assignment")
        }
      }
      if (lower ~ /(^|[^a-z0-9_-])uuid[[:space:]]*[:=]/ && $0 ~ /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/ && lower !~ /redacted/) {
        add("uuid_assignment")
      }
      if ($0 ~ /(sk-proj-|sk-)[A-Za-z0-9_-]{20,}/) {
        add("openai_key")
      }
      if ($0 ~ /(ghp_|github_pat_)[A-Za-z0-9_]{20,}/) {
        add("github_token")
      }
      if ($0 ~ /AKIA[0-9A-Z]{16}/) {
        add("aws_access_key")
      }
      if ($0 ~ /AIza[0-9A-Za-z_-]{20,}/) {
        add("google_api_key")
      }
    }
  ' "$file" >>"$findings_file"
}

if [ "$#" -gt 0 ]; then
  collect_scan_path_files "$@" >"$files_file"
else
  collect_default_files >"$files_file"
fi

while IFS= read -r file; do
  [ -f "$file" ] || continue
  rel=$(display_path "$file")
  size=$(wc -c <"$file" | tr -d ' ')
  sensitive_name=0
  case "$rel" in
    */SUBSCRIPTION.local|SUBSCRIPTION.local|*subscription*.txt|*subscription*.local|*subscription*.yaml|*subscription*.yml|*nodes*.yaml|*.key|*.pem|.env|*/.env)
      add_finding "$rel" 0 sensitive_filename
      sensitive_name=1
      ;;
  esac
  checked=$((checked + 1))
  if [ "$sensitive_name" = "0" ] && should_skip_file "$rel" "$size"; then
    checked=$((checked - 1))
    skipped=$((skipped + 1))
    continue
  fi
  scan_file_patterns "$file" "$rel"
done <"$files_file"

echo "# Secret Scan"
echo
if [ -s "$findings_file" ]; then
  echo "secret_scan_state=failed"
  cat "$findings_file"
  echo "checked_files=$checked"
  echo "skipped_files=$skipped"
  exit 1
fi

echo "secret_scan_state=ready"
echo "checked_files=$checked"
echo "skipped_files=$skipped"
