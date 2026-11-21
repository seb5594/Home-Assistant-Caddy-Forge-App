// Adds the developer footer below the admin UI. The UI is a single-page app that renders its
// own body, so the footer is appended once the page has loaded and put back if the app drops it.
(function () {
  var REPOSITORY = 'https://github.com/seb5594/Home-Assistant-Caddy-Webserver-App';
  var APPS = 'https://github.com/seb5594/Home-Assistant-Apps';
  var SUPPORT = 'https://paypal.me/seb5594';

  function link(className, href, text) {
    var anchor = document.createElement('a');
    anchor.className = className;
    anchor.href = href;
    anchor.target = '_blank';
    anchor.rel = 'noopener noreferrer';
    anchor.textContent = text;
    return anchor;
  }

  function build() {
    var footer = document.createElement('footer');
    footer.id = 'forge-footer';

    var credit = link('forge-credit', REPOSITORY, 'Application developed by seb5594 (Sebastian Schmidt) - Made with ');
    var heart = document.createElement('span');
    heart.className = 'forge-heart';
    heart.textContent = '♥';
    credit.appendChild(heart);
    credit.appendChild(document.createTextNode(' in Germany'));
    footer.appendChild(credit);

    var actions = document.createElement('div');
    actions.className = 'forge-actions';
    actions.appendChild(link('forge-link', APPS, 'More Home Assistant Apps'));
    actions.appendChild(link('forge-link', SUPPORT, 'Support my work ☕'));
    footer.appendChild(actions);
    return footer;
  }

  function ensure() {
    if (document.body && !document.getElementById('forge-footer')) {
      document.body.appendChild(build());
    }
  }

  function start() {
    setTimeout(ensure, 300);
    new MutationObserver(ensure).observe(document.body, { childList: true });
  }

  if (document.readyState === 'complete') {
    start();
  } else {
    window.addEventListener('load', start);
  }
})();
