#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Moving from nginx: if a nginx.conf is dropped into the config folder's `migrate`
# folder and the nginx adapter plugin is part of the binary, it is converted on start.
# The adapter writes Caddy's JSON format; it is a starting point for rewriting the
# setup as sites, not a replacement (the adapter covers only part of nginx).
# ==============================================================================

NGINX_ADAPTER_MODULE='github.com/caddyserver/nginx-adapter'

migrate_nginx() {
  local dir="$FORGE_CONFIG_DIR/migrate" source target output line
  source="$dir/nginx.conf"
  target="$dir/nginx.converted.json"
  [[ -f $source ]] || return 0

  if ! "$CADDY_BIN" list-modules 2>/dev/null | grep -qx 'caddy.adapters.nginx'; then
    log_warn "Found $source, but this Caddy has no nginx adapter. Add the plugin $NGINX_ADAPTER_MODULE to the plugin list."
    return 0
  fi
  if output=$("$CADDY_BIN" adapt --adapter nginx --config "$source" --pretty 2>"$dir/.adapter.log"); then
    printf '%s\n' "$output" >"$target"
    log_info "Converted $source to $target. Directives the adapter does not know are listed below."
  else
    log_warn "The nginx adapter could not convert $source:"
  fi
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      log_warn "nginx adapter: $line"
    fi
  done <"$dir/.adapter.log"
  rm -f "$dir/.adapter.log"
  return 0
}
