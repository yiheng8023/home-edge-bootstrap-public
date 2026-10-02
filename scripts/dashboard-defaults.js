/* Site defaults for Yacd-meta. Explicit browser choices always win. */
(() => {
  try {
    const key = 'yacd.metacubex.one';
    const raw = localStorage.getItem(key);
    const config = raw === null ? {} : JSON.parse(raw);
    if (!config || typeof config !== 'object' || Array.isArray(config)) return;
    let changed = false;
    for (const [name, value] of Object.entries({
      proxySortBy: 'LatencyAsc',
      hideUnavailableProxies: true,
      autoCloseOldConns: false,
    })) {
      if (!Object.prototype.hasOwnProperty.call(config, name)) {
        config[name] = value;
        changed = true;
      }
    }
    if (changed) localStorage.setItem(key, JSON.stringify(config));
  } catch (_) {
    // Unavailable/invalid storage is not permission to reset user settings.
  }
})();
