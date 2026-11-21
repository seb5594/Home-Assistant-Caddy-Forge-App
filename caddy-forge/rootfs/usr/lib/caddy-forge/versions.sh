#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# "Is there something newer?" The Go module proxy knows every release of Caddy and
# of each plugin, needs no token and has no rate limit, so it is the single source.
# ==============================================================================

CADDY_MODULE='github.com/caddyserver/caddy/v2'

# Base URL of the module proxy: the first http(s) entry of GOPROXY, else the public one.
versions_proxy_url() {
  local entry
  for entry in $(printf '%s' "${GOPROXY:-}" | tr ',|' '  '); do
    case "$entry" in
      http://* | https://*)
        printf '%s' "${entry%/}"
        return 0
        ;;
    esac
  done
  printf 'https://proxy.golang.org'
}

# The proxy spells upper case letters as `!` plus the lower case letter.
versions_escape_path() {
  local input=$1 output='' char i
  for ((i = 0; i < ${#input}; i++)); do
    char=${input:i:1}
    if [[ $char == [[:upper:]] ]]; then
      output+="!${char,,}"
    else
      output+=$char
    fi
  done
  printf '%s' "$output"
}

# Newest release of the Go module that contains <import path>. A plugin is often a package
# inside a bigger module (github.com/mholt/caddy-l4/modules/l4ssh), so unknown paths are
# retried one directory up. Prints e.g. `v1.2.3`; fails when the proxy cannot be reached.
versions_latest_module() {
  local path=$1 reply code body version base
  base=$(versions_proxy_url)
  while [[ $path == */* ]]; do
    reply=$(curl --silent --location --max-time 20 --write-out '\n%{http_code}' \
      "$base/$(versions_escape_path "$path")/@latest") || return 1
    code=${reply##*$'\n'}
    body=${reply%$'\n'*}
    case "$code" in
      200)
        version=$(jq -r '.Version // empty' <<<"$body" 2>/dev/null) || version=''
        [[ -n $version ]] && { printf '%s\n' "$version"; return 0; }
        ;;
      404 | 410) ;;
      *) return 1 ;;
    esac
    path=${path%/*}
  done
  return 1
}

# Newest stable Caddy release, e.g. `v2.11.9`.
versions_latest_caddy() {
  versions_latest_module "$CADDY_MODULE"
}

# `v2.11.9` and `2.11.9` both become `2.11.9`.
versions_strip_v() {
  printf '%s' "${1#v}"
}

# Succeeds when version <a> is strictly newer than version <b> (versions without a leading `v`).
versions_is_newer() {
  local a=$1 b=$2
  [[ $a != "$b" && $(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1) == "$a" ]]
}

# Maps a module path to the version a binary was built with (`go version -m` output on stdin,
# tab separated: `<kind> <path> <version>`). The longest module path that prefixes <import path> wins.
versions_in_build_info() {
  local import_path=$1
  awk -F'\t' -v target="$import_path" '
    ($2 == "dep" || $2 == "mod") && (target == $3 || index(target, $3 "/") == 1) {
      if (length($3) > best) { best = length($3); version = $4 }
    }
    END { if (best) print version }'
}
