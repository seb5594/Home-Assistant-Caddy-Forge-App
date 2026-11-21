# Umzug von der Caddy-2- und der CaddyBuilder-App

Viele Setups nutzen zwei Apps: *CaddyBuilder* kompiliert ein Caddy mit Plugins, *Caddy 2* führt es aus. Caddy Forge macht beides und
kann übernehmen, was die beiden Apps wissen: Plugins und Caddy-Version aus dem Build-Befehl sowie die Caddyfile. Was sich aus einer
anderen App nicht lesen lässt (ihre Optionen), ist unten zugeordnet.

## Ein Schalter: übernehmen

1. Beide alten Apps installiert lassen (gestoppt genügt); die App liest deren Konfigurationsordner.
2. In Caddy Forge **Caddy-2- und CaddyBuilder-App übernehmen** einschalten und die App starten.
3. Sie liest
   * den Build-Befehl von CaddyBuilder (`xcaddyCommand.sh`): die **Caddy-Version** und jedes `--with`-Plugin als Eintrag unter
     *Plugins*, mit festem Tag, Branch oder Commit im Feld *Version*. Auskommentierte Zeilen deines Skripts werden zu Einträgen, die
     *ausgeschaltet* sind; nichts geht verloren und nichts Ungewolltes wird gebaut;
   * die Caddyfile von Caddy 2, wodurch der **Modus** auf `advanced (caddyfile)` wechselt (sie wird beim nächsten Start importiert, siehe unten);
     gibt es keinen Build-Befehl, werden die Plugins der eigenen `caddy`-Binary von Caddy 2 genommen;
   * die Namen der **Umgebungsvariablen**, die diese Caddyfile nutzt; sie werden leer angelegt, damit du die Werte einträgst.
4. Die App speichert das Ergebnis in ihren eigenen Optionen, schaltet **übernehmen** wieder aus und startet neu. Bereits vorhandene Einträge und
   Einstellungen bleiben; die Caddy-Version ändert sich nur, solange sie noch dem mitgelieferten Standard entspricht.
5. Optionen prüfen, Werte der Umgebungsvariablen eintragen, die alten Apps stoppen und deinstallieren.

Dein eigenes `xcaddyCommand.sh` sieht etwa so aus und wird zu den Einträgen rechts:

| Zeile | Eintrag |
| --- | --- |
| `xcaddy build latest \` | Caddy-Version `latest` |
| `--with github.com/caddy-dns/cloudflare \` | `github.com/caddy-dns/cloudflare`, an |
| `#  --with github.com/mholt/caddy-l4@ef01c22 #@31ae08c` | `github.com/mholt/caddy-l4`, Version `ef01c22`, **aus** |
| `# v2.9.1`, `# latest` | ignoriert (kein `--with`) |

Dafür braucht die App die Supervisor-API (`hassio_api`, nur für ihre eigenen Optionen und ihren eigenen Neustart).

### Ältere Home-Assistant-Versionen

Die App fragt die Konfigurationsordner aller Apps mit dem Map-Typ `all_addon_configs` an, den jede Home-Assistant-Version seit seiner
Einführung versteht und den neuere weiter akzeptieren (dort heißt er `all_app_configs` und wird unter `/app_configs` statt
`/addon_configs` eingebunden). Die App schaut an beiden Stellen nach und läuft deshalb auf alten wie neuen Versionen.

## Der kurze Weg, nur die Caddyfile

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
