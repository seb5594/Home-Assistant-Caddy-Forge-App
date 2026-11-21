# Changelog

## 2026.11.21

- ✨ First release: Caddy 2.11.9 and the xcaddy builder in one app.
- ✨ Plugins are listed in the app configuration; a custom binary is built on demand and swapped in only after it passed validation.
- ✨ Optional update check on start for `latest` and for plugins without a pinned version.
- ✨ Simple mode creates the Caddyfile from the options (reverse proxy, static files, redirects, certificates, login, allow lists); a Caddyfile mode is available for everything else.
