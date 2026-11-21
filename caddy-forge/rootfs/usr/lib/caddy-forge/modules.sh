#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# The plugin list: clean up what the user typed, validate it and split a
# specification such as `github.com/caddy-dns/cloudflare@v0.2.1` into its parts.
# ==============================================================================

# <go module path>[/sub/package][@version][=replacement]
MODULE_PATTERN='^[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)+(@[A-Za-z0-9._+~/-]+)?(=[^[:space:]]+)?$'
# DNS providers are published as github.com/caddy-dns/<provider>.
DNS_PROVIDER_PATTERN='^[a-z0-9][a-z0-9_-]*$'
DNS_MODULE_PREFIX='github.com/caddy-dns/'
ADMIN_UI_MODULE='github.com/gsmlg-dev/caddy-admin-ui'
# Rewrites the UI's pages on their way out, which is how the footer gets in.
ADMIN_UI_REPLACE_MODULE='github.com/caddyserver/replace-response'

# Normalizes raw module lines (stdin) into one specification per line (stdout).
# People paste lines straight from xcaddy commands, so a leading `--with`, trailing
# backslashes and `#` comments are accepted and dropped; duplicates are removed.
modules_clean() {
  sed -E 's/#.*$//; s/[[:space:]]+$//; s/\\$//' \
    | sed -E 's/(^|[[:space:]])--with[[:space:]=]+/\n/g' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | awk 'NF && !seen[$0]++'
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

# Appends <path> to the specifications (stdin to stdout) unless the user already listed that module,
# with or without a version.
modules_add_unless_present() {
  local path=$1 specs found=false spec
  specs=$(cat)
  while IFS= read -r spec; do
    if [[ -n $spec && $(modules_path "$spec") == "$path" ]]; then
      found=true
    fi
  done <<<"$specs"
  if [[ $found == false ]]; then
    specs+=$'\n'"$path"
  fi
  printf '%s\n' "$specs" | awk 'NF'
}

# Every plugin to build in: the user's list plus what the chosen features need
# (the DNS provider's module, the admin UI).
modules_requested() {
  local specs provider
  specs=$(option_lines .caddy.modules | modules_clean)
  provider=$(modules_dns_provider)
  if [[ -n $provider ]]; then
    specs=$(printf '%s\n' "$specs" | modules_add_unless_present "$DNS_MODULE_PREFIX$provider")
  fi
  if option_is_true .admin_ui.enabled; then
    specs=$(printf '%s\n' "$specs" | modules_add_unless_present "$ADMIN_UI_MODULE" | modules_add_unless_present "$ADMIN_UI_REPLACE_MODULE")
  fi
  specs=$(printf '%s\n' "$specs" | awk 'NF')
  printf '%s\n' "$specs" | modules_validate
  if [[ -n $specs ]]; then
    printf '%s\n' "$specs"
  fi
  return 0
}
