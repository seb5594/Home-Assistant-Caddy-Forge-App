# Changelog

## 2026.11.21.9

- ✨ The admin UI opens on the **Upstream** page, and every upstream names the sites that use it as links, so a click shows whether the proxy entry is correct.
- 🎨 Bigger, clearer navigation (also the menu on phones) with the current page marked; the footer sits at the bottom of the window. The UI is called **Caddy Forge Admin**, and the unused shell entry is hidden.
- ✨ The takeover reads the options of the Caddy 2 app through the Supervisor: log level, environment variables with their values, the formatting switch and, when it ran without a Caddyfile, its email and site. This needs the role `manager`, used for that app only.
- 🔧 The log level is the first option.

## 2026.11.21.8

- ✨ The admin UI opens from Home Assistant's sidebar (ingress) and is always on; the option to switch it off is gone. Only the Supervisor can reach its port, Home Assistant does the login.
- ✨ The UI works below the ingress path: a response rewrite puts the path in front of its absolute links. Inside Home Assistant's frame the page can read Home Assistant's own primary colour, so the accent follows your theme (a colour picked in the footer still wins).
- 🔧 The shipped Caddy now contains the two plugins of the admin UI (compiled for every architecture when the image is built), so nothing has to be built on first start. Custom builds always include them at the same versions.
- 🔒 Your Caddyfile is never changed: the app reads it into JSON in memory, adds the admin UI and, when it says `admin off`, switches the admin API on at a private unix socket. Generated Caddyfiles use that socket instead of a TCP port.

## 2026.11.21.7

- 🔧 The app runs on the host network (like the Caddy 2 app), so there is nothing to map: Caddy listens on 8080 for HTTP, on 443 for HTTPS and on 5594 for the admin UI. The port section of the app is gone.
- 🔧 Home Assistant is `localhost:8123` (also the default site). Home Assistant sees the proxy as `127.0.0.1`.
- 🔒 Generated Caddyfiles switch the admin API off unless the admin UI is enabled, because on the host network it would be open to everything on the host.
- 🔧 A Caddyfile imported from the Caddy 2 app no longer needs its `localhost` addresses rewritten.

## 2026.11.21.6

- ✨ **Take over the Caddy 2 and CaddyBuilder apps:** one switch reads the build command of CaddyBuilder (Caddy version and `--with` plugins, commented-out ones as disabled entries) and the Caddyfile of Caddy 2, enters them into this app's options, switches itself off and restarts. Existing entries are kept.
- 🔧 Works with both spellings of the config folder mount: `/addon_configs` (legacy map type, understood by every Home Assistant version) and `/app_configs`.
- 🔒 The app now uses the Supervisor API (`hassio_api`) for its own options and its own restart.

## 2026.11.21.5

- ✨ The Caddyfile of the Caddy 2 app is imported automatically when the mode is `advanced (caddyfile)` and no Caddyfile exists yet, together with the small files next to it. `localhost:8123` becomes `homeassistant:8123`; missing environment variables, plugins of the old binary and other `localhost` addresses are named in the log.
- 🔒 For this the config folders of all apps are mounted read-only (`all_addon_configs`); only folders named `*_caddy-2` are looked at.
- 📚 Migration guide with a mapping of the Caddy 2 app's options.

## 2026.11.21.4

- ✨ Plugins are entries with a **plugin**, an optional **version** (tag, branch or commit) and an **enabled** switch. `owner/repo` is taken from github.com; module paths and repository URLs of other hosts work as well. The plugin hint links to a list of Caddy modules.
- 🔧 The HTTP port defaults to host port 8080, the admin UI listens on port 5594 inside the container.
- 🔧 The accent colour option is gone; the admin UI starts in a light blue and visitors pick their own in the footer.
- 🔧 The mode `caddyfile` is called `advanced (caddyfile)` (the old value is still understood).
- ⚠️ Plugin lists saved by an earlier version have to be entered again, because each plugin is now an entry instead of a text line.
- 📄 The license file carries the copyright notice.

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
