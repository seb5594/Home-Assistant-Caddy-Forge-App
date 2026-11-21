# Moving from the Caddy 2 app

If you run the *Caddy 2* app with its own `Caddyfile`, Caddy Forge imports that file for you. What can not be read
from another app (its options) is mapped below.

## The short way

1. Stop the Caddy 2 app. Both apps want ports 80 and 443.
2. Install Caddy Forge and set the mode to **advanced (caddyfile)**.
3. Start it. If the app's config folder has no `Caddyfile` yet, the one of the Caddy 2 app is imported, together with the
   small files next to it (snippets, a `www` folder; up to 200 files of 5 MB each, the Caddy binary is left out).
4. Read the log. It tells you what is still to do:
   * **Environment variables** the Caddyfile uses (`{$NAME}` or `{env.NAME}`) that are not defined yet. Add them under
     *Environment variables*; the values live in the old app's options and are not copied.
   * **Plugins** found in the custom `caddy` binary of the old app. Add each one under *Plugins* (`owner/repo` is enough); the app builds
     them on the next start.
   * **Addresses that point at `localhost`**. The old app ran on the host network, so Home Assistant was `localhost:8123`.
     That is rewritten to `homeassistant:8123` automatically; other services on `localhost` or `127.0.0.1` need their real address.
5. Check the sites, then uninstall the Caddy 2 app. A Caddyfile that already exists here is never replaced.

While the mode is still `simple`, the log only mentions once per start that an import is possible.

## Without a Caddyfile

The Caddy 2 app keeps a Caddyfile out of the picture when only its options are filled in. Those options can not be read from here,
so enter them once:

| Caddy 2 app | Caddy Forge |
| --- | --- |
| `non_caddyfile_config.email` | **Simple mode → Email address** |
| `non_caddyfile_config.domain` | a site with this **Domain** |
| `non_caddyfile_config.destination` and `port` | that site's **Target**, for Home Assistant `homeassistant:8123` (not `localhost`) |
| `env_vars` | **Environment variables** |
| `log_level` | **Log level** (`trace`/`debug` → debug, `info`/`notice` → info, `warning` → warn, `error`/`fatal` → error) |
| `caddy_fmt: true` | **Format Caddyfile** (advanced mode) |
| `caddy_upgrade: true` and a custom binary | **Plugins** plus **Caddy version** `latest` and **Update check** `install` |
| `args: ["--watch"]` | not needed; restart the app after changes |

## What the app is allowed to read

To find the Caddyfile, the app mounts the config folders of all apps read-only (`all_addon_configs`). It only looks at folders named
`*_caddy-2` or `*_caddy_2`, and only reads the Caddyfile, small files next to it and the list of plugins of the `caddy` binary
(that binary is started once with `list-modules`). Nothing is written there.
