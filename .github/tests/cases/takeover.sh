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

# The options of the Caddy 2 app as the Supervisor reports them.
CADDY2_OPTIONS='{"non_caddyfile_config":{"email":"me@example.org","domain":"nas.example.org","destination":"192.168.1.5","port":8006},
  "args":["--watch","--environ"],"env_vars":[{"name":"CLOUDFLARE_TOKEN","value":"secret-token"},{"name":"DOMAIN","value":"example.org"}],
  "log_level":"warning","caddy_fmt":true,"caddy_upgrade":true}'

test_takeover_caddy2_options() {
  local patch
  patch=$(takeover_caddy2_patch "$CADDY2_OPTIONS" 0)
  assert_equals "warn" "$(jq -r .log_level <<<"$patch")" "options: the log level is translated to the scale of this app"
  assert_equals "CLOUDFLARE_TOKEN=secret-token DOMAIN=example.org" "$(jq -r '[.env_vars[] | .name + "=" + .value] | join(" ")' <<<"$patch")" "options: environment variables arrive with their values"
  assert_equals "true" "$(jq -r .format_caddyfile <<<"$patch")" "options: the formatting switch is taken over"
  assert_equals "me@example.org" "$(jq -r .email <<<"$patch")" "options: without a Caddyfile the email is taken over"
  assert_equals "nas.example.org 192.168.1.5:8006" "$(jq -r '.site | .domain + " " + .target' <<<"$patch")" "options: without a Caddyfile domain, destination and port become a site"
  assert_equals "--environ" "$(jq -r '.ignored_args | join(" ")' <<<"$patch")" "options: start arguments other than --watch are reported"

  patch=$(takeover_caddy2_patch "$CADDY2_OPTIONS" 1)
  assert_equals "null" "$(jq -r '.site' <<<"$patch")" "options: with a Caddyfile the simple options are not in use and stay behind"
  patch=$(takeover_caddy2_patch '{"non_caddyfile_config":{"email":"your@email.com","domain":"mydomain.com"},"log_level":"trace"}' 0)
  assert_equals "null" "$(jq -r '.site' <<<"$patch")" "options: the placeholder domain of the old app is no site"
  assert_equals "null" "$(jq -r '.email' <<<"$patch")" "options: the placeholder email of the old app is ignored"
  assert_equals "debug" "$(jq -r '.log_level' <<<"$patch")" "options: trace is debug here"
  assert_equals "error" "$(jq -r '.log_level' <<<"$(takeover_caddy2_patch '{"log_level":"fatal"}' 0)")" "options: fatal is error here"

  use_options '.env_vars = [{"name": "DOMAIN", "value": "mine.example"}, {"name": "EMPTY", "value": ""}] | .caddy.version = "2.11.9" | .simple.email = "" | .simple.sites = [{"domain": "homeassistant.local", "type": "proxy", "target": "localhost:8123"}]'
  patch=$(takeover_caddy2_patch '{"env_vars":[{"name":"DOMAIN","value":"old.example"},{"name":"EMPTY","value":"filled"},{"name":"NEW","value":"v"}],"log_level":"debug","caddy_upgrade":true,"caddy_fmt":true,"non_caddyfile_config":{"email":"me@example.org","domain":"nas.example.org"}}' 0)
  local merged
  merged=$(takeover_merge_options "[]" "" "" '["FROM_CADDYFILE"]' "2.11.9" "$patch")
  assert_equals "DOMAIN=mine.example EMPTY=filled NEW=v FROM_CADDYFILE=" "$(jq -r '[.env_vars[] | .name + "=" + .value] | join(" ")' <<<"$merged")" "options merge: own values win, empty ones are filled, new ones and Caddyfile names follow"
  assert_equals "debug" "$(jq -r .log_level <<<"$merged")" "options merge: the log level follows while it is the default"
  assert_equals "true" "$(jq -r .format_caddyfile <<<"$merged")" "options merge: formatting is switched on"
  assert_equals "latest" "$(jq -r .caddy.version <<<"$merged")" "options merge: an upgrading Caddy 2 app means the latest Caddy"
  assert_equals "me@example.org" "$(jq -r .simple.email <<<"$merged")" "options merge: the email is filled in"
  assert_equals "nas.example.org" "$(jq -r '.simple.sites[-1].domain' <<<"$merged")" "options merge: the site is added to the existing ones"
  assert_equals "2" "$(jq '.simple.sites | length' <<<"$merged")" "options merge: one site added to the default site only"

  use_options '.log_level = "error" | .simple.email = "keep@example.org" | .simple.sites = [{"domain": "NAS.example.org", "type": "proxy", "target": "x:1"}]'
  merged=$(takeover_merge_options "[]" "" "" "[]" "2.11.9" "$patch")
  assert_equals "error" "$(jq -r .log_level <<<"$merged")" "options merge: a log level you chose stays"
  assert_equals "keep@example.org" "$(jq -r .simple.email <<<"$merged")" "options merge: an email you entered stays"
  assert_equals "1" "$(jq '.simple.sites | length' <<<"$merged")" "options merge: a site that exists (in any spelling) is not doubled"
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
  FAKE_LIST='{"result":"ok","data":{"addons":[{"slug":"core_ssh"},{"slug":"c80c7555_caddy-2"}]}}'
  FAKE_INFO="{\"result\":\"ok\",\"data\":{\"options\":$CADDY2_OPTIONS}}"
  curl() {
    local body=''
    [[ " $* " == *" --data-binary "* ]] && body=$(cat)
    printf '%s\n' "$*" >>"$calls"
    [[ -z $body ]] || printf '%s' "$body" >"$TEST_TMP/posted.json"
    case " $* " in
      *"/addons/self/"*) printf '%s' "$FAKE_REPLY" ;;
      *"/info "*) printf '%s' "$FAKE_INFO" ;;
      *) printf '%s' "$FAKE_LIST" ;;
    esac
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
  assert_equals "DOMAIN CLOUDFLARE_TOKEN" "$(jq -r '[.options.env_vars[].name] | join(" ")' "$TEST_TMP/posted.json")" "takeover run: the environment variables of the old app and its Caddyfile are added to the existing ones"
  assert_equals "secret-token" "$(jq -r '.options.env_vars[] | select(.name == "CLOUDFLARE_TOKEN") | .value' "$TEST_TMP/posted.json")" "takeover run: their values come from the old app's options"
  assert_equals "warn" "$(jq -r '.options.log_level' "$TEST_TMP/posted.json")" "takeover run: the log level of the old app is taken over"
  assert_equals "true" "$(jq -r '.options.format_caddyfile' "$TEST_TMP/posted.json")" "takeover run: so is the formatting switch"
  assert_contains "$(cat "$calls")" "/addons/c80c7555_caddy-2/info" "takeover run: the options are read from the Caddy 2 app through the Supervisor"
  assert_not_contains "$(takeover_run 2>&1 || true)" "secret-token" "takeover run: values of variables never appear in the log"

  # Without a Caddyfile the old app runs from its simple options: email and site are taken over.
  rm -f "$TEST_TMP/apps/c80c7555_caddy-2/Caddyfile"
  use_options ".takeover = true | .simple.email = \"\" | .simple.sites = [{\"domain\": \"homeassistant.local\", \"type\": \"proxy\", \"target\": \"localhost:8123\"}] | .caddy.version = \"$(builder_bundled_version)\""
  takeover_run >/dev/null 2>&1 || true
  assert_equals "me@example.org" "$(jq -r '.options.simple.email' "$TEST_TMP/posted.json")" "takeover run: without a Caddyfile the email is taken over"
  assert_equals "nas.example.org" "$(jq -r '.options.simple.sites[-1].domain' "$TEST_TMP/posted.json")" "takeover run: and the site of the old app"
  assert_equals "simple" "$(jq -r '.options.mode' "$TEST_TMP/posted.json")" "takeover run: the mode stays simple"
  printf 'example.org {\n\ttls {env.CLOUDFLARE_TOKEN}\n}\n' >"$TEST_TMP/apps/c80c7555_caddy-2/Caddyfile"
  use_options ".takeover = true | .caddy.version = \"$(builder_bundled_version)\""

  FAKE_INFO=''
  takeover_run >/dev/null 2>&1 || true
  assert_equals "info" "$(jq -r '.options.log_level' "$TEST_TMP/posted.json")" "takeover run: options that cannot be read leave the rest of the takeover working"
  assert_equals "9" "$(jq '.options.caddy.modules | length' "$TEST_TMP/posted.json")" "takeover run: the plugins are still taken over then"
  FAKE_INFO="{\"result\":\"ok\",\"data\":{\"options\":$CADDY2_OPTIONS}}"

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
