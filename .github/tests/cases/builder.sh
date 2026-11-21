#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2329,SC2016,SC2034  # test doubles are called indirectly; the shell script is written verbatim
# Which binary runs: planning, validation before activation and the atomic swap.

# A stand-in for a freshly built Caddy that rejects every Caddyfile.
make_rejecting_binary() {
  printf '#!/bin/sh\ncase "$1" in\n  version) echo v2.11.9 ;;\n  adapt) echo "unrecognized directive: demo" >&2; exit 1 ;;\nesac\n' >"$1"
  chmod +x "$1"
}

# Pretends a custom binary was built for the current request.
install_custom_binary() {
  mkdir -p "$FORGE_DATA_DIR/bin"
  cp "$FORGE_BUNDLED_CADDY" "$FORGE_CUSTOM_CADDY"
  builder_write_state "$FORGE_CUSTOM_CADDY"
}

# Rewrites one plugin's recorded version in state.json.
set_built_module_version() {
  jq --arg path "$1" --arg version "$2" '.modules[$path] = $version' "$FORGE_STATE_FILE" >"$FORGE_STATE_FILE.tmp"
  mv "$FORGE_STATE_FILE.tmp" "$FORGE_STATE_FILE"
}

test_builder_plan() {
  use_clean_folders
  versions_latest_caddy() { echo v2.11.9; }
  versions_latest_module() { echo v1.0.0; }
  local bundled
  bundled=$(builder_bundled_version)

  use_options ".caddy.version = \"$bundled\""
  builder_load_request
  builder_plan
  assert_equals "stock" "$PLAN_ACTION" "plan: the pinned default needs no build"

  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b\"}]"
  builder_load_request
  builder_plan
  assert_equals "build" "$PLAN_ACTION" "plan: a plugin needs a build"

  use_options '.caddy.version = "2.0.0"'
  builder_load_request
  builder_plan
  assert_equals "build" "$PLAN_ACTION" "plan: another pinned version needs a build"

  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b@v1.0.0\"}]"
  builder_load_request
  install_custom_binary
  builder_plan
  assert_equals "reuse" "$PLAN_ACTION" "plan: a matching build is reused"

  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b@v1.0.0\"}, {\"module\": \"github.com/c/d@v1.0.0\"}]"
  builder_load_request
  builder_plan
  assert_equals "build" "$PLAN_ACTION" "plan: changed plugins invalidate the old build"

  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b\"}]"
  builder_load_request
  install_custom_binary
  set_built_module_version github.com/a/b v0.9.0
  builder_plan
  assert_equals "build" "$PLAN_ACTION" "plan: a newer plugin release triggers a rebuild"
  assert_contains "${PENDING_UPDATES[*]}" "github.com/a/b v0.9.0 -> v1.0.0" "plan: the update is reported"

  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b\"}] | .caddy.updates = \"notify\""
  builder_load_request
  builder_plan
  assert_equals "reuse" "$PLAN_ACTION" "plan: notify only reports a plugin update"

  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b\"}] | .caddy.updates = \"off\""
  builder_load_request
  builder_plan
  assert_equals "reuse" "$PLAN_ACTION" "plan: with updates off nothing is looked up"

  use_options '.caddy.version = "latest"'
  builder_load_request
  rm -f "${FORGE_CUSTOM_CADDY:?}" "${FORGE_STATE_FILE:?}"
  builder_plan
  assert_equals "stock" "$PLAN_ACTION" "plan: latest equals the shipped version, no build"
  assert_equals "true" "$PLAN_PRUNE" "plan: a leftover custom build is marked for removal"

  versions_latest_caddy() { echo v99.0.0; }
  builder_plan
  assert_equals "build" "$PLAN_ACTION" "plan: a newer Caddy release triggers a build"
  assert_equals "v99.0.0" "$PLAN_TARGET" "plan: the new release is the build target"

  use_options '.caddy.version = "latest" | .caddy.updates = "notify"'
  builder_load_request
  builder_plan
  assert_equals "stock" "$PLAN_ACTION" "plan: notify keeps the shipped Caddy"

}

test_builder_activation() {
  use_clean_folders
  local bundled before
  bundled=$(builder_bundled_version)
  use_options ".caddy.version = \"$bundled\" | .caddy.modules = [{\"module\": \"github.com/a/b@v1.0.0\"}]"
  builder_load_request
  CADDYFILE="$FORGE_CONFIG_DIR/Caddyfile"
  printf ':8080 {\n\trespond "ok"\n}\n' >"$CADDYFILE"

  install_custom_binary
  before=$(sha256sum <"$FORGE_CUSTOM_CADDY")

  builder_build() {
    mkdir -p "$FORGE_WORK_DIR"
    make_rejecting_binary "$FORGE_WORK_DIR/caddy"
    BUILD_CANDIDATE="$FORGE_WORK_DIR/caddy"
  }
  builder_try_build "$CADDYFILE" >/dev/null 2>&1 || true
  assert_equals "$before" "$(sha256sum <"$FORGE_CUSTOM_CADDY")" "activation: a build that rejects the config never replaces the live binary"
  assert_equals "$(builder_signature "$CADDYFILE")" "$(builder_state_get .rejected)" "activation: the failed attempt is remembered"
  assert_equals "" "$(ls "$FORGE_WORK_DIR" 2>/dev/null)" "activation: the scratch folder is cleaned up after a rejection"

  builder_build() {
    mkdir -p "$FORGE_WORK_DIR"
    cp "$FORGE_BUNDLED_CADDY" "$FORGE_WORK_DIR/caddy"
    BUILD_CANDIDATE="$FORGE_WORK_DIR/caddy"
  }
  rm -f "${FORGE_STATE_FILE:?}"
  builder_try_build "$CADDYFILE" >/dev/null 2>&1
  assert_equals "$(builder_fingerprint)" "$(builder_state_get .fingerprint)" "activation: a valid build is activated and recorded"
  assert_equals "" "$(ls "$FORGE_CUSTOM_CADDY".new 2>/dev/null)" "activation: no temporary file is left next to the live binary"

  builder_remember_rejection "$(builder_signature "$CADDYFILE")"
  assert_fails "activation: the same failed combination is not built again" builder_try_build "$CADDYFILE"
}

test_builder_selection() {
  use_clean_folders
  local bundled
  bundled=$(builder_bundled_version)
  use_options ".caddy.version = \"$bundled\""
  builder_load_request
  CADDYFILE="$FORGE_CONFIG_DIR/Caddyfile"
  printf ':8080 {\n\trespond "ok"\n}\n' >"$CADDYFILE"
  builder_select_binary "$CADDYFILE" >/dev/null
  assert_equals "$FORGE_BUNDLED_CADDY" "$CADDY_BIN" "selection: the shipped binary starts a plain setup"

  printf ':8080 {\n\tnonsense_directive\n}\n' >"$CADDYFILE"
  assert_fails "selection: an unusable Caddyfile stops the app with a message" builder_select_binary "$CADDYFILE"
}
