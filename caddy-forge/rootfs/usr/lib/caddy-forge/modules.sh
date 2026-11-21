#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# The plugin list: turn what the user typed into Go module specifications, validate them and
# split a specification such as `github.com/caddy-dns/cloudflare@v0.2.1` into its parts.
#
# An entry has a `module` (required), an optional `version` (tag, branch or commit) and an
# `enabled` switch. The module may be `owner/repo` (taken from github.com), a module path
# such as `gitlab.com/group/project`, or the URL of a repository.
# ==============================================================================

# <go module path>[/sub/package][@version][=replacement]
MODULE_PATTERN='^[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)+(@[A-Za-z0-9._+~/-]+)?(=[^[:space:]]+)?$'
# DNS providers are published as github.com/caddy-dns/<provider>.
DNS_PROVIDER_PATTERN='^[a-z0-9][a-z0-9_-]*$'
DNS_MODULE_PREFIX='github.com/caddy-dns/'
# The two plugins of the admin UI are part of every build: the UI itself and the response rewrite that
# lets it live below Home Assistant's ingress path. The shipped binary contains them at the versions
# the image pins (FORGE_ADMIN_UI_REF, FORGE_REPLACE_RESPONSE_REF); custom builds use the same ones.
ADMIN_UI_MODULE='github.com/gsmlg-dev/caddy-admin-ui'
REPLACE_RESPONSE_MODULE='github.com/caddyserver/replace-response'

# Normalizes raw module lines (stdin) into one specification per line (stdout).
# People paste lines straight from xcaddy commands, so a leading `--with`, trailing
# backslashes and `#` comments are accepted and dropped; duplicates are removed.
modules_clean() {
  sed -E 's/#.*$//; s/[[:space:]]+$//; s/\\$//' \
    | sed -E 's/(^|[[:space:]])--with[[:space:]=]+/\n/g' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | awk 'NF && !seen[$0]++'
}

# Turns shorthand and URLs into a module specification:
#   owner/repo                        -> github.com/owner/repo
#   https://gitlab.com/g/p.git        -> gitlab.com/g/p
#   https://github.com/o/r/tree/main  -> github.com/o/r@main
# Paths that already start with a host name (`github.com/...`, `go.example.org/...`) stay as they are;
# `@version` and `=replacement` are kept.
modules_expand() {
  local spec=$1 path rest first
  spec=${spec#http://}
  spec=${spec#https://}
  path=${spec%%[@=]*}
  rest=${spec#"$path"}
  path=${path%/}
  path=${path%.git}
  if [[ $path =~ ^(github[.]com/[^/]+/[^/]+)/(tree|blob)/([^/]+)(/.*)?$ ]]; then
    path=${BASH_REMATCH[1]}
    [[ -n $rest ]] || rest="@${BASH_REMATCH[3]}"
  fi
  first=${path%%/*}
  if [[ $path == */* && $first != *.* ]]; then
    path="github.com/$path"
  fi
  printf '%s%s' "$path" "$rest"
}

# Sets the version of a specification: `github.com/a/b` + `v1.2.3` -> `github.com/a/b@v1.2.3`.
# A `=replacement` stays; an empty version leaves the specification unchanged.
modules_with_version() {
  local spec=$1 version=${2#@}
  version=${version//[[:space:]]/}
  if [[ -z $version ]]; then
    printf '%s' "$spec"
    return 0
  fi
  local replacement=''
  if [[ $spec == *=* ]]; then
    replacement="=${spec#*=}"
  fi
  printf '%s@%s%s' "$(modules_path "$spec")" "$version" "$replacement"
}

# Stops the app with a hint when a cleaned specification (stdin) is malformed.
modules_validate() {
  local invalid
  invalid=$(grep -Ev "$MODULE_PATTERN" || true)
  if [[ -n $invalid ]]; then
    fail "Invalid plugin entry (expected e.g. github.com/caddy-dns/cloudflare or ...@v1.2.3): ${invalid//$'\n'/, }"
  fi
}

# `github.com/a/b@v1=../b` -> `github.com/a/b`
modules_path() {
  local spec=$1
  printf '%s' "${spec%%[@=]*}"
}

# `github.com/a/b@v1=../b` -> `v1`; prints nothing for an unpinned plugin.
modules_ref() {
  local spec=${1%%=*}
  if [[ $spec == *@* ]]; then
    printf '%s' "${spec#*@}"
  fi
  return 0
}

# Succeeds when the plugin follows the newest release (no `@version`, no local replacement).
modules_is_floating() {
  [[ -z $(modules_ref "$1") && $1 != *=* ]]
}

# The DNS provider chosen in simple mode, or nothing.
modules_dns_provider() {
  [[ $(option_or .mode simple) == simple ]] || return 0
  local provider
  provider=$(option .simple.dns_provider)
  [[ -z $provider ]] && return 0
  [[ $provider =~ $DNS_PROVIDER_PATTERN ]] \
    || fail "DNS provider '$provider' must be lower case letters, digits, '-' or '_' (for example: cloudflare)"
  printf '%s' "$provider"
}

# The specifications of the plugins the shipped binary already contains, one per line.
modules_bundled_specs() {
  printf '%s%s\n' "$ADMIN_UI_MODULE" "${FORGE_ADMIN_UI_REF:+@$FORGE_ADMIN_UI_REF}"
  printf '%s%s\n' "$REPLACE_RESPONSE_MODULE" "${FORGE_REPLACE_RESPONSE_REF:+@$FORGE_REPLACE_RESPONSE_REF}"
}

# Succeeds when <spec> is exactly a plugin of the shipped binary (so it needs no build of its own).
modules_is_bundled() {
  modules_bundled_specs | grep -qxF -- "$1"
}

# Appends <spec> to the specifications (stdin to stdout) unless the user already listed that
# module, with or without a version.
modules_add_unless_present() {
  local wanted=$1 specs found=false spec
  specs=$(cat)
  while IFS= read -r spec; do
    if [[ -n $spec && $(modules_path "$spec") == "$(modules_path "$wanted")" ]]; then
      found=true
    fi
  done <<<"$specs"
  if [[ $found == false ]]; then
    specs+=$'\n'"$wanted"
  fi
  printf '%s\n' "$specs" | awk 'NF'
}

# The enabled entries of the `caddy.modules` option as specifications, one per line.
# Plain strings are accepted as well, so an older options file keeps working.
modules_from_options() {
  local module version lines line count
  while IFS=$'\037' read -r module version; do
    lines=$(printf '%s\n' "$module" | modules_clean)
    [[ -n $lines ]] || continue
    count=$(printf '%s\n' "$lines" | wc -l)
    while IFS= read -r line; do
      line=$(modules_expand "$line")
      if ((count == 1)); then
        line=$(modules_with_version "$line" "$version")
      fi
      printf '%s\n' "$line"
    done <<<"$lines"
  done < <(jq -r '.caddy.modules[]? | (if type == "string" then {module: .} else . end)
    | select(.enabled != false) | [(.module // ""), (.version // "")] | join("\u001f")' "$OPTIONS_FILE")
}

# Every plugin to build in: the user's list, the module of the chosen DNS provider and the plugins
# of the admin UI.
modules_requested() {
  local specs provider spec
  specs=$(modules_from_options | awk 'NF && !seen[$0]++')
  provider=$(modules_dns_provider)
  if [[ -n $provider ]]; then
    specs=$(printf '%s\n' "$specs" | modules_add_unless_present "$DNS_MODULE_PREFIX$provider")
  fi
  while IFS= read -r spec; do
    specs=$(printf '%s\n' "$specs" | modules_add_unless_present "$spec")
  done < <(modules_bundled_specs)
  specs=$(printf '%s\n' "$specs" | awk 'NF')
  modules_validate <<<"$specs"
  printf '%s\n' "$specs"
}
