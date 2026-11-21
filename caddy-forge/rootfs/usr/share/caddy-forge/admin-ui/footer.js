// Page script of the admin UI: the accent colour picker and the developer footer.
// The UI is a single-page app that renders its own body, so everything is added once the page has
// loaded and put back if the app drops it.
(function () {
  var REPOSITORY = 'https://github.com/seb5594/Home-Assistant-Caddy-Forge-App';
  var APPS = 'https://github.com/seb5594/Home-Assistant-Apps';
  var SUPPORT = 'https://paypal.me/seb5594';
  var DEFAULT_ACCENT = '#4fc3f7';
  var STORAGE_KEY = 'forge-accent';

  // ---- language ----------------------------------------------------------------------------------
  // The page follows the language of the browser (German or English). Names that come from the plugin
  // itself are translated by UI_WORDS once the page has rendered.
  var LANGUAGE = ((navigator.languages && navigator.languages[0]) || navigator.language || 'en').slice(0, 2).toLowerCase();
  var STRINGS = {
    en: {
      accent: 'Accent', auto: 'Auto', autoTitle: 'Back to the default', custom: 'Custom colour', preset: 'Preset', theme: 'Home Assistant theme',
      creditBefore: 'Application developed by seb5594 (Sebastian Schmidt) - Made with ', creditAfter: ' in Germany',
      more: 'More Home Assistant Apps', support: 'Support my work ☕', site: 'Site', siteTitle: 'Open the site'
    },
    de: {
      accent: 'Akzent', auto: 'Auto', autoTitle: 'Zurück zum Standard', custom: 'Eigene Farbe', preset: 'Vorgabe', theme: 'Home-Assistant-Theme',
      creditBefore: 'Anwendung entwickelt von seb5594 (Sebastian Schmidt) – Mit ', creditAfter: ' in Deutschland gemacht',
      more: 'Weitere Home-Assistant-Apps', support: 'Unterstütze meine Arbeit ☕', site: 'Seite', siteTitle: 'Seite öffnen'
    }
  };
  var COLOR_NAMES = {
    de: { 'Light blue': 'Hellblau', 'Teal': 'Türkis', 'Green': 'Grün', 'Amber': 'Bernstein', 'Red': 'Rot', 'Pink': 'Rosa', 'Purple': 'Violett' }
  };
  // Words of the plugin's own pages, exact matches of an element's text.
  var UI_WORDS = {
    de: {
      'Config': 'Konfiguration', 'Setup': 'Einrichtung', 'Metrics': 'Metriken', 'Upstream': 'Upstreams', 'Requests': 'Anfragen',
      'Convert Caddyfile to JSON': 'Caddyfile in JSON umwandeln', 'Put your Caddyfile here': 'Caddyfile hier einfügen',
      'Convert': 'Umwandeln', 'JSON config': 'JSON-Konfiguration', 'Save config to caddy server': 'Konfiguration an Caddy senden'
    }
  };

  function t(key) {
    return (STRINGS[LANGUAGE] || STRINGS.en)[key] || STRINGS.en[key];
  }

  function colorName(name) {
    return (COLOR_NAMES[LANGUAGE] || {})[name] || name;
  }

  // The script's own address: the palette lies next to it, whatever path (ingress prefix) it is served below.
  var SCRIPT = document.currentScript ? document.currentScript.src : '/_forge/footer.js';
  var palette = { default: null, presets: [], themes: [] };
  var chosen = readChoice();

  // ---- storage ---------------------------------------------------------------------------------
  function readChoice() {
    try { return window.localStorage.getItem(STORAGE_KEY) || ''; } catch (e) { return ''; }
  }

  function saveChoice(color) {
    chosen = color || '';
    try {
      if (chosen) { window.localStorage.setItem(STORAGE_KEY, chosen); } else { window.localStorage.removeItem(STORAGE_KEY); }
    } catch (e) { /* private mode: the choice lasts until the page is closed */ }
  }

  // ---- accent colour ---------------------------------------------------------------------------
  // The colour of the Home Assistant page around us, if it is the same origin and we are embedded.
  function colorOfParent() {
    try {
      if (window.parent && window.parent !== window) {
        return getComputedStyle(window.parent.document.documentElement).getPropertyValue('--primary-color').trim();
      }
    } catch (e) { /* another origin: not readable */ }
    return '';
  }

  function colorFromAddress() {
    return new URLSearchParams(window.location.search).get('accent') || '';
  }

  function effectiveColor() {
    return chosen || colorFromAddress() || colorOfParent() || palette.default || DEFAULT_ACCENT;
  }

  // Red, green and blue of any CSS colour, via a one-pixel canvas.
  function rgbOf(color) {
    var context = document.createElement('canvas').getContext('2d');
    context.fillStyle = '#000';
    context.fillStyle = color;
    context.fillRect(0, 0, 1, 1);
    var data = context.getImageData(0, 0, 1, 1).data;
    return [data[0], data[1], data[2]];
  }

  // Relative luminance as defined by WCAG.
  function luminanceOf(rgb) {
    var parts = rgb.map(function (value) {
      var channel = value / 255;
      return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2];
  }

  // Whichever of dark and light text has the better contrast on the accent.
  function contentColor(color) {
    var luminance = luminanceOf(rgbOf(color));
    var againstWhite = 1.05 / (luminance + 0.05);
    var againstDark = (luminance + 0.05) / (luminanceOf([26, 26, 26]) + 0.05);
    return againstDark > againstWhite ? '#1a1a1a' : '#ffffff';
  }

  function applyAccent() {
    var color = effectiveColor();
    var root = document.documentElement;
    root.style.setProperty('--color-primary', color);
    root.style.setProperty('--color-primary-content', contentColor(color));
    var marked = document.querySelectorAll('#forge-footer [data-color]');
    for (var i = 0; i < marked.length; i++) {
      marked[i].classList.toggle('forge-active', !!chosen && marked[i].getAttribute('data-color').toLowerCase() === chosen.toLowerCase());
    }
  }

  // ---- footer ----------------------------------------------------------------------------------
  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text) { node.textContent = text; }
    return node;
  }

  function link(className, href, text) {
    var anchor = element('a', className, text);
    anchor.href = href;
    anchor.target = '_blank';
    anchor.rel = 'noopener noreferrer';
    return anchor;
  }

  function swatch(entry, group) {
    var button = element('button', 'forge-swatch');
    button.type = 'button';
    var label = group === 'preset' ? colorName(entry.name) : entry.name;
    button.title = label;
    button.setAttribute('aria-label', t(group) + ': ' + label);
    button.setAttribute('data-color', entry.color);
    button.style.backgroundColor = entry.color;
    button.addEventListener('click', function () { saveChoice(entry.color); applyAccent(); });
    return button;
  }

  function colorPicker() {
    var label = element('label', 'forge-swatch forge-custom');
    label.title = t('custom');
    var input = element('input');
    input.type = 'color';
    input.setAttribute('aria-label', t('custom'));
    input.value = /^#[0-9a-f]{6}$/i.test(effectiveColor()) ? effectiveColor() : DEFAULT_ACCENT;
    input.addEventListener('input', function () { saveChoice(input.value); applyAccent(); });
    label.appendChild(input);
    return label;
  }

  function accentRow() {
    var row = element('div', 'forge-accent');
    row.appendChild(element('span', 'forge-accent-label', t('accent')));
    var entries = palette.presets.concat(palette.themes);
    for (var i = 0; i < entries.length; i++) {
      row.appendChild(swatch(entries[i], i < palette.presets.length ? 'preset' : 'theme'));
    }
    row.appendChild(colorPicker());
    var reset = element('button', 'forge-reset', t('auto'));
    reset.type = 'button';
    reset.title = t('autoTitle');
    reset.addEventListener('click', function () { saveChoice(''); applyAccent(); });
    row.appendChild(reset);
    return row;
  }

  function build() {
    var footer = element('footer');
    footer.id = 'forge-footer';
    footer.appendChild(accentRow());

    var credit = link('forge-credit', REPOSITORY, t('creditBefore'));
    credit.appendChild(element('span', 'forge-heart', '♥'));
    credit.appendChild(document.createTextNode(t('creditAfter')));
    footer.appendChild(credit);

    var actions = element('div', 'forge-actions');
    actions.appendChild(link('forge-link', APPS, t('more')));
    actions.appendChild(link('forge-link', SUPPORT, t('support')));
    footer.appendChild(actions);
    return footer;
  }

  // ---- navigation: mark the current page -------------------------------------------------------
  function markCurrentPage() {
    var links = document.querySelectorAll('.navbar .menu a');
    for (var i = 0; i < links.length; i++) {
      var here = window.location.pathname.replace(/\/$/, '');
      var target = new URL(links[i].href, window.location.href).pathname.replace(/\/$/, '');
      links[i].classList.toggle('forge-current', here === target);
    }
  }

  // ---- the plugin's own words in the language of the browser -------------------------------------
  // Exact matches of a text, except inside code and text fields. Words of a heading read differently there.
  var HEADING_WORDS = { de: { 'Convert': 'Konvertiere', 'to': 'nach' } };

  function translateText(node, words, headingWords) {
    var value = node.nodeValue.trim();
    var inHeading = node.parentNode && node.parentNode.closest && node.parentNode.closest('h1, h2, h3, h4, .card-title');
    var translated = (inHeading && headingWords[value]) || words[value] || (/^Fails:/.test(value) ? value.replace('Fails:', 'Fehler:') : '');
    if (translated) { node.nodeValue = node.nodeValue.replace(value, translated); }
  }

  function translatePage() {
    var words = UI_WORDS[LANGUAGE];
    if (!words) { return; }
    var headingWords = HEADING_WORDS[LANGUAGE] || {};
    var roots = document.querySelectorAll('.navbar, main');
    for (var i = 0; i < roots.length; i++) {
      var walker = document.createTreeWalker(roots[i], NodeFilter.SHOW_TEXT, {
        acceptNode: function (node) {
          return node.parentNode.closest('pre, code, textarea, script, style') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
        }
      });
      var texts = [];
      while (walker.nextNode()) { texts.push(walker.currentNode); }
      texts.forEach(function (node) { translateText(node, words, headingWords); });
    }
    var fields = document.querySelectorAll('main [placeholder], main [title]');
    for (var k = 0; k < fields.length; k++) {
      ['placeholder', 'title'].forEach(function (name) {
        var text = fields[k].getAttribute(name);
        if (text && words[text]) { fields[k].setAttribute(name, words[text]); }
      });
    }
  }

  // ---- upstream page: which sites use an upstream ----------------------------------------------
  // The admin API's configuration lies below the same base as this script, whatever ingress prefix it has.
  var BASE = new URL('../', SCRIPT).href;
  var sites = null;
  var sitesRequested = false;

  // Collects { hosts, dial } for every reverse proxy of a list of routes, also inside nested routes.
  function collectProxies(routes, hosts, found) {
    (routes || []).forEach(function (route) {
      var names = hosts;
      (route.match || []).forEach(function (matcher) { if (matcher.host) { names = matcher.host; } });
      (route.handle || []).forEach(function (handler) {
        if (handler.handler === 'subroute') {
          collectProxies(handler.routes, names, found);
        } else if (handler.handler === 'reverse_proxy') {
          (handler.upstreams || []).forEach(function (upstream) {
            if (upstream.dial) { found.push({ hosts: names, dial: upstream.dial }); }
          });
        }
      });
    });
  }

  // The address of a site as a visitor types it. The ports Caddy listens on (`http_port` and `https_port`, 8080 and
  // 443 here) stand for the usual 80 and 443 outside, where the router forwards them, so they are left out.
  function siteAddress(host, secure, port, app) {
    var standard = [secure ? '443' : '80', String(secure ? app.https_port || 443 : app.http_port || 80)];
    return (secure ? 'https://' : 'http://') + host + (!port || standard.indexOf(port) >= 0 ? '' : ':' + port);
  }

  function readSites(app) {
    var found = [];
    var servers = (app && app.servers) || {};
    Object.keys(servers).forEach(function (name) {
      var server = servers[name];
      var port = ((server.listen || [''])[0].split(':').pop()) || '';
      var proxies = [];
      collectProxies(server.routes, [], proxies);
      var secure = !!server.tls_connection_policies || port === String(app.https_port || 443);
      proxies.forEach(function (proxy) {
        proxy.hosts = proxy.hosts.map(function (host) { return { name: host, address: siteAddress(host, secure, port, app) }; });
        found.push(proxy);
      });
    });
    sites = found;
  }

  function loadSites() {
    if (sitesRequested) { return; }
    sitesRequested = true;
    fetch(BASE + 'config/apps/http', { cache: 'no-store' })
      .then(function (reply) { return reply.json(); })
      .then(readSites)
      .catch(function () { sites = []; })
      .then(decorateUpstreams);
  }

  function hostChip(host) {
    var plain = host.name.indexOf('*') >= 0;
    var chip = plain ? element('span', 'forge-host') : link('forge-host', host.address, '');
    if (!plain) { chip.title = t('siteTitle') + ': ' + host.address; }
    chip.appendChild(element('span', 'forge-host-label', t('site')));
    chip.appendChild(document.createTextNode(host.name + (plain ? '' : ' ↗')));
    return chip;
  }

  function decorateUpstreams() {
    if (!sites || !/\/upstream\/?$/.test(window.location.pathname)) { return; }
    var cards = document.querySelectorAll('.stat');
    for (var i = 0; i < cards.length; i++) {
      var description = cards[i].querySelector('.stat-desc');
      if (!description || cards[i].querySelector('.forge-hosts')) { continue; }
      var dial = description.textContent.trim();
      var list = element('div', 'forge-hosts');
      sites.filter(function (entry) { return entry.dial === dial; }).forEach(function (entry) {
        entry.hosts.forEach(function (host) { list.appendChild(hostChip(host)); });
      });
      if (list.childNodes.length) { description.parentNode.appendChild(list); }
    }
  }

  // The footer belongs below everything. When the app renders a new page it may put its content behind the footer,
  // so the footer is moved to the end again.
  function keepFooterLast(footer) {
    var next = footer.nextElementSibling;
    while (next && /^(SCRIPT|LINK|NEXT-ROUTE-ANNOUNCER)$/.test(next.tagName)) { next = next.nextElementSibling; }
    if (next) { document.body.appendChild(footer); }
  }

  function ensure() {
    if (!document.body) { return; }
    var footer = document.getElementById('forge-footer');
    if (!footer) {
      document.body.appendChild(build());
      applyAccent();
    } else {
      keepFooterLast(footer);
    }
    translatePage();
    markCurrentPage();
    if (/\/upstream\/?$/.test(window.location.pathname)) {
      loadSites();
      decorateUpstreams();
    }
  }

  function start() {
    setTimeout(ensure, 300);
    var pending = false;
    // The app re-renders on navigation and when its numbers refresh; everything above is put back afterwards.
    new MutationObserver(function () {
      if (pending) { return; }
      pending = true;
      window.requestAnimationFrame(function () { pending = false; ensure(); });
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  // ---- start -----------------------------------------------------------------------------------
  applyAccent();
  fetch(new URL('palette.json', SCRIPT), { cache: 'no-store' })
    .then(function (reply) { return reply.json(); })
    .then(function (data) { palette = data; })
    .catch(function () { /* the built-in defaults stay */ })
    .then(function () {
      applyAccent();
      if (document.readyState === 'complete') { start(); } else { window.addEventListener('load', start); }
    });
})();
