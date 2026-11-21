# Caddy Forge

[🇬🇧 English](README.md) · **🇩🇪 Deutsch**

Caddy und seine Build-Werkstatt in einer einzigen Home-Assistant-App. Starte mit dem gepinnten Upstream-Release
oder trage die gewünschten Plugins ein: Die App kompiliert dann eine passende Binary, sucht bei jedem Start nach
neuen Releases und tauscht das Ergebnis erst aus, wenn es die Prüfung bestanden hat. Für die üblichen Fälle
brauchst du kein Caddyfile-Wissen; wenn das nicht reicht, gibt es einen vollwertigen Caddyfile-Modus.

## Highlights

- **Plugins als Liste.** Ein Go-Modul pro Zeile in der App-Konfiguration, optional mit `@version`.
  Zeilen aus einem xcaddy-Befehl (`--with …`) lassen sich einfach hineinkopieren.
- **Sichere Updates.** Gebaut wird in einem Arbeitsordner, die neue Binary muss deine Konfiguration verstehen,
  erst dann ersetzt ein einziges Umbenennen die alte. Ein fehlgeschlagener Build ändert nichts.
- **Update-Prüfung beim Start.** Für `latest` und für Plugins ohne feste Version: installieren, nur melden
  oder komplett offline bleiben.
- **Einfacher Modus.** Reverse Proxy, statische Dateien, Weiterleitungen, kostenlose Zertifikate (auch per DNS
  und als Wildcard), Login und Zugriffslisten als Formular statt als Caddyfile.
- **Websites aus Git.** Ein Seitentyp, der ein Repository ausliefert und aktuell hält; kein Plugin nötig.
- **Admin-Oberfläche.** Ein Schalter fügt eine Weboberfläche für Caddys Admin-API hinzu, nur aus privaten Netzen erreichbar.
- **Caddyfile-Modus.** Beim ersten Mal aus deinem einfachen Setup erzeugt, danach ganz deins. Eine Caddyfile der Caddy-2-App wird automatisch importiert.
- **Sofort startklar.** Das gepinnte Caddy-Release steckt im Image; die Go-Toolchain arbeitet nur, wenn wirklich
  gebaut werden muss.
- **Alle Architekturen:** amd64, aarch64, armv7, armhf und i386. Builds passen sich dem freien Speicher an und
  laufen mit niedriger Priorität.

## Loslegen

1. Dieses Repository im Home-Assistant-App-Store hinzufügen, **Caddy Forge** installieren und die Konfiguration öffnen.
2. Deine Domain in die Standard-Seite eintragen, den Zertifikatstyp wählen und die Ports 80 (die App lauscht auf Host-Port 8080) und 443 weiterleiten.
3. In den `http:`-Einstellungen von Home Assistant `use_x_forwarded_for` und `trusted_proxies` ergänzen.
4. App starten.

Eine Konfiguration mit Plugin, per DNS validiertem Wildcard-Zertifikat und zwei Seiten:

```yaml
mode: simple
caddy:
  version: 2.11.9
  modules:
    - module: hslatman/caddy-crowdsec-bouncer     # owner/repo wird auf github.com gesucht
      version: main                               # optional Tag, Branch oder Commit
    - module: mholt/caddy-l4
      enabled: false                              # bleibt erhalten, wird aber nicht mitgebaut
  updates: install
simple:
  email: du@example.org
  dns_provider: cloudflare        # fügt github.com/caddy-dns/cloudflare zum Build hinzu
  dns_token: !secret cloudflare_token
  sites:
    - domain: "*.example.org"
      type: proxy
      target: homeassistant:8123
    - domain: dateien.example.org
      type: static
      target: /share/www
      auth_user: familie
      auth_password: !secret dateien_passwort
```

Alle Optionen, das Update-Verhalten und die Fehlersuche stehen in der [App-Dokumentation](caddy-forge/DOCS.md)
(englisch). Dazu auf Deutsch:

- [Praxisbeispiele](docs/examples.de.md): private Homepage, Website aus Git, PHP und Single-Page-Apps, Wildcard-Zertifikate
- [Umzug von der Caddy-2-App](docs/migrating-from-the-caddy-2-app.de.md): automatischer Caddyfile-Import und Zuordnung ihrer Optionen
- [Umzug von nginx oder Apache](docs/migrating-from-nginx-and-apache.de.md): Direktiven-Tabellen und ein durchgespieltes Beispiel

## Ablauf beim Start

1. Die App liest die Optionen und erzeugt (einfacher Modus) oder lädt (Caddyfile-Modus) die Caddyfile.
2. Sie wählt die Binary: die mitgelieferte (gepinnter Standard, keine Plugins), einen passenden früheren Build
   oder einen neuen Build mit xcaddy.
3. Ein neuer Build ersetzt die laufende Binary nur, wenn er deine Caddyfile versteht. Sonst bleibt alles beim Alten.
4. Caddy startet, oder die App endet nach dem Build, wenn „Webserver starten“ ausgeschaltet ist.

## Entwicklung

Versionen folgen `YYYY.MM.DD`, weitere Builds am selben Tag erhalten `.1`, `.2` …. `version` in `config.yaml` und
`BUILD_VERSION` im `Dockerfile` werden gemeinsam erhöht, dazu kommt ein Eintrag im [Changelog](caddy-forge/CHANGELOG.md).
Die Caddy-Version im Options-Standard und `ARG CADDY_VERSION` im `Dockerfile` müssen dasselbe Upstream-Release nennen;
`.github/checks/app_consistency.py` prüft das.

Die Tests laufen im Image so wie in der Pipeline:

```bash
docker build --build-arg BUILD_ARCH=amd64 -t caddy-forge caddy-forge
docker run --rm --entrypoint /bin/bash \
  -v "$PWD/.github/tests/runtime.sh:/runtime.sh:ro" -v "$PWD/.github/tests:/tests:ro" \
  caddy-forge /runtime.sh        # FORGE_TEST_BUILD=0 überspringt den echten Build
```
