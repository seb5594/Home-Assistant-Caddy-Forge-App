#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# One app instead of two: take over the settings of the Caddy 2 app and the
# CaddyBuilder app.
#
# Switched on with the option `takeover`, it reads
#   * the build command of CaddyBuilder (xcaddyCommand.sh): the Caddy version and
#     every `--with` plugin, commented-out ones as disabled entries, and
#   * the Caddyfile of the Caddy 2 app (and the plugins of its custom binary when
#     there is no build command), whose use switches the mode to advanced,
# enters the result into this app's own options through the Supervisor API, switches
# `takeover` off again and restarts the app. Existing entries and settings are kept.
# The options of the old apps themselves (domain, email, environment variable values)
# are stored in their data folders and cannot be read; the migration guide maps them.
# ==============================================================================

: "${FORGE_SUPERVISOR_URL:=http://supervisor}"

# Reads an xcaddyCommand.sh and prints what it asks for, tab separated:
#   version <caddy version or branch>
#   with <module spec> <1 = active, 0 = commented out>
#   ignored <flag and value that have no counterpart here>
# The script may spread the command over lines with a trailing backslash; commented-out lines
# that carry a `--with` become disabled entries, other comments are ignored. Active entries come first.
takeover_parse_xcaddy() {
  awk '
    function collect(text, enabled,    n, t, i, spec) {
      n = split(text, t, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        spec = ""
        if (t[i] == "--with") { spec = t[i + 1]; i++ }
        else if (t[i] ~ /^--with=/) { spec = substr(t[i], 8) }
        if (spec == "") { continue }
        if (enabled) { active = active "with\t" spec "\t1\n" } else { disabled = disabled "with\t" spec "\t0\n" }
      }
    }
    /^[ \t]*#/ {
      if ($0 ~ /--with/) {
        line = $0
        sub(/^[ \t]*#+[ \t]*/, "", line)
        sub(/[ \t]+#.*$/, "", line)
        collect(line, 0)
      }
      next
    }
    {
      line = $0
      sub(/[ \t]+#.*$/, "", line)
      if (building || line ~ /xcaddy/) {
        building = 1
        continued = (line ~ /\\[ \t]*$/)
        sub(/\\[ \t]*$/, "", line)
        command = command " " line
        if (!continued) { building = 0 }
      }
    }
    END {
      n = split(command, t, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (t[i] == "build" && t[i + 1] != "" && t[i + 1] !~ /^-/) { print "version\t" t[i + 1] }
        if (t[i] == "--replace" || t[i] == "--embed" || t[i] == "--pgo") { print "ignored\t" t[i] " " t[i + 1]; i++ }
      }
      collect(command, 1)
      printf "%s%s", active, disabled
    }' "$1"
}

# `latest` stays, `v2.9.1` becomes `2.9.1` (the form of the option); branches and commits pass through.
takeover_version_option() {
  local version=$1
  if [[ ${version,,} == latest ]]; then
    printf 'latest'
  else
    printf '%s' "${version#v}"
  fi
}

# Events (stdin, see takeover_parse_xcaddy) to plugin entries as a JSON array.
takeover_plugin_entries() {
  local kind spec enabled expanded path ref
  while IFS=$'\t' read -r kind spec enabled; do
    [[ $kind == with ]] || continue
    expanded=$(modules_expand "$spec")
    if [[ $expanded == *=* ]]; then
      path=$expanded
      ref=''
    else
      path=$(modules_path "$expanded")
      ref=$(modules_ref "$expanded")
    fi
    printf '%s\037%s\037%s\n' "$path" "$ref" "$enabled"
  done | jq -Rn '[inputs | split("\u001f") | {module: .[0], version: .[1], enabled: (.[2] == "1")}
    | if .version == "" then del(.version) else . end]'
}

# The current options with the old apps' settings added. Arguments: plugin entries (JSON array), Caddy version
# option ("" = leave), mode ("" = leave), names of environment variables (JSON array), the shipped version.
# Entries that are already there (compared by module, whether written as owner/repo or as a full path) are kept as
# they are; the Caddy version only changes while it still is the shipped default.
takeover_merge_options() {
  jq --argjson plugins "$1" --arg version "$2" --arg mode "$3" --argjson envs "$4" --arg shipped "$5" '
    def key: ascii_downcase | sub("^https?://"; "") | sub("^github[.]com/"; "") | sub("[.]git$"; "") | sub("[@=].*$"; "");
    ((.caddy.modules // []) | map(if type == "string" then {module: .} else . end)) as $current
    | ($current | map(.module | key)) as $known
    | ((.env_vars // []) | map(.name)) as $defined
    | .caddy.modules = ($current + ($plugins | map(select((.module | key) as $k | ($known | index($k)) == null))))
    | (if $version != "" and (.caddy.version | tostring) == $shipped then .caddy.version = $version else . end)
    | (if $mode != "" then .mode = $mode else . end)
    | .env_vars = ((.env_vars // []) + ($envs | map(select(. as $n | ($defined | index($n)) == null) | {name: ., value: ""})))
    | .takeover = false' "$OPTIONS_FILE"
}

# Stores the options through the Supervisor and asks it to restart this app. Both routes exist on every
# Supervisor: `/addons/...` is the old spelling, still served after the rename to apps.
takeover_apply() {
  local merged=$1 reply
  if [[ -z ${SUPERVISOR_TOKEN:-} ]]; then
    log_error "No Supervisor token: the options can not be stored from here."
    return 1
  fi
  reply=$(jq -n --argjson options "$(cat "$merged")" '{options: $options}' \
    | curl --silent --show-error --max-time 30 -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H 'Content-Type: application/json' --data-binary @- "$FORGE_SUPERVISOR_URL/addons/self/options") || reply=''
  if [[ $(jq -r '.result // empty' <<<"$reply" 2>/dev/null) != ok ]]; then
    log_error "The Supervisor did not accept the new options: $(jq -r '.message // empty' <<<"$reply" 2>/dev/null || true)"
    return 1
  fi
  return 0
}

takeover_restart() {
  curl --silent --show-error --max-time 30 -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    "$FORGE_SUPERVISOR_URL/addons/self/restart" >/dev/null
}

# Runs the takeover. Succeeds when new options were stored and a restart was requested (the caller then
# ends); fails when there was nothing to take over or the Supervisor refused, so the app starts as usual.
takeover_run() {
  local caddy2 builder events='' plugins='[]' version='' mode='' envs='[]' ignored scratch
  caddy2=$(migrate_caddy2_folder) || caddy2=''
  builder=$(migrate_builder_folder) || builder=''
  if [[ -z $caddy2 && -z $builder ]]; then
    log_warn "Takeover: found neither the Caddy 2 nor the CaddyBuilder app's config folder. Turn the option off or install/keep the apps until this ran."
    return 1
  fi

  if [[ -n $builder ]]; then
    events=$(takeover_parse_xcaddy "$builder/xcaddyCommand.sh")
    log_info "Takeover: read the build command of the CaddyBuilder app ($(basename "$builder"))."
    ignored=$(awk -F'\t' '$1 == "ignored" { print $2 }' <<<"$events" | tr '\n' ';')
    if [[ -n $ignored ]]; then
      log_warn "Not taken over (no counterpart here): ${ignored%;}"
    fi
  fi
  if [[ -n $caddy2 ]]; then
    if [[ -f $caddy2/Caddyfile && ! -e $FORGE_CONFIG_DIR/Caddyfile && $(option_or .mode simple) == simple ]]; then
      mode='advanced (caddyfile)'
      envs=$(migrate_variable_names "$caddy2/Caddyfile" | jq -Rn '[inputs | select(length > 0)]')
      log_info "Takeover: the Caddyfile of the Caddy 2 app will be imported (mode: advanced)."
    fi
    if [[ -z $builder ]]; then
      # No build command: the plugin packages of its binary are the next best source.
      events=$(migrate_binary_plugins "$caddy2/caddy" | awk '{ print "with\t" $0 "\t1" }')
    fi
  fi

  plugins=$(takeover_plugin_entries <<<"$events")
  version=$(awk -F'\t' '$1 == "version" { print $2; exit }' <<<"$events")
  [[ -z $version ]] || version=$(takeover_version_option "$version")

  scratch=$(mktemp)
  takeover_merge_options "$plugins" "$version" "$mode" "$envs" "$(builder_bundled_version)" >"$scratch"
  log_info "Takeover: $(jq length <<<"$plugins") plugin(s) found, Caddy version '${version:-unchanged}', mode '${mode:-unchanged}'."
  if ! takeover_apply "$scratch"; then
    rm -f "$scratch"
    return 1
  fi
  rm -f "$scratch"
  log_info "Takeover done: the options were updated and 'takeover' switched off. Restarting to apply them ..."
  if ! takeover_restart; then
    log_warn "The restart could not be requested; the new options apply the next time the app starts."
    return 2
  fi
  return 0
}
