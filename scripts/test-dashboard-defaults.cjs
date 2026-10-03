const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, 'dashboard-defaults.js'), 'utf8');
function execute(saved) {
  let value = saved === null ? null : JSON.stringify(saved);
  vm.runInNewContext(source, { localStorage: { getItem: () => value, setItem: (_, x) => { value = x; } } });
  return JSON.parse(value);
}
assert.deepEqual(execute(null), { proxySortBy: 'LatencyAsc', hideUnavailableProxies: true, autoCloseOldConns: false });
const explicit = { proxySortBy: 'Natural', hideUnavailableProxies: false, autoCloseOldConns: true, theme: 'dark', clashAPIConfigs: [{ secret: "<REDACTED>" }] };
assert.deepEqual(execute(explicit), explicit);
assert.deepEqual(execute({ hideUnavailableProxies: true }), { hideUnavailableProxies: true, proxySortBy: 'LatencyAsc', autoCloseOldConns: false });
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.events = {}; }
  appendChild(child) { child.parent = this; this.children.push(child); }
  setAttribute(name, value) { this[name] = value; }
  addEventListener(name, callback) { this.events[name] = callback; }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(x => x !== this); }
}
async function browser(saved, { status = 200, href = 'http://192.168.50.1:9999/ui/', fetchError = false } = {}) {
  let value = saved === null ? null : JSON.stringify(saved);
  const calls = [];
  const doc = { head: new Element('head'), body: new Element('body'), readyState: 'complete', createElement: tag => new Element(tag) };
  let reloads = 0;
  let reply = status;
  vm.runInNewContext(source, {
    URL, AbortController, setTimeout, clearTimeout, document: doc,
    window: { location: { href, reload: () => reloads++ }, navigator: { language: 'zh-CN' } },
    localStorage: { getItem: () => value, setItem: (_, next) => { value = next; } },
    fetch: async (url, init) => {
      calls.push({ url, init });
      if (fetchError) throw Error('offline');
      return { status: reply, ok: reply === 200, json: async () => ({ version: 'fixture' }) };
    },
  });
  const settle = () => new Promise(resolve => setImmediate(resolve));
  await settle();
  const nodes = root => [root, ...root.children.flatMap(nodes)];
  return {
    read: () => JSON.parse(value), calls, doc, nodes: () => nodes(doc.body),
    reloads: () => reloads, setStatus: next => { reply = next; }, settle,
  };
}
(async () => {
  const fresh = await browser(null, { status: 401 });
  assert.equal(fresh.read().clashAPIConfigs[0].baseURL, 'http://192.168.50.1:9999');
  assert.equal(fresh.read().selectedClashAPIConfigIndex, 0);
  assert.equal(fresh.nodes().filter(x => x.tag === 'input').length, 1);
  assert.equal(fresh.nodes().find(x => x.tag === 'input').type, 'password');
  assert.equal(fresh.nodes().some(x => x.textContent === 'Add'), false);
  assert.equal(fresh.calls[0].url, 'http://192.168.50.1:9999/version');
  assert.equal(fresh.calls[0].init.method, 'GET');
  assert.equal(fresh.calls[0].init.redirect, 'error');
  assert.equal(fresh.calls[0].init.headers.Authorization, undefined);

  const saved = { ...explicit, selectedClashAPIConfigIndex: 0, clashAPIConfigs: [
    { baseURL: 'http://192.168.50.1:9999', secret: '' },
    { baseURL: 'http://192.168.50.1:9999/', secret: 'fixture-key', addedAt: 1 },
    { baseURL: 'http://192.168.9.1:9999', secret: "<REDACTED>" },
  ] };
  const remembered = await browser(saved);
  assert.equal(remembered.read().selectedClashAPIConfigIndex, 1);
  assert.deepEqual(remembered.read().clashAPIConfigs, saved.clashAPIConfigs);
  assert.equal(remembered.read().proxySortBy, 'Natural');
  assert.equal(remembered.read().autoCloseOldConns, true);
  assert.equal(remembered.doc.body.children.length, 0);
  assert.equal(remembered.doc.head.children.length, 0);
  assert.equal(remembered.calls[0].init.headers.Authorization, 'Bearer fixture-key');
  assert.equal(remembered.calls.length, 1);
  assert.equal(remembered.reloads(), 0);
  const reopened = await browser(remembered.read());
  assert.equal(reopened.doc.body.children.length, 0);
  assert.equal(reopened.read().selectedClashAPIConfigIndex, 1);

  fresh.nodes().find(x => x.tag === 'input').value = 'new-fixture-key';
  fresh.setStatus(200);
  fresh.nodes().find(x => x.tag === 'form').events.submit({ preventDefault() {} });
  await fresh.settle();
  assert.equal(fresh.read().clashAPIConfigs[0].secret, 'new-fixture-key');
  assert.equal(fresh.reloads(), 1);
  assert.equal(fresh.calls[1].url.includes('new-fixture-key'), false);

  const wrong = await browser(saved, { status: 401 });
  wrong.nodes().find(x => x.tag === 'input').value = 'incorrect-key';
  wrong.nodes().find(x => x.tag === 'form').events.submit({ preventDefault() {} });
  await wrong.settle();
  assert.deepEqual(wrong.read().clashAPIConfigs, saved.clashAPIConfigs);
  assert.equal(wrong.reloads(), 0);
  assert(wrong.nodes().some(x => x.textContent === '访问密钥不正确，请重新输入。'));
  const unavailable = await browser(saved, { fetchError: true });
  assert.deepEqual(unavailable.read().clashAPIConfigs, saved.clashAPIConfigs);
  assert.equal(unavailable.nodes().filter(x => x.tag === 'input').length, 0);
  assert(unavailable.nodes().some(x => x.textContent === '重试连接'));

  const interrupted = await browser(null, { status: 401 });
  interrupted.nodes().find(x => x.tag === 'input').value = 'retry-fixture-key';
  interrupted.setStatus(503);
  interrupted.nodes().find(x => x.tag === 'form').events.submit({ preventDefault() {} });
  await interrupted.settle();
  assert.equal(interrupted.read().clashAPIConfigs[0].secret, '');
  interrupted.setStatus(200);
  interrupted.nodes().find(x => x.textContent === '重试连接').events.click();
  await interrupted.settle();
  assert.equal(interrupted.read().clashAPIConfigs[0].secret, 'retry-fixture-key');
  assert.equal(interrupted.reloads(), 1);

  const explicitLink = await browser(saved, { href: 'http://192.168.50.1:9999/ui/?hostname=other' });
  assert.deepEqual(explicitLink.read(), saved);
  assert.equal(explicitLink.calls.length, 0);
  const unrelated = await browser(saved, { href: 'http://192.168.50.1:9999/other/' });
  assert.deepEqual(unrelated.read(), saved);
  assert.equal(unrelated.calls.length, 0);
  const path = require('node:path');
  const parent = fs.realpathSync(require('node:os').tmpdir());
  const fixture = fs.mkdtempSync(path.join(parent, 'home-edge-dashboard-'));
  assert.equal(path.dirname(fixture), parent);
  const sourceFile = path.join(__dirname, 'dashboard-defaults.js');
  try {
    fs.mkdirSync(path.join(fixture, 'assets'));
    fs.writeFileSync(path.join(fixture, 'assets', 'index-fixture.js'), 'yacd.metacubex.one');
    const html = path.join(fixture, 'index.html');
    fs.writeFileSync(html, '<html><head></head><body><div id="app"></div></body></html>');
    const install = (...args) => require('node:child_process').spawnSync('sh',
      [path.join(__dirname, 'configure-dashboard-defaults.sh'), ...args], {
        env: { ...process.env, HOME_EDGE_DASHBOARD_DIR: fixture,
          HOME_EDGE_DASHBOARD_DEFAULTS_SOURCE: sourceFile }, encoding: 'utf8',
      });
    assert.equal(install().status, 0);
    assert.match(fs.readFileSync(html, 'utf8'), /home-edge-defaults\.js\?v=2/);
    assert.equal(install().status, 0);
    assert.equal(fs.readFileSync(html, 'utf8').split('<!-- home-edge-dashboard-defaults -->').length, 2);
    fs.writeFileSync(html, fs.readFileSync(html, 'utf8').replace('?v=2', '?v=1'));
    assert.equal(install().status, 0);
    assert.match(fs.readFileSync(html, 'utf8'), /home-edge-defaults\.js\?v=2/);
    assert.equal(install('--remove').status, 0);
    assert.equal(fs.existsSync(path.join(fixture, 'home-edge-defaults.js')), false);
    assert.equal(fs.readFileSync(html, 'utf8').includes('home-edge-dashboard-defaults'), false);
  } finally {
    assert.equal(path.dirname(fixture), parent);
    fs.rmSync(fixture, { recursive: true, force: true });
  }
  console.log('dashboard_defaults_tests=ok; local_entry_saved_connection_reopen=ok; credential_and_network_guards=ok');
})().catch(error => { console.error(error); process.exitCode = 1; });
