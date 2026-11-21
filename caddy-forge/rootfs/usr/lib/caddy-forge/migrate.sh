#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Moving from other setups.
#
# Caddy 2 app: its Caddyfile (and the small files next to it) is imported when the mode is
# switched to "advanced (caddyfile)" and no Caddyfile exists here yet. The app's config folder is
# readable through the `all_addon_configs` mount, read-only.
#
# nginx: if a nginx.conf is dropped into the config folder's `migrate`
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

# ------------------------------------------------------------------------------
# Caddy 2 app
# ------------------------------------------------------------------------------

# Where the config folders of all apps are mounted: /addon_configs with the legacy map type
# (`all_addon_configs`, which this app uses so that it also installs on older Home Assistant versions),
# /app_configs with the new one (`all_app_configs`). Both are looked at; FORGE_APP_CONFIG_ROOTS
# (space separated) replaces them, which is how the tests use it.
migrate_config_roots() {
  # shellcheck disable=SC2086  # a list of folders, split on purpose
  printf '%s\n' ${FORGE_APP_CONFIG_ROOTS:-/app_configs /addon_configs}
}
MIGRATE_MAX_FILE_KB=5120
MIGRATE_MAX_FILES=200

# Prints the config folder of an app: <folder patterns, space separated> <marker files...>. A folder
# counts when it holds at least one of the marker files. The folder is named <repository hash>_<slug>.
migrate_app_folder() {
  local patterns=$1 root pattern folder marker
  shift
  while IFS= read -r root; do
    for pattern in $patterns; do
      # shellcheck disable=SC2231  # the pattern is a glob on purpose
      for folder in "$root"/$pattern; do
        [[ -d $folder ]] || continue
        for marker in "$@"; do
          if [[ -f $folder/$marker ]]; then
            printf '%s' "$folder"
            return 0
          fi
        done
      done
    done
  done < <(migrate_config_roots)
  return 1
}

# The Caddy 2 app (Caddyfile and optionally its own `caddy` binary).
migrate_caddy2_folder() {
  migrate_app_folder '*_caddy-2 *_caddy_2' Caddyfile caddy
}

# The CaddyBuilder app, whose build command is the file xcaddyCommand.sh.
migrate_builder_folder() {
  migrate_app_folder '*_caddybuilder *_caddy-builder *_caddy_builder' xcaddyCommand.sh
}

# Simple mode: tells once per start that an import is possible.
migrate_caddy2_hint() {
  local target=$1 folder
  [[ -e $target ]] && return 0
  folder=$(migrate_caddy2_folder) || return 0
  if [[ -f $folder/Caddyfile ]]; then
    log_info "Found the Caddyfile of the Caddy 2 app. Set the mode to 'advanced (caddyfile)' to import it."
  fi
}

# Copies the small files next to the Caddyfile (snippets, a www folder) so that `/config/...` paths in the
# imported Caddyfile keep working. The binary and the Caddyfile itself are left out, existing files stay.
migrate_copy_companions() {
  local source=$1 target=$2 copied=0 skipped=0 file
  while IFS= read -r file; do
    [[ -n $file && ! -e $target/$file ]] || continue
    if ((copied >= MIGRATE_MAX_FILES)); then
      skipped=$((skipped + 1))
      continue
    fi
    mkdir -p "$target/$(dirname "$file")"
    cp "$source/$file" "$target/$file"
    copied=$((copied + 1))
  done < <(cd "$source" && find . -type f ! -path ./caddy ! -path ./Caddyfile ! -size +"${MIGRATE_MAX_FILE_KB}k" | sed 's|^\./||')
  if ((copied > 0)); then
    log_info "Copied $copied more file(s) from the Caddy 2 app's folder."
  fi
  if ((skipped > 0)); then
    log_warn "Skipped $skipped file(s): at most $MIGRATE_MAX_FILES files of up to $((MIGRATE_MAX_FILE_KB / 1024)) MB are copied."
  fi
}

# The Caddy 2 app runs on the host network, where Home Assistant is `localhost:8123`. Here it is
# `homeassistant:8123`; other local addresses cannot be guessed, so they are only pointed out.
migrate_adjust_upstreams() {
  local file=$1 changed others
  changed=$(grep -c -E '(localhost|127[.]0[.]0[.]1|\[::1\]):8123' "$file" || true)
  if ((changed > 0)); then
    sed -i -E 's/(localhost|127[.]0[.]0[.]1|\[::1\]):8123/homeassistant:8123/g' "$file"
    log_info "Changed $changed address(es) from localhost:8123 to homeassistant:8123, because this app does not use the host network."
  fi
  others=$(grep -v '^[[:space:]]*#' "$file" | grep -c -E '(localhost|127[.]0[.]0[.]1|\[::1\]):[0-9]+' || true)
  if ((others > 0)); then
    log_warn "$others line(s) of the imported Caddyfile still point at localhost or 127.0.0.1. Inside this app that is the app itself: use the address or host name of the service instead."
  fi
}

# Names of the environment variables a Caddyfile uses (`{$NAME}` or `{env.NAME}`), one per line.
migrate_variable_names() {
  grep -o -E '[{](\$|env[.])[A-Za-z_][A-Za-z0-9_]*' "$1" | sed -E 's/^[{](\$|env[.])//' | sort -u || true
}

# Environment variables are not copied (they live in the other app's options): name the ones the
# imported Caddyfile needs and that are not defined here yet.
migrate_report_variables() {
  local file=$1 name missing=()
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    if [[ -z $(jq -r --arg n "$name" '.env_vars[]? | select(.name == $n) | .name' "$OPTIONS_FILE") ]]; then
      missing+=("$name")
    fi
  done < <(migrate_variable_names "$file")
  if ((${#missing[@]} > 0)); then
    log_warn "The imported Caddyfile uses the environment variables ${missing[*]}. Add them under 'Environment variables'; their values were not copied."
  fi
}

# The plugin packages of a custom Caddy binary, one per line (the binary is started once, with a time limit).
migrate_binary_plugins() {
  [[ -x $1 ]] || return 0
  timeout 20 "$1" list-modules --skip-standard --packages 2>/dev/null \
    | awk 'NF == 2 && $2 !~ /caddyserver\/caddy\/v2$/ { print $2 }' | sort -u || true
}

# The plugins of the other app's custom binary, as a list ready for the 'Plugins' option.
migrate_report_plugins() {
  local plugins
  plugins=$(migrate_binary_plugins "$1/caddy" | tr '\n' ' ')
  if [[ -n ${plugins// /} ]]; then
    log_warn "The custom Caddy of the Caddy 2 app contains these plugins; add them under 'Plugins' (one entry each): ${plugins% }"
  fi
}

# Imports the Caddyfile of the Caddy 2 app as <target>. Succeeds only if something was imported;
# an existing Caddyfile is never touched.
migrate_caddy2_import() {
  local target=$1 folder scratch
  [[ -e $target ]] && return 1
  folder=$(migrate_caddy2_folder) || return 1
  [[ -f $folder/Caddyfile ]] || return 1
  scratch=$(mktemp)
  {
    printf '# Imported from the Caddy 2 app (%s) on %s.\n# This file is yours now; the app does not change it.\n\n' "$(basename "$folder")" "$(date '+%Y-%m-%d')"
    cat "$folder/Caddyfile"
  } >"$scratch"
  mv -f "$scratch" "$target"
  chmod 644 "$target"
  log_info "Imported the Caddyfile of the Caddy 2 app to $target."
  migrate_adjust_upstreams "$target"
  migrate_copy_companions "$folder" "$(dirname "$target")"
  migrate_report_variables "$target"
  migrate_report_plugins "$folder"
  return 0
}
