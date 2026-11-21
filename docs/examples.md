# Practical examples

Every example is a site entry under **Simple mode → Sites** (shown as YAML, the way the app's
configuration editor stores it). Add as many as you like; they run side by side.

## 1. Home Assistant on your own domain

```yaml
- domain: ha.example.org
  type: proxy
  target: homeassistant:8123
```

Set an email address under **Simple mode**, forward ports 80 and 443 and add `trusted_proxies` to Home Assistant
(see the app documentation). The certificate is requested and renewed automatically.

## 2. A private homepage for yourself or the family

A folder with an `index.html` is all it takes. Put the files into `/share/www` (reachable through the
*Samba share* or the *File editor* app) and serve them with a login:

```yaml
- domain: home.example.org
  type: static
  target: /share/www
  auth_user: family
  auth_password: !secret homepage_password
```

Use `/media` for photo galleries or `/homeassistant/www` to share the files of Home Assistant's `www` folder
under your own domain. Only for the local network? Add `allow_from: [192.168.0.0/16]` and set the certificate
to `internal`.

## 3. A website that updates itself from git

Type `git` keeps a shallow clone of a repository and fetches new commits, so publishing means *pushing*:

```yaml
- domain: docs.example.org
  type: git
  target: https://github.com/you/your-site.git
  branch: gh-pages          # optional, default branch otherwise
  folder: public            # optional sub folder, e.g. the output of a site generator
  refresh: 15               # minutes, 0 = only when the app starts
```

Typical sources: a Hugo, MkDocs, Jekyll or Astro project whose CI pushes the generated site to a `gh-pages` branch,
or a repository with a hand-written page. Private repositories work with a token in the URL
(`https://you:TOKEN@github.com/you/private.git`); put the whole URL into Home Assistant's `secrets.yaml` and write
`target: !secret site_repository`. Credentials are hidden in the app log and the `.git` folder is never served.

## 4. What about dynamic pages, PHP and friends?

Caddy serves files and forwards requests; it does not run application code itself. That still covers a lot:

| You have | Use |
| --- | --- |
| Static pages, documentation, a landing page | Type `static` or `git` |
| A single-page app (Vue, React, Svelte …) | Type `static` or `git` plus the extra directive `try_files {path} /index.html` |
| A service with its own web server (Node, Go, Python, a container) | Type `proxy` |
| PHP (WordPress, Nextcloud, small scripts) | Run PHP-FPM in its own container or app and connect it, see below |

PHP through PHP-FPM, with the extra directives of a `static` site (one line per entry):

```yaml
- domain: blog.example.org
  type: static
  target: /share/blog
  extra:
    - php_fastcgi 192.168.1.20:9000 {
    - root /var/www/html
    - }
```

`target` is the folder as Caddy sees it, `root` the same files as PHP-FPM sees them. FrankenPHP, the Caddy
variant with PHP built in, needs a C toolchain and PHP libraries and therefore cannot be built with this app.

## 5. Many services, one wildcard certificate

```yaml
simple:
  dns_provider: cloudflare
  dns_token: !secret cloudflare_token
  sites:
    - domain: ha.example.org
      type: proxy
      target: homeassistant:8123
    - domain: nas.example.org
      type: proxy
      target: https://192.168.1.5:5001
      skip_verify: true
    - domain: "*.lan.example.org"
      type: proxy
      target: 192.168.1.30:8080
```

DNS validation needs no open port 80 and works for local-only names that you point at a private address.

## 6. Keep something inside the house

```yaml
- domain: grafana.example.org
  type: proxy
  target: 192.168.1.40:3000
  allow_from:
    - 192.168.0.0/16
    - 172.30.32.0/23
  auth_user: admin
  auth_password: !secret grafana_proxy_password
```

Everybody outside the listed networks gets a plain "Forbidden"; inside, the login is asked on top.

## 7. Look at Caddy itself: the admin UI

Switch on **Admin UI** in the configuration. The app adds the plugin
[`caddy-admin-ui`](https://github.com/gsmlg-dev/caddy-admin-ui) to the next build and serves it on port **8099**
(enable the port under *Network*, then use *Open Web UI* on the app page). You can read the running configuration,
upstreams and metrics; changes made there live in memory until the next start, so keep the options as the source
of truth.

Notes on how it is secured: only private networks may connect, you can add a login, requests from other web pages are
refused, and the plugin's built-in web shell stays off with its endpoint blocked. The UI is a single-page app with absolute
links, which is why it is offered on its own port and not inside Home Assistant's sidebar (ingress).
