#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016  # the stand-in binary is a shell script written verbatim
# Importing the Caddyfile of the Caddy 2 app.

# Lays out a config folder the way the Caddy 2 app leaves it: its Caddyfile, a www folder,
# a custom binary and one file that is too big to copy.
make_caddy2_folder() {
  local folder="$TEST_TMP/addon_configs/c80c7555_caddy-2"
  mkdir -p "$folder/www" "$TEST_TMP/addon_configs/a0d7b954_other-app"
  printf '{\n\temail {$EMAIL}\n}\n\nexample.org {\n\ttls {env.CLOUDFLARE_TOKEN}\n\troot * /config/www\n\tfile_server\n}\n\nha.example.org {\n\treverse_proxy localhost:8123\n}\n\napp.example.org {\n\treverse_proxy 127.0.0.1:3000\n}\n' >"$folder/Caddyfile"
  echo "hello" >"$folder/www/index.html"
  printf '#!/bin/sh\ncase "$1" in\n  list-modules) echo "http.handlers.crowdsec github.com/hslatman/caddy-crowdsec-bouncer"; echo "dns.providers.cloudflare github.com/caddy-dns/cloudflare"; echo; echo "  Non-standard modules: 2" ;;\nesac\n' >"$folder/caddy"
  chmod +x "$folder/caddy"
  dd if=/dev/zero of="$folder/big.bin" bs=1k count=6000 2>/dev/null
  echo "secret" >"$TEST_TMP/addon_configs/a0d7b954_other-app/options"
}

test_caddy2_import() {
  use_clean_folders
  use_options '.env_vars = [{"name": "EMAIL", "value": "a@b.c"}]'
  local target="$FORGE_CONFIG_DIR/Caddyfile" output
  export FORGE_APP_CONFIG_ROOTS="$TEST_TMP/addon_configs"
  local folder="$TEST_TMP/addon_configs/c80c7555_caddy-2"
  make_caddy2_folder
  assert_equals "$folder" "$(migrate_caddy2_folder)" "caddy2: the app's config folder is found by its name"

  assert_contains "$(migrate_caddy2_hint "$target" 2>&1)" "advanced (caddyfile)" "caddy2: simple mode points out that an import is possible"

  output=$(migrate_caddy2_import "$target" 2>&1)
  assert_contains "$(cat "$target")" "example.org {" "caddy2: the Caddyfile is imported"
  assert_contains "$(head -n 1 "$target")" "Imported from the Caddy 2 app" "caddy2: the file says where it came from"
  assert_equals "hello" "$(cat "$FORGE_CONFIG_DIR/www/index.html")" "caddy2: files next to the Caddyfile are copied, so /config paths keep working"
  assert_equals "" "$(ls "$FORGE_CONFIG_DIR/caddy" "$FORGE_CONFIG_DIR/big.bin" 2>/dev/null)" "caddy2: the binary and oversized files are left behind"
  assert_contains "$(cat "$target")" "reverse_proxy homeassistant:8123" "caddy2: Home Assistant is addressed by its host name, not by localhost"
  assert_contains "$(cat "$target")" "reverse_proxy 127.0.0.1:3000" "caddy2: other local addresses are left alone"
  assert_contains "$output" "1 line(s) of the imported Caddyfile still point at localhost" "caddy2: other local addresses are pointed out"
  assert_contains "$output" "CLOUDFLARE_TOKEN" "caddy2: environment variables the Caddyfile needs are named"
  assert_not_contains "$output" "variables EMAIL" "caddy2: variables that are already defined are not reported"
  assert_contains "$output" "github.com/caddy-dns/cloudflare github.com/hslatman/caddy-crowdsec-bouncer" "caddy2: the plugins of the old binary are listed for the plugin option"
  assert_equals "" "$(migrate_caddy2_hint "$target" 2>&1)" "caddy2: no hint once a Caddyfile exists"

  printf '# mine\n' >"$target"
  assert_fails "caddy2: an existing Caddyfile is never replaced" migrate_caddy2_import "$target"
  assert_equals "# mine" "$(cat "$target")" "caddy2: the existing Caddyfile stays as it is"
}

# Home Assistant versions differ in where the other apps' folders are mounted: /addon_configs with the legacy
# map type, /app_configs with the new one. Both are searched.
test_caddy2_mount_paths() {
  use_clean_folders
  mkdir -p "$TEST_TMP/legacy/c80c7555_caddy-2" "$TEST_TMP/new/c80c7555_caddy-2"
  echo "example.org { respond ok }" >"$TEST_TMP/new/c80c7555_caddy-2/Caddyfile"
  export FORGE_APP_CONFIG_ROOTS="$TEST_TMP/legacy $TEST_TMP/new"
  assert_equals "$TEST_TMP/new/c80c7555_caddy-2" "$(migrate_caddy2_folder)" "caddy2: the folder is found in whichever mount path exists"
  assert_equals "/app_configs"$'\n'"/addon_configs" "$(FORGE_APP_CONFIG_ROOTS='' migrate_config_roots)" "caddy2: by default both the new and the legacy mount path are searched"
}

test_caddy2_absent() {
  use_clean_folders
  export FORGE_APP_CONFIG_ROOTS="$TEST_TMP/nothing-here"
  assert_fails "caddy2: without the Caddy 2 app nothing is imported" migrate_caddy2_import "$FORGE_CONFIG_DIR/Caddyfile"
  assert_equals "" "$(migrate_caddy2_hint "$FORGE_CONFIG_DIR/Caddyfile" 2>&1)" "caddy2: and no hint is shown"
}
