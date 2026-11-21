#!/usr/bin/env bash
# shellcheck shell=bash
# The real thing: compile Caddy with plugins through xcaddy and run the admin UI from that binary.

# A small DNS plugin keeps the build short; the admin UI plugin comes in through its switch.
TEST_PLUGIN='github.com/caddy-dns/duckdns'
TEST_SITE='[{"domain": "localhost:18090", "type": "static", "target": "/tmp", "tls": "off"}]'

# Waits until <url> answers, at most 30 seconds.
wait_for_url() {
  local waited=0
  until curl -fsS "$1" >/dev/null 2>&1 || ((waited >= 30)); do
    sleep 1
    waited=$((waited + 1))
  done
}

test_real_build() {
  use_clean_folders
  local bundled before pid
  bundled=$(builder_bundled_version)
  use_options ".caddy.version = \"$bundled\" | .caddy.updates = \"off\" | .admin_ui.enabled = true | .caddy.modules = [\"$TEST_PLUGIN\"] | .simple.sites = $TEST_SITE"
  builder_load_request
  caddyfile_write "$FORGE_CONFIG_DIR/generated.Caddyfile"
  CADDYFILE=$(adminui_compose "$FORGE_CONFIG_DIR/generated.Caddyfile")

  LOG_LEVEL=warn builder_select_binary "$CADDYFILE" >"$TEST_TMP/build.log" 2>&1 || cat "$TEST_TMP/build.log" >&2
  assert_equals "$FORGE_CUSTOM_CADDY" "$CADDY_BIN" "build: the custom binary is selected after a build"
  assert_contains "$("$CADDY_BIN" list-modules)" "dns.providers.duckdns" "build: the plugin is part of the new binary"
  assert_contains "$("$CADDY_BIN" list-modules)" "http.handlers.caddy_admin_ui" "build: the admin UI plugin is part of the new binary"
  assert_equals "v$bundled" "$(builder_state_get .caddy)" "build: the built Caddy version is recorded"
  assert_contains "$(builder_state_get '.modules | keys[]')" "$TEST_PLUGIN" "build: the plugin version is recorded"
  assert_equals "" "$(ls "$FORGE_WORK_DIR" 2>/dev/null)" "build: the scratch folder is gone afterwards"

  # Start the whole app with the binary just built and talk to the admin UI.
  "${RUN_SCRIPT:-/run.sh}" >"$TEST_TMP/admin.log" 2>&1 &
  pid=$!
  wait_for_url http://localhost:8099/
  assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8099/)" "admin UI: the page is served"
  assert_contains "$(curl -s http://localhost:8099/)" '<script src="/_forge/footer.js" defer></script></body>' "admin UI: the footer script is injected into the page"
  assert_contains "$(curl -s http://localhost:8099/_forge/footer.js)" "Sebastian Schmidt" "admin UI: the footer script is served"
  assert_contains "$(curl -s -H 'Accept-Encoding: gzip' http://localhost:8099/)" "</html>" "admin UI: pages stay readable for browsers that accept compression"
  assert_contains "$(curl -s http://localhost:8099/config/)" '"apps"' "admin UI: the admin API answers through it"
  assert_equals "403" "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8099/ws/pty)" "admin UI: the web shell stays closed"
  curl -s http://localhost:8099/config/ >"$TEST_TMP/current.json"
  # What a browser sends when the page itself asks for the configuration.
  assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-origin' \
    -H 'Referer: http://localhost:8099/' http://localhost:8099/config/)" "admin UI: the page's own requests are accepted"
  assert_equals "403" "$(curl -s -o /dev/null -w '%{http_code}' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: cross-site' \
    -H 'Referer: https://evil.example/page' http://localhost:8099/config/)" "admin UI: requests that come from another web page are refused"
  assert_equals "403" "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example:8099' http://localhost:8099/config/)" \
    "admin UI: a public host name (DNS rebinding) is refused"
  assert_equals "403" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Origin: https://evil.example' \
    -H 'Content-Type: application/json' --data-binary "@$TEST_TMP/current.json" http://localhost:8099/load)" \
    "admin UI: requests from foreign origins are refused"
  assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Origin: http://localhost:8099' \
    -H 'Content-Type: application/json' --data-binary "@$TEST_TMP/current.json" http://localhost:8099/load)" \
    "admin UI: its own requests are accepted"
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  before=$(sha256sum <"$FORGE_CUSTOM_CADDY")
  use_options ".caddy.version = \"$bundled\" | .caddy.updates = \"off\" | .caddy.modules = [\"$TEST_PLUGIN\", \"github.com/this-module/does-not-exist\"] | .simple.sites = $TEST_SITE"
  builder_load_request
  LOG_LEVEL=error builder_select_binary "$FORGE_CONFIG_DIR/generated.Caddyfile" >/dev/null 2>&1 || true
  assert_equals "$before" "$(sha256sum <"$FORGE_CUSTOM_CADDY")" "build: a failing build leaves the previous binary untouched"
}
