#!/usr/bin/env bash
# shellcheck shell=bash
# The real thing: compile Caddy with a plugin through xcaddy.

# A small DNS plugin keeps the build short.
TEST_PLUGIN='github.com/caddy-dns/duckdns'

test_real_build() {
  use_clean_folders
  local bundled before
  bundled=$(builder_bundled_version)
  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [\"$TEST_PLUGIN\"] | .simple.sites = [{\"domain\": \"http://localhost\", \"type\": \"static\", \"target\": \"/tmp\"}]"
  builder_load_request
  caddyfile_write "$FORGE_CONFIG_DIR/generated.Caddyfile"

  LOG_LEVEL=warn builder_select_binary "$FORGE_CONFIG_DIR/generated.Caddyfile" >"$TEST_TMP/build.log" 2>&1 || cat "$TEST_TMP/build.log" >&2
  assert_equals "$FORGE_CUSTOM_CADDY" "$CADDY_BIN" "build: the custom binary is selected after a build"
  assert_contains "$("$CADDY_BIN" list-modules)" "dns.providers.duckdns" "build: the plugin is part of the new binary"
  assert_equals "v$bundled" "$(builder_state_get .caddy)" "build: the built Caddy version is recorded"
  assert_contains "$(builder_state_get '.modules | keys[]')" "$TEST_PLUGIN" "build: the plugin version is recorded"
  assert_equals "" "$(ls "$FORGE_WORK_DIR" 2>/dev/null)" "build: the scratch folder is gone afterwards"

  before=$(sha256sum <"$FORGE_CUSTOM_CADDY")
  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [\"$TEST_PLUGIN\", \"github.com/this-module/does-not-exist\"] | .caddy.updates = \"off\" | .simple.sites = [{\"domain\": \"http://localhost\", \"type\": \"static\", \"target\": \"/tmp\"}]"
  builder_load_request
  LOG_LEVEL=error builder_select_binary "$FORGE_CONFIG_DIR/generated.Caddyfile" >/dev/null 2>&1 || true
  assert_equals "$before" "$(sha256sum <"$FORGE_CUSTOM_CADDY")" "build: a failing build leaves the previous binary untouched"
}
