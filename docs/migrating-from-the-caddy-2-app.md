# Moving from the Caddy 2 and CaddyBuilder apps

Many setups use two apps: *CaddyBuilder* compiles a Caddy with plugins and *Caddy 2* runs it. Caddy Forge does both and can take
over what the two apps know: the plugins and Caddy version of the build command, and the Caddyfile. What can not be read from
another app (its options) is mapped below.

## One switch: take over

1. Leave both old apps installed (stopped is fine); the app reads their config folders.
2. In Caddy Forge, switch on **Take over the Caddy 2 and CaddyBuilder apps** and start the app.
3. It reads
   * the build command of CaddyBuilder (`xcaddyCommand.sh`): the **Caddy version** and every `--with` plugin as an entry under
     *Plugins*, with a pinned tag, branch or commit in the *Version* field. Lines that are commented out in your script become
     entries that are switched *off*, so nothing is lost and nothing unwanted is built;
   * the Caddyfile of Caddy 2, which switches the **mode** to `advanced (caddyfile)` (it is imported on the next start, see below);
     if there is no build command, the plugins of Caddy 2's own `caddy` binary are used instead;
   * the **environment variable** names that Caddyfile uses; they are added with an empty value for you to fill in.
4. The app stores the result in its own options, switches **take over** off again and restarts. Entries and settings you already made are kept;
   the Caddy version only changes while it still is the shipped default.
5. Check the options, fill in the environment variable values, stop and uninstall the old apps.

Your own `xcaddyCommand.sh` looks like this and becomes the entries on the right:

| Line | Entry |
| --- | --- |
| `xcaddy build latest \` | Caddy version `latest` |
| `--with github.com/caddy-dns/cloudflare \` | `github.com/caddy-dns/cloudflare`, on |
| `#  --with github.com/mholt/caddy-l4@ef01c22 #@31ae08c` | `github.com/mholt/caddy-l4`, version `ef01c22`, **off** |
| `# v2.9.1`, `# latest` | ignored (no `--with`) |

The app needs the Supervisor API for this (`hassio_api`, only for its own options and its own restart).

### Old Home Assistant versions

The app asks for the config folders of all apps with the map type `all_addon_configs`, which every Home Assistant version since it
exists understands and newer ones still accept (they call it `all_app_configs` and mount it at `/app_configs` instead of
`/addon_configs`). The app looks in both places, so it works on old and new versions alike.

## The short way, Caddyfile only

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
