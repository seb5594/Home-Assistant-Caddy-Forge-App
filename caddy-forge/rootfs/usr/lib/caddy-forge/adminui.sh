#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Optional admin UI: a web front end for Caddy's admin API (plugin caddy-admin-ui).
#
# It is a single-page app that links to absolute paths, so it cannot live below
# Home Assistant's ingress prefix. It gets its own port instead, which the app
# page offers as "Open Web UI" once the port is enabled in the network settings.
# Only private networks may connect, an optional login adds a second barrier, and
# the plugin's built-in web shell is never switched on and its endpoint is blocked.
# The developer footer and the accent colour picker are added to every page by a small script
# (see the assets), which a response rewrite hooks into the HTML.
#
# Accent colour: Home Assistant keeps a user's theme in the browser's local storage, which a page on
# another port cannot read. The script therefore offers a palette and picks a default in this order:
# the visitor's own choice, `?accent=` in the address, the colour of the surrounding Home Assistant page
# when embedded in it, the `accent` option (a colour or the name of a Home Assistant theme), Home
# Assistant blue.
# ==============================================================================

ADMIN_UI_PORT=8099
ADMIN_API_ADDRESS='localhost:2019'
: "${ADMIN_UI_ASSETS:=/usr/share/caddy-forge/admin-ui}"
ADMIN_UI_ASSET_PATH='/_forge'
: "${FORGE_HA_THEMES_DIR:=/homeassistant/themes}"
ADMIN_UI_COLOR_PATTERN='^(#[0-9a-fA-F]{3,8}|rgba?\([0-9., %]+\))$'
ADMIN_UI_PRESETS='[
  {"name": "Home Assistant", "color": "#03a9f4"}, {"name": "Teal", "color": "#009688"},
  {"name": "Green", "color": "#4caf50"}, {"name": "Amber", "color": "#ffc107"},
  {"name": "Orange", "color": "#ff9800"}, {"name": "Red", "color": "#f44336"},
  {"name": "Pink", "color": "#e91e63"}, {"name": "Purple", "color": "#9c27b0"},
  {"name": "Indigo", "color": "#3f51b5"}
]'
# IPv4/IPv6 addresses, single-label names (homeassistant) and local suffixes; a rebinding attack needs a public name.
ADMIN_UI_HOST_PATTERN='^([0-9]{1,3}([.][0-9]{1,3}){3}|[0-9a-f:]+|localhost|[^.]+|.+[.](local|lan|home[.]arpa|internal|fritz[.]box))$'

adminui_enabled() {
  option_is_true .admin_ui.enabled
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

# The accent from the `accent` option: a colour as it is, or the colour of the named Home Assistant theme.
adminui_default_accent() {
  local accent name color
  accent=$(option .admin_ui.accent)
  [[ -n $accent ]] || return 0
  if [[ $accent =~ $ADMIN_UI_COLOR_PATTERN ]]; then
    printf '%s' "$accent"
    return 0
  fi
  while IFS=$'\t' read -r name color; do
    if [[ ${name,,} == "${accent,,}" ]]; then
      printf '%s' "$color"
      return 0
    fi
  done < <(adminui_themes)
  log_warn "Admin UI accent '$accent' is neither a colour nor a theme found in $FORGE_HA_THEMES_DIR."
}

# Writes the palette the page script offers: presets, the user's themes and the default accent.
adminui_write_palette() {
  local dir="$FORGE_DATA_DIR/admin-ui" themes
  mkdir -p "$dir"
  themes=$(adminui_themes | jq -Rn '[inputs | split("\t") | {name: .[0], color: .[1]}]')
  jq -n --arg default "$(adminui_default_accent)" --argjson presets "$ADMIN_UI_PRESETS" --argjson themes "$themes" \
    '{default: (if $default == "" then null else $default end), presets: $presets, themes: $themes}' >"$dir/palette.json"
}

# Prints the site block that serves the UI and forwards the rest to the admin API.
adminui_generate() {
  local user password
  user=$(option .admin_ui.user)
  password=$(option .admin_ui.password)

  printf '# Caddy Forge: admin UI for private networks\n'
  printf 'http://:%s {\n' "$ADMIN_UI_PORT"
  printf '\t@private client_ip private_ranges\n'
  printf '\thandle @private {\n'
  if [[ -n $user && -n $password ]]; then
    printf '\t\tbasic_auth {\n\t\t\t"%s" %s\n\t\t}\n' "$user" "$(caddyfile_password_hash "$password")"
  fi
  printf '\t\troute {\n'
  printf '\t\t\t@pty path /ws/pty*\n\t\t\trespond @pty "Forbidden" 403\n'
  printf '\t\t\t@badhost expression !({http.request.host}.matches("%s"))\n' "$ADMIN_UI_HOST_PATTERN"
  printf '\t\t\trespond @badhost "Forbidden" 403\n'
  # The palette, generated on every start, and the page script with its style sheet.
  printf '\t\t\thandle %s/palette.json {\n\t\t\t\troot * %s/admin-ui\n\t\t\t\trewrite * /palette.json\n\t\t\t\tfile_server\n\t\t\t}\n' \
    "$ADMIN_UI_ASSET_PATH" "$FORGE_DATA_DIR"
  printf '\t\t\thandle_path %s/* {\n\t\t\t\troot * %s\n\t\t\t\tfile_server\n\t\t\t}\n' "$ADMIN_UI_ASSET_PATH" "$ADMIN_UI_ASSETS"
  # The admin API only talks to its own origin and checks the Host header against DNS rebinding. Both
  # checks are lost behind a proxy, so they are redone here: only plain addresses and local names are
  # accepted as Host, and only requests of this very page (the browser marks them `Sec-Fetch-Site:
  # same-origin`, which a web page cannot forge) get the origin the admin API expects.
  printf '\t\t\t@samepage expression {http.request.header.Sec-Fetch-Site} == "same-origin" || {http.request.header.Origin} == "http://" + {http.request.hostport}\n'
  printf '\t\t\trequest_header @samepage Origin http://%s\n\t\t\trequest_header @samepage -Referer\n' "$ADMIN_API_ADDRESS"
  # Pages must arrive uncompressed and without validators so that the rewrite below is seen by browsers.
  printf '\t\t\trequest_header Accept-Encoding identity\n\t\t\theader -ETag\n\t\t\theader -Last-Modified\n'
  printf '\t\t\treplace {\n\t\t\t\tmatch {\n\t\t\t\t\theader Content-Type text/html*\n\t\t\t\t}\n'
  printf '\t\t\t\t</body> "<link rel=\\"stylesheet\\" href=\\"%s/footer.css\\"><script src=\\"%s/footer.js\\" defer></script></body>"\n\t\t\t}\n' \
    "$ADMIN_UI_ASSET_PATH" "$ADMIN_UI_ASSET_PATH"
  printf '\t\t\tcaddy_admin_ui\n'
  printf '\t\t\treverse_proxy %s {\n\t\t\t\theader_up Host %s\n\t\t\t}\n' "$ADMIN_API_ADDRESS" "$ADMIN_API_ADDRESS"
  printf '\t\t}\n\t}\n'
  printf '\thandle {\n\t\trespond "Forbidden" 403\n\t}\n'
  printf '}\n'
}

# Writes the admin UI block and a small Caddyfile that loads <base> followed by it.
# Prints the path of the Caddyfile to run. The user's own file stays untouched.
adminui_compose() {
  local base=$1 block="$FORGE_DATA_DIR/admin-ui.Caddyfile" combined="$FORGE_DATA_DIR/run.Caddyfile"
  adminui_write_palette
  adminui_generate | caddyfile_format >"$block"
  {
    printf '# Assembled by Caddy Forge on every start.\n'
    printf 'import %s\nimport %s\n' "$base" "$block"
  } >"$combined"
  printf '%s' "$combined"
}

# The admin UI talks to the admin API at its default address.
adminui_check_admin_api() {
  local base=$1
  if grep -Eq '^[[:space:]]*admin[[:space:]]' "$base"; then
    log_warn "Your Caddyfile configures the admin endpoint; the admin UI expects $ADMIN_API_ADDRESS and may not work."
  fi
}
