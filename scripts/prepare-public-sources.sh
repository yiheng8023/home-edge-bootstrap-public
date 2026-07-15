#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
output=
payload_dir=
lock="$repo/config/third-party-lock.json"
manifest=
mihomo_url=
shellcrash_url=
go_command=${HOME_EDGE_GO_COMMAND:-}
go_work_root=
go_archive=
go_proxy=https://proxy.golang.org
allow_direct=0
fixture_mode=0
fixture_os=
fixture_arch=
max_modules=2000
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) [ "$#" -ge 2 ] || exit 2; output=$2; shift 2 ;;
    --payload-dir) [ "$#" -ge 2 ] || exit 2; payload_dir=$2; shift 2 ;;
    --lock) [ "$#" -ge 2 ] || exit 2; lock=$2; shift 2 ;;
    --manifest) [ "$#" -ge 2 ] || exit 2; manifest=$2; shift 2 ;;
    --mihomo-url) [ "$#" -ge 2 ] || exit 2; mihomo_url=$2; shift 2 ;;
    --shellcrash-url) [ "$#" -ge 2 ] || exit 2; shellcrash_url=$2; shift 2 ;;
    --go-command) [ "$#" -ge 2 ] || exit 2; go_command=$2; shift 2 ;;
    --go-work-root) [ "$#" -ge 2 ] || exit 2; go_work_root=$2; shift 2 ;;
    --go-archive) [ "$#" -ge 2 ] || exit 2; go_archive=$2; shift 2 ;;
    --go-proxy) [ "$#" -ge 2 ] || exit 2; go_proxy=$2; shift 2 ;;
    --allow-direct-go-fallback) allow_direct=1; shift ;;
    --fixture-mode) fixture_mode=1; shift ;;
    --fixture-os) [ "$#" -ge 2 ] || exit 2; fixture_os=$2; shift 2 ;;
    --fixture-arch) [ "$#" -ge 2 ] || exit 2; fixture_arch=$2; shift 2 ;;
    --max-modules) [ "$#" -ge 2 ] || exit 2; max_modules=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$output" ] && [ -n "$payload_dir" ] || { echo 'required: --output and --payload-dir' >&2; exit 2; }

python_cmd=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'; then python_cmd=$candidate; break; fi
done
[ -n "$python_cmd" ] || { echo 'Python 3 is required' >&2; exit 1; }

lock=$($python_cmd -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$lock")
payload_dir=$($python_cmd -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$payload_dir")
output=$($python_cmd -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")
[ -n "$manifest" ] || manifest="$payload_dir/MANIFEST.json"
manifest=$($python_cmd -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$manifest")
[ -f "$lock" ] || { echo "third-party lock not found: $lock" >&2; exit 1; }
[ -d "$payload_dir" ] || { echo "payload directory not found: $payload_dir" >&2; exit 1; }
[ -f "$manifest" ] || { echo "payload manifest not found: $manifest" >&2; exit 1; }
[ ! -e "$output" ] || { echo "output already exists: $output" >&2; exit 1; }

if [ "$fixture_mode" -eq 1 ]; then
  [ -n "$fixture_os" ] && [ -n "$fixture_arch" ] || { echo 'fixture platform requires --fixture-os and --fixture-arch' >&2; exit 2; }
  platform_os=$(printf '%s' "$fixture_os" | tr '[:upper:]' '[:lower:]')
  platform_arch=$(printf '%s' "$fixture_arch" | tr '[:upper:]' '[:lower:]')
else
  [ -z "$fixture_os$fixture_arch" ] || { echo 'platform override is forbidden outside fixture mode' >&2; exit 2; }
  case "$(uname -s)" in
    Linux) platform_os=linux ;;
    Darwin) platform_os=darwin ;;
    MINGW*|MSYS*|CYGWIN*) platform_os=windows ;;
    *) echo 'unsupported source-preparation operating system' >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) platform_arch=amd64 ;;
    aarch64|arm64) platform_arch=arm64 ;;
    *) echo "unsupported source-preparation architecture: $(uname -m)" >&2; exit 1 ;;
  esac
fi

eval "$($python_cmd - "$lock" "$platform_os" "$platform_arch" <<'PY'
import json, pathlib, shlex, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
if d.get('schema_version') != 1 or len(d.get('components', [])) != 2: raise SystemExit('invalid third-party lock structure')
by={x.get('id'):x for x in d['components']}
if set(by) != {'mihomo-linux-arm64','shellcrash'}: raise SystemExit('required component lock missing or duplicated')
for key,prefix in [('mihomo-linux-arm64','MIHOMO'),('shellcrash','SHELLCRASH')]:
    c=by[key]
    for field in ('version','source_repository','source_commit','payload_sha256','license_sha256'):
        print(f"{prefix}_{field.upper()}={shlex.quote(str(c[field]))}")
acq=d.get('source_acquisition')
if acq:
    supported={('windows','amd64'),('windows','arm64'),('linux','amd64'),('linux','arm64'),('darwin','amd64'),('darwin','arm64')}
    tools=acq.get('go_toolchains',[]); keys={(x.get('os'),x.get('arch')) for x in tools}
    if len(tools)!=6 or len(keys)!=6 or keys!=supported: raise SystemExit('Go toolchain platform lock is incomplete or duplicated')
    version=str(acq['go_toolchain_version'])
    for item in tools:
        ext='zip' if item['os']=='windows' else 'tar.gz'; expected=f"{version}.{item['os']}-{item['arch']}.{ext}"
        if item.get('filename')!=expected or not __import__('re').fullmatch(r'[0-9a-f]{64}',str(item.get('sha256',''))): raise SystemExit(f"invalid Go toolchain platform lock: {item.get('os')}/{item.get('arch')}")
    selected=[x for x in tools if (x['os'],x['arch'])==(sys.argv[2],sys.argv[3])]
    if len(selected)!=1: raise SystemExit(f'unsupported source-preparation platform: {sys.argv[2]}/{sys.argv[3]}')
    selected=selected[0]
    print('GO_LOCK_VERSION='+shlex.quote(version))
    print('GO_LOCK_OS='+shlex.quote(str(selected['os'])))
    print('GO_LOCK_ARCH='+shlex.quote(str(selected['arch'])))
    print('GO_LOCK_ARCHIVE='+shlex.quote(str(selected['filename'])))
    print('GO_LOCK_ARCHIVE_SHA256='+shlex.quote(str(selected['sha256'])))
PY
)"
[ -n "$mihomo_url" ] || mihomo_url=$MIHOMO_SOURCE_REPOSITORY
[ -n "$shellcrash_url" ] || shellcrash_url=$SHELLCRASH_SOURCE_REPOSITORY
validate_locator() {
  if [ "$fixture_mode" -eq 1 ]; then
    [ -d "$1/.git" ] || { echo 'fixture source must be a local Git repository' >&2; exit 1; }
  else
    case "$1" in https://*) :;; *) echo 'production source URL must use credential-free HTTPS' >&2; exit 1;; esac
    case "$1" in *://*@*|*\?*|*\#*) echo 'credential-bearing or decorated source URL is forbidden' >&2; exit 1;; esac
  fi
}
validate_locator "$mihomo_url"
validate_locator "$shellcrash_url"
case "$max_modules" in ''|*[!0-9]*) echo 'invalid module limit' >&2; exit 2;; esac
[ "$max_modules" -ge 1 ] && [ "$max_modules" -le 5000 ] || { echo 'invalid module limit' >&2; exit 2; }
case ",$go_proxy," in *,direct,*) [ "$allow_direct" -eq 1 ] || { echo 'direct Go module fallback requires explicit opt-in' >&2; exit 1; };; esac
if [ "$allow_direct" -eq 1 ]; then case ",$go_proxy," in *,direct,*) :;; *) go_proxy="$go_proxy,direct";; esac; fi

sha256_file() {
  "$python_cmd" -c 'import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "$1"
}
if [ "${GO_LOCK_VERSION:-}" ]; then
  [ -f "$go_archive" ] || { echo 'locked Go toolchain archive is required' >&2; exit 1; }
  go_archive_name=$($python_cmd -c 'import os,sys; print(os.path.basename(os.path.abspath(sys.argv[1])))' "$go_archive")
  [ "$go_archive_name" = "$GO_LOCK_ARCHIVE" ] || { echo "Go toolchain archive filename mismatch for $GO_LOCK_OS/$GO_LOCK_ARCH" >&2; exit 1; }
  [ "$(sha256_file "$go_archive")" = "$GO_LOCK_ARCHIVE_SHA256" ] || { echo "Go toolchain archive hash mismatch for $GO_LOCK_OS/$GO_LOCK_ARCH" >&2; exit 1; }
  [ -z "$go_command" ] || { echo 'custom Go command is forbidden when a locked toolchain archive is configured' >&2; exit 1; }
fi
mihomo_payload="$payload_dir/mihomo-linux-arm64"
shellcrash_payload="$payload_dir/ShellCrash.tar.gz"
[ -f "$mihomo_payload" ] && [ -f "$shellcrash_payload" ] || { echo 'required payload missing' >&2; exit 1; }
[ "$(sha256_file "$mihomo_payload")" = "$MIHOMO_PAYLOAD_SHA256" ] || { echo 'payload hash mismatch: mihomo-linux-arm64' >&2; exit 1; }
[ "$(sha256_file "$shellcrash_payload")" = "$SHELLCRASH_PAYLOAD_SHA256" ] || { echo 'payload hash mismatch: shellcrash' >&2; exit 1; }

"$python_cmd" - "$manifest" "$lock" <<'PY'
import json,pathlib,sys,urllib.parse
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')); lock=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
if manifest.get('schema')!=1 or len(manifest.get('payloads',[]))!=2: raise SystemExit('invalid payload manifest structure')
entries={x.get('id'):x for x in manifest['payloads']}; components={x['id']:x for x in lock['components']}
paths={'mihomo-linux-arm64':'mihomo-linux-arm64','shellcrash':'ShellCrash.tar.gz'}
for cid,c in components.items():
    if cid not in entries: raise SystemExit(f'payload manifest component missing or duplicated: {cid}')
    e=entries[cid]; repository=urllib.parse.urlparse(c['source_repository']).path.strip('/')
    if repository.endswith('.git'): repository=repository[:-4]
    if (e.get('version'),e.get('path'),e.get('sourceRepository'),e.get('sha256'))!=(c['version'],paths[cid],repository,c['payload_sha256']): raise SystemExit(f'payload manifest drift: {cid}')
PY

"$python_cmd" - "$shellcrash_payload" <<'PY'
import pathlib, sys, tarfile, zipfile
p=pathlib.Path(sys.argv[1])
def safe(n):
    n=n.replace('\\','/'); parts=pathlib.PurePosixPath(n).parts
    return bool(n) and not n.startswith('/') and not any(x in ('','.','..') for x in parts) and not (parts and ':' in parts[0])
if tarfile.is_tarfile(p):
    with tarfile.open(p,'r:*') as a:
        for m in a.getmembers():
            if not safe(m.name) or m.issym() or m.islnk() or m.isdev(): raise SystemExit('unsafe archive path or entry')
elif zipfile.is_zipfile(p):
    with zipfile.ZipFile(p) as a:
        for m in a.infolist():
            if not safe(m.filename): raise SystemExit('unsafe archive path')
else: raise SystemExit('unsupported archive')
PY

stage="$output.stage.$$"
[ ! -e "$stage" ] || { echo "staging path already exists: $stage" >&2; exit 1; }
mkdir -p "$stage/.acquire"
cleanup() { [ ! -e "$stage" ] || rm -rf "$stage"; }
trap cleanup EXIT HUP INT TERM

if [ "${GO_LOCK_VERSION:-}" ]; then
  "$python_cmd" - "$go_archive" "$stage/.go-toolchain" <<'PY'
import os,pathlib,shutil,stat,sys,tarfile,zipfile
archive,dest=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]); dest.mkdir(parents=True)
def target(name):
    name=name.replace('\\','/'); parts=pathlib.PurePosixPath(name).parts
    if not name or name.startswith('/') or any(x in ('','.','..') for x in parts) or (parts and ':' in parts[0]): raise SystemExit('unsafe Go toolchain archive path')
    return dest.joinpath(*parts)
if zipfile.is_zipfile(archive):
    with zipfile.ZipFile(archive) as z:
        for m in z.infolist():
            out=target(m.filename)
            if m.is_dir(): out.mkdir(parents=True,exist_ok=True); continue
            mode=(m.external_attr>>16)&0xffff
            if stat.S_ISLNK(mode): raise SystemExit('unsafe Go toolchain archive entry')
            out.parent.mkdir(parents=True,exist_ok=True)
            with z.open(m) as src,out.open('wb') as dst: shutil.copyfileobj(src,dst)
            if mode: os.chmod(out,mode&0o777)
elif tarfile.is_tarfile(archive):
    with tarfile.open(archive,'r:*') as t:
        for m in t.getmembers():
            out=target(m.name)
            if m.issym() or m.islnk() or m.isdev(): raise SystemExit('unsafe Go toolchain archive entry')
            if m.isdir(): out.mkdir(parents=True,exist_ok=True); continue
            if not m.isfile(): raise SystemExit('unsupported Go toolchain archive entry')
            out.parent.mkdir(parents=True,exist_ok=True)
            with t.extractfile(m) as src,out.open('wb') as dst: shutil.copyfileobj(src,dst)
            os.chmod(out,m.mode&0o777)
else: raise SystemExit('unsupported Go toolchain archive')
PY
  for candidate in "$stage/.go-toolchain/go/bin/go" "$stage/.go-toolchain/go/bin/go.exe" "$stage/.go-toolchain/go/bin/go.cmd"; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then go_command=$candidate; break; fi
  done
  [ -n "$go_command" ] || { echo 'verified Go toolchain archive does not contain executable go/bin/go' >&2; exit 1; }
elif [ "$fixture_mode" -ne 1 ]; then
  echo 'locked Go toolchain provenance is required' >&2; exit 1
fi

mkdir -p "$stage/.git-home"
: >"$stage/.git-home/gitconfig"
HOME="$stage/.git-home" XDG_CONFIG_HOME="$stage/.git-home" GIT_CONFIG_GLOBAL="$stage/.git-home/gitconfig" GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -c credential.helper= -c credential.interactive=never -c core.askPass= -c http.extraHeader= clone --no-checkout --depth 1 --single-branch --branch "$MIHOMO_VERSION" "$mihomo_url" "$stage/.acquire/mihomo"
git -C "$stage/.acquire/mihomo" checkout --detach "$MIHOMO_SOURCE_COMMIT"
[ "$(git -C "$stage/.acquire/mihomo" rev-parse HEAD)" = "$MIHOMO_SOURCE_COMMIT" ] || { echo 'source commit mismatch: mihomo-linux-arm64' >&2; exit 1; }
[ "$(git -C "$stage/.acquire/mihomo" rev-list -n 1 "$MIHOMO_VERSION")" = "$MIHOMO_SOURCE_COMMIT" ] || { echo 'tag commit mismatch: mihomo-linux-arm64' >&2; exit 1; }

HOME="$stage/.git-home" XDG_CONFIG_HOME="$stage/.git-home" GIT_CONFIG_GLOBAL="$stage/.git-home/gitconfig" GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -c credential.helper= -c credential.interactive=never -c core.askPass= -c http.extraHeader= clone --no-checkout --depth 1 --single-branch --branch "$SHELLCRASH_VERSION" "$shellcrash_url" "$stage/.acquire/shellcrash"
git -C "$stage/.acquire/shellcrash" checkout --detach "$SHELLCRASH_SOURCE_COMMIT"
[ "$(git -C "$stage/.acquire/shellcrash" rev-parse HEAD)" = "$SHELLCRASH_SOURCE_COMMIT" ] || { echo 'source commit mismatch: shellcrash' >&2; exit 1; }
[ "$(git -C "$stage/.acquire/shellcrash" rev-list -n 1 "$SHELLCRASH_VERSION")" = "$SHELLCRASH_SOURCE_COMMIT" ] || { echo 'tag commit mismatch: shellcrash' >&2; exit 1; }

"$python_cmd" - "$stage/.acquire/mihomo" "$stage/third-party/mihomo/source" "$stage/.acquire/shellcrash" "$stage/third-party/shellcrash/source" <<'PY'
import pathlib, shutil, subprocess, sys
for repo,dest in [(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2])),(pathlib.Path(sys.argv[3]),pathlib.Path(sys.argv[4]))]:
    dest.mkdir(parents=True)
    records=subprocess.check_output(['git','-C',str(repo),'ls-files','--stage','-z']).split(b'\0'); count=0
    for raw in records:
        if not raw: continue
        head,path=raw.split(b'\t',1); mode=head.split(b' ',1)[0]
        if mode not in (b'100644',b'100755'): raise SystemExit(f'unsupported tracked source mode: {mode.decode()}: {path.decode()}')
        rel=path.decode('utf-8'); target=dest/pathlib.PurePosixPath(rel); target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(subprocess.check_output(['git','-C',str(repo),'show','HEAD:'+rel])); count+=1
    if not count: raise SystemExit('upstream tree has no tracked files')
PY

mihomo_tree="$stage/third-party/mihomo/source"
shellcrash_tree="$stage/third-party/shellcrash/source"
[ -f "$mihomo_tree/LICENSE" ] && [ -f "$shellcrash_tree/LICENSE.txt" ] || { echo 'upstream license missing' >&2; exit 1; }
[ "$(sha256_file "$mihomo_tree/LICENSE")" = "$MIHOMO_LICENSE_SHA256" ] || { echo 'license mismatch: mihomo-linux-arm64' >&2; exit 1; }
[ "$(sha256_file "$shellcrash_tree/LICENSE.txt")" = "$SHELLCRASH_LICENSE_SHA256" ] || { echo 'license mismatch: shellcrash' >&2; exit 1; }
[ -f "$shellcrash_tree/ShellCrash.tar.gz" ] && [ "$(sha256_file "$shellcrash_tree/ShellCrash.tar.gz")" = "$SHELLCRASH_PAYLOAD_SHA256" ] || { echo 'ShellCrash runtime payload does not match tagged source evidence' >&2; exit 1; }
cp "$mihomo_tree/LICENSE" "$stage/third-party/mihomo/LICENSE"
cp "$shellcrash_tree/LICENSE.txt" "$stage/third-party/shellcrash/LICENSE.txt"
cp "$mihomo_payload" "$stage/third-party/mihomo/mihomo-linux-arm64"
cp "$shellcrash_payload" "$stage/third-party/shellcrash/ShellCrash.tar.gz"

if [ -z "$go_command" ]; then go_command=$(command -v go || true); fi
[ -n "$go_command" ] && [ -x "$go_command" ] || { echo 'Go toolchain is required for Mihomo complete corresponding source' >&2; exit 1; }
[ -n "$go_work_root" ] || go_work_root="$stage/.go-work"
mkdir -p "$go_work_root/modcache" "$go_work_root/buildcache" "$go_work_root/gopath"
go_version_output=$($go_command version)
go_version=$(printf '%s\n' "$go_version_output" | sed -nE 's/^go version (go[0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')
[ -n "$go_version" ] || { echo 'unable to record Go toolchain version' >&2; exit 1; }
if [ "${GO_LOCK_VERSION:-}" ]; then [ "$go_version" = "$GO_LOCK_VERSION" ] || { echo 'Go toolchain version mismatch' >&2; exit 1; }; fi
(
  cd "$mihomo_tree"
  export GOMODCACHE="$go_work_root/modcache" GOCACHE="$go_work_root/buildcache" GOPATH="$go_work_root/gopath" GOENV=off GOTOOLCHAIN=local GOFLAGS=-modcacherw
  export GOPROXY="$go_proxy" GOSUMDB=sum.golang.org GOPRIVATE= GONOPROXY= GONOSUMDB= GOMAXPROCS=4
  "$go_command" mod download -json all >"$go_work_root/module-download.jsonstream"
  "$python_cmd" - "$go_work_root/module-download.jsonstream" "$go_work_root/downloaded-modules.json" "$max_modules" <<'PY'
import json,pathlib,sys
source,target,limit=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),int(sys.argv[3]); text=source.read_text(encoding='utf-8-sig'); d=json.JSONDecoder(); pos=0; modules=[]
while pos<len(text):
    while pos<len(text) and text[pos].isspace(): pos+=1
    if pos>=len(text): break
    item,pos=d.raw_decode(text,pos)
    if item.get('Error'): raise SystemExit(f"Go module download error: {item.get('Path','unknown')}: {item['Error']}")
    if item.get('Path') and item.get('Version'): modules.append({k:item[k] for k in ('Path','Version','Sum','GoModSum') if item.get(k)})
if not modules: raise SystemExit('Go module download returned zero modules')
if len(modules)>limit: raise SystemExit(f'Go module count exceeds limit: {len(modules)} > {limit}')
modules.sort(key=lambda x:(x['Path'],x['Version'])); target.write_text(json.dumps({'schema_version':1,'module_count':len(modules),'modules':modules},indent=2)+'\n',encoding='utf-8',newline='\n')
PY
  "$go_command" mod verify
  "$go_command" mod vendor
  "$python_cmd" - "$go_work_root/downloaded-modules.json" "$mihomo_tree/vendor" "$mihomo_tree/VENDORED-MODULES.json" <<'PY'
import json,pathlib,sys
download_path,vendor,target=map(pathlib.Path,sys.argv[1:4]); known={(m['Path'],m['Version']) for m in json.loads(download_path.read_text(encoding='utf-8'))['modules']}
lines=(vendor/'modules.txt').read_text(encoding='utf-8').splitlines(); modules=[]; current=None
for line in lines:
    if line.startswith('# ') and not line.startswith('## '):
        parts=line[2:].split()
        if len(parts)<2 or not parts[1].startswith('v'): current=None; continue
        current={'Path':parts[0],'Version':parts[1],'Packages':[]}
        if '=>' in parts:
            i=parts.index('=>')
            if len(parts)<=i+2: raise SystemExit('invalid vendor replacement identity')
            current.update({'ReplacementPath':parts[i+1],'ReplacementVersion':parts[i+2]}); identity=(parts[i+1],parts[i+2])
        else: identity=(parts[0],parts[1])
        if identity not in known: raise SystemExit(f'vendored module absent from verified download log: {identity[0]} {identity[1]}')
        modules.append(current); continue
    if current is not None and line and not line.startswith('#'):
        package=line.strip(); package_dir=vendor/pathlib.PurePosixPath(package)
        if not package_dir.is_dir() or not any(p.is_file() for p in package_dir.rglob('*')): raise SystemExit(f'vendored package source missing: {package}')
        current['Packages'].append(package)
if not modules or not any(m['Packages'] for m in modules): raise SystemExit('Mihomo vendored module source is incomplete')
target.write_text(json.dumps({'schema_version':1,'module_count':len(modules),'package_count':sum(len(m['Packages']) for m in modules),'modules':modules},indent=2)+'\n',encoding='utf-8',newline='\n')
PY
)
[ -f "$mihomo_tree/vendor/modules.txt" ] || { echo 'Mihomo vendored module source is incomplete' >&2; exit 1; }
vendor_count=$(find "$mihomo_tree/vendor" -type f ! -name modules.txt | wc -l | tr -d ' ')
[ "$vendor_count" -gt 0 ] || { echo 'Mihomo vendored module source is incomplete' >&2; exit 1; }

mihomo_epoch=$(git -C "$stage/.acquire/mihomo" show -s --format=%ct HEAD)
shellcrash_epoch=$(git -C "$stage/.acquire/shellcrash" show -s --format=%ct HEAD)
"$python_cmd" - "$mihomo_tree" "$shellcrash_tree" "$MIHOMO_VERSION" "$MIHOMO_SOURCE_REPOSITORY" "$MIHOMO_SOURCE_COMMIT" "$mihomo_epoch" "$go_version" "$SHELLCRASH_VERSION" "$SHELLCRASH_SOURCE_REPOSITORY" "$SHELLCRASH_SOURCE_COMMIT" "$shellcrash_epoch" "$go_proxy" <<'PY'
import json,pathlib,sys
m,s=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2])
items=[(m,{'schema_version':1,'component_id':'mihomo-linux-arm64','version':sys.argv[3],'source_repository':sys.argv[4],'source_commit':sys.argv[5],'source_commit_epoch':int(sys.argv[6]),'build_workflow':'go mod download -json all; go mod verify; go mod vendor','go_version':sys.argv[7]}),(s,{'schema_version':1,'component_id':'shellcrash','version':sys.argv[8],'source_repository':sys.argv[9],'source_commit':sys.argv[10],'source_commit_epoch':int(sys.argv[11]),'build_workflow':'full tagged Git source tree including build and install scripts'})]
modules=json.loads((m/'VENDORED-MODULES.json').read_text(encoding='utf-8'))
items[0][1].update({'go_proxy':sys.argv[12],'go_sumdb':'sum.golang.org','go_private':'','go_max_procs':4,'module_count':modules['module_count']})
for root,data in items: (root/'SOURCE-BUILD.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8',newline='\n')
PY

mkdir -p "$stage/third-party/sources"
canonical_archiver=$(CDPATH= cd "$(dirname "$0")" && pwd)/canonical-source-archive.go
[ -f "$canonical_archiver" ] || { echo 'canonical source archiver is missing' >&2; exit 1; }
canonical_archive() {
  GOMODCACHE="$go_work_root/modcache" GOCACHE="$go_work_root/buildcache" GOPATH="$go_work_root/gopath" \
  GOENV=off GOTOOLCHAIN=local GOFLAGS=-modcacherw GOPROXY=off GOSUMDB=off \
  GOPRIVATE= GONOPROXY= GONOSUMDB= \
    "$go_command" run "$canonical_archiver" "$1" "$2" "$3" "$4"
}
mihomo_archive="$stage/third-party/sources/mihomo-v1.19.28-complete-source.tar.gz"
shellcrash_archive="$stage/third-party/sources/shellcrash-1.9.4-complete-source.tar.gz"
canonical_archive "$mihomo_tree" "$mihomo_archive" mihomo-v1.19.28-source "$mihomo_epoch"
canonical_archive "$shellcrash_tree" "$shellcrash_archive" shellcrash-1.9.4-source "$shellcrash_epoch"
mihomo_archive_sha=$(sha256_file "$mihomo_archive")
"$python_cmd" - "$stage/third-party/mihomo/SOURCE-PREPARATION.json" "$MIHOMO_VERSION" "$MIHOMO_SOURCE_REPOSITORY" "$MIHOMO_SOURCE_COMMIT" "$go_version" "$GO_LOCK_OS" "$GO_LOCK_ARCH" "$GO_LOCK_ARCHIVE" "$GO_LOCK_ARCHIVE_SHA256" "$(basename "$mihomo_archive")" "$mihomo_archive_sha" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); data={'schema_version':1,'component_id':'mihomo-linux-arm64','component_version':sys.argv[2],'source_repository':sys.argv[3],'source_commit':sys.argv[4],'go_version':sys.argv[5],'host_os':sys.argv[6],'host_arch':sys.argv[7],'go_toolchain_archive':sys.argv[8],'go_toolchain_archive_sha256':sys.argv[9],'complete_source_archive':sys.argv[10],'complete_source_sha256':sys.argv[11]}
path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8',newline='\n')
PY
rm -rf "$stage/.acquire"
rm -rf "$stage/.git-home"
if [ "$go_work_root" = "$stage/.go-work" ]; then rm -rf "$go_work_root"; fi
rm -rf "$stage/.go-toolchain"
mv "$stage" "$output"
trap - EXIT HUP INT TERM
echo 'third_party_source_state=ready'
echo "mihomo_source_commit=$MIHOMO_SOURCE_COMMIT"
echo "mihomo_source_sha256=$(sha256_file "$output/third-party/sources/mihomo-v1.19.28-complete-source.tar.gz")"
echo "shellcrash_source_commit=$SHELLCRASH_SOURCE_COMMIT"
echo "shellcrash_source_sha256=$(sha256_file "$output/third-party/sources/shellcrash-1.9.4-complete-source.tar.gz")"
