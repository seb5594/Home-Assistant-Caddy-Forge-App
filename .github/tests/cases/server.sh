#!/usr/bin/env bash
# shellcheck shell=bash
# The whole app, started like the Supervisor does: /run.sh with an options file.

test_server_start() {
  use_clean_folders
  local web="$TEST_TMP/www" port=18080 pid body='' waited=0
  mkdir -p "$web"
  echo "hello from caddy forge" >"$web/index.html"
  use_options ".caddy.version = \"$(builder_bundled_version)\" | .simple.sites = [{\"domain\": \"localhost:$port\", \"type\": \"static\", \"target\": \"$web\", \"tls\": \"off\"}]"

  "${RUN_SCRIPT:-/run.sh}" >"$TEST_TMP/server.log" 2>&1 &
  pid=$!
  until body=$(curl -fsS "http://localhost:$port/" 2>/dev/null) || ((waited >= 30)); do
    sleep 1
    waited=$((waited + 1))
  done
  assert_contains "$body" "hello from caddy forge" "server: the app starts Caddy and serves the site"
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  assert_fails "server: the web server stops with the app" curl -fsS --max-time 2 "http://localhost:$port/"

  use_options '.caddy.start_server = false | .simple.sites = []'
  assert_succeeds "server: build-only mode ends without starting the web server" "${RUN_SCRIPT:-/run.sh}"
}

# Path under which Home Assistant's ingress would present the admin UI.
TEST_INGRESS_PATH='/api/hassio_ingress/TESTTOKEN'

# GET <path> on the admin UI the way the ingress gateway asks for it; extra arguments go to curl.
ingress_get() {
  local path=$1
  shift
  curl -s -H "X-Ingress-Path: $TEST_INGRESS_PATH" "$@" "http://127.0.0.1:5594$path"
}

ingress_status() {
  ingress_get "$@" -o /dev/null -w '%{http_code}'
}

# Starts the app in the background and waits for the admin UI; sets APP_PID.
start_app_with_admin_ui() {
  FORGE_INGRESS_IP=127.0.0.1 "${RUN_SCRIPT:-/run.sh}" >"$TEST_TMP/app.log" 2>&1 &
  APP_PID=$!
  local waited=0
  until curl -fsS http://127.0.0.1:5594/ >/dev/null 2>&1 || ((waited >= 30)); do
    sleep 1
    waited=$((waited + 1))
  done
}

stop_app() {
  kill -TERM "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
}

# What a visitor of the admin UI can and cannot do through ingress; the app is already running.
check_admin_ui_through_ingress() {
  local page
  page=$(ingress_get /)
  assert_equals "200" "$(ingress_status /)" "ingress: the admin UI is served"
  assert_contains "$page" "$TEST_INGRESS_PATH/_next/" "ingress: the page's assets are fetched below the ingress path"
  assert_not_contains "$page" "$TEST_INGRESS_PATH$TEST_INGRESS_PATH" "ingress: the path is never put in front twice"
  assert_contains "$page" "src=\"$TEST_INGRESS_PATH/_forge/footer.js\" defer></script></body>" "ingress: the footer script is injected"
  assert_contains "$(ingress_get /_forge/footer.js)" "Sebastian Schmidt" "ingress: the footer script is served"
  assert_equals "Light blue" "$(ingress_get /_forge/palette.json | jq -r '.presets[0].name')" "ingress: the colour palette is served"
  assert_contains "$(ingress_get / -H 'Accept-Encoding: gzip')" "</html>" "ingress: pages stay readable for browsers that accept compression"
  assert_contains "$(ingress_get /config/)" '"apps"' "ingress: the admin API answers through the UI"
  assert_equals "403" "$(ingress_status /ws/pty)" "ingress: the web shell stays closed"
  assert_equals "200" "$(ingress_status /config/ -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-origin' \
    -H 'Referer: http://homeassistant.local:8123/')" "ingress: the page's own requests are accepted"
  assert_equals "403" "$(ingress_status /config/ -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: cross-site' \
    -H 'Referer: https://evil.example/page')" "ingress: requests from another web page are refused"
  assert_equals "403" "$(ingress_status / --interface 127.0.0.2)" "ingress: only the ingress gateway may connect"
}

test_admin_ui_simple_mode() {
  use_clean_folders
  use_options ".caddy.version = \"$(builder_bundled_version)\" | .simple.sites = [{\"domain\": \"localhost:18081\", \"type\": \"static\", \"target\": \"/tmp\", \"tls\": \"off\"}]"
  start_app_with_admin_ui
  check_admin_ui_through_ingress
  stop_app
}

test_admin_ui_with_own_caddyfile() {
  use_clean_folders
  local caddyfile="$FORGE_CONFIG_DIR/Caddyfile" original
  printf '{\n\tadmin off\n\thttp_port 18082\n}\n\n:18082 {\n\trespond "own caddyfile"\n}\n' >"$caddyfile"
  original=$(cat "$caddyfile")
  use_options ".caddy.version = \"$(builder_bundled_version)\" | .mode = \"advanced (caddyfile)\""
  start_app_with_admin_ui
  assert_equals "own caddyfile" "$(curl -s http://localhost:18082/)" "own Caddyfile: it is served as written"
  check_admin_ui_through_ingress
  assert_equals "$original" "$(cat "$caddyfile")" "own Caddyfile: the file itself is never modified, not even for the admin UI"
  stop_app
}
