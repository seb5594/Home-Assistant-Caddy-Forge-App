#!/usr/bin/env bash
set -Eeuo pipefail

# Runs inside the built image: loads the app like the Supervisor would and exercises every part.
# The whole tests folder is mounted at /tests; every case file adds one or more test_* functions.
TEST_DIR="${TEST_DIR:-/tests}"
export TEST_DIR
# shellcheck source=.github/tests/lib.sh
source "$TEST_DIR/lib.sh"
# shellcheck source=/dev/null
source "${RUN_SCRIPT:-/run.sh}"

for case_file in "$TEST_DIR"/cases/*.sh; do
  # shellcheck source=/dev/null
  source "$case_file"
done

# A real build downloads Caddy's dependencies and takes a few minutes; skip it with FORGE_TEST_BUILD=0.
tests=(modules versions caddyfile recipes gitsites adminui migrate builder_plan builder_activation builder_selection server_start)
if [[ ${FORGE_TEST_BUILD:-1} == 1 ]]; then
  tests+=(real_build)
fi

# Every test runs in a subshell, so the stubs and environment changes of one cannot leak into the next.
for name in "${tests[@]}"; do
  ( "test_$name" ) || flunk "test_$name stopped unexpectedly"
done

if [[ -s $FAILURES_FILE ]]; then
  echo "$(wc -l <"$FAILURES_FILE") check(s) failed" >&2
  exit 1
fi
