"""Offline integration tests: real shell/merger/parser, controlled external adapters."""
import argparse
import gzip
import hashlib
import json
import os
import pathlib
import shutil
import signal
import subprocess
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[1]

CURL = r'''#!/usr/bin/env python3
import os,sys,json,pathlib,subprocess,tempfile,hashlib
a=sys.argv[1:]; root=pathlib.Path(os.environ['F_ROOT'])
url=next((x for x in reversed(a) if x.startswith('http')), '')
def value(flag):
 return a[a.index(flag)+1] if flag in a else None
def output(obj):
 text=json.dumps(obj)
 out=value('-o')
 if out: pathlib.Path(out).write_text(text)
 else: print(text)
with (root/'calls').open('a') as f:f.write(('PUT' if value('-X')=='PUT' else 'GET')+' '+('/subscription' if url.startswith('https://source.invalid') else url.split('?')[0])+'\n')
if url.startswith('https://source.invalid'):
 if os.environ.get('F_FETCH_DIRECT_TIMEOUT')=='1' and '--proxy' not in a:sys.exit(28)
 if os.environ.get('F_FETCH_FAIL')=='1':sys.exit(22)
 shutil=__import__('shutil');shutil.copyfile(root/'fresh.json',value('-o'))
 if value('-D'):pathlib.Path(value('-D')).write_text('HTTP/1.1 200 OK\r\nprofile-update-interval: '+os.environ.get('F_HINT_HOURS','24')+'\r\n')
 sys.exit(0)
if url.startswith('https://example.com'):sys.exit(0)
canary=':19999' in url
if canary and not (root/'canary-ready').exists():sys.exit(7)
if url.endswith('/version'):output({'version':'v1.19.31'});sys.exit(0)
if url.endswith('/configs') and value('-X')=='PUT':
 with (root/'reloads').open('a') as f:f.write('PUT_CONFIGS\n')
 if os.environ.get('F_RELOAD_FAIL')=='1' and not (root/'failed-once').exists():(root/'failed-once').touch();sys.exit(22)
 if os.environ.get('F_SWITCH_AFTER_RELOAD')=='1':
  state=json.loads((root/'api-state.json').read_text());state['choices']['Manual']=os.environ.get('F_SWITCH_NODE','A');(root/'api-state.json').write_text(json.dumps(state))
 if '-w' in a:sys.stdout.write('204')
 sys.exit(0)
if '/delay?' in url:
 if os.environ.get('F_CORE_EXIT')=='1' and not (root/'core-exited').exists():
  __import__('signal');os.kill(int(os.environ['SUBSCRIPTION_CORE_PID']),15);(root/'core-exited').touch()
 if os.environ.get('F_MANUAL_SWITCH')=='1' and not (root/'switched').exists():
  state=json.loads((root/'api-state.json').read_text());state['choices']['Manual']='A';(root/'api-state.json').write_text(json.dumps(state));(root/'switched').touch()
 if os.environ.get('F_CANARY_FAIL')=='1':sys.exit(22)
 output({'delay':123});sys.exit(0)
if '/proxies' in url:
 raw=(root/'live.yaml').read_bytes(); digest=hashlib.sha256(raw).hexdigest()
 fd,out=tempfile.mkstemp(dir=root);os.close(fd);os.unlink(out)
 subprocess.run([os.environ['F_PARSER'],'decode',str(root/'live.yaml'),out],check=True,stdout=subprocess.DEVNULL)
 doc=json.loads(pathlib.Path(out).read_text());os.unlink(out)
 saved=root/'api-state.json'
 state=json.loads(saved.read_text()) if saved.exists() else {'digest':digest,'choices':{}}
 # store-selected retains valid choices across native reloads.
 if state['digest']!=digest:state['digest']=digest
 if value('-X')=='PUT':
  from urllib.parse import unquote
  group=unquote(url.rsplit('/',1)[1]);state['choices'][group]=json.loads(sys.stdin.read())['name'];saved.write_text(json.dumps(state));sys.exit(0)
 p={n['name']:{'name':n['name'],'type':n['type'].capitalize(),'alive':os.environ.get('F_HEALTH_BAD')!='1'} for n in doc['proxies']}
 for g in doc['proxy-groups']:
  p[g['name']]={'name':g['name'],'type':'Selector' if g['type']=='select' else 'URLTest','all':g['proxies'],'now':state['choices'].get(g['name'],g['proxies'][0])}
 saved.write_text(json.dumps(state));output({'proxies':p});sys.exit(0)
sys.exit(2)
'''
CORE = r'''#!/usr/bin/env python3
import os,sys,pathlib,time,signal,json,subprocess,tempfile
r=pathlib.Path(os.environ['F_ROOT'])
if '-t' in sys.argv:sys.exit(1 if os.environ.get('F_CONFIG_FAIL')=='1' else 0)
if 'main' in sys.argv:
 def hup(*_):
  with (r/'reloads').open('a') as f:f.write('HUP\n')
 signal.signal(signal.SIGHUP,hup)
else:
 fd,out=tempfile.mkstemp(dir=r);os.close(fd);os.unlink(out)
 subprocess.run([os.environ['F_PARSER'],'decode',sys.argv[sys.argv.index('-f')+1],out],check=True)
 doc=json.loads(pathlib.Path(out).read_text());os.unlink(out)
 assert doc['external-controller']=='127.0.0.1:19999'
 (r/'canary-ready').touch()
 signal.signal(signal.SIGTERM,lambda *_:sys.exit(0))
try:
 while True:time.sleep(.1)
finally:
 if 'main' not in sys.argv:(r/'canary-ready').unlink(missing_ok=True)
'''

class Fixture:
    def __init__(self, parser, jq):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix='home-edge-auto-test.', dir='/tmp'))
        r = self.root
        (r/'runtime').mkdir()
        (r/'cache').mkdir()
        binary = pathlib.Path(parser).read_bytes()
        (r/'runtime/yamlbridge.gz').write_bytes(gzip.compress(binary))
        (r/'runtime/yamlbridge.sha256').write_text(hashlib.sha256(binary).hexdigest())
        (r/'SUBSCRIPTION.local').write_text('https://source.invalid/provider-fixture\n')
        (r/'CONTROLLER_SECRET.local').write_text('fixtureSecret')
        (r/'filters.json').write_text(json.dumps({'JP':'A'}))
        (r/'policy.env').write_text(':\n')
        nodes=[{'name':'A','type':'http','server':'old.invalid','port':443},{'name':'B','type':'http','server':'old2.invalid','port':443}]
        groups=[{'name':'Main','type':'select','proxies':['Auto','Manual','DIRECT']},{'name':'Manual','type':'select','proxies':['A','B']},{'name':'Auto','type':'url-test','proxies':['A','B']},{'name':'JP','type':'url-test','proxies':['A']}]
        self.before={'proxies':nodes,'proxy-groups':groups,'rules':['DOMAIN,fixture.invalid,Main','MATCH,DIRECT'],'dns':{'enable':True},'secret':'fixtureSecret','mixed-port':7890,'external-controller':':9999'}
        self.fresh={'proxies':[dict(nodes[0],server='new.invalid'),nodes[1],{'name':'C','type':'anytls','server':'new3.invalid','password':'fixture-private'}],'proxy-groups':[{'name':'Untrusted','type':'select','proxies':['C']}],'rules':['MATCH,Untrusted'],'secret':'do-not-adopt'}
        for n in ['source.yaml','live.yaml']:(r/n).write_text(json.dumps(self.before))
        (r/'fresh.json').write_text(json.dumps(self.fresh))
        for name,source in [('curl',CURL),('core',CORE),('verify',"#!/bin/sh\n[ \"${F_ROUTE_FAIL:-0}\" != 1 ] || exit 1\n[ \"${F_ROUTE_BLOCK:-0}\" != 1 ] || sleep \"${F_ROUTE_SLEEP:-5}\"\necho verification_state=pass\n"),('cru',"#!/bin/sh\ncase \"$1\" in a) echo \"$3 #$2#\" >\"$F_ROOT/cron\";; l) cat \"$F_ROOT/cron\" 2>/dev/null || true;; d) rm -f \"$F_ROOT/cron\";; esac\n"),('cp',"#!/bin/sh\nfor last do :; done\ncase \"$last\" in */transactions/tx-*) [ \"${F_TX_BACKUP_FAIL:-0}\" != 1 ] || exit 1;; esac\nexec /bin/cp \"$@\"\n")]:
            (r/name).write_text(source);(r/name).chmod(0o700)
        self.env=dict(os.environ,HOME_EDGE_STATE_ROOT=str(r),SUBSCRIPTION_POLICY_FILE=str(r/'policy.env'),SUBSCRIPTION_AUTO_ENABLED='1',SUBSCRIPTION_API='http://127.0.0.1:9999',SUBSCRIPTION_SOURCE_PROFILE=str(r/'source.yaml'),SUBSCRIPTION_LIVE_PROFILE=str(r/'live.yaml'),SUBSCRIPTION_GROUP_FILTERS_FILE=str(r/'filters.json'),SUBSCRIPTION_PARSER_BIN=str(r/'cache/parser'),HOME_EDGE_WRITE_LOCK_DIR=str(r/'write.lock'),CURL_BIN=str(r/'curl'),JQ_BIN=str(jq),SUBSCRIPTION_SELF_HEAL_SCRIPT=str(r/'verify'),HOME_EDGE_SHELLCRASH_DIR=str(r/'shellcrash'),SUBSCRIPTION_CORE_BIN=str(r/'core'),SUBSCRIPTION_TEST_NOW='2000000000',F_ROOT=str(r),F_PARSER=str(parser))
        self.env['PATH']=str(r)+os.pathsep+os.environ['PATH']
        (r/'shellcrash/configs').mkdir(parents=True)
        self.main=subprocess.Popen([str(r/'core'),'main'],env=self.env,start_new_session=True)
        self.env['SUBSCRIPTION_CORE_PID']=str(self.main.pid)
        time.sleep(.15)
        self.seed_choices()
    def seed_choices(self):
        p=self.root/'api-state.json'
        p.write_text(json.dumps({'digest':hashlib.sha256((self.root/'live.yaml').read_bytes()).hexdigest(),'choices':{'Main':'Manual','Manual':'B'}}))
    def run(self, mode='--refresh', **extra):
        env=dict(self.env,**extra)
        return subprocess.run(['sh',str(REPO/'scripts/subscription-auto.sh'),mode],env=env,capture_output=True,text=True,timeout=60)
    def status(self):return json.loads((self.root/'subscription-auto/status.json').read_text())
    def assert_clean(self):
        assert not (self.root/'write.lock').exists()
        assert not list((self.root/'cache').glob('.subscription-auto.*'))
        if (self.root/'canary-ready').exists():raise AssertionError('canary allocation survived')
    def close(self):
        if self.main.poll() is None:os.killpg(self.main.pid,signal.SIGTERM)
        self.main.wait(timeout=5)
        shutil.rmtree(self.root)

def main():
    p=argparse.ArgumentParser();p.add_argument('--parser',required=True);p.add_argument('--jq',default='jq');args=p.parse_args()
    f=Fixture(args.parser,args.jq)
    try:
        build=f.root/'build';build.mkdir()
        shutil.copyfile(args.parser,build/'yamlbridge-linux-arm64')
        (build/'yamlbridge-linux-arm64.gz').write_bytes(gzip.compress(pathlib.Path(args.parser).read_bytes()))
        # Run only stage allocation and failure cleanup through a local fake SSH.
        (f.root/'ssh').write_text('#!/bin/sh\nfor last do :; done\ncase "$last" in *home-edge-subscription-enable.*) sh -c "$last";; *) exit 2;; esac\n')
        (f.root/'scp').write_text('#!/bin/sh\nexit 1\n')
        for name in ['ssh','scp']:(f.root/name).chmod(0o700)
        env=dict(f.env,APPLY='1',SUBSCRIPTION_PARSER_BUILD_DIR=str(build))
        before=set(pathlib.Path('/tmp').glob('home-edge-subscription-enable.*'))
        for _ in range(2):
            out=subprocess.run(['sh',str(REPO/'scripts/enable-subscription-auto.sh'),'fixture@invalid',str(f.root/'filters.json')],env=env,capture_output=True,text=True)
            assert out.returncode!=0
            assert set(pathlib.Path('/tmp').glob('home-edge-subscription-enable.*'))==before
        print('subscription_auto_case=activation_failure_retry_cleanup:pass',flush=True)
    finally:f.close()
    f=Fixture(args.parser,args.jq)
    try:
        out=f.run(F_SWITCH_AFTER_RELOAD='1',F_SWITCH_NODE='C',F_ROUTE_FAIL='1')
        assert out.returncode!=0 and 'rollback_selection_conflict' in out.stderr
        assert list((f.root/'subscription-auto/transactions').glob('tx-*/selection-conflict'))
        candidate=(f.root/'source.yaml').read_bytes()
        boot=f.run('--boot');assert boot.returncode!=0 and 'rollback_selection_conflict' in boot.stderr
        assert (f.root/'source.yaml').read_bytes()==candidate
        assert json.loads((f.root/'api-state.json').read_text())['choices']['Manual']=='C'
        f.assert_clean()
        print('subscription_auto_case=rollback_new_choice_conflict_gates_boot:pass',flush=True)
    finally:f.close()
    f=Fixture(args.parser,args.jq)
    try:
        tx=f.root/'subscription-auto/transactions/tx-1-1';tx.mkdir(parents=True)
        old=hashlib.sha256((f.root/'source.yaml').read_bytes()).hexdigest()
        (tx/'journal.json').write_text(json.dumps({'old_source':old,'new_source':old,'boot_id':'previous-boot'}))
        shutil.copyfile(f.root/'source.yaml',tx/'source-before.yaml')
        (tx/'recovery.lock').mkdir()  # Persistent mutex left by an old implementation/crash.
        out=f.run('--boot');assert out.returncode==0,(out.stdout,out.stderr)
        assert (tx/'rolled-back').exists()
        f.assert_clean()
        (f.root/'write.lock').mkdir();(f.root/'write.lock/pid').write_text(str(os.getpid()))
        out=f.run('--boot');assert out.returncode!=0 and 'busy' in out.stderr
        shutil.rmtree(f.root/'write.lock')
        print('subscription_auto_case=boot_orphan_and_busy:pass',flush=True)
    finally:f.close()
    f=Fixture(args.parser,args.jq)
    try:
        env=dict(f.env,F_ROUTE_BLOCK='1',F_ROUTE_SLEEP='10',SUBSCRIPTION_TEST_GUARD_SECONDS='2')
        parent=subprocess.Popen(['sh',str(REPO/'scripts/subscription-auto.sh'),'--refresh'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        deadline=time.monotonic()+40
        while time.monotonic()<deadline:
            if list((f.root/'subscription-auto/transactions').glob('tx-*/rolled-back')) and not (f.root/'write.lock').exists():break
            time.sleep(.05)
        else:raise AssertionError('guard did not release owned lock')
        (f.root/'write.lock').mkdir();(f.root/'write.lock/pid').write_text(str(os.getpid()));(f.root/'write.lock/operation').write_text('successor-writer')
        stdout,stderr=parent.communicate(timeout=20)
        assert parent.returncode!=0,(stdout,stderr)
        assert (f.root/'write.lock/operation').read_text()=='successor-writer'
        shutil.rmtree(f.root/'write.lock');f.assert_clean()
        print('subscription_auto_case=successor_lock_preserved:pass',flush=True)
    finally:f.close()
    scenarios=['updated','unchanged','removed_pin','invalid_subscription','reload_validation','canary_failure','route_rollback','cooldown','demand_trigger','periodic_trigger','fetch_failure','guard_timeout','reload_failure','insecure_downgrade','manual_switch_during_update','manual_switch_after_reload','manual_switch_before_rollback','local_proxy_fetch_fallback','candidate_check_no_publish','live_controller_binding','backup_failure_cleanup','core_exit_during_staging']
    for scenario in scenarios:
        f=Fixture(args.parser,args.jq)
        try:
            if scenario=='unchanged':(f.root/'fresh.json').write_text(json.dumps(f.before))
            if scenario=='removed_pin':f.fresh['proxies']=[f.fresh['proxies'][0],f.fresh['proxies'][2]];(f.root/'fresh.json').write_text(json.dumps(f.fresh))
            if scenario=='invalid_subscription':(f.root/'fresh.json').write_text('<html>private-fixture</html>')
            if scenario=='insecure_downgrade':f.fresh['proxies'][0]['skip-cert-verify']=True;(f.root/'fresh.json').write_text(json.dumps(f.fresh))
            extra={'reload_validation':{'F_CONFIG_FAIL':'1'},'canary_failure':{'F_CANARY_FAIL':'1'},'route_rollback':{'F_ROUTE_FAIL':'1'},'fetch_failure':{'F_FETCH_FAIL':'1'},'guard_timeout':{'F_ROUTE_BLOCK':'1','SUBSCRIPTION_TEST_GUARD_SECONDS':'3'},'reload_failure':{'F_RELOAD_FAIL':'1'},'manual_switch_during_update':{'F_MANUAL_SWITCH':'1'},'manual_switch_after_reload':{'F_SWITCH_AFTER_RELOAD':'1'},'manual_switch_before_rollback':{'F_SWITCH_AFTER_RELOAD':'1','F_ROUTE_FAIL':'1'}}.get(scenario,{})
            if scenario=='local_proxy_fetch_fallback':extra={'F_FETCH_DIRECT_TIMEOUT':'1'}
            if scenario=='live_controller_binding':extra={'SUBSCRIPTION_API':''}
            if scenario=='backup_failure_cleanup':extra={'F_TX_BACKUP_FAIL':'1'}
            if scenario=='core_exit_during_staging':extra={'F_CORE_EXIT':'1'}
            out=f.run('--check' if scenario=='candidate_check_no_publish' else '--refresh',**extra)
            if scenario=='candidate_check_no_publish':
                assert out.returncode==0 and 'candidate_verified' in out.stdout,(out.stdout,out.stderr)
                assert not (f.root/'reloads').exists() and not (f.root/'subscription-auto/status.json').exists()
                assert (f.root/'live.yaml').read_text()==json.dumps(f.before)
            elif scenario in ('updated','cooldown','demand_trigger','periodic_trigger','manual_switch_after_reload','local_proxy_fetch_fallback','live_controller_binding'):
                assert out.returncode==0,(scenario,out.stdout,out.stderr)
                doc=json.loads(subprocess.check_output([args.jq,'.',str(f.root/'subscription-auto/status.json')]))
                assert doc['last_result']=='updated'
                tmp=f.root/'parsed.json';subprocess.run([args.parser,'decode',str(f.root/'live.yaml'),str(tmp)],check=True)
                actual=json.loads(tmp.read_text());assert actual['rules']==f.before['rules'] and actual['secret']=='fixtureSecret'
                assert actual['proxy-groups'][0]==f.before['proxy-groups'][0]
                assert json.loads((f.root/'api-state.json').read_text())['choices']=={'Main':'Manual','Manual':'A' if scenario=='manual_switch_after_reload' else 'B'}
                if scenario=='cooldown':
                    again=f.run('--tick',F_HEALTH_BAD='1');assert again.returncode==0 and 'cooldown' in again.stdout
                if scenario=='demand_trigger':
                    # A sustained health collapse before the daily deadline may refresh.
                    st=f.status();st['last_attempt']=1999990000;st['last_success']=1999990000;(f.root/'subscription-auto/status.json').write_text(json.dumps(st))
                    for _ in range(2):assert 'not_due' in f.run('--tick',F_HEALTH_BAD='1').stdout
                    assert 'unchanged' in f.run('--tick',F_HEALTH_BAD='1').stdout
                if scenario=='periodic_trigger':
                    st=f.status();st['last_success']=1999900000;st['last_attempt']=1999900000;(f.root/'subscription-auto/status.json').write_text(json.dumps(st))
                    assert 'unchanged' in f.run('--tick').stdout
            elif scenario=='unchanged':
                assert out.returncode==0 and 'unchanged' in out.stdout
                assert not (f.root/'reloads').exists()
                assert (f.root/'live.yaml').read_text()==json.dumps(f.before)
            else:
                assert out.returncode!=0,(scenario,out.stdout,out.stderr)
                assert (f.root/'live.yaml').read_text()==json.dumps(f.before)
                assert (f.root/'source.yaml').read_text()==json.dumps(f.before)
                assert f.status()['failures']==1
                if scenario in ('manual_switch_during_update','manual_switch_before_rollback'):assert json.loads((f.root/'api-state.json').read_text())['choices']['Manual']=='A'
                if scenario in ('route_rollback','guard_timeout','reload_failure','manual_switch_before_rollback'):
                    if scenario!='guard_timeout':assert 'rolled_back' in out.stdout
                    else:assert list((f.root/'subscription-auto/transactions').glob('tx-*/rolled-back'))
                    assert len((f.root/'reloads').read_text().splitlines())==2
                again=f.run('--tick');assert again.returncode==0 and 'backoff' in again.stdout
            f.assert_clean()
            if scenario=='backup_failure_cleanup':assert not list((f.root/'subscription-auto/transactions').glob('tx-*'))
            assert 'DELETE' not in (f.root/'calls').read_text()
            print('subscription_auto_case='+scenario+':pass',flush=True)
        finally:f.close()
    print('subscription_auto_tests=ok')
if __name__=='__main__':main()
