// Page script of the admin UI: the accent colour picker and the developer footer.
// The UI is a single-page app that renders its own body, so everything is added once the page has
// loaded and put back if the app drops it.
(function () {
  var REPOSITORY = 'https://github.com/seb5594/Home-Assistant-Caddy-Forge-App';
  var APPS = 'https://github.com/seb5594/Home-Assistant-Apps';
  var SUPPORT = 'https://paypal.me/seb5594';
  var DEFAULT_ACCENT = '#4fc3f7';
  var STORAGE_KEY = 'forge-accent';

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
    button.title = entry.name;
    button.setAttribute('aria-label', group + ': ' + entry.name);
    button.setAttribute('data-color', entry.color);
    button.style.backgroundColor = entry.color;
    button.addEventListener('click', function () { saveChoice(entry.color); applyAccent(); });
    return button;
  }

  function colorPicker() {
    var label = element('label', 'forge-swatch forge-custom');
    label.title = 'Custom colour';
    var input = element('input');
    input.type = 'color';
    input.setAttribute('aria-label', 'Custom accent colour');
    input.value = /^#[0-9a-f]{6}$/i.test(effectiveColor()) ? effectiveColor() : DEFAULT_ACCENT;
    input.addEventListener('input', function () { saveChoice(input.value); applyAccent(); });
    label.appendChild(input);
    return label;
  }

  function accentRow() {
    var row = element('div', 'forge-accent');
    row.appendChild(element('span', 'forge-accent-label', 'Accent'));
    var entries = palette.presets.concat(palette.themes);
    for (var i = 0; i < entries.length; i++) {
      row.appendChild(swatch(entries[i], i < palette.presets.length ? 'Preset' : 'Home Assistant theme'));
    }
    row.appendChild(colorPicker());
    var reset = element('button', 'forge-reset', 'Auto');
    reset.type = 'button';
    reset.title = 'Back to the default';
    reset.addEventListener('click', function () { saveChoice(''); applyAccent(); });
    row.appendChild(reset);
    return row;
  }

  function build() {
    var footer = element('footer');
    footer.id = 'forge-footer';
    footer.appendChild(accentRow());

    var credit = link('forge-credit', REPOSITORY, 'Application developed by seb5594 (Sebastian Schmidt) - Made with ');
    credit.appendChild(element('span', 'forge-heart', '♥'));
    credit.appendChild(document.createTextNode(' in Germany'));
    footer.appendChild(credit);

    var actions = element('div', 'forge-actions');
    actions.appendChild(link('forge-link', APPS, 'More Home Assistant Apps'));
    actions.appendChild(link('forge-link', SUPPORT, 'Support my work ☕'));
    footer.appendChild(actions);
    return footer;
  }

  function ensure() {
    if (document.body && !document.getElementById('forge-footer')) {
      document.body.appendChild(build());
      applyAccent();
    }
  }

  function start() {
    setTimeout(ensure, 300);
    new MutationObserver(ensure).observe(document.body, { childList: true });
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
