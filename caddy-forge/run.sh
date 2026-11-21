#!/usr/bin/env bash
# ==============================================================================
# Caddy Forge: pick or build the right Caddy binary, then run the web server.
#
#   1. read the options and prepare the environment
#   2. produce the Caddyfile (simple mode: generated from options, pro mode: yours)
#   3. choose the binary: shipped, previously built or freshly built with plugins
#   4. start Caddy, or stop after the build when so configured
# ==============================================================================
# shellcheck source-path=SCRIPTDIR/rootfs/usr/lib/caddy-forge
set -Eeuo pipefail

FORGE_LIB_DIR="${FORGE_LIB_DIR:-/usr/lib/caddy-forge}"
# shellcheck source=log.sh
source "$FORGE_LIB_DIR/log.sh"
# shellcheck source=options.sh
source "$FORGE_LIB_DIR/options.sh"
# shellcheck source=modules.sh
source "$FORGE_LIB_DIR/modules.sh"
# shellcheck source=versions.sh
source "$FORGE_LIB_DIR/versions.sh"
# shellcheck source=builder.sh
source "$FORGE_LIB_DIR/builder.sh"
# shellcheck source=caddyfile.sh
source "$FORGE_LIB_DIR/caddyfile.sh"

readonly REQUIRED_TOOLS=(curl jq go git xcaddy)
readonly ENV_NAME_PATTERN='^[A-Za-z_][A-Za-z0-9_]*$'
GENERATED_CADDYFILE="$FORGE_CONFIG_DIR/generated.Caddyfile"
USER_CADDYFILE="$FORGE_CONFIG_DIR/Caddyfile"
CADDYFILE=''

require_tools() {
  local tool
  for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool '$tool' is missing from the image."
  done
}

# Caddy keeps certificates and its state below /data, so they survive restarts and ride along in backups.
prepare_directories() {
  mkdir -p "$FORGE_DATA_DIR/data" "$FORGE_DATA_DIR/config" "$FORGE_CONFIG_DIR"
  export XDG_DATA_HOME="$FORGE_DATA_DIR/data" XDG_CONFIG_HOME="$FORGE_DATA_DIR/config"
}

# Makes the `env_vars` option and the DNS token available as {env.NAME} inside Caddy.
export_variables() {
  local count i name value token
  count=$(option_count .env_vars)
  for ((i = 0; i < count; i++)); do
    name=$(option_item .env_vars "$i" name)
    value=$(option_item .env_vars "$i" value)
    [[ $name =~ $ENV_NAME_PATTERN ]] || fail "Environment variable name '$name' is invalid (letters, digits and '_' only)."
    export "$name=$value"
  done
  token=$(option .simple.dns_token)
  if [[ -n $token ]]; then
    export "$DNS_TOKEN_VARIABLE=$token"
  fi
}

# Sets CADDYFILE to the file Caddy will load.
prepare_caddyfile() {
  local mode
  mode=$(option_or .mode simple)
  case "$mode" in
    simple)
      caddyfile_write "$GENERATED_CADDYFILE"
      CADDYFILE=$GENERATED_CADDYFILE
      ;;
    caddyfile)
      caddyfile_seed_pro_mode "$USER_CADDYFILE"
      if option_is_true .format_caddyfile; then
        "$FORGE_BUNDLED_CADDY" fmt --overwrite "$USER_CADDYFILE" || log_warn "Could not format $USER_CADDYFILE"
      fi
      CADDYFILE=$USER_CADDYFILE
      ;;
    *) fail "Unknown mode '$mode' (use 'simple' or 'caddyfile')." ;;
  esac
}

# Caddy creates its own certificate authority the first time a site uses `tls internal`.
# Copy its root certificate into the app's config folder so it can be installed on devices.
export_root_certificate() {
  local source="$XDG_DATA_HOME/caddy/pki/authorities/local/root.crt"
  local target="$FORGE_CONFIG_DIR/caddy-root-ca.crt" waited=0
  while [[ ! -s $source ]] && ((waited < 120)); do
    sleep 2
    waited=$((waited + 2))
  done
  if [[ -s $source ]] && ! cmp -s "$source" "$target"; then
    cp "$source" "$target"
    log_info "Root certificate for 'tls internal' sites: $target (install it on your devices to remove browser warnings)"
  fi
}

uses_internal_certificates() {
  grep -Eq '(^|[[:space:]])(tls[[:space:]]+internal|local_certs)' "$CADDYFILE"
}

start_server() {
  log_info "Starting Caddy $(builder_binary_version "$CADDY_BIN")"
  if uses_internal_certificates; then
    export_root_certificate &
    disown
  fi
  cd "$FORGE_CONFIG_DIR"
  exec "$CADDY_BIN" run --config "$CADDYFILE" --adapter caddyfile
}

main() {
  LOG_LEVEL=$(option_or .log_level info)
  log_info "Caddy Forge ${APP_VERSION:-dev} on $(uname -m), mode: $(option_or .mode simple)"
  require_tools
  prepare_directories
  export_variables
  builder_load_request
  prepare_caddyfile
  builder_select_binary "$CADDYFILE"
  if [[ $(option_or .caddy.start_server true) != true ]]; then
    log_info "Build-only run finished; the web server is not started because 'start_server' is off."
    return 0
  fi
  start_server
}

# Run only when executed; sourcing the file lets tests call the functions directly.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
