#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tree=
lock="$repo/config/third-party-lock.json"
sbom="$repo/config/sbom.json"
notice="$repo/THIRD_PARTY_NOTICES.md"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tree) [ "$#" -ge 2 ] || exit 2; tree=$2; shift 2 ;;
    --lock) [ "$#" -ge 2 ] || exit 2; lock=$2; shift 2 ;;
    --sbom) [ "$#" -ge 2 ] || exit 2; sbom=$2; shift 2 ;;
    --notice) [ "$#" -ge 2 ] || exit 2; notice=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$tree" ] || { echo 'required: --tree' >&2; exit 2; }
py=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'; then py=$candidate; break; fi
done
[ -n "$py" ] || { echo 'Python 3 is required' >&2; exit 1; }

"$py" - "$tree" "$lock" "$sbom" "$notice" <<'PY'
import hashlib, json, pathlib, re, sys, tarfile
tree, lock_path, sbom_path, notice_path = map(pathlib.Path, sys.argv[1:5])
if not tree.is_dir(): raise SystemExit(f"compliance tree missing: {tree}")
for p in (lock_path, sbom_path, notice_path):
    if not p.is_file(): raise SystemExit(f"required compliance input missing: {p}")
lock=json.loads(lock_path.read_text(encoding="utf-8")); sbom=json.loads(sbom_path.read_text(encoding="utf-8")); notice=notice_path.read_text(encoding="utf-8")
if lock.get("schema_version") != 1 or len(lock.get("components",[])) != 2: raise SystemExit("invalid third-party lock structure")
components={c.get("id"):c for c in lock["components"]}
if set(components) != {"mihomo-linux-arm64","shellcrash"}: raise SystemExit("required component lock missing or duplicated")
hex64=re.compile(r"^[0-9a-f]{64}$"); git_oid=re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
paths={
 "mihomo-linux-arm64":{"payload":"third-party/mihomo/mihomo-linux-arm64","license":"third-party/mihomo/LICENSE","source":"third-party/mihomo/source","archive":"third-party/sources/mihomo-v1.19.28-complete-source.tar.gz","prefix":"mihomo-v1.19.28-source","license_name":"LICENSE"},
 "shellcrash":{"payload":"third-party/shellcrash/ShellCrash.tar.gz","license":"third-party/shellcrash/LICENSE.txt","source":"third-party/shellcrash/source","archive":"third-party/sources/shellcrash-1.9.4-complete-source.tar.gz","prefix":"shellcrash-1.9.4-source","license_name":"LICENSE.txt"},
}
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def notice_sections(text):
    sections={}; current=None
    for line in text.splitlines():
        if line.startswith('## '):
            current=line[3:].strip()
            if current in sections: raise SystemExit(f'duplicate notice section: {current}')
            sections[current]=[]
        elif current is not None: sections[current].append(line.rstrip())
    return sections
sections=notice_sections(notice)
def normalized_archive(archive,source,prefix,epoch):
    expected={p.relative_to(source).as_posix():p for p in source.rglob('*') if p.is_file()}; seen=set()
    with tarfile.open(archive,'r:gz') as tf:
        for m in tf.getmembers():
            name=m.name.replace('\\','/'); parts=pathlib.PurePosixPath(name).parts
            if not name or name.startswith('/') or any(x in ('','.','..') for x in parts) or (parts and ':' in parts[0]): raise SystemExit('unsafe archive path')
            if m.issym() or m.islnk() or m.isdev(): raise SystemExit('unsafe archive entry')
            if m.uid != 0 or m.gid != 0 or m.uname or m.gname or int(m.mtime) != epoch: raise SystemExit('source archive metadata is not normalized')
            if not (name==prefix or name.startswith(prefix+'/')): raise SystemExit('source archive root mismatch')
            rel=name[len(prefix):].lstrip('/')
            if m.isdir():
                if m.mode != 0o755: raise SystemExit('source archive directory mode mismatch')
                continue
            if not m.isfile(): raise SystemExit('unsupported source archive entry')
            if m.mode != (0o755 if pathlib.PurePosixPath(rel).suffix=='.sh' else 0o644): raise SystemExit('source archive file mode mismatch')
            if rel in seen: raise SystemExit('duplicate source archive path')
            if rel not in expected or hashlib.sha256(tf.extractfile(m).read()).hexdigest()!=sha(expected[rel]): raise SystemExit('source archive/source tree mismatch')
            seen.add(rel)
    if seen!=set(expected): raise SystemExit('source archive/source tree mismatch')
for cid,c in components.items():
    for field in ('version','source_repository','source_commit','license','payload_sha256','license_sha256','complete_source_sha256'):
        if not c.get(field): raise SystemExit(f'missing lock field: {cid}.{field}')
    if c['license']!='GPL-3.0-only' or not git_oid.fullmatch(c['source_commit']) or not all(hex64.fullmatch(c[x]) for x in ('payload_sha256','license_sha256','complete_source_sha256')): raise SystemExit(f'invalid lock identity: {cid}')
    p=paths[cid]; payload=tree/p['payload']; license_file=tree/p['license']; source=tree/p['source']; archive=tree/p['archive']
    for required in (payload,license_file,source,archive):
        if not required.exists(): raise SystemExit(f'required compliance artifact missing: {required}')
    if sha(payload)!=c['payload_sha256']: raise SystemExit(f'payload hash mismatch: {cid}')
    if sha(license_file)!=c['license_sha256']: raise SystemExit(f'license mismatch: {cid}')
    if not (source/p['license_name']).is_file() or sha(source/p['license_name'])!=c['license_sha256']: raise SystemExit(f'source license mismatch: {cid}')
    if sha(archive)!=c['complete_source_sha256']: raise SystemExit(f'complete source hash mismatch: {cid}')
    metadata_path=source/'SOURCE-BUILD.json'
    if not metadata_path.is_file(): raise SystemExit(f'source build metadata missing: {cid}')
    metadata=json.loads(metadata_path.read_text(encoding='utf-8'))
    if (metadata.get('component_id'),metadata.get('version'),metadata.get('source_commit'))!=(cid,c['version'],c['source_commit']): raise SystemExit(f'source build metadata mismatch: {cid}')
    epoch=metadata.get('source_commit_epoch')
    if not isinstance(epoch,int) or epoch<=0: raise SystemExit(f'invalid source commit epoch: {cid}')
    normalized_archive(archive,source,p['prefix'],epoch)
    title=('Mihomo ' if cid=='mihomo-linux-arm64' else 'ShellCrash ')+c['version']
    if title not in sections: raise SystemExit(f'notice component section missing: {cid}')
    lines=set(sections[title]); expected_archive=pathlib.PurePosixPath(p['archive']).name
    required={f"- Source: {c['source_repository']}",f"- Source commit: `{c['source_commit']}`",f"- License: {c['license']}",f"- Upstream license SHA-256: `{c['license_sha256']}`",f"- Runtime payload SHA-256: `{c['payload_sha256']}`",f"- Complete corresponding source: `{expected_archive}`",f"- Complete corresponding source SHA-256: `{c['complete_source_sha256']}`"}
    if not required.issubset(lines): raise SystemExit(f'notice component fields missing or cross-assigned: {cid}')
mihomo_source=tree/paths['mihomo-linux-arm64']['source']; vendor=mihomo_source/'vendor'
if not (vendor/'modules.txt').is_file() or not any(p.is_file() and p.name!='modules.txt' for p in vendor.rglob('*')): raise SystemExit('Mihomo vendored module source is incomplete')
meta=json.loads((mihomo_source/'SOURCE-BUILD.json').read_text(encoding='utf-8'))
if not re.match(r'^go[0-9]+\.[0-9]+(?:\.[0-9]+)?$',str(meta.get('go_version',''))) or meta.get('build_workflow')!='go mod download -json all; go mod verify; go mod vendor': raise SystemExit('Mihomo Go acquisition metadata invalid')
if any(field in meta for field in ('go_toolchain_os','go_toolchain_arch','go_toolchain_archive','go_toolchain_archive_sha256','host_os','host_arch')): raise SystemExit('Mihomo SOURCE-BUILD metadata is not platform neutral')
modules_path=mihomo_source/'VENDORED-MODULES.json'
if not modules_path.is_file(): raise SystemExit('Mihomo normalized module manifest missing')
modules=json.loads(modules_path.read_text(encoding='utf-8'))
if modules.get('schema_version')!=1 or modules.get('module_count')!=len(modules.get('modules',[])) or modules.get('module_count',0)<1 or modules.get('package_count')!=sum(len(x.get('Packages',[])) for x in modules.get('modules',[])): raise SystemExit('Mihomo normalized module manifest invalid')
parsed=[]; current=None
for line in (vendor/'modules.txt').read_text(encoding='utf-8').splitlines():
    if line.startswith('# ') and not line.startswith('## '):
        parts=line[2:].split()
        if len(parts)<2 or not parts[1].startswith('v'): current=None; continue
        current={'Path':parts[0],'Version':parts[1],'Packages':[]}
        if '=>' in parts:
            i=parts.index('=>')
            if len(parts)<=i+2: raise SystemExit('invalid vendor replacement identity')
            current.update({'ReplacementPath':parts[i+1],'ReplacementVersion':parts[i+2]})
        parsed.append(current); continue
    if current is not None and line and not line.startswith('#'):
        package=line.strip(); package_dir=vendor/pathlib.PurePosixPath(package)
        if not package_dir.is_dir() or not any(p.is_file() for p in package_dir.rglob('*')): raise SystemExit(f'Mihomo vendored package source missing: {package}')
        current['Packages'].append(package)
if modules['modules']!=parsed or modules['package_count']<1: raise SystemExit('Mihomo vendor manifest/modules.txt mismatch')
acq=lock.get('source_acquisition')
if acq:
    supported={('windows','amd64'),('windows','arm64'),('linux','amd64'),('linux','arm64'),('darwin','amd64'),('darwin','arm64')}
    toolchains=acq.get('go_toolchains',[]); keys={(x.get('os'),x.get('arch')) for x in toolchains}
    if len(toolchains)!=6 or len(keys)!=6 or keys!=supported or not re.fullmatch(r'go[0-9]+\.[0-9]+(?:\.[0-9]+)?',str(acq.get('go_toolchain_version',''))): raise SystemExit('Go toolchain platform lock is incomplete or duplicated')
    version=acq['go_toolchain_version']
    for item in toolchains:
        ext='zip' if item['os']=='windows' else 'tar.gz'
        if item.get('filename')!=f"{version}.{item['os']}-{item['arch']}.{ext}" or not hex64.fullmatch(str(item.get('sha256',''))): raise SystemExit(f"invalid Go toolchain platform lock: {item.get('os')}/{item.get('arch')}")
    if acq.get('go_proxy')!='https://proxy.golang.org' or acq.get('go_sumdb')!='sum.golang.org' or acq.get('go_direct_fallback') is not False or acq.get('go_max_procs')!=4: raise SystemExit('Go acquisition network/concurrency policy mismatch')
    if modules['module_count']>acq.get('go_module_count_limit',0): raise SystemExit('Mihomo module count exceeds locked limit')
    preparation_path=tree/'third-party/mihomo/SOURCE-PREPARATION.json'
    if not preparation_path.is_file(): raise SystemExit('Mihomo external source preparation provenance missing')
    preparation=json.loads(preparation_path.read_text(encoding='utf-8'))
    if (preparation.get('schema_version'),preparation.get('component_id'),preparation.get('component_version'),preparation.get('source_repository'),preparation.get('source_commit'),preparation.get('go_version'),preparation.get('complete_source_archive'),preparation.get('complete_source_sha256'))!=(1,'mihomo-linux-arm64',components['mihomo-linux-arm64']['version'],components['mihomo-linux-arm64']['source_repository'],components['mihomo-linux-arm64']['source_commit'],version,'mihomo-v1.19.28-complete-source.tar.gz',components['mihomo-linux-arm64']['complete_source_sha256']): raise SystemExit('Mihomo external source preparation identity mismatch')
    selected=[x for x in toolchains if (x['os'],x['arch'])==(preparation.get('host_os'),preparation.get('host_arch'))]
    if len(selected)!=1: raise SystemExit('Mihomo selected Go toolchain platform is unsupported')
    selected=selected[0]
    if (preparation.get('go_toolchain_archive'),preparation.get('go_toolchain_archive_sha256'))!=(selected['filename'],selected['sha256']): raise SystemExit('Go toolchain provenance mismatch')
    if meta.get('go_version')!=version: raise SystemExit('Mihomo platform-neutral Go version mismatch')
    if (meta.get('go_proxy'),meta.get('go_sumdb'),meta.get('go_private'),meta.get('go_max_procs'),meta.get('module_count')) != (acq['go_proxy'],acq['go_sumdb'],'',4,modules['module_count']): raise SystemExit('Go acquisition metadata mismatch')
    mihomo_notice=set(sections['Mihomo '+components['mihomo-linux-arm64']['version']])
    tool_notice={f"- Pinned Go source-preparation archive ({x['os']}/{x['arch']}): `{x['filename']}`, SHA-256 `{x['sha256']}`" for x in toolchains}
    tool_notice.update({'- Source-preparation selection: automatic host OS/architecture detection in production; explicit platform selection is fixture-only',f"- Module services: `{acq['go_proxy']}` and `{acq['go_sumdb']}`, without automatic direct fallback"})
    if not tool_notice.issubset(mihomo_notice): raise SystemExit('notice Go acquisition fields missing or unscoped')
shell_source=tree/paths['shellcrash']['source']
if not (shell_source/'install.sh').is_file() or not (shell_source/'scripts').is_dir(): raise SystemExit('ShellCrash full tagged source/build scripts missing')
if not (shell_source/'ShellCrash.tar.gz').is_file() or sha(shell_source/'ShellCrash.tar.gz')!=components['shellcrash']['payload_sha256']: raise SystemExit('ShellCrash runtime payload/tagged source evidence mismatch')
if (sbom.get('spdxVersion'),sbom.get('dataLicense'),sbom.get('SPDXID')) != ('SPDX-2.3','CC0-1.0','SPDXRef-DOCUMENT'): raise SystemExit('invalid SPDX document identity')
packages={p.get('SPDXID'):p for p in sbom.get('packages',[])}; spdx_ids={'mihomo-linux-arm64':'SPDXRef-Package-Mihomo','shellcrash':'SPDXRef-Package-ShellCrash'}
for cid,c in components.items():
    p=packages.get(spdx_ids[cid])
    if not p: raise SystemExit(f'SBOM package missing: {cid}')
    if (p.get('versionInfo'),p.get('downloadLocation'),p.get('licenseConcluded'),p.get('licenseDeclared')) != (c['version'],c['source_repository'],c['license'],c['license']): raise SystemExit(f'SBOM package identity mismatch: {cid}')
    sums={(x.get('algorithm'),x.get('checksumValue')) for x in p.get('checksums',[])}
    if ('SHA256',c['payload_sha256']) not in sums: raise SystemExit(f'SBOM payload checksum missing: {cid}')
    refs={(x.get('referenceCategory'),x.get('referenceType'),x.get('referenceLocator')) for x in p.get('externalRefs',[])}
    if ('OTHER','vcs-url',f"git+{c['source_repository']}@{c['source_commit']}") not in refs or ('OTHER','complete-source-sha256',c['complete_source_sha256']) not in refs: raise SystemExit(f'SBOM external reference missing: {cid}')
    if cid=='mihomo-linux-arm64' and acq:
        expected={('OTHER','build-toolchain',f"{acq['go_toolchain_version']}|{x['os']}|{x['arch']}|{x['filename']}|{x['sha256']}") for x in acq['go_toolchains']}
        if not expected.issubset(refs): raise SystemExit('SBOM Go toolchain external references missing')
print('third_party_compliance_state=ready')
PY
