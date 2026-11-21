#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Tiny assertion helpers. Every passing check prints "PASS: <name>"; the pipeline
# counts those lines for the README badge.
# ==============================================================================

TEST_TMP=$(mktemp -d)
FAILURES_FILE="$TEST_TMP/failures"
trap 'rm -rf -- "${TEST_TMP:?}"' EXIT

pass() {
  printf 'PASS: %s\n' "$1"
}

flunk() {
  printf 'FAIL: %s\n' "$1" >&2
  # A file, not a counter: every test runs in its own subshell.
  printf '%s\n' "$1" >>"$FAILURES_FILE"
}

assert_equals() {
  local expected=$1 actual=$2 name=$3
  if [[ $actual == "$expected" ]]; then
    pass "$name"
  else
    flunk "$name"
    printf '  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
  fi
}

assert_contains() {
  local haystack=$1 needle=$2 name=$3
  if [[ $haystack == *"$needle"* ]]; then
    pass "$name"
  else
    flunk "$name"
    printf '  missing: %s\n  in:\n%s\n' "$needle" "$haystack" >&2
  fi
}

assert_not_contains() {
  local haystack=$1 needle=$2 name=$3
  if [[ $haystack != *"$needle"* ]]; then
    pass "$name"
  else
    flunk "$name"
    printf '  unexpected: %s\n' "$needle" >&2
  fi
}

# assert_succeeds <name> <command...>: runs in a subshell so `fail`/`exit` cannot end the suite.
assert_succeeds() {
  local name=$1
  shift
  if ("$@") >/dev/null 2>&1; then pass "$name"; else flunk "$name"; fi
}

assert_fails() {
  local name=$1
  shift
  if ("$@") >/dev/null 2>&1; then flunk "$name"; else pass "$name"; fi
}

# Starts every test from the default options, optionally changed by a jq filter:
#   use_options '.caddy.modules = ["github.com/a/b"]'
use_options() {
  local filter=${1:-.}
  OPTIONS_FILE="$TEST_TMP/options.json"
  jq "$filter" "${TEST_DIR:-/tests}/fixtures/options.json" >"$OPTIONS_FILE"
  export OPTIONS_FILE
}

# Gives a test its own empty data and config folders.
use_clean_folders() {
  FORGE_DATA_DIR=$(mktemp -d "$TEST_TMP/data.XXXXXX")
  FORGE_CONFIG_DIR=$(mktemp -d "$TEST_TMP/config.XXXXXX")
  FORGE_WORK_DIR="$TEST_TMP/work"
  FORGE_RUN_DIR=$(mktemp -d "$TEST_TMP/run.XXXXXX")
  export FORGE_DATA_DIR FORGE_CONFIG_DIR FORGE_WORK_DIR FORGE_RUN_DIR
  builder_init_paths
}

# The requested plugins without the two of the admin UI that every build contains.
requested_without_bundled() {
  modules_requested | grep -vxF -f <(modules_bundled_specs) || true
}
