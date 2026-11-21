#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2329  # curl is replaced by a test double that is called indirectly
# Version lookups against a pretend module proxy.

# Stands in for curl: only github.com/mholt/caddy-l4 exists; /broken/ answers with a server error.
fake_curl() {
  local url=${*: -1}
  case "$url" in
    */github.com/mholt/caddy-l4/@latest) printf '{"Version":"v0.1.3"}\n200' ;;
    */broken/*) printf '\n500' ;;
    *) printf 'not found\n404' ;;
  esac
}

test_versions() {
  curl() { fake_curl "$@"; }
  assert_equals "v0.1.3" "$(versions_latest_module github.com/mholt/caddy-l4/modules/l4ssh)" \
    "versions: a package inside a module resolves to the newest module release"
  assert_fails "versions: an unknown module has no version" versions_latest_module github.com/nobody/nothing
  assert_fails "versions: a proxy error is a failure, not a missing module" versions_latest_module example.org/broken/module

  assert_equals "github.com/!burnt!sushi/toml" "$(versions_escape_path github.com/BurntSushi/toml)" "versions: capital letters are escaped for the proxy"
  assert_equals "https://goproxy.example" "$(GOPROXY='https://goproxy.example/,direct' versions_proxy_url)" "versions: the configured proxy is used"
  assert_equals "https://proxy.golang.org" "$(GOPROXY='off' versions_proxy_url)" "versions: the public proxy is the fallback"
  assert_equals "2.11.9" "$(versions_strip_v v2.11.9)" "versions: a leading v is stripped"
  assert_succeeds "versions: 2.11.10 is newer than 2.11.9" versions_is_newer 2.11.10 2.11.9
  assert_fails "versions: 2.11.9 is not newer than itself" versions_is_newer 2.11.9 2.11.9
  assert_fails "versions: 2.11.9 is not newer than 2.11.10" versions_is_newer 2.11.9 2.11.10

  local info
  info=$'\tpath\tcaddy\n\tmod\tcaddy\t(devel)\t\n\tdep\tgithub.com/caddyserver/caddy/v2\tv2.11.9\th1:x=\n\tdep\tgithub.com/mholt/caddy-l4\tv0.1.3\th1:y='
  assert_equals "v0.1.3" "$(versions_in_build_info github.com/mholt/caddy-l4/modules/l4ssh <<<"$info")" "versions: build info maps a package to its module version"
  assert_equals "v2.11.9" "$(versions_in_build_info github.com/caddyserver/caddy/v2 <<<"$info")" "versions: build info knows the Caddy version"
  assert_equals "" "$(versions_in_build_info github.com/other/thing <<<"$info")" "versions: build info is empty for a module that is not part of the binary"
}
