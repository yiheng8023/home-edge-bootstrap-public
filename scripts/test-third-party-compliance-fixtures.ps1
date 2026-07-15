param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = "Stop"
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-third-party-fixtures-" + [guid]::NewGuid().ToString("N"))
$Python = $null
foreach ($Name in @("python3", "python")) {
  $Command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $Command) { continue }
  & $Command.Source -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'
  if ($LASTEXITCODE -eq 0) { $Python = [string]$Command.Source; break }
}
if (-not $Python) { throw "Python 3 is required" }
$PowerShell = (Get-Command powershell -ErrorAction Stop).Source

$Code = @'
import gzip, hashlib, io, json, os, pathlib, shutil, subprocess, sys, tarfile, zipfile
root, public, powershell = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
prepare=public/'scripts/prepare-public-sources.ps1'; verify=public/'scripts/verify-third-party-compliance.ps1'; verify_sh=public/'scripts/verify-third-party-compliance.sh'
root.mkdir(parents=True,exist_ok=True)

canonical_archiver=public/'scripts/canonical-source-archive.go'
if not canonical_archiver.is_file() or canonical_archiver.name not in prepare.read_text(encoding='utf-8'):
    raise SystemExit('PowerShell source preparation is not bound to the canonical Go archiver')

def run(cmd, ok=True):
    p=subprocess.run([str(x) for x in cmd],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    if ok and p.returncode: raise SystemExit(f"command failed ({p.returncode}): {' '.join(map(str,cmd))}\n{p.stdout}")
    if not ok and p.returncode==0: raise SystemExit(f"expected rejection: {' '.join(map(str,cmd))}")
    return p.stdout
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def git(repo,*args): return run(['git','-C',repo,*args]).strip()
def write(path,data,binary=False):
    path=pathlib.Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(data) if binary else path.write_text(data,encoding='utf-8',newline='\n')
def safe_payload(path):
    with path.open('wb') as raw:
      with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=1) as gz:
       with tarfile.open(fileobj=gz,mode='w') as tf:
        data=b'fixture\n'; i=tarfile.TarInfo('ShellCrash/fixture.txt'); i.size=len(data); i.mtime=1; tf.addfile(i,io.BytesIO(data))
def unsafe_payload(path):
    with path.open('wb') as raw:
      with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=1) as gz:
       with tarfile.open(fileobj=gz,mode='w') as tf:
        data=b'escape\n'; i=tarfile.TarInfo('../escape.txt'); i.size=len(data); i.mtime=1; tf.addfile(i,io.BytesIO(data))
def init_repo(path,files,tag,wrong_tag=False):
    path.mkdir(parents=True); run(['git','init','-q',path]); git(path,'config','user.email','fixture@example.invalid'); git(path,'config','user.name','Compliance Fixture')
    for rel,data in files.items(): write(path/rel,data,isinstance(data,bytes))
    git(path,'add','.'); git(path,'commit','-q','-m','fixture source'); first=git(path,'rev-parse','HEAD'); git(path,'tag',tag)
    if wrong_tag:
        write(path/'after-tag.txt','after tag\n'); git(path,'add','.'); git(path,'commit','-q','-m','after tag')
    return git(path,'rev-parse','HEAD')
def make_fixture(name,missing_license=False,wrong_tag=False,wrong_hash=False,license_mismatch=False,unsafe=False):
    f=root/name; f.mkdir(); payload=f/'payload'; payload.mkdir()
    mihomo_files={'.gitattributes':'* text=auto eol=lf\n','go.mod':'module example.invalid/mihomo\n\ngo 1.20\n\nrequire (\n example.invalid/dep-a v0.0.0\n example.invalid/dep-b v0.0.0\n)\n','go.sum':'','main.go':'package main\n','LICENSE':'fixture GPL-3.0-only license\n'}
    shell_files={'.gitattributes':'* text=auto eol=lf\n','install.sh':'#!/bin/sh\nexit 0\n','scripts/run.sh':'#!/bin/sh\nexit 0\n','LICENSE.txt':'fixture GPL-3.0-only license\n','version':'1.9.4\n'}
    if missing_license: mihomo_files.pop('LICENSE')
    mrepo=f/'mihomo-upstream'; srepo=f/'shellcrash-upstream'
    mc=init_repo(mrepo,mihomo_files,'v1.19.28',wrong_tag=wrong_tag)
    safe_payload(f/'shell-payload.tmp'); shell_files['ShellCrash.tar.gz']=(f/'shell-payload.tmp').read_bytes(); (f/'shell-payload.tmp').unlink()
    sc=init_repo(srepo,shell_files,'1.9.4')
    write(payload/'mihomo-linux-arm64',b'mihomo fixture binary\n',True)
    (unsafe_payload if unsafe else safe_payload)(payload/'ShellCrash.tar.gz')
    license_hash=hashlib.sha256(b'fixture GPL-3.0-only license\n').hexdigest()
    fake_archive=f/'fake-archive.py'; write(fake_archive,"import gzip,io,pathlib,sys,tarfile\nsource,archive,prefix,epoch=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3],int(sys.argv[4])\nwith archive.open('wb') as raw:\n with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=epoch,compresslevel=9) as gz:\n  with tarfile.open(fileobj=gz,mode='w',format=tarfile.PAX_FORMAT) as tf:\n   dirs=sorted((p for p in source.rglob('*') if p.is_dir()),key=lambda p:p.relative_to(source).as_posix()); files=sorted((p for p in source.rglob('*') if p.is_file()),key=lambda p:p.relative_to(source).as_posix())\n   for p in [source]+dirs:\n    rel='' if p==source else p.relative_to(source).as_posix(); i=tarfile.TarInfo(prefix+('/'+rel if rel else '')); i.type,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=tarfile.DIRTYPE,0o755,0,0,'','',epoch; tf.addfile(i)\n   for p in files:\n    rel=p.relative_to(source).as_posix(); data=p.read_bytes(); i=tarfile.TarInfo(prefix+'/'+rel); i.size,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=len(data),(0o755 if p.suffix=='.sh' else 0o644),0,0,'','',epoch; tf.addfile(i,io.BytesIO(data))\n")
    fake_py=f/'fake-go.py'; write(fake_py,"import json,pathlib,subprocess,sys\na=sys.argv[1:]\nif a==['version']: print('go version go1.20.99 fixture/amd64')\nelif a[:2]==['mod','download']:\n print(json.dumps({'Path':'example.invalid/dep-a','Version':'v0.0.0','Sum':'h1:fixture-a'},separators=(',',':'))); print(json.dumps({'Path':'example.invalid/dep-b','Version':'v0.0.0','Sum':'h1:fixture-b'},separators=(',',':')))\nelif a[:2]==['mod','verify']: print('all modules verified')\nelif a[:2]==['mod','vendor']:\n for name in ('dep-a','dep-b'):\n  p=pathlib.Path('vendor/example.invalid')/name; p.mkdir(parents=True,exist_ok=True); (p/'dep.go').write_bytes(b'package dep\\n')\n pathlib.Path('vendor/modules.txt').write_bytes(b'# example.invalid/dep-a v0.0.0\\n## explicit\\nexample.invalid/dep-a\\n# example.invalid/dep-b v0.0.0\\n## explicit\\nexample.invalid/dep-b\\n')\nelif a[:1]==['run']: raise SystemExit(subprocess.run([sys.executable,pathlib.Path(__file__).with_name('fake-archive.py'),*a[2:]]).returncode)\nelse: raise SystemExit(1)\n")
    fake=f/'fake-go.cmd'; write(fake,'@echo off\r\npython "%~dp0fake-go.py" %*\r\n')
    fake_sh=f/'fake-go.sh'; write(fake_sh,"#!/bin/sh\nexec python \"$(dirname \"$0\")/fake-go.py\" \"$@\"\n"); os.chmod(fake_sh,0o755)
    toolchains=[]
    for tool_os,tool_arch in [('windows','amd64'),('windows','arm64'),('linux','amd64'),('linux','arm64'),('darwin','amd64'),('darwin','arm64')]:
      filename=f"go1.20.99.{tool_os}-{tool_arch}."+('zip' if tool_os=='windows' else 'tar.gz'); archive=f/filename
      if tool_os=='windows':
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
          z.write(fake,'go/bin/go.cmd'); z.write(fake_sh,'go/bin/go'); z.write(fake_py,'go/bin/fake-go.py'); z.write(fake_archive,'go/bin/fake-archive.py')
      else:
        with tarfile.open(archive,'w:gz') as tf:
          tf.add(fake_sh,arcname='go/bin/go'); tf.add(fake,arcname='go/bin/go.cmd'); tf.add(fake_py,arcname='go/bin/fake-go.py'); tf.add(fake_archive,arcname='go/bin/fake-archive.py')
      toolchains.append({'os':tool_os,'arch':tool_arch,'filename':filename,'sha256':sha(archive)})
    archive=f/'go1.20.99.windows-amd64.zip'
    lock={'schema_version':1,'source_acquisition':{'go_toolchain_version':'go1.20.99','go_toolchains':toolchains,'go_proxy':'https://proxy.golang.org','go_sumdb':'sum.golang.org','go_direct_fallback':False,'go_max_procs':4,'go_module_count_limit':2000},'components':[
      {'id':'mihomo-linux-arm64','version':'v1.19.28','source_repository':'https://example.invalid/mihomo','source_commit':mc,'license':'GPL-3.0-only','payload_sha256':sha(payload/'mihomo-linux-arm64'),'license_sha256':('0'*64 if license_mismatch else license_hash),'complete_source_sha256':'0'*64},
      {'id':'shellcrash','version':'1.9.4','source_repository':'https://example.invalid/shellcrash','source_commit':sc,'license':'GPL-3.0-only','payload_sha256':sha(payload/'ShellCrash.tar.gz'),'license_sha256':license_hash,'complete_source_sha256':'0'*64}]}
    if wrong_hash: lock['components'][0]['payload_sha256']='0'*64
    write(f/'lock.json',json.dumps(lock,indent=2)+'\n')
    manifest={'schema':1,'payloads':[{'id':'mihomo-linux-arm64','path':'mihomo-linux-arm64','version':'v1.19.28','sourceRepository':'mihomo','sha256':sha(payload/'mihomo-linux-arm64')},{'id':'shellcrash','path':'ShellCrash.tar.gz','version':'1.9.4','sourceRepository':'shellcrash','sha256':sha(payload/'ShellCrash.tar.gz')}]}
    write(payload/'MANIFEST.json',json.dumps(manifest,indent=2)+'\n')
    return f,mrepo,srepo,payload,archive
def prepare_cmd(f,m,s,payload,archive,out,tool_os='windows',tool_arch='amd64'):
    return [powershell,'-NoProfile','-ExecutionPolicy','Bypass','-File',prepare,'--output',out,'--payload-dir',payload,'--lock',f/'lock.json','--mihomo-url',m,'--shellcrash-url',s,'--go-archive',archive,'--go-work-root',f/'go-work','--fixture-mode','--fixture-os',tool_os,'--fixture-arch',tool_arch]
def replace_tool(f,archive,body):
    py=f/'replacement-go.py'; cmd=f/'replacement-go.cmd'; sh=f/'replacement-go.sh'
    write(py,body); write(cmd,'@echo off\r\npython "%~dp0fake-go.py" %*\r\n'); write(sh,"#!/bin/sh\nexec python \"$(dirname \"$0\")/fake-go.py\" \"$@\"\n"); os.chmod(sh,0o755)
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
      z.write(cmd,'go/bin/go.cmd'); z.write(sh,'go/bin/go'); z.write(py,'go/bin/fake-go.py')
    lock=json.loads((f/'lock.json').read_text(encoding='utf-8')); selected=[x for x in lock['source_acquisition']['go_toolchains'] if x['filename']==archive.name]
    if len(selected)!=1: raise SystemExit('replacement fixture toolchain lock missing')
    selected[0]['sha256']=sha(archive); write(f/'lock.json',json.dumps(lock,indent=2)+'\n')
def normalize(source,archive,prefix,epoch):
    source=pathlib.Path(source); archive=pathlib.Path(archive)
    with archive.open('wb') as raw:
      with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=epoch,compresslevel=9) as gz:
       with tarfile.open(fileobj=gz,mode='w',format=tarfile.PAX_FORMAT) as tf:
        dirs=sorted((p for p in source.rglob('*') if p.is_dir()),key=lambda p:p.relative_to(source).as_posix()); files=sorted((p for p in source.rglob('*') if p.is_file()),key=lambda p:p.relative_to(source).as_posix())
        for p in [source]+dirs:
            rel='' if p==source else p.relative_to(source).as_posix(); i=tarfile.TarInfo(prefix+('/'+rel if rel else '')); i.type,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=tarfile.DIRTYPE,0o755,0,0,'','',epoch; tf.addfile(i)
        for p in files:
            rel=p.relative_to(source).as_posix(); data=p.read_bytes(); i=tarfile.TarInfo(prefix+'/'+rel); i.size,i.mode,i.uid,i.gid,i.uname,i.gname,i.mtime=len(data),(0o755 if p.suffix=='.sh' else 0o644),0,0,'','',epoch; tf.addfile(i,io.BytesIO(data))
def contracts(f,out):
    lock=json.loads((f/'lock.json').read_text(encoding='utf-8')); by={x['id']:x for x in lock['components']}
    by['mihomo-linux-arm64']['complete_source_sha256']=sha(out/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz')
    by['shellcrash']['complete_source_sha256']=sha(out/'third-party/sources/shellcrash-1.9.4-complete-source.tar.gz')
    write(f/'lock.json',json.dumps(lock,indent=2)+'\n')
    packages=[{'name':'fixture source','SPDXID':'SPDXRef-Package-Source','versionInfo':'test','downloadLocation':'NOASSERTION','filesAnalyzed':False,'licenseConcluded':'Apache-2.0','licenseDeclared':'Apache-2.0','copyrightText':'NOASSERTION'}]
    for cid,spdx in [('mihomo-linux-arm64','SPDXRef-Package-Mihomo'),('shellcrash','SPDXRef-Package-ShellCrash')]:
      c=by[cid]; refs=[{'referenceCategory':'OTHER','referenceType':'vcs-url','referenceLocator':f"git+{c['source_repository']}@{c['source_commit']}"},{'referenceCategory':'OTHER','referenceType':'complete-source-sha256','referenceLocator':c['complete_source_sha256']}]
      if cid=='mihomo-linux-arm64': refs += [{'referenceCategory':'OTHER','referenceType':'build-toolchain','referenceLocator':f"{lock['source_acquisition']['go_toolchain_version']}|{x['os']}|{x['arch']}|{x['filename']}|{x['sha256']}"} for x in lock['source_acquisition']['go_toolchains']]
      packages.append({'name':cid,'SPDXID':spdx,'versionInfo':c['version'],'downloadLocation':c['source_repository'],'filesAnalyzed':False,'licenseConcluded':c['license'],'licenseDeclared':c['license'],'copyrightText':'NOASSERTION','checksums':[{'algorithm':'SHA256','checksumValue':c['payload_sha256']}],'externalRefs':refs})
    sbom={'spdxVersion':'SPDX-2.3','dataLicense':'CC0-1.0','SPDXID':'SPDXRef-DOCUMENT','name':'fixture','documentNamespace':'https://example.invalid/spdx/fixture','creationInfo':{'created':'2026-01-01T00:00:00Z','creators':['Tool: fixture']},'packages':packages}
    write(f/'sbom.json',json.dumps(sbom,indent=2)+'\n')
    m,s=by['mihomo-linux-arm64'],by['shellcrash']
    tool_lines=[f"- Pinned Go source-preparation archive ({x['os']}/{x['arch']}): `{x['filename']}`, SHA-256 `{x['sha256']}`" for x in lock['source_acquisition']['go_toolchains']]
    facts=['# Fixture notices','',f"## Mihomo {m['version']}",f"- Source: {m['source_repository']}",f"- Source commit: `{m['source_commit']}`",f"- License: {m['license']}",f"- Upstream license SHA-256: `{m['license_sha256']}`",f"- Runtime payload SHA-256: `{m['payload_sha256']}`",'- Complete corresponding source: `mihomo-v1.19.28-complete-source.tar.gz`',f"- Complete corresponding source SHA-256: `{m['complete_source_sha256']}`"]+tool_lines+['- Source-preparation selection: automatic host OS/architecture detection in production; explicit platform selection is fixture-only','- Module services: `https://proxy.golang.org` and `sum.golang.org`, without automatic direct fallback','',f"## ShellCrash {s['version']}",f"- Source: {s['source_repository']}",f"- Source commit: `{s['source_commit']}`",f"- License: {s['license']}",f"- Upstream license SHA-256: `{s['license_sha256']}`",f"- Runtime payload SHA-256: `{s['payload_sha256']}`",'- Complete corresponding source: `shellcrash-1.9.4-complete-source.tar.gz`',f"- Complete corresponding source SHA-256: `{s['complete_source_sha256']}`",'']
    write(f/'notice.md','\n'.join(facts)+'\n')
def verify_cmd(f,out): return [powershell,'-NoProfile','-ExecutionPolicy','Bypass','-File',verify,'-Tree',out,'-Lock',f/'lock.json','-Sbom',f/'sbom.json','-Notice',f/'notice.md']

for name,kwargs in [('wrong-tag',{'wrong_tag':True}),('wrong-binary',{'wrong_hash':True}),('absent-license',{'missing_license':True}),('license-mismatch',{'license_mismatch':True}),('unsafe-payload',{'unsafe':True})]:
    f,m,s,p,g=make_fixture(name,**kwargs); run(prepare_cmd(f,m,s,p,g,f/'out'),ok=False)
f,m,s,p,g=make_fixture('direct-forbidden'); run(prepare_cmd(f,m,s,p,g,f/'out')+['-GoProxy','direct'],ok=False)
f,m,s,p,g=make_fixture('module-error'); replace_tool(f,g,"import json,sys\na=sys.argv[1:]\nif a==['version']: print('go version go1.20.99 fixture/amd64')\nelif a[:2]==['mod','download']: print(json.dumps({'Path':'example.invalid/dep-a','Version':'v0.0.0','Error':'fixture error'}))\nelse: raise SystemExit(1)\n"); run(prepare_cmd(f,m,s,p,g,f/'out'),ok=False)
f,m,s,p,g=make_fixture('module-zero'); replace_tool(f,g,"import sys\na=sys.argv[1:]\nif a==['version']: print('go version go1.20.99 fixture/amd64')\nelif a[:2]==['mod','download']: print('{}')\nelse: raise SystemExit(1)\n"); run(prepare_cmd(f,m,s,p,g,f/'out'),ok=False)
f,m,s,p,g=make_fixture('module-limit'); replace_tool(f,g,"import json,sys\na=sys.argv[1:]\nif a==['version']: print('go version go1.20.99 fixture/amd64')\nelif a[:2]==['mod','download']:\n print(json.dumps({'Path':'example.invalid/dep-a','Version':'v0.0.0'})); print(json.dumps({'Path':'example.invalid/dep-b','Version':'v0.0.0'}))\nelse: raise SystemExit(1)\n"); run(prepare_cmd(f,m,s,p,g,f/'out')+['--max-modules','1'],ok=False)
f,m,s,p,g=make_fixture('manifest-drift'); manifest=json.loads((p/'MANIFEST.json').read_text(encoding='utf-8')); manifest['payloads'][0]['path']='wrong-name'; write(p/'MANIFEST.json',json.dumps(manifest,indent=2)+'\n'); run(prepare_cmd(f,m,s,p,g,f/'out'),ok=False)
f,m,s,p,g=make_fixture('hostile-same-version-tool'); run(prepare_cmd(f,m,s,p,g,f/'out')+['--go-command',f/'fake-go.cmd'],ok=False)
f,m,s,p,g=make_fixture('local-source-without-fixture-boundary'); cmd=prepare_cmd(f,m,s,p,g,f/'out'); cmd.remove('--fixture-mode'); run(cmd,ok=False)
f,m,s,p,g=make_fixture('credential-locator'); cmd=prepare_cmd(f,m,s,p,g,f/'out'); cmd[cmd.index('--mihomo-url')+1]='git@fixture.invalid:MetaCubeX/mihomo'; cmd.remove('--fixture-mode'); run(cmd,ok=False)
f,m,s,p,g=make_fixture('unsupported-platform'); run(prepare_cmd(f,m,s,p,g,f/'out','freebsd','amd64'),ok=False)
f,m,s,p,g=make_fixture('archive-platform-mismatch'); run(prepare_cmd(f,m,s,p,g,f/'out','linux','amd64'),ok=False)
f,m,s,p,g=make_fixture('toolchain-hash-mismatch'); g.write_bytes(g.read_bytes()+b'tampered'); run(prepare_cmd(f,m,s,p,g,f/'out'),ok=False)
f,m,s,p,g=make_fixture('incomplete-platform-lock'); lock=json.loads((f/'lock.json').read_text()); lock['source_acquisition']['go_toolchains'].pop(); write(f/'lock.json',json.dumps(lock,indent=2)+'\n'); run(prepare_cmd(f,m,s,p,g,f/'out'),ok=False)
f,m,s,p,g=make_fixture('production-platform-override'); cmd=prepare_cmd(f,m,s,p,g,f/'out'); cmd.remove('--fixture-mode'); run(cmd,ok=False)
for platform_os,platform_arch in [('linux','amd64'),('darwin','arm64')]:
    f,m,s,p,g=make_fixture(f'{platform_os}-{platform_arch}-selection'); archive=f/f'go1.20.99.{platform_os}-{platform_arch}.tar.gz'; out=f/'out'; result=run(prepare_cmd(f,m,s,p,archive,out,platform_os,platform_arch)); provenance=json.loads((out/'third-party/mihomo/SOURCE-PREPARATION.json').read_text(encoding='utf-8')); source_meta=json.loads((out/'third-party/mihomo/source/SOURCE-BUILD.json').read_text(encoding='utf-8'))
    if 'third_party_source_state=ready' not in result or (provenance.get('host_os'),provenance.get('host_arch'),provenance.get('go_toolchain_archive'),provenance.get('go_toolchain_archive_sha256'))!=(platform_os,platform_arch,archive.name,sha(archive)) or any(k.startswith('go_toolchain_') or k in ('host_os','host_arch') for k in source_meta): raise SystemExit(f'platform toolchain selection mismatch: {platform_os}/{platform_arch}')

f,m,s,p,g=make_fixture('compliant'); outputs=[]
for platform_os,platform_arch in [('windows','amd64'),('linux','amd64'),('darwin','arm64')]:
    extension='zip' if platform_os=='windows' else 'tar.gz'; archive=f/f'go1.20.99.{platform_os}-{platform_arch}.{extension}'; candidate=f/f'out-{platform_os}-{platform_arch}'; result=run(prepare_cmd(f,m,s,p,archive,candidate,platform_os,platform_arch))
    if 'third_party_source_state=ready' not in result: raise SystemExit(f'source ready marker missing: {platform_os}/{platform_arch}')
    outputs.append(candidate)
source_hashes={sha(candidate/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz') for candidate in outputs}
if len(source_hashes)!=1: raise SystemExit(f'platform-dependent complete source hash: {sorted(source_hashes)}')
out=outputs[0]; contracts(f,out)
for candidate in outputs:
    if 'third_party_compliance_state=ready' not in run(verify_cmd(f,candidate)): raise SystemExit('PowerShell compliance ready marker missing')
    if shutil.which('sh') and 'third_party_compliance_state=ready' not in run(['sh',verify_sh,'--tree',candidate,'--lock',f/'lock.json','--sbom',f/'sbom.json','--notice',f/'notice.md']): raise SystemExit('POSIX compliance ready marker missing')
case=f/'notice-missing-toolchain'; shutil.copytree(out,case); notice=(f/'notice.md').read_text(encoding='utf-8'); first_tool=next(line for line in notice.splitlines() if line.startswith('- Pinned Go source-preparation archive ')); write(f/'notice-missing-toolchain.md',notice.replace(first_tool+'\n','',1)); cmd=verify_cmd(f,case); cmd[cmd.index('-Notice')+1]=f/'notice-missing-toolchain.md'; run(cmd,ok=False)
case=f/'sbom-missing-toolchain'; shutil.copytree(out,case); sbom=json.loads((f/'sbom.json').read_text()); package=next(x for x in sbom['packages'] if x['SPDXID']=='SPDXRef-Package-Mihomo'); package['externalRefs'].remove(next(x for x in package['externalRefs'] if x['referenceType']=='build-toolchain')); write(f/'sbom-missing-toolchain.json',json.dumps(sbom,indent=2)+'\n'); cmd=verify_cmd(f,case); cmd[cmd.index('-Sbom')+1]=f/'sbom-missing-toolchain.json'; run(cmd,ok=False)

second=f/'out-2'; run(prepare_cmd(f,m,s,p,g,second));
for rel in ('third-party/sources/mihomo-v1.19.28-complete-source.tar.gz','third-party/sources/shellcrash-1.9.4-complete-source.tar.gz'):
    if sha(out/rel)!=sha(second/rel): raise SystemExit(f'nondeterministic complete source: {rel}')
if shutil.which('sh'):
    posix=f/'out-posix'; run(['sh',public/'scripts/prepare-public-sources.sh','--output',posix,'--payload-dir',p,'--lock',f/'lock.json','--mihomo-url',m,'--shellcrash-url',s,'--go-archive',g,'--go-work-root',f/'go-work-posix','--fixture-mode','--fixture-os','windows','--fixture-arch','amd64'])
    for rel in ('third-party/sources/mihomo-v1.19.28-complete-source.tar.gz','third-party/sources/shellcrash-1.9.4-complete-source.tar.gz'):
        if sha(out/rel)!=sha(posix/rel): raise SystemExit(f'PowerShell/POSIX complete source parity mismatch: {rel}')

case=f/'absent-complete'; shutil.copytree(out,case); (case/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz').unlink(); run(verify_cmd(f,case),ok=False)
case=f/'wrong-payload'; shutil.copytree(out,case); write(case/'third-party/mihomo/mihomo-linux-arm64',b'changed\n',True); run(verify_cmd(f,case),ok=False)
case=f/'wrong-license'; shutil.copytree(out,case); write(case/'third-party/mihomo/LICENSE','changed\n'); run(verify_cmd(f,case),ok=False)
case=f/'shellcrash-mismatch'; shutil.copytree(out,case); write(case/'third-party/shellcrash/source/extra.txt','not archived\n'); run(verify_cmd(f,case),ok=False)
case=f/'shellcrash-runtime-source-mismatch'; shutil.copytree(out,case); write(case/'third-party/shellcrash/source/ShellCrash.tar.gz',b'not the runtime payload\n',True); meta=json.loads((case/'third-party/shellcrash/source/SOURCE-BUILD.json').read_text(encoding='utf-8')); normalize(case/'third-party/shellcrash/source',case/'third-party/sources/shellcrash-1.9.4-complete-source.tar.gz','shellcrash-1.9.4-source',meta['source_commit_epoch']); contracts(f,case); run(verify_cmd(f,case),ok=False)

case=f/'notice-missing-component-field'; shutil.copytree(out,case); notice=(f/'notice.md').read_text(encoding='utf-8'); write(f/'notice-missing.md',notice.replace(f"- Source: {json.loads((f/'lock.json').read_text())['components'][0]['source_repository']}\n",'',1)); cmd=verify_cmd(f,case); cmd[cmd.index('-Notice')+1]=f/'notice-missing.md'; run(cmd,ok=False)
case=f/'notice-cross-assigned-field'; shutil.copytree(out,case); lock_now=json.loads((f/'lock.json').read_text()); mc,sc=lock_now['components'][0]['source_commit'],lock_now['components'][1]['source_commit']; notice=(f/'notice.md').read_text(encoding='utf-8').replace(mc,'__MIHOMO_COMMIT__').replace(sc,mc).replace('__MIHOMO_COMMIT__',sc); write(f/'notice-cross.md',notice); cmd=verify_cmd(f,case); cmd[cmd.index('-Notice')+1]=f/'notice-cross.md'; run(cmd,ok=False)

case=f/'partial-vendor-loss'; shutil.copytree(out,case); dep=case/'third-party/mihomo/source/vendor/example.invalid/dep-a/dep.go'; dep.unlink()
meta=json.loads((case/'third-party/mihomo/source/SOURCE-BUILD.json').read_text(encoding='utf-8')); archive=case/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz'; normalize(case/'third-party/mihomo/source',archive,'mihomo-v1.19.28-source',meta['source_commit_epoch']); contracts(f,case); run(verify_cmd(f,case),ok=False)

case=f/'unsafe-source'; shutil.copytree(out,case); archive=case/'third-party/sources/mihomo-v1.19.28-complete-source.tar.gz'
with archive.open('wb') as raw:
  with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=1) as gz:
   with tarfile.open(fileobj=gz,mode='w') as tf:
    data=b'escape'; i=tarfile.TarInfo('../escape'); i.size=len(data); i.mtime=1; tf.addfile(i,io.BytesIO(data))
contracts(f,case); run(verify_cmd(f,case),ok=False)

case=f/'preparation-cross-assignment'; shutil.copytree(out,case); provenance_path=case/'third-party/mihomo/SOURCE-PREPARATION.json'; provenance=json.loads(provenance_path.read_text(encoding='utf-8')); provenance['host_os']='linux'; provenance['host_arch']='amd64'; write(provenance_path,json.dumps(provenance,indent=2)+'\n'); run(verify_cmd(f,case),ok=False)
case=f/'preparation-source-hash-tamper'; shutil.copytree(out,case); provenance_path=case/'third-party/mihomo/SOURCE-PREPARATION.json'; provenance=json.loads(provenance_path.read_text(encoding='utf-8')); provenance['complete_source_sha256']='0'*64; write(provenance_path,json.dumps(provenance,indent=2)+'\n'); run(verify_cmd(f,case),ok=False)
case=f/'preparation-missing'; shutil.copytree(out,case); (case/'third-party/mihomo/SOURCE-PREPARATION.json').unlink(); run(verify_cmd(f,case),ok=False)
print('third_party_compliance_fixture_tests=ok')
'@

try {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  $Driver = Join-Path $Root "fixture-driver.py"
  [System.IO.File]::WriteAllText($Driver, $Code, (New-Object System.Text.UTF8Encoding($false)))
  & $Python $Driver $Root $Repo $PowerShell
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  if ($env:HOME_EDGE_KEEP_THIRD_PARTY_FIXTURES) { Write-Host "third_party_fixture_root=$Root" }
  elseif (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
}
