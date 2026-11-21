# Caddy Forge

[Caddy](https://caddyserver.com) as a Home Assistant app, with its own build workshop on board. Run the
web server as shipped, or name a few plugins and the app compiles a matching binary for you. The
binary lives next to the server, so there is nothing to copy between apps.

## Quick start

1. Install the app and open **Configuration**. The default entry serves Home Assistant on
   `https://homeassistant.local` with a certificate from Caddy's own authority.
2. Replace the **Domain** with yours, pick **Certificate: auto** for a free public certificate
   and set an **Email address**.
3. Forward ports **80** and **443** (TCP, and 443 UDP for HTTP/3) from your router to the Home Assistant host. The app
   listens for HTTP on host port **8080** by default (change it under *Network*), so forward external port 80 to 8080.
4. Tell Home Assistant to trust the proxy, in `configuration.yaml`:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 172.30.33.0/24
   ```

5. Start the app.

> **Local names and `tls: internal`**: browsers do not know Caddy's authority yet. The app copies its
> root certificate to `caddy-root-ca.crt` in the app's config folder; install it on your devices to get
> rid of the warning.

## How the app starts

```
options ──► Caddyfile ──► which Caddy? ──► start
              │               │
              │               ├─ shipped binary   (pinned default, no plugins)
              │               ├─ earlier custom build, still up to date
              │               └─ new build ──► must understand your Caddyfile ──► replaces the old binary
              └─ simple mode: generated      pro mode: your own file
```

A new binary is compiled in a scratch folder. It only replaces the running one after it has proven
that it understands your configuration, and the swap is a single rename. If a build fails, nothing
changes and the previous binary keeps serving.

## Options

### Mode

| Mode | What it does |
| --- | --- |
| `simple` | Builds the Caddyfile from the options below. Covers reverse proxies, static sites, redirects, certificates, logins and allow lists. |
| `advanced (caddyfile)` | Runs your own `Caddyfile` from the app's config folder. On first use it is created from your simple options, so you start from something that works. |

### Caddy build

| Option | Description |
| --- | --- |
| **Caddy version** | A pinned upstream release (the default ships with the app and starts instantly), another release such as `2.10.2`, or `latest`. |
| **Plugins** | One entry per plugin with three fields: the **plugin** (`owner/repo` is taken from github.com, so `caddy-dns/cloudflare` is enough; a module path such as `gitlab.com/group/project` or a repository URL works too), an optional **version** (tag, branch or commit; without one the plugin follows its newest release) and an **enabled** switch that leaves the entry out of the build without deleting it. Lines copied from an `xcaddy build --with …` command work as they are. A list of plugins: <https://github.com/Sjord/caddy-modules> |
| **Update check on start** | `install`: rebuild when `latest` or an unpinned plugin has a newer release. `notify`: only write it to the log. `off`: no lookups, no internet needed. |
| **Start web server** | Switch off to only check and build, then stop the app. |

What triggers a build:

| Situation | Result |
| --- | --- |
| Pinned default version, no plugins | The shipped binary starts, nothing is built. |
| Plugins listed, or another version pinned | A build on first start and whenever the list or version changes. |
| `latest` or unpinned plugins, update check on | Newer releases are detected on start (via the Go module proxy) and built when set to `install`. |
| Plugins removed again | The custom binary is deleted, the shipped one is used. |

The update check never blocks a start: without internet it logs a warning and carries on with what is installed.

Building needs about 2.5 GB of free disk space and 1 GB of free memory while it runs (the scratch folder is deleted
afterwards). Expect one to three minutes on a mini PC and considerably longer on a Raspberry Pi; the app limits
parallelism and memory to what is free and runs the build at a low priority so Home Assistant stays responsive.

### Simple mode

| Option | Description |
| --- | --- |
| **Email address** | Contact for the certificate authority. |
| **Certificate authority** | `auto` keeps Caddy's default. Use `staging` while testing to avoid rate limits. |
| **DNS provider / token** | Validate certificates via DNS instead of port 80, which also allows wildcard domains. Enter the provider name (`cloudflare`, `duckdns`, `hetzner`, …); its plugin is added to the build automatically. |
| **Trusted proxies** | Networks of proxies or tunnels in front of Caddy. |
| **Compression / Security headers / Access log** | Switches that apply to every site. HSTS is only sent for publicly trusted certificates. |

Each entry under **Sites**:

| Field | Description |
| --- | --- |
| **Domain** | The address visitors use. Separate several with commas. `*.example.com` needs a DNS provider. |
| **Type** | `proxy` forwards to a service, `static` serves a folder, `redirect` sends visitors elsewhere, `git` serves a website from a git repository. |
| **Target** | Proxy: `homeassistant:8123` or `https://192.168.1.5:8006`. Static: a folder such as `/share/www`, `/media` or `/homeassistant/www`. Redirect: the new address (the path is kept). Git: the repository URL. |
| **Git branch / sub folder / refresh** | Only for type `git`: the branch to serve (default branch if empty), a folder inside the repository such as `public`, and how often new commits are fetched in minutes (default 30, `0` = only on start). |
| **Certificate** | `auto` (public, free), `internal` (Caddy's own authority), `custom` (`/ssl/fullchain.pem` and `/ssl/privkey.pem`), `off` (plain HTTP). |
| **Skip upstream certificate check** | For HTTPS targets with a self-signed certificate. |
| **Username / Password** | Protects the site with a login. A plain password is hashed on every start; a bcrypt hash is used as is. |
| **Allowed networks** | Only these networks may open the site, for example `192.168.0.0/16`. |
| **Extra directives** | One Caddyfile line per row, added to this site. |

### Websites from git

A site of type `git` keeps a shallow clone below `/data/sites`, updates it before Caddy starts and then on the chosen
schedule. Nothing has to be built for it. Private repositories work with a token in the URL
(`https://user:TOKEN@host/repo.git`, best taken from `secrets.yaml` with `!secret`); credentials never appear in the log and the
`.git` folder is not served. If the repository cannot be reached, the last checkout keeps being served.

### Admin UI

Switch on **Admin UI** to add the plugin [`caddy-admin-ui`](https://github.com/gsmlg-dev/caddy-admin-ui) to the build.
It shows the running configuration, upstreams and metrics and is served on port **5594**, to private networks only, optionally
behind a username and password. Enable port 5594 under *Network*, then *Open Web UI* on the app page works.
The accent colour of the UI is a light blue. Visitors can change it in the footer palette (presets, the primary colours of the themes in
Home Assistant's `themes` folder and a free colour picker); the choice is kept in that browser. `?accent=%23e91e63` in the address
works too, and so does the colour of the Home Assistant page around it when the UI is embedded in one. Home Assistant keeps a user's
chosen theme in that user's browser, which a page on another port cannot read, so it cannot be picked up automatically.

Open it by IP address or a local name (`homeassistant.local:5594`, `192.168.1.10:5594`); public host names are refused as a
protection against DNS rebinding. The pages carry the developer footer of this app. Changes made in the UI last until the next
start; the options remain the source of truth. In Caddyfile mode the UI expects the
admin endpoint at its default address `localhost:2019`.

It is not part of Home Assistant's sidebar (ingress) because it is a single-page app with absolute links that cannot live below an
ingress path. Its built-in web shell is never enabled and its endpoint is blocked.

### Importing from the Caddy 2 app

In `advanced (caddyfile)` mode, a Caddyfile of the *Caddy 2* app is imported once if this app's config folder has none yet.
For that the app reads the config folders of all apps read-only (`all_addon_configs`) and looks only at those named `*_caddy-2`.

### Environment variables

Available to Caddy as `{env.NAME}`. Values can point into Home Assistant's `secrets.yaml` with `!secret`.

## Going beyond the options

Open the app's config folder (`/addon_configs/…`, for example with the *File editor* app) and add optional files.
Simple mode picks them up on the next start:

| File | Purpose |
| --- | --- |
| `global.caddy` | Lines for the global options block: plugin settings, `order …`, `servers { … }`. |
| `sites.caddy` | Extra sites and snippets, appended after the generated sites. Combine with **Extra directives**, e.g. `import my_snippet`. |

`generated.Caddyfile` shows exactly what simple mode produced. When even that is not enough, switch the mode to
`advanced (caddyfile)`: the app seeds `Caddyfile` from your options once and from then on only runs your file.
Turn on **Format Caddyfile** to let Caddy tidy the indentation on every start.

## Examples and migration

* [Practical examples](https://github.com/seb5594/Home-Assistant-Caddy-Forge-App/blob/dev/docs/examples.md): a private homepage, a site from git, PHP and single-page apps, wildcard certificates, LAN-only services.
* [Moving from the Caddy 2 app](https://github.com/seb5594/Home-Assistant-Caddy-Forge-App/blob/dev/docs/migrating-from-the-caddy-2-app.md): the Caddyfile is imported when you switch to the advanced mode; the options are mapped in the guide.
* [Moving from nginx or Apache](https://github.com/seb5594/Home-Assistant-Caddy-Forge-App/blob/dev/docs/migrating-from-nginx-and-apache.md): directive tables, a worked example and an
  adapter that reads a `nginx.conf` dropped into the `migrate` folder.

## Plugin ideas

| Plugin | Module |
| --- | --- |
| DNS challenge providers | `github.com/caddy-dns/<provider>` (set via **DNS provider**) |
| CrowdSec bouncer | `github.com/hslatman/caddy-crowdsec-bouncer` |
| GeoIP filtering | `github.com/porech/caddy-maxmind-geolocation` |
| Dynamic DNS | `github.com/mholt/caddy-dynamicdns` |
| Rate limiting | `github.com/mholt/caddy-ratelimit` |
| nginx config adapter | `github.com/caddyserver/nginx-adapter` |
| Admin UI | `github.com/gsmlg-dev/caddy-admin-ui` (set via **Admin UI**) |
| TCP/UDP routing (layer 4) | `github.com/mholt/caddy-l4` |

Plugins bring their own settings; consult the plugin's documentation and place them in `global.caddy` or `sites.caddy`.

## Files

| Where | What |
| --- | --- |
| App config folder | `Caddyfile` (pro mode), `generated.Caddyfile`, `global.caddy`, `sites.caddy`, `caddy-root-ca.crt`, `migrate/` |
| `/data/caddy` (included in backups) | Certificates and Caddy's state, the custom binary and `state.json` |
| `/data/sites` | Clones of the git sites |

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Home Assistant answers `400: Bad Request` | `trusted_proxies` is missing in Home Assistant's `http:` settings (see Quick start). |
| Certificate cannot be obtained | Ports 80/443 are not forwarded, the domain does not point at your address, or you hit a rate limit: try `staging` first. |
| `No Caddy binary accepts the configuration` | A directive in your Caddyfile or `global.caddy`/`sites.caddy` needs a plugin that is not in the list. The log shows Caddy's message. |
| `This exact combination already failed validation` | The same plugins and Caddyfile were rejected before. Change any of them to try again. |
| Build fails with `no space left` | Free at least 2.5 GB, then restart the app. |
