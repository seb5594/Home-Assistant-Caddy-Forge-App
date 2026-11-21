# Changelog

## 2026.11.21.3

- ✨ The admin UI has an accent colour: a palette in the page footer (presets, the primary colours of your Home Assistant themes and a free colour picker) that is remembered per browser.
- ✨ New option `accent` for the default: a colour, or the name of a theme in Home Assistant's themes folder to follow its primary colour. Home Assistant blue otherwise.
- ✨ The page also takes `?accent=%23e91e63` from the address and the colour of the surrounding Home Assistant page when it is embedded in one.

## 2026.11.21.2

- ✨ The admin UI shows the developer footer (credit, more apps, support link). It is added by a small script after the page has loaded, so the UI keeps working when it re-renders.
- 🔒 The admin UI now redoes the admin API's own browser protections behind its proxy: only plain addresses and local names are accepted as host name (protection against DNS rebinding), and only requests of the page itself are passed on.
- 🐛 The admin UI could not load the configuration in a browser; fixed.

## 2026.11.21.1

- ✨ Admin UI: one switch adds the `caddy-admin-ui` plugin and serves it on its own port for private networks, optionally behind a login.
- ✨ New site type `git`: a website that lives in a git repository, cloned on start and refreshed on a schedule, no plugin needed.
- ✨ nginx helper: a `nginx.conf` in the `migrate` folder is converted on start when the nginx adapter plugin is part of the build.
- 📚 Practical examples and migration guides for nginx and Apache, in English and German.
- 🎨 New icon and logo that show Caddy for Home Assistant.

## 2026.11.21

- ✨ First release: Caddy 2.11.9 and the xcaddy builder in one app.
- ✨ Plugins are listed in the app configuration; a custom binary is built on demand and swapped in only after it passed validation.
- ✨ Optional update check on start for `latest` and for plugins without a pinned version.
- ✨ Simple mode creates the Caddyfile from the options (reverse proxy, static files, redirects, certificates, login, allow lists); a Caddyfile mode is available for everything else.
