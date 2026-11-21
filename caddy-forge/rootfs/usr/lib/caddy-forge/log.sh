#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Leveled logging. Messages go to stderr (the Supervisor shows both streams in order)
# so that functions which print a result on stdout can log without polluting it.
# ==============================================================================

LOG_LEVEL="${LOG_LEVEL:-info}"

LOG_COLOR_RESET=$'\033[0m'

# Numeric rank of a level name; unknown names count as "info".
log_rank() {
  case "$1" in
    debug) echo 0 ;;
    warn | warning) echo 2 ;;
    error) echo 3 ;;
    *) echo 1 ;;
  esac
}

# log_write <level> <ansi-color-code> <message...>
log_write() {
  local level=$1 color=$2
  shift 2
  if (($(log_rank "$level") < $(log_rank "$LOG_LEVEL"))); then
    return 0
  fi
  local stamp
  stamp=$(date '+%H:%M:%S')
  if [[ -n ${NO_COLOR:-} ]]; then
    printf '[%s] %-5s %s\n' "$stamp" "${level^^}" "$*" >&2
  else
    printf '\033[%sm[%s] %-5s %s%s\n' "$color" "$stamp" "${level^^}" "$*" "$LOG_COLOR_RESET" >&2
  fi
}

log_debug() { log_write debug 90 "$@"; }
log_info() { log_write info 32 "$@"; }
log_warn() { log_write warn 33 "$@"; }
log_error() { log_write error 31 "$@"; }

# Prints an error and stops the whole app with a failing exit code.
fail() {
  log_error "$@"
  exit 1
}
