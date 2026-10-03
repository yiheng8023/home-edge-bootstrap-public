/* Site defaults and same-origin entry for the local Yacd-meta panel. */
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

    if (typeof window === 'undefined' || typeof document === 'undefined') return;
    const here = new URL(window.location.href);
    if (!/^https?:$/.test(here.protocol) || !/^\/ui(?:\/|$)/.test(here.pathname)) return;
    // Explicit upstream connection links keep their existing meaning.
    if (['hostname', 'port', 'secret'].some(name => here.searchParams.has(name))) return;
    const origin = here.origin;
    const previousEntries = Array.isArray(config.clashAPIConfigs) ? config.clashAPIConfigs : [];
    const selectedEntry = previousEntries[config.selectedClashAPIConfigIndex];
    // Retire only Yacd's identifiable, never-configured built-in placeholder.
    const entries = previousEntries.filter(entry => !(entry &&
      entry.baseURL === 'http://127.0.0.1:9090' && entry.secret === '' && entry.addedAt === 0));
    const selectedIndex = entries.indexOf(selectedEntry);
    const isLocal = entry => {
      try {
        const url = new URL(entry.baseURL);
        return url.origin === origin && url.pathname === '/' && !url.search && !url.hash &&
          !url.username && !url.password;
      } catch (_) { return false; }
    };
    const local = entries.map((entry, index) => ({ entry, index })).filter(({ entry }) => isLocal(entry));
    const isText = value => typeof value === 'string';
    const hasKey = ({ entry }) => isText(entry.secret) && entry.secret.length > 0;
    const current = local.find(item => item.index === selectedIndex && hasKey(item)) ||
      local.filter(hasKey).sort((a, b) => (b.entry.addedAt || 0) - (a.entry.addedAt || 0))[0] || local[0];
    const index = current ? current.index : entries.push({
      baseURL: origin,
      secret: '',
      addedAt: Date.now(),
    }) - 1;
    // Persist before Yacd's deferred module reads its initial application state.
    config.clashAPIConfigs = entries;
    config.selectedClashAPIConfigIndex = index;
    localStorage.setItem(key, JSON.stringify(config));

    const zh = /^zh/i.test(window.navigator && window.navigator.language || '');
    const words = zh ? {
      title: '连接本地路由器', checking: '正在连接当前路由器…',
      hint: '首次输入面板访问密钥，此浏览器会记住连接。', label: '面板访问密钥',
      enter: '保存并进入', invalid: '访问密钥不正确，请重新输入。',
      offline: '暂时无法连接路由器，请稍后重试。', retry: '重试连接',
      edit: '重新输入密钥', storage: '浏览器无法保存连接，请允许网站存储后重试。',
    } : {
      title: 'Connect to this router', checking: 'Connecting to this router…',
      hint: 'Enter the panel access key once. This browser will remember the connection.', label: 'Panel access key',
      enter: 'Save and open', invalid: 'The access key is incorrect. Try again.',
      offline: 'The router is temporarily unavailable. Try again shortly.', retry: 'Retry connection',
      edit: 'Enter another key', storage: 'Allow website storage in this browser, then try again.',
    };
    const style = document.createElement('style');
    // Yacd's API picker is a body portal, outside #app. Hide both while gating.
    style.textContent = 'body>:not(.home-edge-entry){display:none!important}.home-edge-entry{position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;background:#202124;color:#e8eaed;font:16px system-ui;padding:20px;box-sizing:border-box}.home-edge-entry section{width:100%;max-width:390px}.home-edge-entry h1{font-size:24px}.home-edge-entry p{line-height:1.6}.home-edge-entry label{display:block;margin:20px 0 8px}.home-edge-entry input{box-sizing:border-box;width:100%;padding:12px;border:1px solid #7b8794;border-radius:6px;background:#30343c;color:#fff;font:inherit}.home-edge-entry button{margin-top:16px;padding:12px 18px;border:0;border-radius:6px;background:#2477d4;color:#fff;font:inherit;cursor:pointer}.home-edge-entry button:disabled{opacity:.5}.home-edge-entry button+button{margin-left:12px;background:#42464f}';
    document.head.appendChild(style);
    let pane;
    let ready = false;
    let view = { mode: 'checking', message: words.checking };
    const element = (tag, text) => {
      const node = document.createElement(tag);
      if (text) node.textContent = text;
      return node;
    };
    const show = (mode, message) => {
      view = { mode, message };
      if (document.readyState !== 'loading') render();
    };
    const release = () => {
      ready = true;
      if (pane) pane.remove();
      style.remove();
    };
    const verify = async secret => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 8000);
      try {
        const response = await fetch(origin + '/version', {
          method: 'GET', headers: secret ? { Authorization: 'Bearer ' + secret } : {},
          credentials: 'omit', redirect: 'error', cache: 'no-store', signal: controller.signal,
        });
        if (response.status === 401 || response.status === 403) return 'key';
        if (!response.ok) return 'offline';
        const data = await response.json();
        return data && typeof data.version === 'string' ? 'ready' : 'offline';
      } catch (_) { return 'offline'; }
      finally { clearTimeout(timer); }
    };
    let attemptedKey = isText(entries[index].secret) ? entries[index].secret : '';
    let attemptedSubmission = false;
    const connect = async (secret, submitted) => {
      attemptedKey = secret;
      attemptedSubmission = submitted;
      show('checking', words.checking);
      const state = await verify(secret);
      if (state === 'key') { show('key', submitted ? words.invalid : words.hint); return; }
      if (state !== 'ready') { show('offline', words.offline); return; }
      if (submitted) {
        try {
          // Re-read preferences: a user may have changed them in another tab.
          const latest = JSON.parse(localStorage.getItem(key));
          if (!latest || !Array.isArray(latest.clashAPIConfigs) || !isLocal(latest.clashAPIConfigs[index])) throw Error();
          latest.clashAPIConfigs[index] = { ...latest.clashAPIConfigs[index], secret };
          latest.selectedClashAPIConfigIndex = index;
          const saved = JSON.stringify(latest);
          localStorage.setItem(key, saved);
          if (localStorage.getItem(key) !== saved) throw Error();
          window.location.reload();
        } catch (_) { show('key', words.storage); }
      } else release();
    };
    function render() {
      if (ready) return;
      if (pane) pane.remove();
      pane = element('div'); pane.className = 'home-edge-entry';
      const section = element('section');
      section.appendChild(element('h1', words.title));
      const message = element('p', view.message); message.setAttribute('role', 'status');
      section.appendChild(message);
      if (view.mode === 'key') {
        const form = element('form');
        const label = element('label', words.label); label.htmlFor = 'home-edge-panel-key';
        const input = element('input'); input.id = label.htmlFor; input.type = 'password';
        input.autocomplete = 'current-password'; input.required = true; input.maxLength = 4096;
        const submit = element('button', words.enter); submit.type = 'submit';
        form.appendChild(label); form.appendChild(input); form.appendChild(submit);
        form.addEventListener('submit', event => { event.preventDefault(); if (input.value) connect(input.value, true); });
        section.appendChild(form);
      } else if (view.mode === 'offline') {
        const retry = element('button', words.retry);
        retry.addEventListener('click', () => connect(attemptedKey, attemptedSubmission));
        const edit = element('button', words.edit);
        edit.addEventListener('click', () => show('key', words.hint));
        section.appendChild(retry); section.appendChild(edit);
      }
      pane.appendChild(section); document.body.appendChild(pane);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', render, { once: true });
    else render();
    connect(attemptedKey, false);
  } catch (_) {
    // Unavailable/invalid storage is not permission to reset user settings.
  }
})();
