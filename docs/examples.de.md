# Praxisbeispiele

Jedes Beispiel ist ein Eintrag unter **Einfacher Modus → Seiten** (als YAML dargestellt, so wie ihn der
Konfigurationseditor der App speichert). Du kannst beliebig viele anlegen; sie laufen nebeneinander.

## 1. Home Assistant auf der eigenen Domain

```yaml
- domain: ha.example.org
  type: proxy
  target: localhost:8123
```

E-Mail-Adresse im einfachen Modus setzen, Ports 80 (auf 8080, wo die App lauscht) und 443 weiterleiten und `trusted_proxies` in Home Assistant
ergänzen (siehe App-Dokumentation). Das Zertifikat wird automatisch angefordert und erneuert.

## 2. Eine private Homepage für dich oder die Familie

Ein Ordner mit einer `index.html` genügt. Lege die Dateien in `/share/www` (erreichbar über die *Samba-Freigabe*
oder die *File-Editor*-App) und liefere sie mit Login aus:

```yaml
- domain: home.example.org
  type: static
  target: /share/www
  auth_user: familie
  auth_password: !secret homepage_passwort
```

`/media` eignet sich für Fotogalerien, `/homeassistant/www` teilt den `www`-Ordner von Home Assistant unter
deiner eigenen Domain. Nur fürs lokale Netz? Ergänze `allow_from: [192.168.0.0/16]` und stelle das Zertifikat auf
`internal`.

## 3. Eine Website, die sich selbst aus Git aktualisiert

Der Typ `git` hält einen flachen Klon eines Repositorys und holt neue Commits ab; veröffentlichen heißt also *pushen*:

```yaml
- domain: docs.example.org
  type: git
  target: https://github.com/du/deine-seite.git
  branch: gh-pages          # optional, sonst der Standard-Branch
  folder: public            # optionaler Unterordner, z. B. die Ausgabe eines Generators
  refresh: 15               # Minuten, 0 = nur beim Start der App
```

Typische Quellen: ein Hugo-, MkDocs-, Jekyll- oder Astro-Projekt, dessen CI die fertige Seite in einen
`gh-pages`-Branch pusht, oder ein Repository mit einer handgeschriebenen Seite. Private Repositories funktionieren
mit einem Token in der URL (`https://du:TOKEN@github.com/du/privat.git`); lege die ganze URL in die `secrets.yaml` von
Home Assistant und schreibe `target: !secret seiten_repository`. Zugangsdaten werden im App-Log verborgen, der
`.git`-Ordner wird nie ausgeliefert.

## 4. Und dynamische Seiten, PHP und Co.?

Caddy liefert Dateien aus und leitet Anfragen weiter; Anwendungscode führt er nicht selbst aus. Das deckt trotzdem viel ab:

| Du hast | Nimm |
| --- | --- |
| Statische Seiten, Dokumentation, eine Startseite | Typ `static` oder `git` |
| Eine Single-Page-App (Vue, React, Svelte …) | Typ `static` oder `git` plus die zusätzliche Direktive `try_files {path} /index.html` |
| Einen Dienst mit eigenem Webserver (Node, Go, Python, Container) | Typ `proxy` |
| PHP (WordPress, Nextcloud, kleine Skripte) | PHP-FPM in eigenem Container oder eigener App betreiben und anbinden, siehe unten |

PHP über PHP-FPM, mit den zusätzlichen Direktiven einer `static`-Seite (eine Zeile pro Eintrag):

```yaml
- domain: blog.example.org
  type: static
  target: /share/blog
  extra:
    - php_fastcgi 192.168.1.20:9000 {
    - root /var/www/html
    - }
```

`target` ist der Ordner, wie Caddy ihn sieht, `root` dieselben Dateien aus Sicht von PHP-FPM. FrankenPHP, die
Caddy-Variante mit eingebautem PHP, braucht eine C-Toolchain und PHP-Bibliotheken und lässt sich deshalb mit dieser App
nicht bauen.

## 5. Viele Dienste, ein Wildcard-Zertifikat

```yaml
simple:
  dns_provider: cloudflare
  dns_token: !secret cloudflare_token
  sites:
    - domain: ha.example.org
      type: proxy
      target: localhost:8123
    - domain: nas.example.org
      type: proxy
      target: https://192.168.1.5:5001
      skip_verify: true
    - domain: "*.lan.example.org"
      type: proxy
      target: 192.168.1.30:8080
```

Die DNS-Validierung braucht keinen offenen Port 80 und funktioniert auch für rein lokale Namen, die du auf eine
private Adresse zeigen lässt.

## 6. Etwas im Haus behalten

```yaml
- domain: grafana.example.org
  type: proxy
  target: 192.168.1.40:3000
  allow_from:
    - 192.168.0.0/16
    - 172.30.32.0/23
  auth_user: admin
  auth_password: !secret grafana_proxy_passwort
```

Wer nicht aus den genannten Netzen kommt, bekommt nur „Forbidden“; im Netz wird zusätzlich das Login verlangt.

## 7. Caddy selbst ansehen: die Admin-Oberfläche

Aktiviere **Admin-Oberfläche** in der Konfiguration. Die App nimmt das Plugin
[`caddy-admin-ui`](https://github.com/gsmlg-dev/caddy-admin-ui) in den nächsten Build auf und liefert es auf Port
**5594** aus (dann auf der App-Seite *Web-UI öffnen* nutzen). Du siehst die laufende
Konfiguration, Upstreams und Metriken; Änderungen dort leben nur im Speicher bis zum nächsten Start, die Optionen bleiben
die maßgebliche Quelle.

Farben: Die Oberfläche startet in einem hellen Blau; Besucher wählen im Seitenfuß ihre eigene Farbe aus der Palette. Öffne sie über die IP-Adresse oder einen lokalen Namen, z. B. `homeassistant.local:5594`. Zur Absicherung: Nur private Netze dürfen zugreifen, ein Login lässt sich ergänzen, Anfragen von fremden Webseiten werden
abgewiesen, und die eingebaute Web-Shell des Plugins bleibt aus, ihr Endpunkt ist gesperrt. Die Oberfläche ist eine
Single-Page-App mit absoluten Links, darum gibt es sie auf einem eigenen Port und nicht in der Seitenleiste von Home
Assistant (Ingress).
