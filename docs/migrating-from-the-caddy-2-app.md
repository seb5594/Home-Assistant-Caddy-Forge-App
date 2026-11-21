# Moving from the Caddy 2 and CaddyBuilder apps

Many setups use two apps: *CaddyBuilder* compiles a Caddy with plugins and *Caddy 2* runs it. Caddy Forge does both and can take
over what the two apps know: the plugins and Caddy version of the build command, the Caddyfile and the options of Caddy 2.

## One switch: take over

1. Leave both old apps installed (stopped is fine); the app reads their config folders.
2. In Caddy Forge, switch on **Take over the Caddy 2 and CaddyBuilder apps** and start the app.
3. It reads
   * the build command of CaddyBuilder (`xcaddyCommand.sh`): the **Caddy version** and every `--with` plugin as an entry under
     *Plugins*, with a pinned tag, branch or commit in the *Version* field. Lines that are commented out in your script become
     entries that are switched *off*, so nothing is lost and nothing unwanted is built;
   * the Caddyfile of Caddy 2, which switches the **mode** to `advanced (caddyfile)` (it is imported on the next start, see below);
     if there is no build command, the plugins of Caddy 2's own `caddy` binary are used instead;
   * the **options** of Caddy 2: log level, environment variables with their values, the formatting switch and, if it had no Caddyfile,
     its email and site (table below). Environment variables that the Caddyfile uses and the old app did not define are added empty;
4. The app stores the result in its own options, switches **take over** off again and restarts. Entries and settings you already made are kept;
   the Caddy version only changes while it still is the shipped default.
5. Check the options, stop and uninstall the old apps.

Your own `xcaddyCommand.sh` looks like this and becomes the entries on the right:

| Line | Entry |
| --- | --- |
| `xcaddy build latest \` | Caddy version `latest` |
| `--with github.com/caddy-dns/cloudflare \` | `github.com/caddy-dns/cloudflare`, on |
| `#  --with github.com/mholt/caddy-l4@ef01c22 #@31ae08c` | `github.com/mholt/caddy-l4`, version `ef01c22`, **off** |
| `# v2.9.1`, `# latest` | ignored (no `--with`) |

The app needs the Supervisor API for this (`hassio_api`): to store its own options, to restart itself and, with the role `manager`, to read the options of the old app.

### Old Home Assistant versions

The app asks for the config folders of all apps with the map type `all_addon_configs`, which every Home Assistant version since it
exists understands and newer ones still accept (they call it `all_app_configs` and mount it at `/app_configs` instead of
`/addon_configs`). The app looks in both places, so it works on old and new versions alike.

## The short way, Caddyfile only

1. Stop the Caddy 2 app. Both apps share the host's ports, so only one of them can listen on 443 (and 80).
2. Install Caddy Forge and set the mode to **advanced (caddyfile)**.
3. Start it. If the app's config folder has no `Caddyfile` yet, the one of the Caddy 2 app is imported, together with the
   small files next to it (snippets, a `www` folder; up to 200 files of 5 MB each, the Caddy binary is left out).
4. Read the log. It tells you what is still to do:
   * **Environment variables** the Caddyfile uses (`{$NAME}` or `{env.NAME}`) that are not defined yet. Add them under
     *Environment variables*; the values live in the old app's options and are not copied.
   * **Plugins** found in the custom `caddy` binary of the old app. Add each one under *Plugins* (`owner/repo` is enough); the app builds
     them on the next start.
   * **Addresses**. Like the old app, this one runs on the host network, so `localhost:8123` and other `localhost` addresses keep
     working unchanged. HTTP is served on 8080 only if the Caddyfile sets `http_port 8080`; the old app's port 80 stays 80 otherwise.
5. Check the sites, then uninstall the Caddy 2 app. A Caddyfile that already exists here is never replaced.

While the mode is still `simple`, the log only mentions once per start that an import is possible.

## What happens to the options of the Caddy 2 app

The switch reads them through the Supervisor (see the end of this guide) and maps them like this:

| Caddy 2 app | Caddy Forge |
| --- | --- |
| `env_vars` | **Environment variables**, with their values. Variables you already entered keep their value; an empty one is filled. |
| `log_level` | **Log level** (`trace`/`debug` → debug, `info`/`notice` → info, `warning` → warn, `error`/`fatal` → error), as long as yours still is `info` |
| `caddy_fmt: true` | **Format Caddyfile** (advanced mode) |
| `caddy_upgrade: true` | **Caddy version** `latest`, as long as it still is the shipped default |
| `non_caddyfile_config.email` | **Simple mode → Email address** (only when the old app had no Caddyfile and ran from these options) |
| `non_caddyfile_config.domain`, `destination` and `port` | a site with this **Domain** and the **Target** `destination:port` (same condition) |
| `args: ["--watch"]` | not needed; restart the app after changes. Other arguments are named in the log. |

The placeholders of the old app's defaults (`mydomain.com`, `your@email.com`) are not taken over. Values of environment variables
end up in this app's options and are never written to the log. If the options can not be read (the old app is already
uninstalled), the log says so and the rest of the takeover still works; enter those values once by hand.

## What the app is allowed to read

To find the Caddyfile, the app mounts the config folders of all apps read-only (`all_addon_configs`). It only looks at folders named
`*_caddy-2` or `*_caddy_2`, and only reads the Caddyfile, small files next to it and the list of plugins of the `caddy` binary
(that binary is started once with `list-modules`). Nothing is written there.

The role `manager` lets the app ask the Supervisor for the saved options of other apps; it is used once, for the takeover, and only for
the Caddy 2 app (found by its name ending in `caddy-2`). Nothing is changed in the old apps.
