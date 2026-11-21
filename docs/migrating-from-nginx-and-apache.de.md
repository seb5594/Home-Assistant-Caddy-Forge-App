# Umzug von nginx oder Apache

Caddy erledigt das meiste, was ein typisches nginx- oder Apache-Setup tut, mit deutlich weniger Zeilen: HTTPS-Zertifikate
werden automatisch geholt und erneuert, HTTP wird auf HTTPS umgeleitet, WebSockets und die üblichen Proxy-Header
funktionieren einfach. Schreibe einen virtuellen Host nach dem anderen neu, statt die ganze Datei zu übersetzen.

## Vorgehen

1. **Bestandsaufnahme.** Liste jeden `server` (nginx) oder `VirtualHost` (Apache) auf: Domains, was ausgeliefert oder
   weitergeleitet wird und alles Besondere (Logins, erlaubte Netze, Rewrites, Upload-Limits).
2. **Ein Seiteneintrag pro Host.** Die meisten Hosts passen in die Liste **Seiten** der App (Domain, Typ, Ziel, Zertifikat,
   Login, erlaubte Netze). Besondere Zeilen kommen in die **Zusätzlichen Direktiven** der Seite, eine Caddyfile-Zeile pro Eintrag.
3. **Mit der Staging-Zertifizierungsstelle testen** (`Zertifizierungsstelle: staging`), bis alles antwortet, danach auf `auto` stellen.
4. **Umschalten.** Alten Server stoppen, die Router-Ports 80 (auf den Host-Port 8080 der App) und 443 auf Home Assistant richten und die App starten.
   Certbot-Cronjobs und Erneuerungs-Hooks löschen; das übernimmt Caddy.

Braucht ein Host mehr, als das Formular bietet, stelle den Modus auf `advanced (caddyfile)` und schreibe die Caddyfile direkt: Die
Tabellen unten sind genau dieses Vokabular.

## nginx → Caddy

| nginx | Caddy |
| --- | --- |
| `server_name a.org b.org;` | Seitenadresse `a.org, b.org {` (das Feld **Domain** akzeptiert Kommas) |
| `listen 443 ssl http2;` | nicht nötig, HTTPS ist automatisch; ein anderer Port gehört in die Adresse (`a.org:8443`) |
| `ssl_certificate x; ssl_certificate_key y;` | `tls x y` oder **Zertifikat: custom** für `/ssl/fullchain.pem` und `/ssl/privkey.pem` |
| `return 301 https://$host$request_uri;` | `redir https://{host}{uri} permanent` (reines HTTP wird automatisch umgeleitet) |
| `root /var/www; index index.html;` | `root * /var/www` und `file_server` oder Seitentyp **static** |
| `try_files $uri $uri/ /index.html;` | `try_files {path} {path}/ /index.html` (zusätzliche Direktive) |
| `location /api/ { proxy_pass http://10.0.0.5:3000; }` | `handle /api/* { reverse_proxy 10.0.0.5:3000 }` |
| `location /app/ { proxy_pass http://10.0.0.5:3000/; }` (Präfix entfernt) | `handle_path /app/* { reverse_proxy 10.0.0.5:3000 }` |
| `proxy_set_header Host $host;` und `X-Forwarded-*` | Standardverhalten; weitere Header mit `header_up Name Wert` in `reverse_proxy` |
| `proxy_http_version 1.1;` plus `Upgrade`/`Connection`-Header | WebSockets funktionieren ohne Zutun |
| `proxy_read_timeout 300s;` | `reverse_proxy … { transport http { read_timeout 5m } }` |
| `upstream app { server a:1; server b:1; }` | `reverse_proxy a:1 b:1 { lb_policy round_robin }` |
| `auth_basic "x"; auth_basic_user_file f;` | `basic_auth { user <hash> }` oder die Felder **Benutzername / Passwort** (bcrypt-Hashes aus htpasswd funktionieren) |
| `allow 192.168.0.0/16; deny all;` | **Erlaubte Netze** oder `@lan client_ip 192.168.0.0/16` mit einem Block `handle @lan { … }` |
| `gzip on;` | `encode zstd gzip` (der Schalter **Komprimierung**) |
| `add_header X-Frame-Options SAMEORIGIN;` | `header X-Frame-Options SAMEORIGIN` |
| `client_max_body_size 100m;` | `request_body { max_size 100MB }` |
| `rewrite ^/old/(.*)$ /new/$1 permanent;` | `@old path_regexp old ^/old/(.*)$`, dann `redir @old /new/{re.old.1} permanent` |
| `fastcgi_pass 127.0.0.1:9000;` | `php_fastcgi 127.0.0.1:9000` |
| `error_page 404 /404.html;` | `handle_errors { rewrite * /404.html` und `file_server }` |
| `access_log /var/log/x;` | `log` (der Schalter **Zugriffslog**) |
| `limit_req_zone …` | Plugin `github.com/mholt/caddy-ratelimit` |
| `stream { … }` (TCP/UDP-Proxy) | Plugin `github.com/mholt/caddy-l4` |

### Beispiel

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

wird zu einem Eintrag in der App,

```yaml
- domain: ha.example.org
  type: proxy
  target: homeassistant:8123
  extra:
    - request_body {
    - max_size 100MB
    - }
```

oder im Caddyfile-Modus:

```caddyfile
ha.example.org {
	request_body {
		max_size 100MB
	}
	reverse_proxy homeassistant:8123
}
```

### Den nginx-Adapter einen ersten Blick werfen lassen

Ein experimenteller Adapter liest nginx-Konfigurationen. Er versteht nur einen Teil von nginx und schreibt Caddys
JSON-Format; behandle das Ergebnis als Hinweis, nicht als Resultat.

1. Das Plugin `github.com/caddyserver/nginx-adapter` unter **Plugins** eintragen, neu starten und den Build abwarten.
2. Deine `nginx.conf` in den Ordner `migrate` im Konfigurationsordner der App kopieren (Ordner bei Bedarf anlegen).
3. App neu starten. Sie schreibt `nginx.converted.json` neben die Datei und meldet jede Direktive, die sie nicht umwandeln konnte.

Verlass dich nicht darauf, dass `include`-Zeilen verfolgt werden; füge den Inhalt eingebundener Dateien in die kopierte Datei ein.

## Apache → Caddy

Für Apache gibt es keinen Adapter; die Übersetzung erfolgt von Hand, die Bausteine sind aber dieselben.

| Apache | Caddy |
| --- | --- |
| `<VirtualHost *:443>` mit `ServerName a.org` und `ServerAlias b.org` | Seitenadresse `a.org, b.org {` |
| `DocumentRoot /var/www/html` | `root * /var/www/html` und `file_server` oder Seitentyp **static** |
| `DirectoryIndex index.html` | Standard; `index.html` wird automatisch ausgeliefert |
| `Options +Indexes` | `file_server browse` (Verzeichnisliste) |
| `ProxyPass / http://10.0.0.5:3000/` und `ProxyPassReverse` | `reverse_proxy 10.0.0.5:3000` |
| `ProxyPreserveHost On` | Standardverhalten |
| `RewriteEngine On` und `RewriteRule ^/old/(.*)$ /new/$1 [R=301]` | `@old path_regexp old ^/old/(.*)$`, dann `redir @old /new/{re.old.1} permanent` |
| `Redirect permanent /old /new` | `redir /old /new permanent` |
| `SSLCertificateFile` / `SSLCertificateKeyFile` | `tls <cert> <key>` oder Zertifikat automatisch von Caddy holen lassen |
| `AuthType Basic`, `AuthUserFile`, `Require valid-user` | `basic_auth { user <hash> }` oder die Felder **Benutzername / Passwort** |
| `Require ip 192.168.0.0/16` | **Erlaubte Netze** oder `@lan client_ip 192.168.0.0/16` |
| `Header set X-Frame-Options "SAMEORIGIN"` | `header X-Frame-Options SAMEORIGIN` |
| `ErrorDocument 404 /404.html` | `handle_errors { rewrite * /404.html` und `file_server }` |
| `AddOutputFilterByType DEFLATE …` | `encode zstd gzip` |
| `LimitRequestBody 104857600` | `request_body { max_size 100MB }` |
| `Alias /files /srv/files` | `handle_path /files/* { root * /srv/files` und `file_server }` |
| `mod_php` oder `proxy_fcgi` zu PHP-FPM | `php_fastcgi host:9000` (PHP selbst läuft weiter in PHP-FPM) |
| `.htaccess` | nicht unterstützt; die Regeln gehören in den Seitenblock |
| `mod_security` | Plugin `github.com/corazawaf/coraza-caddy/v2` |

`caddy hash-password` erzeugt bcrypt-Hashes; Einträge einer `.htpasswd`, die bereits bcrypt (`$2y$…`) nutzen, lassen sich
unverändert weiterverwenden.

## Ergebnis prüfen

* `generated.Caddyfile` im Konfigurationsordner der App zeigt genau, was die Optionen erzeugen.
* Das App-Log nennt den Grund, wenn Caddy eine Zeile ablehnt; eine unbekannte Direktive heißt meist, dass ein Plugin in der Liste fehlt.
* `caddy fmt` (Schalter **Caddyfile formatieren**) hält deine eigene Datei aufgeräumt.
