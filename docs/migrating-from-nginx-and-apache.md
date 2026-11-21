# Moving from nginx or Apache

Caddy replaces most of what a typical nginx or Apache setup does with far fewer lines: HTTPS certificates are
obtained and renewed automatically, HTTP is redirected to HTTPS, WebSockets and the usual proxy headers just work.
Rewrite one virtual host at a time instead of translating the whole file.

## The plan

1. **Inventory.** List every `server` (nginx) or `VirtualHost` (Apache): its domains, what it serves or forwards to, and
   anything special (logins, allowed networks, rewrites, upload limits).
2. **One site entry per host.** Most hosts fit the app's **Sites** list (domain, type, target, certificate, login,
   allowed networks). Special lines go into the site's **Extra directives**, one Caddyfile line per row.
3. **Test with the staging authority** (`Certificate authority: staging`) until everything answers, then switch to `auto`.
4. **Switch over.** Stop the old server, point the router's ports 80 and 443 at Home Assistant and start the app. Delete
   certbot cron jobs and renewal hooks; Caddy does that itself.

When a host needs more than the form offers, set the mode to `caddyfile` and write the Caddyfile directly: the
mapping tables below are exactly that vocabulary.

## nginx → Caddy

| nginx | Caddy |
| --- | --- |
| `server_name a.org b.org;` | site address `a.org, b.org {` (the **Domain** field accepts commas) |
| `listen 443 ssl http2;` | not needed, HTTPS is automatic; another port goes into the address (`a.org:8443`) |
| `ssl_certificate x; ssl_certificate_key y;` | `tls x y`, or **Certificate: custom** for `/ssl/fullchain.pem` and `/ssl/privkey.pem` |
| `return 301 https://$host$request_uri;` | `redir https://{host}{uri} permanent` (plain HTTP is redirected automatically) |
| `root /var/www; index index.html;` | `root * /var/www` and `file_server`, or site type **static** |
| `try_files $uri $uri/ /index.html;` | `try_files {path} {path}/ /index.html` (extra directive) |
| `location /api/ { proxy_pass http://10.0.0.5:3000; }` | `handle /api/* { reverse_proxy 10.0.0.5:3000 }` |
| `location /app/ { proxy_pass http://10.0.0.5:3000/; }` (prefix removed) | `handle_path /app/* { reverse_proxy 10.0.0.5:3000 }` |
| `proxy_set_header Host $host;` and `X-Forwarded-*` | default behavior; extra headers with `header_up Name value` inside `reverse_proxy` |
| `proxy_http_version 1.1; Upgrade` / `Connection` headers | WebSockets work out of the box |
| `proxy_read_timeout 300s;` | `reverse_proxy … { transport http { read_timeout 5m } }` |
| `upstream app { server a:1; server b:1; }` | `reverse_proxy a:1 b:1 { lb_policy round_robin }` |
| `auth_basic "x"; auth_basic_user_file f;` | `basic_auth { user <hash> }`, or the **Username / Password** fields (bcrypt hashes from htpasswd work) |
| `allow 192.168.0.0/16; deny all;` | **Allowed networks**, or `@lan client_ip 192.168.0.0/16` with a `handle @lan { … }` block |
| `gzip on;` | `encode zstd gzip` (the **Compression** switch) |
| `add_header X-Frame-Options SAMEORIGIN;` | `header X-Frame-Options SAMEORIGIN` |
| `client_max_body_size 100m;` | `request_body { max_size 100MB }` |
| `rewrite ^/old/(.*)$ /new/$1 permanent;` | `@old path_regexp old ^/old/(.*)$` then `redir @old /new/{re.old.1} permanent` |
| `fastcgi_pass 127.0.0.1:9000;` | `php_fastcgi 127.0.0.1:9000` |
| `error_page 404 /404.html;` | `handle_errors { rewrite * /404.html` and `file_server }` |
| `access_log /var/log/x;` | `log` (the **Access log** switch) |
| `limit_req_zone …` | plugin `github.com/mholt/caddy-ratelimit` |
| `stream { … }` (TCP/UDP proxying) | plugin `github.com/mholt/caddy-l4` |

### Example

```nginx
server {
    listen 443 ssl http2;
    server_name ha.example.org;
    ssl_certificate     /etc/letsencrypt/live/ha.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ha.example.org/privkey.pem;
    client_max_body_size 100m;

    location / {
        proxy_pass http://192.168.1.10:8123;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
server {
    listen 80;
    server_name ha.example.org;
    return 301 https://$host$request_uri;
}
```

becomes one entry in the app,

```yaml
- domain: ha.example.org
  type: proxy
  target: homeassistant:8123
  extra:
    - request_body {
    - max_size 100MB
    - }
```

or, in Caddyfile mode:

```caddyfile
ha.example.org {
	request_body {
		max_size 100MB
	}
	reverse_proxy homeassistant:8123
}
```

### Let the nginx adapter take a first look

An experimental adapter reads nginx configuration. It understands only part of nginx and writes Caddy's JSON format,
so treat its output as a hint, not as the result.

1. Add the plugin `github.com/caddyserver/nginx-adapter` to **Plugins** and restart; wait for the build.
2. Copy your `nginx.conf` into the `migrate` folder of the app's config folder (create the folder if needed).
3. Restart the app. It writes `nginx.converted.json` next to the file and logs every directive it could not convert.

Do not count on `include` lines being followed; paste the contents of included files into the file you copy.

## Apache → Caddy

There is no adapter for Apache; the translation is manual, but the building blocks are the same.

| Apache | Caddy |
| --- | --- |
| `<VirtualHost *:443>` with `ServerName a.org` and `ServerAlias b.org` | site address `a.org, b.org {` |
| `DocumentRoot /var/www/html` | `root * /var/www/html` and `file_server`, or site type **static** |
| `DirectoryIndex index.html` | default; `index.html` is served automatically |
| `Options +Indexes` | `file_server browse` (directory listing) |
| `ProxyPass / http://10.0.0.5:3000/` and `ProxyPassReverse` | `reverse_proxy 10.0.0.5:3000` |
| `ProxyPreserveHost On` | default behavior |
| `RewriteEngine On` and `RewriteRule ^/old/(.*)$ /new/$1 [R=301]` | `@old path_regexp old ^/old/(.*)$` then `redir @old /new/{re.old.1} permanent` |
| `Redirect permanent /old /new` | `redir /old /new permanent` |
| `SSLCertificateFile` / `SSLCertificateKeyFile` | `tls <cert> <key>`, or let Caddy obtain a certificate |
| `AuthType Basic`, `AuthUserFile`, `Require valid-user` | `basic_auth { user <hash> }`, or the **Username / Password** fields |
| `Require ip 192.168.0.0/16` | **Allowed networks**, or `@lan client_ip 192.168.0.0/16` |
| `Header set X-Frame-Options "SAMEORIGIN"` | `header X-Frame-Options SAMEORIGIN` |
| `ErrorDocument 404 /404.html` | `handle_errors { rewrite * /404.html` and `file_server }` |
| `AddOutputFilterByType DEFLATE …` | `encode zstd gzip` |
| `LimitRequestBody 104857600` | `request_body { max_size 100MB }` |
| `Alias /files /srv/files` | `handle_path /files/* { root * /srv/files` and `file_server }` |
| `mod_php` or `proxy_fcgi` to PHP-FPM | `php_fastcgi host:9000` (PHP itself keeps running in PHP-FPM) |
| `.htaccess` | not supported; move its rules into the site block |
| `mod_security` | plugin `github.com/corazawaf/coraza-caddy/v2` |

`caddy hash-password` produces bcrypt hashes; entries from an `.htpasswd` file that already use bcrypt (`$2y$…`) can be
reused as they are.

## Check your result

* Read `generated.Caddyfile` in the app's config folder to see exactly what the options produce.
* The log of the app prints the reason whenever Caddy rejects a line; an unknown directive usually means a plugin is
  missing from the list.
* `caddy fmt` (switch **Format Caddyfile**) keeps your own file tidy.
