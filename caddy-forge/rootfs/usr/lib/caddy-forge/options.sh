#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Typed access to the app options the Supervisor writes to /data/options.json.
# Every accessor takes a jq path such as `.caddy.version`.
# ==============================================================================

OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"

# Prints a scalar option; prints nothing when it is unset or null.
option() {
  jq -r "($1) | if . == null then empty else tostring end" "$OPTIONS_FILE"
}

# Prints a scalar option or <default> when it is unset or empty.
option_or() {
  local value
  value=$(option "$1")
  printf '%s\n' "${value:-$2}"
}

# Prints the items of a list option, one per line.
option_lines() {
  jq -r "($1)[]? | tostring" "$OPTIONS_FILE"
}

# Succeeds when a boolean option is true.
option_is_true() {
  jq -e "($1) == true" "$OPTIONS_FILE" >/dev/null 2>&1
}

# Number of items in a list option.
option_count() {
  jq -r "($1) | length" "$OPTIONS_FILE"
}

# Reads one field of the n-th item of a list option, e.g. `option_item .simple.sites 0 domain`.
option_item() {
  local list=$1 index=$2 key=$3
  jq -r --argjson i "$index" --arg k "$key" \
    "($list)[\$i][\$k] | if . == null then empty else tostring end" "$OPTIONS_FILE"
}

# Reads a list field of the n-th item of a list option, one entry per line.
option_item_lines() {
  local list=$1 index=$2 key=$3
  jq -r --argjson i "$index" --arg k "$key" "($list)[\$i][\$k][]? | tostring" "$OPTIONS_FILE"
}

# Like option_item, but falls back to <default> for an unset or empty field.
option_item_or() {
  local value
  value=$(option_item "$1" "$2" "$3")
  printf '%s' "${value:-$4}"
}
