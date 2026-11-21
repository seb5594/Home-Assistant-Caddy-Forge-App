#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Simple mode: turns the app options into a Caddyfile.
#
# The result is written to /config/generated.Caddyfile on every start. Anything that
# does not fit the options can be added in two optional files next to it:
#   global.caddy  lines for the global options block (plugin settings, `order ...`)
#   sites.caddy   extra sites and snippets, appended after the generated sites
# ==============================================================================

: "${FORGE_CONFIG_DIR:=/config}"

ACME_LETSENCRYPT='https://acme-v02.api.letsencrypt.org/directory'
ACME_LETSENCRYPT_STAGING='https://acme-staging-v02.api.letsencrypt.org/directory'
DEFAULT_CERTIFICATE='/ssl/fullchain.pem'
DEFAULT_CERTIFICATE_KEY='/ssl/privkey.pem'
DNS_TOKEN_VARIABLE='FORGE_DNS_TOKEN'
# The app runs on the host network, where nothing maps ports for it: Caddy itself listens for HTTP on 8080
# (the router forwards port 80 to it) and for HTTPS on the standard port 443.
HTTP_PORT=8080
# shellcheck disable=SC2016  # a regular expression, nothing to expand
BCRYPT_PREFIX='^\$2[aby]\$'

# Indents every line of stdin by one tab.
caddyfile_indent() {
  awk '{ print (length($0) ? "\t" $0 : $0) }'
}

# Succeeds when a non-empty optional file exists.
caddyfile_has_file() {
  [[ -s $1 ]]
}

# ------------------------------------------------------------------------------
# Global options
# ------------------------------------------------------------------------------

caddyfile_global_block() {
  local email ca provider proxies level
  email=$(option .simple.email)
  ca=$(option_or .simple.acme_ca auto)
  provider=$(modules_dns_provider)
  level=$(option_or .log_level info)

  printf '{\n'
  printf '\thttp_port %s\n' "$HTTP_PORT"
  # On the host network a TCP admin address would be open to everything on the host: use a private socket.
  printf '\tadmin unix/%s\n' "$(adminui_socket)"
  [[ -n $email ]] && printf '\temail %s\n' "$email"
  case "$ca" in
    letsencrypt) printf '\tacme_ca %s\n' "$ACME_LETSENCRYPT" ;;
    staging) printf '\tacme_ca %s\n' "$ACME_LETSENCRYPT_STAGING" ;;
    zerossl) printf '\tcert_issuer zerossl\n' ;;
  esac
  if [[ -n $provider ]]; then
    [[ -n $(option .simple.dns_token) ]] || fail "A DNS provider is set but the DNS token is empty."
    printf '\tacme_dns %s {env.%s}\n' "$provider" "$DNS_TOKEN_VARIABLE"
  fi
  printf '\tlog {\n\t\tlevel %s\n\t\tformat console\n\t}\n' "${level^^}"
  proxies=$(option_lines .simple.trusted_proxies | tr '\n' ' ')
  if [[ -n ${proxies// /} ]]; then
    printf '\tservers {\n\t\ttrusted_proxies static %s\n\t}\n' "${proxies% }"
  fi
  if caddyfile_has_file "$FORGE_CONFIG_DIR/global.caddy"; then
    printf '\timport %s/global.caddy\n' "$FORGE_CONFIG_DIR"
  fi
  printf '}\n\n'
}

# ------------------------------------------------------------------------------
# Snippets shared by all generated sites
# ------------------------------------------------------------------------------

caddyfile_defaults_snippet() {
  printf '(forge_defaults) {\n'
  if option_is_true .simple.compression; then
    printf '\tencode zstd gzip\n'
  fi
  if option_is_true .simple.security_headers; then
    printf '\theader {\n\t\tX-Content-Type-Options nosniff\n\t\tReferrer-Policy strict-origin-when-cross-origin\n\t\t-Server\n\t}\n'
  fi
  if option_is_true .simple.access_log; then
    printf '\tlog {\n\t\tformat console\n\t}\n'
  fi
  printf '}\n\n'
}

# ------------------------------------------------------------------------------
# Sites
# ------------------------------------------------------------------------------

# `a.com,b.com` -> `a.com, b.com`; with plain HTTP every address gets an `http://` prefix.
caddyfile_address() {
  local domains=$1 tls=$2 token result=''
  for token in ${domains//,/ }; do
    if [[ $tls == off && $token != *://* ]]; then
      token="http://$token"
    fi
    result+="${result:+, }$token"
  done
  printf '%s' "$result"
}

# bcrypt hashes pass through, plain passwords are hashed with the shipped Caddy.
caddyfile_password_hash() {
  local password=$1
  if [[ $password =~ $BCRYPT_PREFIX ]]; then
    printf '%s' "$password"
  else
    "$FORGE_BUNDLED_CADDY" hash-password --plaintext "$password"
  fi
}

caddyfile_site_tls() {
  local tls=$1
  case "$tls" in
    internal) printf 'tls internal\n' ;;
    custom) printf 'tls %s %s\n' "$DEFAULT_CERTIFICATE" "$DEFAULT_CERTIFICATE_KEY" ;;
  esac
}

# HSTS is only sent where the browser can verify the certificate: it would take away the
# "continue anyway" button for certificates from Caddy's own authority.
caddyfile_site_hsts() {
  local tls=$1
  if option_is_true .simple.security_headers && [[ $tls == auto || $tls == custom ]]; then
    printf 'header Strict-Transport-Security "max-age=31536000"\n'
  fi
}

# The handler of one site: what is served once the visitor is let in.
caddyfile_site_handler() {
  local type=$1 target=$2 skip_verify=$3 user=$4 password=$5
  if [[ -n $user && -n $password ]]; then
    printf 'basic_auth {\n\t"%s" %s\n}\n' "$user" "$(caddyfile_password_hash "$password")"
  fi
  case "$type" in
    proxy)
      if [[ $skip_verify == true ]]; then
        printf 'reverse_proxy %s {\n\ttransport http {\n\t\ttls_insecure_skip_verify\n\t}\n}\n' "$target"
      else
        printf 'reverse_proxy %s\n' "$target"
      fi
      ;;
    static)
      printf 'root * %s\nfile_server\n' "$target"
      ;;
    git)
      printf 'root * %s\nfile_server {\n\thide .git\n}\n' "$target"
      ;;
    redirect)
      [[ $target == *'{'* ]] || target+='{uri}'
      printf 'redir %s permanent\n' "$target"
      ;;
  esac
}

# One site block from the n-th entry of `simple.sites`.
caddyfile_site() {
  local i=$1 domain type target tls skip_verify user password allowed
  domain=$(option_item .simple.sites "$i" domain)
  type=$(option_item_or .simple.sites "$i" type proxy)
  target=$(option_item .simple.sites "$i" target)
  tls=$(option_item_or .simple.sites "$i" tls auto)
  skip_verify=$(option_item_or .simple.sites "$i" skip_verify false)
  user=$(option_item .simple.sites "$i" auth_user)
  password=$(option_item .simple.sites "$i" auth_password)
  [[ -n $domain ]] || fail "Site #$((i + 1)) has no domain."
  [[ -n $target ]] || fail "Site '$domain' has no target."
  if [[ $type == git ]]; then
    target=$(gitsite_root "$i")
  fi
  allowed=$(option_item_lines .simple.sites "$i" allow_from | tr '\n' ' ')

  printf '%s {\n' "$(caddyfile_address "$domain" "$tls")"
  {
    caddyfile_site_tls "$tls"
    caddyfile_site_hsts "$tls"
    printf 'import forge_defaults\n'
    option_item_lines .simple.sites "$i" extra | awk 'NF'
    if [[ -n ${allowed// /} ]]; then
      printf '@allowed client_ip %s\n' "${allowed% }"
      printf 'handle @allowed {\n'
      caddyfile_site_handler "$type" "$target" "$skip_verify" "$user" "$password" | caddyfile_indent
      printf '}\nhandle {\n\trespond "Forbidden" 403\n}\n'
    else
      caddyfile_site_handler "$type" "$target" "$skip_verify" "$user" "$password"
    fi
  } | caddyfile_indent
  printf '}\n\n'
}

caddyfile_sites() {
  local count i
  count=$(option_count .simple.sites)
  if ((count == 0)); then
    log_warn "No sites are configured; Caddy will start without serving anything."
    return 0
  fi
  caddyfile_defaults_snippet
  for ((i = 0; i < count; i++)); do
    caddyfile_site "$i"
  done
}

# ------------------------------------------------------------------------------
# Entry points
# ------------------------------------------------------------------------------

# Prints the complete Caddyfile for the current options.
caddyfile_generate() {
  printf '# Generated by Caddy Forge from the app options (simple mode).\n'
  printf '# Rewritten on every start: change the options or put extras into %s/sites.caddy.\n\n' "$FORGE_CONFIG_DIR"
  caddyfile_global_block
  caddyfile_sites
  if caddyfile_has_file "$FORGE_CONFIG_DIR/sites.caddy"; then
    printf '# Your own sites and snippets\nimport %s/sites.caddy\n' "$FORGE_CONFIG_DIR"
  fi
}

# Runs a Caddyfile (stdin) through Caddy's own formatter so it never triggers the
# "not formatted" warning; unchanged when the formatter cannot parse it.
caddyfile_format() {
  local raw
  raw=$(cat)
  "$FORGE_BUNDLED_CADDY" fmt - <<<"$raw" 2>/dev/null || printf '%s\n' "$raw"
}

# Writes the simple-mode Caddyfile to <path> via a temporary file, so a failing
# generator never leaves a half-written Caddyfile behind.
caddyfile_write() {
  local target=$1 scratch
  scratch=$(mktemp)
  if ! caddyfile_generate | caddyfile_format >"$scratch"; then
    rm -f "$scratch"
    return 1
  fi
  mv -f "$scratch" "$target"
  chmod 644 "$target"
}

# First start in Caddyfile mode: hand the user the simple-mode result as a starting point.
caddyfile_seed_pro_mode() {
  local target=$1 scratch
  [[ -e $target ]] && return 0
  scratch=$(mktemp)
  {
    printf '# Seeded by Caddy Forge from your simple-mode options on %s.\n' "$(date '+%Y-%m-%d')"
    printf '# This file is yours now: while the mode is "advanced (caddyfile)", the simple options are ignored.\n'
    printf '# Reference: https://caddyserver.com/docs/caddyfile\n\n'
    caddyfile_generate | tail -n +3
  } | caddyfile_format >"$scratch" || {
    printf '# Caddy Forge starter. Reference: https://caddyserver.com/docs/caddyfile\n\n:80 {\n\trespond "Caddy Forge is running" 200\n}\n' >"$scratch"
  }
  mv -f "$scratch" "$target"
  chmod 644 "$target"
  log_info "Created $target from your simple-mode options."
}
