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
# ==============================================================================

ADMIN_UI_PORT=8099
ADMIN_API_ADDRESS='localhost:2019'

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
  # The admin API refuses requests from foreign origins; only the UI's own origin is let through.
  printf '\t\t\t@sameorigin expression {http.request.header.Origin} == "http://" + {http.request.hostport}\n'
  printf '\t\t\trequest_header @sameorigin -Origin\n'
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
