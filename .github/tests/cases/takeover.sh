#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2329  # curl is replaced by a test double that is called indirectly
# Taking over the settings of the CaddyBuilder and Caddy 2 apps.

test_takeover_parse() {
  local events
  events=$(takeover_parse_xcaddy "$TEST_DIR/fixtures/xcaddyCommand.sh")
  assert_equals "latest" "$(awk -F'\t' '$1 == "version" { print $2 }' <<<"$events")" "takeover: the Caddy version of the build command is read"
  assert_equals $'github.com/caddy-dns/cloudflare\ngithub.com/hslatman/caddy-crowdsec-bouncer\ngithub.com/porech/caddy-maxmind-geolocation\ngithub.com/mholt/caddy-dynamicdns' \
    "$(awk -F'\t' '$1 == "with" && $3 == 1 { print $2 }' <<<"$events")" "takeover: the plugins of the command, spread over lines, are active entries"
  assert_equals $'github.com/mholt/caddy-l4@ef01c22\ngithub.com/caddyserver/transform-encoder\ngithub.com/abiosoft/caddy-exec\ngithub.com/mholt/caddy-l4/modules/l4ssh\ngithub.com/gsmlg-dev/caddy-admin-ui@main' \
    "$(awk -F'\t' '$1 == "with" && $3 == 0 { print $2 }' <<<"$events")" "takeover: commented-out plugins become disabled entries, trailing comments are dropped"

  printf 'xcaddy build v2.9.1 --with github.com/a/b@v1 --with=github.com/c/d --replace github.com/e/f=../f --output /x/caddy\n' >"$TEST_TMP/one-line.sh"
  events=$(takeover_parse_xcaddy "$TEST_TMP/one-line.sh")
  assert_equals "v2.9.1" "$(awk -F'\t' '$1 == "version" { print $2 }' <<<"$events")" "takeover: a pinned version is read from a one-line command"
  assert_equals $'github.com/a/b@v1\ngithub.com/c/d' "$(awk -F'\t' '$1 == "with" { print $2 }' <<<"$events")" "takeover: --with=module works as well"
  assert_contains "$(awk -F'\t' '$1 == "ignored" { print $2 }' <<<"$events")" "--replace" "takeover: flags without a counterpart are reported"
  assert_equals "2.9.1" "$(takeover_version_option v2.9.1)" "takeover: a version loses its v"
  assert_equals "latest" "$(takeover_version_option LATEST)" "takeover: latest stays latest"
}

test_takeover_merge() {
  local entries
  entries=$(takeover_parse_xcaddy "$TEST_DIR/fixtures/xcaddyCommand.sh" | takeover_plugin_entries)
  assert_equals "github.com/mholt/caddy-l4" "$(jq -r '.[4].module' <<<"$entries")" "takeover: entries carry the module path ..."
  assert_equals "ef01c22" "$(jq -r '.[4].version' <<<"$entries")" "takeover: ... and the pinned commit as version"
  assert_equals "false" "$(jq -r '.[4].enabled' <<<"$entries")" "takeover: ... and whether the line was commented out"
  assert_equals "null" "$(jq -r '.[0].version' <<<"$entries")" "takeover: plugins without a version have none"

  use_options '.caddy.modules = [{"module": "caddy-dns/cloudflare", "version": "v0.2.1"}] | .env_vars = [{"name": "EMAIL", "value": "a@b.c"}] | .caddy.version = "2.11.9"'
  local merged
  merged=$(takeover_merge_options "$entries" "latest" "advanced (caddyfile)" '["EMAIL", "CROWDSEC_TOKEN"]' "2.11.9")
  assert_equals "9" "$(jq '.caddy.modules | length' <<<"$merged")" "takeover: new plugins are added, the one that exists (as owner/repo) is not doubled"
  assert_equals "v0.2.1" "$(jq -r '.caddy.modules[0].version' <<<"$merged")" "takeover: an existing entry keeps its own settings"
  assert_equals "latest" "$(jq -r '.caddy.version' <<<"$merged")" "takeover: the Caddy version follows the old build command"
  assert_equals "advanced (caddyfile)" "$(jq -r '.mode' <<<"$merged")" "takeover: the mode switches to advanced"
  assert_equals "EMAIL CROWDSEC_TOKEN" "$(jq -r '[.env_vars[].name] | join(" ")' <<<"$merged")" "takeover: missing environment variables are added empty, defined ones stay"
  assert_equals "false" "$(jq -r '.takeover' <<<"$merged")" "takeover: the switch is turned off again"

  use_options '.caddy.version = "2.10.2"'
  merged=$(takeover_merge_options "[]" "latest" "" "[]" "2.11.9")
  assert_equals "2.10.2" "$(jq -r '.caddy.version' <<<"$merged")" "takeover: a Caddy version you chose yourself is not overwritten"
  assert_equals "simple" "$(jq -r '.mode' <<<"$merged")" "takeover: the mode stays when there is no Caddyfile to import"
}

test_takeover_run() {
  use_clean_folders
  export FORGE_APP_CONFIG_ROOTS="$TEST_TMP/apps"
  export SUPERVISOR_TOKEN=test-token
  mkdir -p "$TEST_TMP/apps/2effc9b9_caddybuilder" "$TEST_TMP/apps/c80c7555_caddy-2"
  cp "$TEST_DIR/fixtures/xcaddyCommand.sh" "$TEST_TMP/apps/2effc9b9_caddybuilder/"
  printf 'example.org {\n\ttls {env.CLOUDFLARE_TOKEN}\n}\n' >"$TEST_TMP/apps/c80c7555_caddy-2/Caddyfile"
  use_options ".takeover = true | .caddy.version = \"$(builder_bundled_version)\""

  local calls="$TEST_TMP/calls"
  FAKE_REPLY='{"result":"ok","data":{}}'
  curl() {
    local body=''
    [[ " $* " == *" --data-binary "* ]] && body=$(cat)
    printf '%s\n' "$*" >>"$calls"
    [[ -z $body ]] || printf '%s' "$body" >"$TEST_TMP/posted.json"
    printf '%s' "$FAKE_REPLY"
  }

  local status=0
  takeover_run >/dev/null 2>&1 || status=$?
  assert_equals "0" "$status" "takeover run: stored options and requested a restart"
  assert_contains "$(cat "$calls")" "/addons/self/options" "takeover run: the options go to the Supervisor of this app"
  assert_contains "$(cat "$calls")" "/addons/self/restart" "takeover run: then the app is restarted"
  assert_contains "$(cat "$calls")" "Authorization: Bearer test-token" "takeover run: with the app's Supervisor token"
  assert_equals "9" "$(jq '.options.caddy.modules | length' "$TEST_TMP/posted.json")" "takeover run: all plugins of the build command arrive as entries"
  assert_equals "true" "$(jq -r '.options.caddy.modules[] | select(.module == "github.com/caddy-dns/cloudflare") | .enabled' "$TEST_TMP/posted.json")" "takeover run: active ones are enabled"
  assert_equals "false" "$(jq -r '.options.caddy.modules[] | select(.module == "github.com/caddyserver/transform-encoder") | .enabled' "$TEST_TMP/posted.json")" "takeover run: commented-out ones are disabled"
  assert_equals "advanced (caddyfile)" "$(jq -r '.options.mode' "$TEST_TMP/posted.json")" "takeover run: a Caddyfile to import means advanced mode"
  assert_equals "DOMAIN CLOUDFLARE_TOKEN" "$(jq -r '[.options.env_vars[].name] | join(" ")' "$TEST_TMP/posted.json")" "takeover run: the Caddyfile's environment variables are added to the existing ones"

  : >"$calls"
  FAKE_REPLY='{"result":"error","message":"Invalid options"}'
  status=0
  takeover_run >/dev/null 2>&1 || status=$?
  assert_equals "1" "$status" "takeover run: a refusal by the Supervisor lets the app start as usual"
  assert_not_contains "$(cat "$calls")" "restart" "takeover run: and nothing is restarted"

  SUPERVISOR_TOKEN='' status=0
  takeover_run >/dev/null 2>&1 || status=$?
  assert_equals "1" "$status" "takeover run: without a Supervisor token nothing is attempted"

  export FORGE_APP_CONFIG_ROOTS="$TEST_TMP/empty"
  export SUPERVISOR_TOKEN=test-token
  status=0
  takeover_run >/dev/null 2>&1 || status=$?
  assert_equals "1" "$status" "takeover run: without the old apps there is nothing to take over"
}
