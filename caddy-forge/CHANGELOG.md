# Changelog

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
