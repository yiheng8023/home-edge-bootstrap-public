#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
python_bin=
for candidate in python3 python; do if which "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; assert sys.version_info.major == 3' >/dev/null 2>&1; then python_bin=$candidate; break; fi; done
[ -n "$python_bin" ] || { echo 'service_health_enable_fixtures=missing_python'; exit 1; }
F_PYTHON="$python_bin" "$python_bin" - "$repo" <<'PY'
import gzip,hashlib,os,pathlib,shutil,subprocess,sys,tempfile
repo=pathlib.Path(sys.argv[1]);entry=repo/'scripts/enable-service-health.sh'
binary=b'#!/bin/sh\n[ "$1" = --help ] && { echo "yamlbridge service-health REQUEST NEW_REPORT"; exit 0; }; exit 2\n'
def put(path,text,mode=0o700):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text);path.chmod(mode)
with tempfile.TemporaryDirectory(prefix='home-edge-enable-fixture.') as temp:
 root=pathlib.Path(temp);fake=root/'bin';fake.mkdir();remote=root/'remote';remote.mkdir();(remote/'tmp').mkdir()
 calls=root/'calls'; payloads=root/'payloads'
 transport='''#!/usr/bin/env python3
import os,pathlib,sys,subprocess,shutil,re
r=pathlib.Path(os.environ['F_REMOTE']);a=sys.argv[1:];name=pathlib.Path(sys.argv[0]).name
with open(os.environ['F_CALLS'],'a') as f:f.write(name+' '+('arch' if 'uname -m' in a[-1] else 'call')+'\\n')
def translate(s):return re.sub(r'/(jffs|tmp|proc)',lambda m:str(r/m.group(1)),s)
if name=='scp':
 src=a[-2];dst=a[-1].split(':',1)[1];shutil.copyfile(src,translate(dst));sys.exit(0)
command=a[-1]
if 'uname -m' in command:
 if os.environ.get('F_NO_HELPERS')=='1':sys.exit(1)
 print(os.environ.get('F_ARCH','aarch64'));sys.exit(0)
body=sys.stdin.read() if command.startswith('tr -d') else command
with open(os.environ['F_PAYLOADS'],'a') as f:f.write(body+'\\n')
result=subprocess.run(['sh','-s'],input=translate(body).encode(),env=os.environ)
sys.exit(result.returncode)
'''
 transport=transport.replace('/usr/bin/env python3','/usr/bin/env '+os.environ['F_PYTHON'])
 for name in ['ssh','scp']:put(fake/name,transport)
 put(fake/'pidof','#!/bin/sh\necho 123\n')
 put(fake/'go',('''#!/usr/bin/env python3
import os,sys,pathlib
with open(os.environ['F_CALLS'],'a') as f:f.write('go '+' '.join(sys.argv[1:])+'\\n')
if os.environ.get('F_GO_FAIL')=='1':sys.exit(1)
if sys.argv[1]=='build':pathlib.Path(sys.argv[sys.argv.index('-o')+1]).write_bytes(bytes.fromhex(os.environ['F_BINARY_HEX']))
''').replace('/usr/bin/env python3','/usr/bin/env '+os.environ['F_PYTHON']))
 scripts=remote/'jffs/scripts';scripts.mkdir(parents=True)
 for name in ['home-edge-service-health.sh','home-edge-service-health-preflight.sh']:put(scripts/name,'#!/bin/sh\nexit 0\n')
 put(scripts/'home-edge-configure-service-health.sh','''#!/bin/sh
printf '%s:%s:%s:%s\\n' "$1" "${SERVICE_HEALTH_PROFILES:-}" "${SERVICE_HEALTH_GOOGLE_MODE:-}" "${SERVICE_HEALTH_MODE:-}" >>"$F_SETUP"
[ "$1" != --apply ] || [ "${F_SETUP_FAIL:-0}" != 1 ]
''')
 (remote/'tmp/ShellCrash').mkdir();(remote/'tmp/ShellCrash/shellcrash.pid').write_text('123\n');put(remote/'tmp/ShellCrash/CrashCore','#!/bin/sh\nexit 0\n')
 proc=remote/'proc/123';proc.mkdir(parents=True);(proc/'exe').symlink_to(remote/'tmp/ShellCrash/CrashCore');(proc/'stat').write_text(' '.join(['123','(CrashCore)']+['1']*19+['999'])+'\n')
 runtime=remote/'jffs/home-edge-bootstrap-state/runtime';runtime.mkdir(parents=True)
 old=b'old parser fixture';(runtime/'yamlbridge.gz').write_bytes(gzip.compress(old));(runtime/'yamlbridge.sha256').write_text(hashlib.sha256(old).hexdigest()+'\n')
 original={p.name:p.read_bytes() for p in runtime.iterdir()}
 prebuilt=root/'prebuilt';prebuilt.write_bytes(binary);prebuilt.chmod(0o700)
 env=dict(os.environ,PATH=str(fake)+os.pathsep+os.environ['PATH'],F_REMOTE=str(remote),F_CALLS=str(calls),F_PAYLOADS=str(payloads),F_SETUP=str(root/'setup'),F_BINARY_HEX=binary.hex())
 def run(extra=None,ok=True,router='user@router'):
  e=dict(env);e.update(extra or {});p=subprocess.run(['sh',str(entry),router],env=e,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  assert (p.returncode==0)==ok,(p.returncode,p.stdout,p.stderr)
  assert not (remote/'tmp/home-edge-bootstrap-write.lock').exists(),'lock leaked'
  stages=list((remote/'tmp').glob('home-edge-service-enable.*'))
  if p.returncode==0:assert not stages,'stage leaked'
  else:
   # Failed remote invocations retain their private stage because a broken SSH
   # channel cannot prove the remote worker has stopped; fixture owns its tree.
   for stage in stages:shutil.rmtree(stage)
  return p
 run()
 assert {p.name:p.read_bytes() for p in runtime.iterdir()}==original,'PLAN mutated protected tools'
 assert (root/'setup').read_text().strip()=='--plan:gemini:auto:auto'
 assert 'go mod verify' in calls.read_text() and 'go test ./...' in calls.read_text() and 'go build ' in calls.read_text()
 run({'APPLY':'1'})
 assert gzip.decompress((runtime/'yamlbridge.gz').read_bytes())==binary
 prev=runtime/'service-health-tools-prev';assert (prev/'yamlbridge.gz').read_bytes()==original['yamlbridge.gz']
 assert (root/'setup').read_text().splitlines()[-2:]==['--plan:gemini:auto:auto','--apply:gemini:auto:auto']
 saved=(prev/'yamlbridge.gz').read_bytes();run({'APPLY':'1'});assert (prev/'yamlbridge.gz').read_bytes()==saved,'same helper destroyed recovery generation'
 run({'SERVICE_HEALTH_PREBUILT':str(prebuilt),'SERVICE_HEALTH_PREBUILT_SHA256':hashlib.sha256(binary).hexdigest()})
 run({'SERVICE_HEALTH_PREBUILT':str(prebuilt),'SERVICE_HEALTH_PREBUILT_SHA256':'0'*64},False)
 before=calls.read_text();run({'F_GO_FAIL':'1'},False);assert calls.read_text().count('scp ')==before.count('scp '),'failed build transferred helper'
 run({'F_NO_HELPERS':'1'},False)
 run({'F_ARCH':'mips'},False)
 run(router='user@router;bad',ok=False)
 (runtime/'yamlbridge.sha256').write_text('0'*64+'\n');run({'APPLY':'1'},False);assert (runtime/'yamlbridge.sha256').read_text()=='0'*64+'\n','hash drift overwritten'
 (runtime/'yamlbridge.sha256').write_text(hashlib.sha256(binary).hexdigest()+'\n')
 run({'APPLY':'1','F_SETUP_FAIL':'1'},False);assert gzip.decompress((runtime/'yamlbridge.gz').read_bytes())==binary,'compatible tools lost after setup boundary'
 unchanged_setup=(root/'setup').read_bytes()
 run({'TOOLS_ONLY':'1','F_SETUP_FAIL':'1'})
 run({'TOOLS_ONLY':'1','APPLY':'1','F_SETUP_FAIL':'1'})
 assert (root/'setup').read_bytes()==unchanged_setup,'tools-only update touched service routing'
 assert 'enable-subscription-auto' not in payloads.read_text()
 print('service_health_enable_fixture_tests=passed')
PY
