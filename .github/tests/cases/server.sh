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
