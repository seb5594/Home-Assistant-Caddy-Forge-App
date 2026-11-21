# Caddy Forge

[Caddy](https://caddyserver.com) as a Home Assistant app, with its own build workshop on board. Run the
web server as shipped, or name a few plugins and the app compiles a matching binary for you. The
binary lives next to the server, so there is nothing to copy between apps.

## Quick start

1. Install the app and open **Configuration**. The default entry serves Home Assistant on
   `https://homeassistant.local` with a certificate from Caddy's own authority.
2. Replace the **Domain** with yours, pick **Certificate: auto** for a free public certificate
   and set an **Email address**.
3. Forward ports **80** and **443** (TCP, and 443 UDP for HTTP/3) from your router to the Home Assistant host.
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
| `caddyfile` | Runs your own `Caddyfile` from the app's config folder. On first use it is created from your simple options, so you start from something that works. |

### Caddy build

| Option | Description |
| --- | --- |
| **Caddy version** | A pinned upstream release (the default ships with the app and starts instantly), another release such as `2.10.2`, or `latest`. |
| **Plugins** | One Go module per row, for example `github.com/caddy-dns/cloudflare`. Append `@version` to pin one; plugins without a version follow their newest release. Lines copied from an `xcaddy build --with …` command work as they are. |
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
| **Type** | `proxy` forwards to a service, `static` serves a folder, `redirect` sends visitors elsewhere. |
| **Target** | Proxy: `homeassistant:8123` or `https://192.168.1.5:8006`. Static: a folder such as `/share/www`, `/media` or `/homeassistant/www`. Redirect: the new address (the path is kept). |
| **Certificate** | `auto` (public, free), `internal` (Caddy's own authority), `custom` (`/ssl/fullchain.pem` and `/ssl/privkey.pem`), `off` (plain HTTP). |
| **Skip upstream certificate check** | For HTTPS targets with a self-signed certificate. |
| **Username / Password** | Protects the site with a login. A plain password is hashed on every start; a bcrypt hash is used as is. |
| **Allowed networks** | Only these networks may open the site, for example `192.168.0.0/16`. |
| **Extra directives** | One Caddyfile line per row, added to this site. |

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
`caddyfile`: the app seeds `Caddyfile` from your options once and from then on only runs your file.
Turn on **Format Caddyfile** to let Caddy tidy the indentation on every start.

## Plugin ideas

| Plugin | Module |
| --- | --- |
| DNS challenge providers | `github.com/caddy-dns/<provider>` (set via **DNS provider**) |
| CrowdSec bouncer | `github.com/hslatman/caddy-crowdsec-bouncer` |
| GeoIP filtering | `github.com/porech/caddy-maxmind-geolocation` |
| Dynamic DNS | `github.com/mholt/caddy-dynamicdns` |
| TCP/UDP routing (layer 4) | `github.com/mholt/caddy-l4` |

Plugins bring their own settings; consult the plugin's documentation and place them in `global.caddy` or `sites.caddy`.

## Files

| Where | What |
| --- | --- |
| App config folder | `Caddyfile` (pro mode), `generated.Caddyfile`, `global.caddy`, `sites.caddy`, `caddy-root-ca.crt` |
| `/data/caddy` (included in backups) | Certificates and Caddy's state, the custom binary and `state.json` |

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Home Assistant answers `400: Bad Request` | `trusted_proxies` is missing in Home Assistant's `http:` settings (see Quick start). |
| Certificate cannot be obtained | Ports 80/443 are not forwarded, the domain does not point at your address, or you hit a rate limit: try `staging` first. |
| `No Caddy binary accepts the configuration` | A directive in your Caddyfile or `global.caddy`/`sites.caddy` needs a plugin that is not in the list. The log shows Caddy's message. |
| `This exact combination already failed validation` | The same plugins and Caddyfile were rejected before. Change any of them to try again. |
| Build fails with `no space left` | Free at least 2.5 GB, then restart the app. |
