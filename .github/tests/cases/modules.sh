#!/usr/bin/env bash
# shellcheck shell=bash
# Plugin list handling.

test_modules() {
  local cleaned
  cleaned=$(printf '%s\n' 'github.com/a/b' '  --with github.com/c/d@v1.2.3 \  # note' 'github.com/a/b' '# only a comment' '' | modules_clean)
  assert_equals $'github.com/a/b\ngithub.com/c/d@v1.2.3' "$cleaned" "modules: pasted xcaddy lines are cleaned and duplicates dropped"

  assert_succeeds "modules: valid specifications are accepted" \
    bash -c 'source /run.sh; printf "%s\n" github.com/a/b github.com/a/b/sub@v1.0.0 github.com/a/b@main=../b | modules_validate'
  assert_fails "modules: a word that is no Go module is rejected" \
    bash -c 'source /run.sh; printf "%s\n" cloudflare | modules_validate'

  assert_equals "github.com/a/b" "$(modules_path 'github.com/a/b@v1=../b')" "modules: path is split from version and replacement"
  assert_equals "v1.2.3" "$(modules_ref 'github.com/a/b@v1.2.3')" "modules: pinned version is read"
  assert_equals "" "$(modules_ref 'github.com/a/b')" "modules: unpinned plugin has no version"
  assert_succeeds "modules: unpinned plugin counts as floating" modules_is_floating github.com/a/b
  assert_fails "modules: pinned plugin is not floating" modules_is_floating github.com/a/b@v1.2.3

  use_options '.simple.dns_provider = "cloudflare" | .caddy.modules = ["github.com/a/b"]'
  assert_equals $'github.com/a/b\ngithub.com/caddy-dns/cloudflare' "$(modules_requested)" "modules: the DNS provider plugin is added automatically"
  use_options '.simple.dns_provider = "cloudflare" | .caddy.modules = ["github.com/caddy-dns/cloudflare@v0.2.1"]'
  assert_equals "github.com/caddy-dns/cloudflare@v0.2.1" "$(modules_requested)" "modules: a pinned DNS plugin is not added twice"
  use_options '.admin_ui.enabled = true'
  assert_equals $'github.com/gsmlg-dev/caddy-admin-ui\ngithub.com/caddyserver/replace-response' "$(modules_requested)" "modules: the admin UI and its footer rewrite are added when the switch is on"
  use_options '.admin_ui.enabled = true | .caddy.modules = ["github.com/gsmlg-dev/caddy-admin-ui@main"]'
  assert_equals $'github.com/gsmlg-dev/caddy-admin-ui@main\ngithub.com/caddyserver/replace-response' "$(modules_requested)" "modules: a pinned admin UI plugin is respected"
  use_options '.admin_ui.enabled = false'
  assert_equals "" "$(modules_requested)" "modules: no admin UI plugin while the switch is off"
  use_options '.mode = "caddyfile" | .simple.dns_provider = "cloudflare"'
  assert_equals "" "$(modules_requested)" "modules: the DNS provider is ignored in Caddyfile mode"
}
