#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
py=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'; then py=$candidate; break; fi
done
[ -n "$py" ] || { echo 'Python 3 is required' >&2; exit 1; }
root=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-third-party-fixtures.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

"$py" - "$root" "$repo" <<'PY'
import gzip,hashlib,io,json,os,pathlib,shutil,subprocess,sys,tarfile
root,public=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]); prepare=public/'scripts/prepare-public-sources.sh'; verify=public/'scripts/verify-third-party-compliance.sh'; verify_ps=public/'scripts/verify-third-party-compliance.ps1'; powershell=shutil.which('powershell')
canonical_archiver=public/'scripts/canonical-source-archive.go'
if not canonical_archiver.is_file() or canonical_archiver.name not in prepare.read_text(encoding='utf-8'):
 raise SystemExit('POSIX source preparation is not bound to the canonical Go archiver')
def run(cmd,ok=True):
 p=subprocess.run([str(x) for x in cmd],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
 if ok and p.returncode: raise SystemExit(f"command failed ({p.returncode}): {' '.join(map(str,cmd))}\n{p.stdout}")
 if not ok and p.returncode==0: raise SystemExit(f"expected rejection: {' '.join(map(str,cmd))}")
 return p.stdout
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def git(repo,*args): return run(['git','-C',repo,*args]).strip()
def write(path,data,binary=False):
 path=pathlib.Path(path); path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data) if binary else path.write_text(data,encoding='utf-8',newline='\n')
def payload(path,unsafe=False):
 with path.open('wb') as raw:
  with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=1) as gz:
   with tarfile.open(fileobj=gz,mode='w') as tf:
    data=b'fixture\n'; i=tarfile.TarInfo('../escape.txt' if unsafe else 'ShellCrash/fixture.txt'); i.size=len(data); i.mtime=1; tf.addfile(i,io.BytesIO(data))
def init_repo(path,files,tag,wrong_tag=False):
 path.mkdir(parents=True); run(['git','init','-q',path]); git(path,'config','user.email','fixture@example.invalid'); git(path,'config','user.name','Compliance Fixture')
 for rel,data in files.items(): write(path/rel,data, isinstance(data,bytes))
 git(path,'add','.'); git(path,'commit','-q','-m','fixture source'); git(path,'tag',tag)
 if wrong_tag: write(path/'after-tag.txt','after tag\n'); git(path,'add','.'); git(path,'commit','-q','-m','after tag')
 return git(path,'rev-parse','HEAD')
def make(name,missing_license=False,wrong_tag=False,wrong_hash=False,license_mismatch=False,unsafe=False):
 f=root/name; f.mkdir(); p=f/'payload'; p.mkdir(); tmp=f/'shell.tmp'; payload(tmp)
 mf={'.gitattributes':'* text=auto eol=lf\n','go.mod':'module example.invalid/mihomo\n\ngo 1.20\n\nrequire (\n example.invalid/dep-a v0.0.0\n example.invalid/dep-b v0.0.0\n)\n','go.sum':'','main.go':'package main\n','LICENSE':'fixture GPL-3.0-only license\n'}
 sf={'.gitattributes':'* text=auto eol=lf\n','install.sh':'#!/bin/sh\nexit 0\n','scripts/run.sh':'#!/bin/sh\nexit 0\n','LICENSE.txt':'fixture GPL-3.0-only license\n','version':'1.9.4\n','ShellCrash.tar.gz':tmp.read_bytes()}; tmp.unlink()
 if missing_license: mf.pop('LICENSE')
 m,s=f/'mihomo-upstream',f/'shellcrash-upstream'; mc=init_repo(m,mf,'v1.19.28',wrong_tag); sc=init_repo(s,sf,'1.9.4')
 write(p/'mihomo-linux-arm64',b'mihomo fixture binary\n',True); payload(p/'ShellCrash.tar.gz',unsafe)
 fake=f/'fake-go.sh'; fake_archive=f/'fake-archive.py'
 write(fake_archive,"import gzip,io,pathlib,sys,tarfile\nsource,archive,prefix,epoch=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3],int(sys.argv[4])\nwith archive.open('wb') as raw:\n with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=epoch,compresslevel=9) as gz:\n  with tarfile.open(fileobj=gz,mode='w',format=tarfile.PAX_FORMAT) as tf:\n   ds=sorted((p for p in source.rglob('*') if p.is_dir()),key=lambda p:p.relative_to(source).as_posix()); fs=sorted((p for p in source.rglob('*') if p.is_file()),key=lambda p:p.relative_to(source).as_posix())\n   for p in [source]+ds:\n    rel='' if p==source else p.relative_to(source).as_posix(); i=tarfile.TarInfo(prefix+('/'+rel if rel else '')); i.type,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=tarfile.DIRTYPE,0o755,0,0,'','',epoch; tf.addfile(i)\n   for p in fs:\n    rel=p.relative_to(source).as_posix(); data=p.read_bytes(); i=tarfile.TarInfo(prefix+'/'+rel); i.size,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=len(data),(0o755 if p.suffix=='.sh' else 0o644),0,0,'','',epoch; tf.addfile(i,io.BytesIO(data))\n")
 write(fake,"#!/bin/sh\nset -eu\nif [ \"$1\" = version ]; then echo 'go version go1.20.99 fixture/amd64'; exit 0; fi\nif [ \"$1\" = mod ] && [ \"$2\" = download ]; then echo '{\"Path\":\"example.invalid/dep-a\",\"Version\":\"v0.0.0\",\"Sum\":\"h1:fixture-a\"}'; echo '{\"Path\":\"example.invalid/dep-b\",\"Version\":\"v0.0.0\",\"Sum\":\"h1:fixture-b\"}'; exit 0; fi\nif [ \"$1\" = mod ] && [ \"$2\" = verify ]; then echo 'all modules verified'; exit 0; fi\nif [ \"$1\" = mod ] && [ \"$2\" = vendor ]; then mkdir -p vendor/example.invalid/dep-a vendor/example.invalid/dep-b; printf '# example.invalid/dep-a v0.0.0\\n## explicit\\nexample.invalid/dep-a\\n# example.invalid/dep-b v0.0.0\\n## explicit\\nexample.invalid/dep-b\\n' >vendor/modules.txt; echo 'package dep' >vendor/example.invalid/dep-a/dep.go; echo 'package dep' >vendor/example.invalid/dep-b/dep.go; exit 0; fi\nif [ \"$1\" = run ]; then exec python \"$(dirname \"$0\")/fake-archive.py\" \"$3\" \"$4\" \"$5\" \"$6\"; fi\nexit 1\n"); os.chmod(fake,0o755)
 toolchains=[]
 for tool_os,tool_arch in [('windows','amd64'),('windows','arm64'),('linux','amd64'),('linux','arm64'),('darwin','amd64'),('darwin','arm64')]:
  filename=f"go1.20.99.{tool_os}-{tool_arch}."+('zip' if tool_os=='windows' else 'tar.gz'); archive=f/filename
  if tool_os=='windows':
   import zipfile
   with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z: z.write(fake,'go/bin/go'); z.write(fake_archive,'go/bin/fake-archive.py')
  else:
   with tarfile.open(archive,'w:gz') as tf: tf.add(fake,arcname='go/bin/go'); tf.add(fake_archive,arcname='go/bin/fake-archive.py')
  toolchains.append({'os':tool_os,'arch':tool_arch,'filename':filename,'sha256':sha(archive)})
 archive=f/'go1.20.99.linux-amd64.tar.gz'
 lh=hashlib.sha256(b'fixture GPL-3.0-only license\n').hexdigest(); lock={'schema_version':1,'source_acquisition':{'go_toolchain_version':'go1.20.99','go_toolchains':toolchains,'go_proxy':'https://proxy.golang.org','go_sumdb':'sum.golang.org','go_direct_fallback':False,'go_max_procs':4,'go_module_count_limit':2000},'components':[{'id':'mihomo-linux-arm64','version':'v1.19.28','source_repository':'https://example.invalid/mihomo','source_commit':mc,'license':'GPL-3.0-only','payload_sha256':sha(p/'mihomo-linux-arm64'),'license_sha256':('0'*64 if license_mismatch else lh),'complete_source_sha256':'0'*64},{'id':'shellcrash','version':'1.9.4','source_repository':'https://example.invalid/shellcrash','source_commit':sc,'license':'GPL-3.0-only','payload_sha256':sha(p/'ShellCrash.tar.gz'),'license_sha256':lh,'complete_source_sha256':'0'*64}]}
 if wrong_hash: lock['components'][0]['payload_sha256']='0'*64
 write(f/'lock.json',json.dumps(lock,indent=2)+'\n')
 write(p/'MANIFEST.json',json.dumps({'schema':1,'payloads':[{'id':'mihomo-linux-arm64','path':'mihomo-linux-arm64','version':'v1.19.28','sourceRepository':'mihomo','sha256':sha(p/'mihomo-linux-arm64')},{'id':'shellcrash','path':'ShellCrash.tar.gz','version':'1.9.4','sourceRepository':'shellcrash','sha256':sha(p/'ShellCrash.tar.gz')}]},indent=2)+'\n')
 return f,m,s,p,archive
def pcmd(f,m,s,p,g,o,tool_os='linux',tool_arch='amd64'): return ['sh',prepare,'--output',o,'--payload-dir',p,'--lock',f/'lock.json','--mihomo-url',m,'--shellcrash-url',s,'--go-archive',g,'--go-work-root',f/'go-work','--fixture-mode','--fixture-os',tool_os,'--fixture-arch',tool_arch]
def replace_tool(f,archive,body):
 fake=f/'replacement-go.sh'; write(fake,body); os.chmod(fake,0o755)
 with tarfile.open(archive,'w:gz') as tf: tf.add(fake,arcname='go/bin/go')
 lock=json.loads((f/'lock.json').read_text(encoding='utf-8')); selected=[x for x in lock['source_acquisition']['go_toolchains'] if x['filename']==archive.name]
 if len(selected)!=1: raise SystemExit('replacement fixture toolchain lock missing')
 selected[0]['sha256']=sha(archive); write(f/'lock.json',json.dumps(lock,indent=2)+'\n')
def normalize(source,archive,prefix,epoch):
 source=pathlib.Path(source)
 with pathlib.Path(archive).open('wb') as raw:
  with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=epoch,compresslevel=9) as gz:
   with tarfile.open(fileobj=gz,mode='w',format=tarfile.PAX_FORMAT) as tf:
    ds=sorted((p for p in source.rglob('*') if p.is_dir()),key=lambda p:p.relative_to(source).as_posix()); fs=sorted((p for p in source.rglob('*') if p.is_file()),key=lambda p:p.relative_to(source).as_posix())
    for p in [source]+ds:
     rel='' if p==source else p.relative_to(source).as_posix(); i=tarfile.TarInfo(prefix+('/'+rel if rel else '')); i.type,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=tarfile.DIRTYPE,0o755,0,0,'','',epoch; tf.addfile(i)
    for p in fs:
     rel=p.relative_to(source).as_posix(); data=p.read_bytes(); i=tarfile.TarInfo(prefix+'/'+rel); i.size,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=len(data),(0o755 if p.suffix=='.sh' else 0o644),0,0,'','',epoch; tf.addfile(i,io.BytesIO(data))
def contracts(f,o):
 lock=json.loads((f/'lock.json').read_text(encoding='utf-8')); by={x['id']:x for x in lock['components']}; by['mihomo-linux-arm64']['complete_source_sha256']=sha(o/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz'); by['shellcrash']['complete_source_sha256']=sha(o/'third-party/sources/shellcrash-1.9.4-complete-source.tar.gz'); write(f/'lock.json',json.dumps(lock,indent=2)+'\n')
 packs=[{'name':'fixture source','SPDXID':'SPDXRef-Package-Source','versionInfo':'test','downloadLocation':'NOASSERTION','filesAnalyzed':False,'licenseConcluded':'Apache-2.0','licenseDeclared':'Apache-2.0','copyrightText':'NOASSERTION'}]
 for cid,spdx in [('mihomo-linux-arm64','SPDXRef-Package-Mihomo'),('shellcrash','SPDXRef-Package-ShellCrash')]:
  c=by[cid]; refs=[{'referenceCategory':'OTHER','referenceType':'vcs-url','referenceLocator':f"git+{c['source_repository']}@{c['source_commit']}"},{'referenceCategory':'OTHER','referenceType':'complete-source-sha256','referenceLocator':c['complete_source_sha256']}]
  if cid=='mihomo-linux-arm64': refs += [{'referenceCategory':'OTHER','referenceType':'build-toolchain','referenceLocator':f"{lock['source_acquisition']['go_toolchain_version']}|{x['os']}|{x['arch']}|{x['filename']}|{x['sha256']}"} for x in lock['source_acquisition']['go_toolchains']]
  packs.append({'name':cid,'SPDXID':spdx,'versionInfo':c['version'],'downloadLocation':c['source_repository'],'filesAnalyzed':False,'licenseConcluded':c['license'],'licenseDeclared':c['license'],'copyrightText':'NOASSERTION','checksums':[{'algorithm':'SHA256','checksumValue':c['payload_sha256']}],'externalRefs':refs})
 write(f/'sbom.json',json.dumps({'spdxVersion':'SPDX-2.3','dataLicense':'CC0-1.0','SPDXID':'SPDXRef-DOCUMENT','name':'fixture','documentNamespace':'https://example.invalid/spdx/fixture','creationInfo':{'created':'2026-01-01T00:00:00Z','creators':['Tool: fixture']},'packages':packs},indent=2)+'\n')
 m,s=by['mihomo-linux-arm64'],by['shellcrash']; tool_lines=[f"- Pinned Go source-preparation archive ({x['os']}/{x['arch']}): `{x['filename']}`, SHA-256 `{x['sha256']}`" for x in lock['source_acquisition']['go_toolchains']]
 facts=['# Fixture notices','',f"## Mihomo {m['version']}",f"- Source: {m['source_repository']}",f"- Source commit: `{m['source_commit']}`",f"- License: {m['license']}",f"- Upstream license SHA-256: `{m['license_sha256']}`",f"- Runtime payload SHA-256: `{m['payload_sha256']}`",'- Complete corresponding source: `mihomo-v1.19.28-complete-source.tar.gz`',f"- Complete corresponding source SHA-256: `{m['complete_source_sha256']}`"]+tool_lines+['- Source-preparation selection: automatic host OS/architecture detection in production; explicit platform selection is fixture-only','- Module services: `https://proxy.golang.org` and `sum.golang.org`, without automatic direct fallback','',f"## ShellCrash {s['version']}",f"- Source: {s['source_repository']}",f"- Source commit: `{s['source_commit']}`",f"- License: {s['license']}",f"- Upstream license SHA-256: `{s['license_sha256']}`",f"- Runtime payload SHA-256: `{s['payload_sha256']}`",'- Complete corresponding source: `shellcrash-1.9.4-complete-source.tar.gz`',f"- Complete corresponding source SHA-256: `{s['complete_source_sha256']}`",'']
 write(f/'notice.md','\n'.join(facts)+'\n')
def vcmd(f,o): return ['sh',verify,'--tree',o,'--lock',f/'lock.json','--sbom',f/'sbom.json','--notice',f/'notice.md']
for n,k in [('wrong-tag',{'wrong_tag':True}),('wrong-binary',{'wrong_hash':True}),('absent-license',{'missing_license':True}),('license-mismatch',{'license_mismatch':True}),('unsafe-payload',{'unsafe':True})]:
 f,m,s,p,g=make(n,**k); run(pcmd(f,m,s,p,g,f/'out'),False)
f,m,s,p,g=make('direct-forbidden'); run(pcmd(f,m,s,p,g,f/'out')+['--go-proxy','direct'],False)
f,m,s,p,g=make('module-error'); replace_tool(f,g,"#!/bin/sh\nif [ \"$1\" = version ]; then echo 'go version go1.20.99 fixture/amd64'; elif [ \"$1\" = mod ] && [ \"$2\" = download ]; then echo '{\"Path\":\"example.invalid/dep-a\",\"Version\":\"v0.0.0\",\"Error\":\"fixture error\"}'; else exit 1; fi\n"); run(pcmd(f,m,s,p,g,f/'out'),False)
f,m,s,p,g=make('module-zero'); replace_tool(f,g,"#!/bin/sh\nif [ \"$1\" = version ]; then echo 'go version go1.20.99 fixture/amd64'; elif [ \"$1\" = mod ] && [ \"$2\" = download ]; then echo '{}'; else exit 1; fi\n"); run(pcmd(f,m,s,p,g,f/'out'),False)
f,m,s,p,g=make('module-limit'); replace_tool(f,g,"#!/bin/sh\nif [ \"$1\" = version ]; then echo 'go version go1.20.99 fixture/amd64'; elif [ \"$1\" = mod ] && [ \"$2\" = download ]; then echo '{\"Path\":\"example.invalid/dep-a\",\"Version\":\"v0.0.0\"}'; echo '{\"Path\":\"example.invalid/dep-b\",\"Version\":\"v0.0.0\"}'; else exit 1; fi\n"); run(pcmd(f,m,s,p,g,f/'out')+['--max-modules','1'],False)
f,m,s,p,g=make('manifest-drift'); manifest=json.loads((p/'MANIFEST.json').read_text(encoding='utf-8')); manifest['payloads'][0]['path']='wrong-name'; write(p/'MANIFEST.json',json.dumps(manifest,indent=2)+'\n'); run(pcmd(f,m,s,p,g,f/'out'),False)
f,m,s,p,g=make('hostile-same-version-tool'); run(pcmd(f,m,s,p,g,f/'out')+['--go-command',f/'fake-go.sh'],False)
f,m,s,p,g=make('local-source-without-fixture-boundary'); cmd=pcmd(f,m,s,p,g,f/'out'); cmd.remove('--fixture-mode'); run(cmd,False)
f,m,s,p,g=make('credential-locator'); cmd=pcmd(f,m,s,p,g,f/'out'); cmd[cmd.index('--mihomo-url')+1]='git@fixture.invalid:MetaCubeX/mihomo'; cmd.remove('--fixture-mode'); run(cmd,False)
f,m,s,p,g=make('unsupported-platform'); run(pcmd(f,m,s,p,g,f/'out','freebsd','amd64'),False)
f,m,s,p,g=make('archive-platform-mismatch'); run(pcmd(f,m,s,p,g,f/'out','darwin','amd64'),False)
f,m,s,p,g=make('toolchain-hash-mismatch'); g.write_bytes(g.read_bytes()+b'tampered'); run(pcmd(f,m,s,p,g,f/'out'),False)
f,m,s,p,g=make('incomplete-platform-lock'); lock=json.loads((f/'lock.json').read_text()); lock['source_acquisition']['go_toolchains'].pop(); write(f/'lock.json',json.dumps(lock,indent=2)+'\n'); run(pcmd(f,m,s,p,g,f/'out'),False)
f,m,s,p,g=make('production-platform-override'); cmd=pcmd(f,m,s,p,g,f/'out'); cmd.remove('--fixture-mode'); run(cmd,False)
for platform_os,platform_arch in [('linux','arm64'),('darwin','amd64')]:
 f,m,s,p,g=make(f'{platform_os}-{platform_arch}-selection'); archive=f/f'go1.20.99.{platform_os}-{platform_arch}.tar.gz'; out=f/'out'; result=run(pcmd(f,m,s,p,archive,out,platform_os,platform_arch)); provenance=json.loads((out/'third-party/mihomo/SOURCE-PREPARATION.json').read_text(encoding='utf-8')); source_meta=json.loads((out/'third-party/mihomo/source/SOURCE-BUILD.json').read_text(encoding='utf-8'))
 if 'third_party_source_state=ready' not in result or (provenance.get('host_os'),provenance.get('host_arch'),provenance.get('go_toolchain_archive'),provenance.get('go_toolchain_archive_sha256'))!=(platform_os,platform_arch,archive.name,sha(archive)) or any(k.startswith('go_toolchain_') or k in ('host_os','host_arch') for k in source_meta): raise SystemExit(f'platform toolchain selection mismatch: {platform_os}/{platform_arch}')
f,m,s,p,g=make('compliant'); outputs=[]
for platform_os,platform_arch in [('windows','amd64'),('linux','amd64'),('darwin','arm64')]:
 extension='zip' if platform_os=='windows' else 'tar.gz'; archive=f/f'go1.20.99.{platform_os}-{platform_arch}.{extension}'; candidate=f/f'out-{platform_os}-{platform_arch}'; result=run(pcmd(f,m,s,p,archive,candidate,platform_os,platform_arch))
 if 'third_party_source_state=ready' not in result: raise SystemExit(f'source ready marker missing: {platform_os}/{platform_arch}')
 outputs.append(candidate)
source_hashes={sha(candidate/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz') for candidate in outputs}
if len(source_hashes)!=1: raise SystemExit(f'platform-dependent complete source hash: {sorted(source_hashes)}')
o=outputs[0]; contracts(f,o)
for candidate in outputs:
 if 'third_party_compliance_state=ready' not in run(vcmd(f,candidate)): raise SystemExit('POSIX compliance ready marker missing')
 if powershell and 'third_party_compliance_state=ready' not in run([powershell,'-NoProfile','-ExecutionPolicy','Bypass','-File',verify_ps,'-Tree',candidate,'-Lock',f/'lock.json','-Sbom',f/'sbom.json','-Notice',f/'notice.md']): raise SystemExit('PowerShell compliance ready marker missing')
case=f/'notice-missing-toolchain'; shutil.copytree(o,case); notice=(f/'notice.md').read_text(encoding='utf-8'); first_tool=next(line for line in notice.splitlines() if line.startswith('- Pinned Go source-preparation archive ')); write(f/'notice-missing-toolchain.md',notice.replace(first_tool+'\n','',1)); cmd=vcmd(f,case); cmd[cmd.index('--notice')+1]=f/'notice-missing-toolchain.md'; run(cmd,False)
case=f/'sbom-missing-toolchain'; shutil.copytree(o,case); sbom=json.loads((f/'sbom.json').read_text()); package=next(x for x in sbom['packages'] if x['SPDXID']=='SPDXRef-Package-Mihomo'); package['externalRefs'].remove(next(x for x in package['externalRefs'] if x['referenceType']=='build-toolchain')); write(f/'sbom-missing-toolchain.json',json.dumps(sbom,indent=2)+'\n'); cmd=vcmd(f,case); cmd[cmd.index('--sbom')+1]=f/'sbom-missing-toolchain.json'; run(cmd,False)
o2=f/'out-2'; run(pcmd(f,m,s,p,g,o2))
for rel in ('third-party/sources/mihomo-v1.19.28-complete-source.tar.gz','third-party/sources/shellcrash-1.9.4-complete-source.tar.gz'):
 if sha(o/rel)!=sha(o2/rel): raise SystemExit(f'nondeterministic complete source: {rel}')
case=f/'absent-complete'; shutil.copytree(o,case); (case/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz').unlink(); run(vcmd(f,case),False)
case=f/'wrong-payload'; shutil.copytree(o,case); write(case/'third-party/mihomo/mihomo-linux-arm64',b'changed\n',True); run(vcmd(f,case),False)
case=f/'wrong-license'; shutil.copytree(o,case); write(case/'third-party/mihomo/LICENSE','changed\n'); run(vcmd(f,case),False)
case=f/'shellcrash-mismatch'; shutil.copytree(o,case); write(case/'third-party/shellcrash/source/extra.txt','not archived\n'); run(vcmd(f,case),False)
case=f/'shellcrash-runtime-source-mismatch'; shutil.copytree(o,case); write(case/'third-party/shellcrash/source/ShellCrash.tar.gz',b'not the runtime payload\n',True); meta=json.loads((case/'third-party/shellcrash/source/SOURCE-BUILD.json').read_text()); normalize(case/'third-party/shellcrash/source',case/'third-party/sources/shellcrash-1.9.4-complete-source.tar.gz','shellcrash-1.9.4-source',meta['source_commit_epoch']); contracts(f,case); run(vcmd(f,case),False)
case=f/'notice-missing-component-field'; shutil.copytree(o,case); notice=(f/'notice.md').read_text(encoding='utf-8'); write(f/'notice-missing.md',notice.replace(f"- Source: {json.loads((f/'lock.json').read_text())['components'][0]['source_repository']}\n",'',1)); cmd=vcmd(f,case); cmd[cmd.index('--notice')+1]=f/'notice-missing.md'; run(cmd,False)
case=f/'notice-cross-assigned-field'; shutil.copytree(o,case); lock_now=json.loads((f/'lock.json').read_text()); mc,sc=lock_now['components'][0]['source_commit'],lock_now['components'][1]['source_commit']; notice=(f/'notice.md').read_text(encoding='utf-8').replace(mc,'__MIHOMO_COMMIT__').replace(sc,mc).replace('__MIHOMO_COMMIT__',sc); write(f/'notice-cross.md',notice); cmd=vcmd(f,case); cmd[cmd.index('--notice')+1]=f/'notice-cross.md'; run(cmd,False)
case=f/'partial-vendor-loss'; shutil.copytree(o,case); (case/'third-party/mihomo/source/vendor/example.invalid/dep-a/dep.go').unlink(); meta=json.loads((case/'third-party/mihomo/source/SOURCE-BUILD.json').read_text()); normalize(case/'third-party/mihomo/source',case/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz','mihomo-v1.19.28-source',meta['source_commit_epoch']); contracts(f,case); run(vcmd(f,case),False)
case=f/'unsafe-source'; shutil.copytree(o,case); a=case/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz'
with a.open('wb') as raw:
 with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=1) as gz:
  with tarfile.open(fileobj=gz,mode='w') as tf:
   data=b'escape'; i=tarfile.TarInfo('../escape'); i.size=len(data); i.mtime=1; tf.addfile(i,io.BytesIO(data))
contracts(f,case); run(vcmd(f,case),False)
case=f/'preparation-cross-assignment'; shutil.copytree(o,case); provenance_path=case/'third-party/mihomo/SOURCE-PREPARATION.json'; provenance=json.loads(provenance_path.read_text(encoding='utf-8')); provenance['host_os']='darwin'; provenance['host_arch']='amd64'; write(provenance_path,json.dumps(provenance,indent=2)+'\n'); run(vcmd(f,case),False)
case=f/'preparation-source-hash-tamper'; shutil.copytree(o,case); provenance_path=case/'third-party/mihomo/SOURCE-PREPARATION.json'; provenance=json.loads(provenance_path.read_text(encoding='utf-8')); provenance['complete_source_sha256']='0'*64; write(provenance_path,json.dumps(provenance,indent=2)+'\n'); run(vcmd(f,case),False)
case=f/'preparation-missing'; shutil.copytree(o,case); (case/'third-party/mihomo/SOURCE-PREPARATION.json').unlink(); run(vcmd(f,case),False)
print('third_party_compliance_fixture_tests=ok')
PY
