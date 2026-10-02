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
console.log('dashboard_defaults_tests=ok');
