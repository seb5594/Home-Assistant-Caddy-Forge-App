#!/usr/bin/env bash
# shellcheck shell=bash
# Plugin list handling.

test_module_entries() {
  assert_equals "github.com/caddy-dns/cloudflare" "$(modules_expand caddy-dns/cloudflare)" "entries: owner/repo is taken from github.com"
  assert_equals "github.com/caddy-dns/cloudflare@v0.2.1" "$(modules_expand caddy-dns/cloudflare@v0.2.1)" "entries: a version after the shorthand is kept"
  assert_equals "github.com/a/b" "$(modules_expand github.com/a/b)" "entries: a full github.com module path stays as it is"
  assert_equals "github.com/a/b" "$(modules_expand https://github.com/a/b)" "entries: a github.com URL is turned into a module path"
  assert_equals "github.com/a/b" "$(modules_expand https://github.com/a/b.git)" "entries: a clone URL loses its .git"
  assert_equals "github.com/a/b@main" "$(modules_expand https://github.com/a/b/tree/main)" "entries: a branch page becomes a version"
  assert_equals "gitlab.com/group/project" "$(modules_expand https://gitlab.com/group/project)" "entries: other hosts are accepted"
  assert_equals "go.example.org/team/plugin@v1.0.0" "$(modules_expand go.example.org/team/plugin@v1.0.0)" "entries: a module path on another host stays as it is"
  assert_equals "github.com/a/b@v2=../b" "$(modules_with_version github.com/a/b=../b v2)" "entries: a version is added in front of a replacement"
  assert_equals "github.com/a/b" "$(modules_with_version github.com/a/b '')" "entries: an empty version changes nothing"

  use_options '.caddy.modules = [
    {"module": "caddy-dns/cloudflare", "version": "v0.2.1"},
    {"module": "https://gitlab.com/group/project", "version": "main"},
    {"module": "mholt/caddy-l4", "enabled": false},
    {"module": "hslatman/caddy-crowdsec-bouncer", "enabled": true},
    {"module": "--with github.com/porech/caddy-maxmind-geolocation  # geo"}
  ]'
  assert_equals $'github.com/caddy-dns/cloudflare@v0.2.1\ngitlab.com/group/project@main\ngithub.com/hslatman/caddy-crowdsec-bouncer\ngithub.com/porech/caddy-maxmind-geolocation' \
    "$(requested_without_bundled)" "entries: shorthand, version field, disabled entries and pasted lines work together"
  use_options '.caddy.modules = ["github.com/a/b"]'
  assert_equals "github.com/a/b" "$(requested_without_bundled)" "entries: plain strings from older options still work"
  use_options '.caddy.modules = [{"module": "not a module"}]'
  assert_fails "entries: an entry that is no module is reported" modules_requested
}

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

  use_options '.simple.dns_provider = "cloudflare" | .caddy.modules = [{"module": "github.com/a/b"}]'
  assert_equals $'github.com/a/b\ngithub.com/caddy-dns/cloudflare' "$(requested_without_bundled)" "modules: the DNS provider plugin is added automatically"
  use_options '.simple.dns_provider = "cloudflare" | .caddy.modules = [{"module": "github.com/caddy-dns/cloudflare@v0.2.1"}]'
  assert_equals "github.com/caddy-dns/cloudflare@v0.2.1" "$(requested_without_bundled)" "modules: a pinned DNS plugin is not added twice"
  use_options '.simple.dns_provider = "cloudflare" | .caddy.modules = []'
  assert_contains "$(modules_requested)" "github.com/gsmlg-dev/caddy-admin-ui" "modules: every build contains the admin UI plugin"
  assert_contains "$(modules_requested)" "github.com/caddyserver/replace-response" "modules: every build contains the footer rewrite plugin"
  use_options '.caddy.modules = [{"module": "github.com/gsmlg-dev/caddy-admin-ui@main"}]'
  assert_equals "github.com/gsmlg-dev/caddy-admin-ui@main" "$(modules_requested | grep admin-ui)" "modules: a pinned admin UI plugin is respected and not added twice"
  use_options '.mode = "advanced (caddyfile)" | .simple.dns_provider = "cloudflare"'
  assert_equals "" "$(requested_without_bundled)" "modules: the DNS provider is ignored in Caddyfile mode"
}
