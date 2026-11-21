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
  assert_contains "$(adminui_generate)" "handle /_forge/palette.json" "accent: the palette is served next to the page script"
}

test_adminui() {
  use_clean_folders
  use_options '.admin_ui.enabled = true'
  local output
  output=$(adminui_generate)
  assert_contains "$output" "http://:5594 {" "admin UI: it listens on its own port"
  assert_contains "$output" "client_ip private_ranges" "admin UI: only private networks may connect"
  assert_contains "$output" "caddy_admin_ui" "admin UI: the plugin's handler serves the pages"
  assert_contains "$output" "reverse_proxy localhost:2019" "admin UI: everything else goes to the admin API"
  assert_contains "$output" 'respond @pty "Forbidden" 403' "admin UI: the web shell endpoint is blocked"
  assert_contains "$output" "respond @badhost" "admin UI: public host names are refused (DNS rebinding)"
  assert_contains "$output" "@samepage expression" "admin UI: requests of the page itself are recognised"
  assert_contains "$output" 'src=\"/_forge/footer.js\"' "admin UI: pages are rewritten to load the footer script"
  assert_contains "$output" "header Content-Type text/html*" "admin UI: only HTML pages are rewritten"
  assert_contains "$output" "root * $ADMIN_UI_ASSETS" "admin UI: the footer files are served from the image"
  assert_succeeds "admin UI: the footer files exist in the image" test -s "$ADMIN_UI_ASSETS/footer.js" -a -s "$ADMIN_UI_ASSETS/footer.css"
  assert_not_contains "$output" "basic_auth" "admin UI: no login unless one is configured"

  use_options '.admin_ui.enabled = true | .admin_ui.user = "root" | .admin_ui.password = "secret"'
  output=$(adminui_generate)
  assert_contains "$output" 'basic_auth {' "admin UI: a configured login is required"
  assert_not_contains "$output" "secret" "admin UI: the plain password never reaches the file"

  printf ':8080 {\n\trespond "ok"\n}\n' >"$FORGE_CONFIG_DIR/Caddyfile"
  local combined original
  original=$(cat "$FORGE_CONFIG_DIR/Caddyfile")
  combined=$(adminui_compose "$FORGE_CONFIG_DIR/Caddyfile")
  assert_contains "$(cat "$combined")" "import $FORGE_CONFIG_DIR/Caddyfile" "admin UI: the combined file loads your Caddyfile first"
  assert_contains "$(cat "$FORGE_DATA_DIR/admin-ui.Caddyfile")" "caddy_admin_ui" "admin UI: followed by the generated block"
  assert_equals "$original" "$(cat "$FORGE_CONFIG_DIR/Caddyfile")" "admin UI: your own Caddyfile is never modified"

  printf '{\n\tadmin :2020\n}\n' >"$FORGE_CONFIG_DIR/Caddyfile"
  assert_contains "$(adminui_check_admin_api "$FORGE_CONFIG_DIR/Caddyfile" 2>&1)" "admin endpoint" "admin UI: a custom admin address is flagged"
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
