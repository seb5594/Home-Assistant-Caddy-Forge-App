#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034  # the PLAN_*, CADDY_BIN and similar globals are read by run.sh
# ==============================================================================
# Decides which Caddy binary runs and builds a custom one when needed.
#
#   stock  the binary that ships with the app (no plugins, pinned upstream version)
#   reuse  the custom binary built earlier for exactly this configuration
#   build  compile a new one with xcaddy
#
# A new binary is compiled in a scratch folder, must pass `caddy adapt` against the
# generated Caddyfile and only then replaces the live one with a single atomic rename.
# Until that moment the previous binary stays untouched.
# ==============================================================================

: "${FORGE_DATA_DIR:=/data/caddy}"
: "${FORGE_BUNDLED_CADDY:=/usr/sbin/caddy}"
: "${FORGE_WORK_DIR:=/var/cache/caddy-forge}"
: "${FORGE_MIN_FREE_MB:=2500}"  # module and build caches of one build reach about 2 GB

# The live custom binary and what is known about it. Recomputed by builder_init_paths.
builder_init_paths() {
  FORGE_CUSTOM_CADDY="$FORGE_DATA_DIR/bin/caddy"
  FORGE_STATE_FILE="$FORGE_DATA_DIR/state.json"
}
builder_init_paths

# Inputs, filled by builder_load_request.
WANTED_CADDY=latest
MODULE_SPECS=()

# Outputs of builder_plan and builder_select_binary.
PLAN_ACTION=stock
PLAN_REASON=''
PLAN_TARGET=''
PLAN_PRUNE=false
PENDING_UPDATES=()
CADDY_BIN=''
BUILD_CANDIDATE=''
HEARTBEAT_PID=''

# ------------------------------------------------------------------------------
# Request: what did the user ask for?
# ------------------------------------------------------------------------------

# `latest` stays as it is, `2.11.9` becomes `v2.11.9`, branches and commits pass through.
builder_normalize_version() {
  local version=$1
  if [[ $version =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.]+)?$ ]]; then
    printf 'v%s' "${version#v}"
  else
    printf '%s' "${version,,}"
  fi
}

builder_load_request() {
  local specs
  WANTED_CADDY=$(builder_normalize_version "$(option_or .caddy.version latest)")
  specs=$(modules_requested)
  MODULE_SPECS=()
  if [[ -n $specs ]]; then
    mapfile -t MODULE_SPECS <<<"$specs"
  fi
}

# Identifies a configuration: the same request on the same CPU gives the same fingerprint.
builder_fingerprint() {
  {
    printf 'arch=%s\ncaddy=%s\n' "$(uname -m)" "$WANTED_CADDY"
    printf 'with=%s\n' "${MODULE_SPECS[@]}" | sort
  } | sha256sum | cut -c1-16
}

# ------------------------------------------------------------------------------
# State: what was built last time?
# ------------------------------------------------------------------------------

builder_state_get() {
  [[ -f $FORGE_STATE_FILE ]] || return 0
  jq -r "($1) // empty" "$FORGE_STATE_FILE" 2>/dev/null || true
}

# Version of a binary as printed by `caddy version`, without the leading `v`.
builder_binary_version() {
  "$1" version 2>/dev/null | awk 'NR == 1 { sub(/^v/, "", $1); print $1 }'
}

builder_bundled_version() {
  builder_binary_version "$FORGE_BUNDLED_CADDY"
}

# Succeeds when a custom binary exists that was built for the current request.
builder_has_custom_binary() {
  [[ -x $FORGE_CUSTOM_CADDY && $(builder_state_get .fingerprint) == "$(builder_fingerprint)" ]]
}

# Writes state.json for a freshly activated binary (versions are read from the binary itself).
builder_write_state() {
  local binary=$1 info spec path modules caddy
  info=$(go version -m "$binary")
  caddy=$(versions_in_build_info "$CADDY_MODULE" <<<"$info")
  modules=$(
    for spec in "${MODULE_SPECS[@]}"; do
      path=$(modules_path "$spec")
      printf '%s\t%s\n' "$path" "$(versions_in_build_info "$path" <<<"$info")"
    done | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
  )
  mkdir -p "$FORGE_DATA_DIR"
  jq -n --arg arch "$(uname -m)" --arg fingerprint "$(builder_fingerprint)" \
    --arg caddy "${caddy:-$(builder_binary_version "$binary")}" --argjson modules "$modules" \
    --arg built "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{arch: $arch, fingerprint: $fingerprint, caddy: $caddy, modules: $modules, built_at: $built, rejected: ""}' \
    >"$FORGE_STATE_FILE.new"
  mv -f "$FORGE_STATE_FILE.new" "$FORGE_STATE_FILE"
}

# Remembers a combination that failed validation so the same build is not repeated on every start.
builder_remember_rejection() {
  local signature=$1 current='{}'
  [[ -f $FORGE_STATE_FILE ]] && current=$(cat "$FORGE_STATE_FILE")
  mkdir -p "$FORGE_DATA_DIR"
  jq --arg signature "$signature" '.rejected = $signature' <<<"$current" >"$FORGE_STATE_FILE.new"
  mv -f "$FORGE_STATE_FILE.new" "$FORGE_STATE_FILE"
}

# Identifies one concrete build attempt: configuration, the versions it would pick up and the Caddyfile.
builder_signature() {
  local caddyfile=$1
  printf '%s|%s|%s|%s' "$(builder_fingerprint)" "$PLAN_TARGET" "${PENDING_UPDATES[*]:-}" \
    "$(sha256sum <"$caddyfile" | cut -c1-16)" | sha256sum | cut -c1-16
}

# ------------------------------------------------------------------------------
# Planning: stock, reuse or build?
# ------------------------------------------------------------------------------

plan_stock() { PLAN_ACTION=stock; PLAN_REASON=$1; }
plan_reuse() { PLAN_ACTION=reuse; PLAN_REASON=$1; }
plan_build() { PLAN_ACTION=build; PLAN_REASON=$1; PLAN_TARGET=${2:-$PLAN_TARGET}; }

# Fills PENDING_UPDATES with one line per floating component that is behind, and moves
# PLAN_TARGET to the newest Caddy release when Caddy itself is behind.
# <caddy-built> is the Caddy version that currently runs (without `v`).
builder_collect_updates() {
  local caddy_built=$1 latest spec path built
  PENDING_UPDATES=()
  if [[ $WANTED_CADDY == latest ]]; then
    if latest=$(versions_latest_caddy); then
      if versions_is_newer "$(versions_strip_v "$latest")" "$caddy_built"; then
        PENDING_UPDATES+=("Caddy ${caddy_built:-unknown} -> $(versions_strip_v "$latest")")
        PLAN_TARGET=$latest
      fi
    else
      log_warn "Could not look up the newest Caddy release; keeping what is installed."
    fi
  fi
  for spec in "${MODULE_SPECS[@]}"; do
    modules_is_floating "$spec" || continue
    path=$(modules_path "$spec")
    built=$(builder_state_get ".modules[\"$path\"]")
    if latest=$(versions_latest_module "$path"); then
      if [[ -n $built && $latest != "$built" ]]; then
        PENDING_UPDATES+=("$path $built -> $latest")
      fi
    else
      log_warn "Could not look up the newest release of $path"
    fi
  done
}

# Applies the user's update policy to PENDING_UPDATES: build, or just report.
builder_apply_update_policy() {
  local policy=$1 line
  ((${#PENDING_UPDATES[@]} > 0)) || return 1
  for line in "${PENDING_UPDATES[@]}"; do
    log_info "Update available: $line"
  done
  if [[ $policy == install ]]; then
    return 0
  fi
  log_info "Updates are set to 'notify'; switch them to 'install' to rebuild with the newer versions."
  return 1
}

# Decides what to run. Sets PLAN_ACTION, PLAN_REASON and PLAN_TARGET (the Caddy ref to build).
builder_plan() {
  local policy bundled floating_caddy=false
  policy=$(option_or .caddy.updates install)
  bundled=$(builder_bundled_version)
  PLAN_TARGET=$WANTED_CADDY
  PLAN_PRUNE=false
  [[ $WANTED_CADDY == latest ]] && floating_caddy=true

  # 1. The shipped binary is exactly what was asked for.
  if ((${#MODULE_SPECS[@]} == 0)) && [[ $floating_caddy == false && $(versions_strip_v "$WANTED_CADDY") == "$bundled" ]]; then
    plan_stock "Caddy $bundled is built into the app"
    PLAN_PRUNE=true
    return 0
  fi

  # 2. A binary for this very configuration exists: only look for newer releases.
  if builder_has_custom_binary; then
    local built
    built=$(builder_state_get .caddy)
    built=$(versions_strip_v "$built")
    if ((${#MODULE_SPECS[@]} == 0)) && ! versions_is_newer "$built" "$bundled"; then
      plan_stock "the built-in Caddy $bundled is as new as the custom build"
      PLAN_PRUNE=true
      return 0
    fi
    plan_reuse "keeping the existing custom build"
    if [[ $policy != off ]]; then
      builder_collect_updates "$built"
      if builder_apply_update_policy "$policy"; then
        plan_build "updates found"
      fi
    fi
    return 0
  fi

  # 3. Plain Caddy that follows the newest release: the shipped binary may already be it.
  if ((${#MODULE_SPECS[@]} == 0)) && [[ $floating_caddy == true ]]; then
    plan_stock "Caddy $bundled is built into the app"
    PLAN_PRUNE=true
    if [[ $policy != off ]]; then
      builder_collect_updates "$bundled"
      if builder_apply_update_policy "$policy"; then
        plan_build "a newer Caddy release exists"
      fi
    fi
    return 0
  fi

  # 4. The configuration needs a binary that does not exist yet.
  plan_build "the configuration changed or no custom build exists yet"
}

# ------------------------------------------------------------------------------
# Building
# ------------------------------------------------------------------------------

# Free space in megabytes on the file system holding <path> (or its nearest existing parent);
# a huge number when it cannot be determined, so the check never blocks a build by mistake.
builder_free_mb() {
  local path=$1 free
  while [[ ! -d $path ]]; do path=$(dirname "$path"); done
  free=$(df -Pk "$path" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }')
  printf '%s\n' "${free:-999999}"
}

# Keeps the build from starving Home Assistant: parallelism and memory follow what is free.
builder_tune_resources() {
  local mem_kb cores jobs
  mem_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  mem_kb=${mem_kb:-2097152}
  cores=$(nproc)
  jobs=$((mem_kb / 716800)) # roughly 700 MiB per parallel compile
  ((jobs < 1)) && jobs=1
  ((jobs > cores)) && jobs=$cores
  GOMAXPROCS=$jobs
  GOMEMLIMIT="$((mem_kb * 70 / 100 / 1024))MiB"
  export GOMAXPROCS GOMEMLIMIT
  log_debug "Build limits: $jobs parallel job(s), memory limit $GOMEMLIMIT"
}

builder_heartbeat_start() {
  local started=$SECONDS
  (
    while sleep 60; do
      log_info "Still building ... ($(((SECONDS - started) / 60)) min)"
    done
  ) &
  HEARTBEAT_PID=$!
}

builder_heartbeat_stop() {
  if [[ -n $HEARTBEAT_PID ]]; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
    HEARTBEAT_PID=''
  fi
}

# The Caddy ref xcaddy compiles: the pinned version, or the newest release for `latest`.
builder_build_ref() {
  if [[ $WANTED_CADDY != latest ]]; then
    printf '%s' "$WANTED_CADDY"
  elif [[ -n $PLAN_TARGET && $PLAN_TARGET != latest ]]; then
    printf '%s' "$PLAN_TARGET"
  else
    versions_latest_caddy
  fi
}

# Compiles Caddy with every plugin into the scratch folder. Sets BUILD_CANDIDATE on success.
builder_build() {
  local ref spec status=0 candidate="$FORGE_WORK_DIR/caddy"
  BUILD_CANDIDATE=''
  ref=$(builder_build_ref) || { log_error "Could not look up the newest Caddy release; build skipped."; return 1; }
  if (($(builder_free_mb "$FORGE_WORK_DIR") < FORGE_MIN_FREE_MB)); then
    log_error "Less than ${FORGE_MIN_FREE_MB} MB free for a build; free some disk space and restart."
    return 1
  fi
  local args=(build "$ref" --output "$candidate")
  for spec in "${MODULE_SPECS[@]}"; do
    args+=(--with "$spec")
  done
  rm -rf "${FORGE_WORK_DIR:?}"
  mkdir -p "$FORGE_WORK_DIR"/{go,cache,tmp}
  builder_tune_resources
  log_info "Building Caddy $ref with ${#MODULE_SPECS[@]} plugin(s). This can take several minutes ..."
  builder_heartbeat_start
  (
    cd "$FORGE_WORK_DIR"
    export GOPATH="$FORGE_WORK_DIR/go" GOCACHE="$FORGE_WORK_DIR/cache" TMPDIR="$FORGE_WORK_DIR/tmp"
    nice -n 15 xcaddy "${args[@]}"
  ) || status=$?
  builder_heartbeat_stop
  if ((status != 0)) || ! "$candidate" version >/dev/null 2>&1; then
    log_error "The build failed (see the log above); the current binary stays in use."
    rm -rf "${FORGE_WORK_DIR:?}"
    return 1
  fi
  BUILD_CANDIDATE=$candidate
}

# Moves the candidate next to the live binary first, then swaps it in with one rename.
builder_activate() {
  mkdir -p "$(dirname "$FORGE_CUSTOM_CADDY")"
  cp "$BUILD_CANDIDATE" "$FORGE_CUSTOM_CADDY.new"
  chmod 755 "$FORGE_CUSTOM_CADDY.new"
  mv -f "$FORGE_CUSTOM_CADDY.new" "$FORGE_CUSTOM_CADDY"
  builder_write_state "$FORGE_CUSTOM_CADDY"
  log_info "Custom Caddy $(builder_binary_version "$FORGE_CUSTOM_CADDY") is ready."
}

builder_discard_scratch() {
  rm -rf "${FORGE_WORK_DIR:?}"
  BUILD_CANDIDATE=''
}

# ------------------------------------------------------------------------------
# Selecting the binary that actually starts
# ------------------------------------------------------------------------------

# Succeeds when <binary> understands the Caddyfile (all directives and plugins resolve).
builder_accepts() {
  local binary=$1 caddyfile=$2 output
  if output=$("$binary" adapt --config "$caddyfile" --adapter caddyfile 2>&1 >/dev/null); then
    return 0
  fi
  log_debug "$binary rejected the configuration: $output"
  REJECTION_REASON=$output
  return 1
}

# Tries a freshly built binary: it replaces the live one only if it accepts the configuration.
builder_try_build() {
  local caddyfile=$1 signature
  signature=$(builder_signature "$caddyfile")
  if [[ $(builder_state_get .rejected) == "$signature" ]]; then
    log_warn "This exact combination already failed validation; not building it again. Change the plugins, version or Caddyfile to retry."
    return 1
  fi
  builder_build || return 1
  if builder_accepts "$BUILD_CANDIDATE" "$caddyfile"; then
    builder_activate
    builder_discard_scratch
    return 0
  fi
  log_error "The new build does not accept your configuration, it was discarded:"
  log_error "$REJECTION_REASON"
  builder_remember_rejection "$signature"
  builder_discard_scratch
  return 1
}

# Chooses CADDY_BIN: the planned binary, then the previous custom one, then the shipped one.
# The first that accepts the Caddyfile wins; if none does, the app stops with the reason.
builder_select_binary() {
  local caddyfile=$1 candidate
  REJECTION_REASON=''
  builder_plan
  log_info "Caddy plan: $PLAN_ACTION ($PLAN_REASON)"
  if [[ $PLAN_ACTION == build ]]; then
    builder_try_build "$caddyfile" || log_warn "Falling back to the previous binary."
    PLAN_ACTION=reuse
  fi
  if [[ $PLAN_ACTION == stock && $PLAN_PRUNE == true && -e $FORGE_CUSTOM_CADDY ]]; then
    log_info "Removing the unused custom build."
    rm -f "$FORGE_CUSTOM_CADDY" "$FORGE_STATE_FILE"
  fi
  local order=("$FORGE_CUSTOM_CADDY" "$FORGE_BUNDLED_CADDY")
  [[ $PLAN_ACTION == stock ]] && order=("$FORGE_BUNDLED_CADDY" "$FORGE_CUSTOM_CADDY")
  for candidate in "${order[@]}"; do
    [[ -x $candidate ]] || continue
    if builder_accepts "$candidate" "$caddyfile"; then
      CADDY_BIN=$candidate
      return 0
    fi
  done
  fail "No Caddy binary accepts the configuration: ${REJECTION_REASON:-unknown error}"
}
