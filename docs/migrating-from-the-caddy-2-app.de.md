# Umzug von der Caddy-2-App

Wenn du die App *Caddy 2* mit eigener `Caddyfile` betreibst, importiert Caddy Forge diese Datei für dich. Was sich aus einer
anderen App nicht lesen lässt (ihre Optionen), ist unten zugeordnet.

## Der kurze Weg

1. Die Caddy-2-App stoppen. Beide Apps wollen die Ports 80 und 443.
2. Caddy Forge installieren und den Modus auf **advanced (caddyfile)** stellen.
3. Starten. Hat der Konfigurationsordner der App noch keine `Caddyfile`, wird die der Caddy-2-App importiert, zusammen mit den
   kleinen Dateien daneben (Snippets, ein `www`-Ordner; bis zu 200 Dateien mit je 5 MB, die Caddy-Binary bleibt außen vor).
4. Das Log lesen. Es nennt, was noch zu tun ist:
   * **Umgebungsvariablen**, die die Caddyfile nutzt (`{$NAME}` oder `{env.NAME}`) und die hier noch fehlen. Unter
     *Umgebungsvariablen* eintragen; die Werte stehen in den Optionen der alten App und werden nicht kopiert.
   * **Plugins** aus der eigenen `caddy`-Binary der alten App. Jedes unter *Plugins* eintragen (`owner/repo` genügt); die App baut sie
     beim nächsten Start.
   * **Adressen auf `localhost`**. Die alte App lief im Host-Netzwerk, Home Assistant war dort `localhost:8123`. Das wird automatisch zu
     `homeassistant:8123`; andere Dienste auf `localhost` oder `127.0.0.1` brauchen ihre echte Adresse.
5. Seiten prüfen, dann die Caddy-2-App deinstallieren. Eine bereits vorhandene Caddyfile wird nie ersetzt.

Solange der Modus noch `simple` ist, weist das Log pro Start nur einmal darauf hin, dass ein Import möglich ist.

## Ohne Caddyfile

Die Caddy-2-App braucht keine Caddyfile, wenn nur ihre Optionen ausgefüllt sind. Diese Optionen lassen sich von hier aus nicht lesen,
trage sie also einmal ein:

| Caddy-2-App | Caddy Forge |
| --- | --- |
| `non_caddyfile_config.email` | **Einfacher Modus → E-Mail-Adresse** |
| `non_caddyfile_config.domain` | eine Seite mit dieser **Domain** |
| `non_caddyfile_config.destination` und `port` | das **Ziel** dieser Seite, für Home Assistant `homeassistant:8123` (nicht `localhost`) |
| `env_vars` | **Umgebungsvariablen** |
| `log_level` | **Log-Level** (`trace`/`debug` → debug, `info`/`notice` → info, `warning` → warn, `error`/`fatal` → error) |
| `caddy_fmt: true` | **Caddyfile formatieren** (erweiterter Modus) |
| `caddy_upgrade: true` und eigene Binary | **Plugins** plus **Caddy-Version** `latest` und **Update-Prüfung** `install` |
| `args: ["--watch"]` | nicht nötig; die App nach Änderungen neu starten |

## Was die App lesen darf

Um die Caddyfile zu finden, bindet die App die Konfigurationsordner aller Apps schreibgeschützt ein (`all_addon_configs`). Sie sieht nur
Ordner namens `*_caddy-2` oder `*_caddy_2` an und liest dort die Caddyfile, kleine Dateien daneben und die Plugin-Liste der
`caddy`-Binary (diese Binary wird einmal mit `list-modules` gestartet). Geschrieben wird dort nichts.
