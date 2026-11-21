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
# The developer footer is added to every page by a small script (see assets below), which
# a response rewrite hooks into the HTML.
# ==============================================================================

ADMIN_UI_PORT=8099
ADMIN_API_ADDRESS='localhost:2019'
: "${ADMIN_UI_ASSETS:=/usr/share/caddy-forge/admin-ui}"
ADMIN_UI_ASSET_PATH='/_forge'
# IPv4/IPv6 addresses, single-label names (homeassistant) and local suffixes; a rebinding attack needs a public name.
ADMIN_UI_HOST_PATTERN='^([0-9]{1,3}([.][0-9]{1,3}){3}|[0-9a-f:]+|localhost|[^.]+|.+[.](local|lan|home[.]arpa|internal|fritz[.]box))$'

adminui_enabled() {
  option_is_true .admin_ui.enabled
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
  # The footer's script and style sheet.
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
