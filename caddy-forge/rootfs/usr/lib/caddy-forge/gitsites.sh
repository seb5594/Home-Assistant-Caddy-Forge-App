#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Websites that live in a git repository (site type "git").
#
# The app keeps a shallow clone below /data/sites, fetches it before Caddy starts and
# then every few minutes. Plain git over HTTPS does the job, so no plugin and no build
# is needed. Private repositories work with a token inside the URL.
# ==============================================================================

: "${FORGE_SITES_DIR:=/data/sites}"
GIT_DEFAULT_REFRESH=30
GIT_TIMEOUT=300

# `Docs.Example.org, www.example.org` -> `docs-example-org`
gitsite_slug() {
  local first=${1%%[, ]*}
  first=${first,,}
  first=${first//[^a-z0-9]/-}
  while [[ $first == *--* ]]; do
    first=${first//--/-}
  done
  first=${first#-}
  printf '%s' "${first%-}"
}

# Hides credentials in URLs (stdin to stdout) before anything is logged.
gitsite_mask() {
  sed -E 's#(://)[^/@[:space:]]*@#\1***@#g'
}

# Indexes of the sites of type git, one per line.
gitsite_indexes() {
  local count i
  count=$(option_count .simple.sites)
  for ((i = 0; i < count; i++)); do
    if [[ $(option_item .simple.sites "$i" type) == git ]]; then
      printf '%s\n' "$i"
    fi
  done
}

gitsite_dir() {
  printf '%s/%s' "$FORGE_SITES_DIR" "$(gitsite_slug "$(option_item .simple.sites "$1" domain)")"
}

# The folder Caddy serves: the checkout, or a sub folder of it (a generator's `public`, `docs` ...).
gitsite_root() {
  local folder
  folder=$(option_item .simple.sites "$1" folder)
  folder=${folder#/}
  if [[ $folder == *..* ]]; then
    fail "Site folder '$folder' must stay inside the repository."
  fi
  printf '%s%s' "$(gitsite_dir "$1")" "${folder:+/$folder}"
}

# Clones or updates the checkout of one site. Failures are reported but never stop the app:
# an offline start still serves the last checkout.
gitsite_sync() {
  local i=$1 url branch dir output
  url=$(option_item .simple.sites "$i" target)
  branch=$(option_item .simple.sites "$i" branch)
  dir=$(gitsite_dir "$i")
  export GIT_TERMINAL_PROMPT=0
  mkdir -p "$FORGE_SITES_DIR"

  if [[ -d $dir/.git ]]; then
    git -C "$dir" remote set-url origin "$url"
    if output=$(timeout "$GIT_TIMEOUT" git -C "$dir" fetch --quiet --depth 1 origin "${branch:-HEAD}" 2>&1 \
      && git -C "$dir" reset --quiet --hard FETCH_HEAD 2>&1); then
      log_debug "Updated $dir to $(git -C "$dir" rev-parse --short HEAD)"
      return 0
    fi
  elif [[ -e $dir ]]; then
    log_warn "$dir exists but is not a git checkout; leaving it alone."
    return 1
  elif output=$(timeout "$GIT_TIMEOUT" git clone --quiet --depth 1 ${branch:+--branch "$branch"} "$url" "$dir" 2>&1); then
    log_info "Cloned $(gitsite_mask <<<"$url") ($(git -C "$dir" rev-parse --short HEAD))"
    return 0
  fi
  log_warn "Could not update $(gitsite_mask <<<"$url"): $(gitsite_mask <<<"$output")"
  return 1
}

gitsite_sync_all() {
  local i
  for i in $(gitsite_indexes); do
    gitsite_sync "$i" || true
  done
}

# Keeps the checkouts current while Caddy runs: one background loop that wakes up every minute.
gitsite_refresh_loop() {
  local -A interval last
  local i now
  for i in $(gitsite_indexes); do
    interval[$i]=$(option_item_or .simple.sites "$i" refresh "$GIT_DEFAULT_REFRESH")
    last[$i]=$SECONDS
  done
  while sleep 60; do
    now=$SECONDS
    for i in "${!interval[@]}"; do
      if ((interval[$i] > 0 && now - last[$i] >= interval[$i] * 60)); then
        gitsite_sync "$i" || true
        last[$i]=$now
      fi
    done
  done
}

# Starts the refresh loop in the background unless every git site is set to "only at start".
gitsite_start_refresh() {
  local i
  for i in $(gitsite_indexes); do
    if (($(option_item_or .simple.sites "$i" refresh "$GIT_DEFAULT_REFRESH") > 0)); then
      gitsite_refresh_loop &
      disown
      return 0
    fi
  done
}
