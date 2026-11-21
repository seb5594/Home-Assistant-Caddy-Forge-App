#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016  # the stand-in binary is a shell script written verbatim
# The optional admin UI and the nginx helper.

# Home Assistant themes as a user would have them in /config/themes.
make_themes() {
  mkdir -p "$TEST_TMP/themes"
  printf '%s\n' '# my themes' 'Ocean Blue:' '  primary-color: "#1e88e5"   # main' '  accent-color: "#ff9800"' \
    'Forest:' '  modes:' '    light:' "      primary-color: '#2e7d32'" '    dark:' '      primary-color: "#66bb6a"' \
    'Linked:' '  primary-color: var(--blue-color)' 'Plain:' '  primary-color: rgb(10, 20, 30)' >"$TEST_TMP/themes/themes.yaml"
  export FORGE_HA_THEMES_DIR="$TEST_TMP/themes"
}

test_accent() {
  use_clean_folders
  make_themes
  assert_equals $'Ocean Blue\t#1e88e5\nForest\t#2e7d32\nPlain\trgb(10, 20, 30)' "$(adminui_themes)" "accent: themes and their primary colours are read from Home Assistant's folder"

  adminui_write_palette
  local palette="$FORGE_DATA_DIR/admin-ui/palette.json"
  assert_equals "#4fc3f7" "$(jq -r .default "$palette")" "accent: a light blue is the default"
  assert_equals "Light blue" "$(jq -r '.presets[0].name' "$palette")" "accent: the default is also the first preset"
  assert_equals "3" "$(jq '.themes | length' "$palette")" "accent: the user's themes are part of the palette"
  assert_contains "$(adminui_generate localhost:2019)" "handle /_forge/palette.json" "accent: the palette is served next to the page script"
}

test_adminui() {
  use_clean_folders
  local output
  output=$(adminui_generate localhost:2019)
  assert_contains "$output" "http://:5594 {" "admin UI: it listens on its own port"
  assert_contains "$output" "@ingress remote_ip $FORGE_INGRESS_IP" "admin UI: only the ingress gateway of the Supervisor may connect"
  assert_contains "$output" 'respond "Forbidden" 403' "admin UI: everybody else is refused"
  assert_contains "$output" "caddy_admin_ui" "admin UI: the plugin's handler serves the pages"
  assert_contains "$output" "reverse_proxy localhost:2019" "admin UI: everything else goes to the admin API"
  assert_contains "$output" "header_up Host localhost:2019" "admin UI: an admin API on a TCP address is addressed by its name"
  assert_contains "$output" 'respond @pty "Forbidden" 403' "admin UI: the web shell endpoint is blocked"
  assert_contains "$output" "@start path /" "admin UI: the start page is chosen by a redirect"
  assert_contains "$output" "redir @start {http.request.header.X-Ingress-Path}/upstream 302" "admin UI: the panel opens on the upstream page, below the ingress path"
  assert_contains "$output" '"Caddy Admin" "Caddy Forge Admin"' "admin UI: the UI is renamed"
  assert_contains "$output" "@samepage header Sec-Fetch-Site same-origin" "admin UI: requests of the page itself are recognised"
  assert_contains "$output" "{http.request.header.X-Ingress-Path}" "admin UI: links get the ingress path of the request"
  assert_contains "$output" 'src=\"{http.request.header.X-Ingress-Path}/_forge/footer.js\"' "admin UI: pages are rewritten to load the footer script"
  assert_contains "$output" "match {" "admin UI: only some responses are rewritten"
  assert_contains "$output" "handle /_forge/palette.json" "admin UI: the palette is served next to the page script"
  assert_contains "$output" "root * $ADMIN_UI_ASSETS" "admin UI: the footer files are served from the image"
  assert_succeeds "admin UI: the footer files exist in the image" test -s "$ADMIN_UI_ASSETS/footer.js" -a -s "$ADMIN_UI_ASSETS/footer.css"
  assert_contains "$(cat "$ADMIN_UI_ASSETS/footer.css")" "#forge-footer { margin-top: auto;" "admin UI: the footer sits at the bottom of the window"
  assert_contains "$(cat "$ADMIN_UI_ASSETS/footer.js")" "config/apps/http'" "admin UI: the upstream page learns the sites and the ports from the configuration"
  assert_contains "$(cat "$ADMIN_UI_ASSETS/footer.js")" "Weitere Home-Assistant-Apps" "admin UI: the page speaks German as well"
  assert_contains "$(cat "$ADMIN_UI_ASSETS/footer.css")" "repeat(auto-fill, minmax(17rem, 1fr))" "admin UI: the upstream cards have the same size"
  assert_not_contains "$output" "basic_auth" "admin UI: no login of its own, Home Assistant does that"
  assert_not_contains "$output" "client_ip" "admin UI: no host name based checks"
  assert_not_contains "$(adminui_generate unix//run/x.sock)" "header_up" "admin UI: a unix socket needs no host header"
  assert_contains "$(adminui_generate unix//run/x.sock)" "reverse_proxy unix//run/x.sock" "admin UI: the admin socket is used as it is"
}

test_adminui_upstream() {
  use_clean_folders
  assert_equals "localhost:2019" "$(adminui_upstream localhost:2019)" "admin upstream: a named address stays"
  assert_equals "localhost:2020" "$(adminui_upstream :2020)" "admin upstream: only a port means this machine"
  assert_equals "localhost:2020" "$(adminui_upstream 0.0.0.0:2020)" "admin upstream: a wildcard address means this machine"
  assert_equals "localhost:2020" "$(adminui_upstream tcp/localhost:2020)" "admin upstream: the tcp prefix goes"
  assert_equals "unix//run/a.sock" "$(adminui_upstream unix//run/a.sock)" "admin upstream: a unix socket stays"

  printf '%s' '{"admin":{"disabled":true}}' >"$TEST_TMP/a.json"
  assert_equals "" "$(adminui_admin_listen "$TEST_TMP/a.json")" "admin listen: a switched off admin API has no address"
  printf '%s' '{"admin":{"listen":"localhost:2020"}}' >"$TEST_TMP/a.json"
  assert_equals "localhost:2020" "$(adminui_admin_listen "$TEST_TMP/a.json")" "admin listen: a chosen address is read"
  printf '%s' '{"apps":{}}' >"$TEST_TMP/a.json"
  assert_equals "localhost:2019" "$(adminui_admin_listen "$TEST_TMP/a.json")" "admin listen: the default address applies when nothing is set"
}

# Adapts a Caddyfile the way the app does and injects the admin UI; prints the resulting JSON.
inject_into() {
  local caddyfile=$1
  "$CADDY_BIN" adapt --config "$caddyfile" --adapter caddyfile >"$TEST_TMP/base.json" 2>/dev/null
  adminui_inject "$TEST_TMP/base.json" "$TEST_TMP/run.json" && cat "$TEST_TMP/run.json"
}

test_adminui_inject() {
  use_clean_folders
  CADDY_BIN="$FORGE_BUNDLED_CADDY"
  local caddyfile="$FORGE_CONFIG_DIR/Caddyfile" original result
  printf '{\n\tadmin off\n}\n\n:8080 {\n\trespond "ok"\n}\n' >"$caddyfile"
  original=$(cat "$caddyfile")
  result=$(inject_into "$caddyfile")
  assert_equals "forge_admin_ui" "$(jq -r '.apps.http.servers | keys[] | select(. == "forge_admin_ui")' <<<"$result")" "inject: the UI's server joins the configuration"
  assert_equals "$(adminui_socket)" "$(jq -r '.admin.listen' <<<"$result" | sed 's#^unix/##')" "inject: a switched off admin API is reachable at the private socket"
  assert_equals "null" "$(jq -r '.admin.disabled' <<<"$result")" "inject: the admin API is no longer disabled"
  assert_equals "2" "$(jq '.apps.http.servers | length' <<<"$result")" "inject: the server of the user stays"
  assert_equals "$original" "$(cat "$caddyfile")" "inject: your own Caddyfile is never modified"

  printf '{\n\tadmin localhost:2020\n}\n:8080 {\n\trespond "ok"\n}\n' >"$caddyfile"
  result=$(inject_into "$caddyfile")
  assert_equals "localhost:2020" "$(jq -r '.admin.listen' <<<"$result")" "inject: an admin address chosen by the user is kept"
  assert_contains "$(jq -r '.. | .dial? // empty' <<<"$result")" "localhost:2020" "inject: the UI talks to that address"

  printf ':8080 {\n\trespond "ok"\n}\n' >"$caddyfile"
  result=$(inject_into "$caddyfile")
  assert_equals "null" "$(jq -r '.admin.listen' <<<"$result")" "inject: the default admin API is left alone"
  assert_contains "$(jq -r '.. | .dial? // empty' <<<"$result")" "localhost:2019" "inject: the UI talks to the default admin address"
  assert_equals "forge_admin_ui" "$(jq -r '.apps.http.servers | keys[] | select(. == "forge_admin_ui")' <<<"$result")" "inject: also works for a plain site"
  assert_succeeds "inject: Caddy accepts the result" "$CADDY_BIN" validate --config "$TEST_TMP/run.json"
}

# A stand-in for Caddy with the nginx adapter: it prints JSON and one warning.
make_adapter_binary() {
  printf '#!/bin/sh\ncase "$1" in\n  list-modules) echo caddy.adapters.nginx ;;\n  adapt) echo "unknown directive: gzip_vary" >&2; echo "{\\"apps\\":{}}" ;;\nesac\n' >"$1"
  chmod +x "$1"
}

test_migrate() {
  use_clean_folders
  mkdir -p "$FORGE_CONFIG_DIR/migrate"
  CADDY_BIN="$FORGE_BUNDLED_CADDY"
  assert_succeeds "migrate: nothing happens without a nginx.conf" migrate_nginx

  printf 'server { listen 80; }\n' >"$FORGE_CONFIG_DIR/migrate/nginx.conf"
  assert_contains "$(migrate_nginx 2>&1)" "no nginx adapter" "migrate: a missing adapter plugin is explained"

  CADDY_BIN="$TEST_TMP/caddy-with-adapter"
  make_adapter_binary "$CADDY_BIN"
  local output
  output=$(migrate_nginx 2>&1)
  assert_contains "$(cat "$FORGE_CONFIG_DIR/migrate/nginx.converted.json")" '"apps"' "migrate: the converted configuration is written"
  assert_contains "$output" "unknown directive: gzip_vary" "migrate: what the adapter could not convert is reported"
}
