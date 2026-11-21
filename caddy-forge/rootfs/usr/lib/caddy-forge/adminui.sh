#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# The admin UI: a web front end for Caddy's admin API (plugin caddy-admin-ui), opened from
# Home Assistant's sidebar through ingress. It is always on.
#
# * Only the Supervisor (the ingress gateway) may connect to its port; Home Assistant
#   authenticates the user. The plugin's built-in web shell is never switched on and its
#   endpoint is blocked.
# * The UI is a single-page app with absolute links. A response rewrite (plugin
#   replace-response) puts the ingress path in front of them, so it works below
#   /api/hassio_ingress/<token>/ as well as directly.
# * Nothing is written into your Caddyfile. The configuration Caddy reads is turned into
#   JSON in memory, the UI's server is added to it and, when the admin API is switched off,
#   it is switched on again at a private unix socket (see adminui_inject).
# * A small script adds the developer footer and the accent colour picker. Because the page
#   runs inside Home Assistant's frame, it can read Home Assistant's own primary colour.
# ==============================================================================

ADMIN_UI_PORT=5594
# The ingress gateway of the Supervisor; tests use another address.
: "${FORGE_INGRESS_IP:=172.30.32.2}"
: "${FORGE_RUN_DIR:=/run/caddy-forge}"
: "${ADMIN_UI_ASSETS:=/usr/share/caddy-forge/admin-ui}"
ADMIN_UI_ASSET_PATH='/_forge'
ADMIN_UI_DEFAULT_ACCENT='#4fc3f7'
: "${FORGE_HA_THEMES_DIR:=/homeassistant/themes}"
ADMIN_UI_COLOR_PATTERN='^(#[0-9a-fA-F]{3,8}|rgba?\([0-9., %]+\))$'
ADMIN_UI_PRESETS='[
  {"name": "Light blue", "color": "#4fc3f7"}, {"name": "Home Assistant", "color": "#03a9f4"}, {"name": "Teal", "color": "#009688"},
  {"name": "Green", "color": "#4caf50"}, {"name": "Amber", "color": "#ffc107"},
  {"name": "Orange", "color": "#ff9800"}, {"name": "Red", "color": "#f44336"},
  {"name": "Pink", "color": "#e91e63"}, {"name": "Purple", "color": "#9c27b0"},
  {"name": "Indigo", "color": "#3f51b5"}
]'
# Rewrites of the UI's responses (regular expressions, see adminui_generate). The first turns the link to the
# start page into /index (a path with a trailing slash would lose its prefix), the second puts the ingress
# path in front of the UI's own absolute paths in one pass, so nothing is prefixed twice.
ADMIN_UI_ROOT_LINK='(href=\\?"|href\\?":\\?")/(\\?")'
ADMIN_UI_PATHS='(["'"'"'])/(_next/|config/|load|adapt|reverse_proxy/upstreams|metrics|upstream|setup|monitor|shell|favicon|index)'
ADMIN_UI_PREFIX='{http.request.header.X-Ingress-Path}'

# The unix socket the admin API listens on unless the configuration chooses an address itself.
adminui_socket() {
  printf '%s/admin.sock' "$FORGE_RUN_DIR"
}

# Theme names and their primary colours from Home Assistant's themes folder, tab separated.
# A theme is a top-level key; its colour is the first `primary-color:` below it. Only plain
# colours are taken, values such as `var(--blue)` are skipped.
adminui_themes() {
  local file name color
  for file in "$FORGE_HA_THEMES_DIR"/*.yaml "$FORGE_HA_THEMES_DIR"/*.yml; do
    [[ -f $file ]] || continue
    while IFS=$'\t' read -r name color; do
      if [[ -n $name && $color =~ $ADMIN_UI_COLOR_PATTERN ]]; then
        printf '%s\t%s\n' "$name" "$color"
      fi
    done < <(awk '
      /^[^ \t#-][^:]*:[ \t]*(#.*)?$/ { name = $0; sub(/:[ \t]*(#.*)?$/, "", name); gsub(/^["\047]|["\047]$/, "", name); next }
      /^[ \t]+primary-color:/ && name != "" && !(name in seen) {
        value = $0; sub(/^[^:]*:[ \t]*/, "", value)
        if (match(value, /^"[^"]*"/) || match(value, /^\047[^\047]*\047/)) { value = substr(value, 2, RLENGTH - 2) }
        else { sub(/[ \t]+#.*$/, "", value); sub(/[ \t\r]+$/, "", value) }
        seen[name] = 1
        print name "\t" value
      }' "$file")
  done
}

# Writes the palette the page script offers: presets, the user's themes and the default accent.
adminui_write_palette() {
  local dir="$FORGE_DATA_DIR/admin-ui" themes
  mkdir -p "$dir"
  themes=$(adminui_themes | jq -Rn '[inputs | split("\t") | {name: .[0], color: .[1]}]')
  jq -n --arg default "$ADMIN_UI_DEFAULT_ACCENT" --argjson presets "$ADMIN_UI_PRESETS" --argjson themes "$themes" \
    '{default: $default, presets: $presets, themes: $themes}' >"$dir/palette.json"
}

# Where the admin API of an adapted configuration (JSON, first argument) listens: its own address, the
# default when it says nothing, or nothing (empty) when it is switched off.
adminui_admin_listen() {
  jq -r 'if (.admin.disabled // false) == true then "" else (.admin.listen // "localhost:2019") end' "$1"
}

# The address a reverse proxy dials for an admin listen address: `:2019` and `0.0.0.0:2019` mean the
# local machine, `unix//path` stays, a `tcp/` prefix goes.
adminui_upstream() {
  local listen=${1#tcp/}
  case "$listen" in
    unix/*) printf '%s' "$listen" ;;
    :*) printf 'localhost%s' "$listen" ;;
    0.0.0.0:* | \[::\]:*) printf 'localhost:%s' "${listen##*:}" ;;
    *) printf '%s' "$listen" ;;
  esac
}

# Prints the site block of the UI. <upstream> is where the admin API listens. Only the Supervisor may
# connect. Requests of the page itself (the browser marks them `Sec-Fetch-Site: same-origin`, which a web
# page cannot forge) lose the headers the admin API would measure against its own origin; anything else keeps
# them and is refused by the API.
adminui_generate() {
  local upstream=$1 host
  printf '# Caddy Forge: admin UI, reachable through Home Assistant only\n'
  printf 'http://:%s {\n' "$ADMIN_UI_PORT"
  printf '\t@ingress remote_ip %s\n' "$FORGE_INGRESS_IP"
  printf '\thandle @ingress {\n\t\troute {\n'
  printf '\t\t\t@pty path /ws/pty*\n\t\t\trespond @pty "Forbidden" 403\n'
  # The palette, generated on every start, and the page script with its style sheet.
  printf '\t\t\thandle %s/palette.json {\n\t\t\t\troot * %s/admin-ui\n\t\t\t\trewrite * /palette.json\n\t\t\t\tfile_server\n\t\t\t}\n' \
    "$ADMIN_UI_ASSET_PATH" "$FORGE_DATA_DIR"
  printf '\t\t\thandle_path %s/* {\n\t\t\t\troot * %s\n\t\t\t\tfile_server\n\t\t\t}\n' "$ADMIN_UI_ASSET_PATH" "$ADMIN_UI_ASSETS"
  printf '\t\t\t@samepage header Sec-Fetch-Site same-origin\n'
  printf '\t\t\trequest_header @samepage -Origin\n\t\t\trequest_header @samepage -Referer\n\t\t\trequest_header @samepage -Sec-Fetch-Mode\n'
  # Pages must arrive uncompressed and without validators so that the rewrite below is seen by browsers.
  printf '\t\t\trequest_header Accept-Encoding identity\n\t\t\theader -ETag\n\t\t\theader -Last-Modified\n'
  printf '\t\t\treplace {\n\t\t\t\tmatch {\n\t\t\t\t\theader Content-Type text/*\n\t\t\t\t}\n'
  # shellcheck disable=SC2016  # ${1} and ${2} are for the regular expression engine, not for the shell
  printf '\t\t\t\tre `%s` `${1}%s/index${2}`\n' "$ADMIN_UI_ROOT_LINK" "$ADMIN_UI_PREFIX"
  # shellcheck disable=SC2016
  printf '\t\t\t\tre `%s` `${1}%s/${2}`\n' "$ADMIN_UI_PATHS" "$ADMIN_UI_PREFIX"
  printf '\t\t\t\t</body> "<link rel=\\"stylesheet\\" href=\\"%s%s/footer.css\\"><script src=\\"%s%s/footer.js\\" defer></script></body>"\n\t\t\t}\n' \
    "$ADMIN_UI_PREFIX" "$ADMIN_UI_ASSET_PATH" "$ADMIN_UI_PREFIX" "$ADMIN_UI_ASSET_PATH"
  printf '\t\t\tcaddy_admin_ui\n'
  if [[ $upstream == unix/* ]]; then
    printf '\t\t\treverse_proxy %s\n' "$upstream"
  else
    # An admin API on a TCP address only answers requests that name it as host.
    host=$upstream
    printf '\t\t\treverse_proxy %s {\n\t\t\t\theader_up Host %s\n\t\t\t}\n' "$upstream" "$host"
  fi
  printf '\t\t}\n\t}\n'
  printf '\thandle {\n\t\trespond "Forbidden" 403\n\t}\n'
  printf '}\n'
}

# Adds the admin UI to an adapted configuration: <base.json> in, <out.json> out, using the Caddy binary
# in CADDY_BIN. The UI's server joins the configuration and, if the admin API is switched off (`admin off`),
# it is switched on at the private unix socket; an address the configuration chose itself is kept and used.
# The Caddyfile it came from is not touched.
adminui_inject() {
  local base=$1 out=$2 listen upstream block ui socket
  listen=$(adminui_admin_listen "$base")
  socket="unix/$(adminui_socket)"
  upstream=$(adminui_upstream "${listen:-$socket}")
  adminui_write_palette
  block="$FORGE_RUN_DIR/admin-ui.Caddyfile"
  ui="$FORGE_RUN_DIR/admin-ui.json"
  adminui_generate "$upstream" | caddyfile_format >"$block"
  "$CADDY_BIN" adapt --config "$block" --adapter caddyfile >"$ui" 2>/dev/null || return 1
  jq --slurpfile ui "$ui" --arg socket "$socket" '
    ($ui[0].apps.http.servers | to_entries[0].value) as $server
    | (if (.admin.disabled // false) == true then .admin = ((.admin // {}) | del(.disabled) | .listen = $socket) else . end)
    | .apps.http.servers.forge_admin_ui = $server' "$base" >"$out"
}
