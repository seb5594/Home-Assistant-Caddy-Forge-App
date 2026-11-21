#!/usr/bin/env bash
# shellcheck shell=bash
# Websites served from git repositories, tested against a repository on the local disk.

# Creates a repository with one commit on branch "pages" and prints its file:// URL.
make_repository() {
  local repo="$TEST_TMP/origin"
  git init -q -b pages "$repo"
  git -C "$repo" config user.email test@example.org
  git -C "$repo" config user.name Test
  mkdir -p "$repo/public"
  echo "version one" >"$repo/public/index.html"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m one
  printf 'file://%s' "$repo"
}

test_gitsites() {
  use_clean_folders
  FORGE_SITES_DIR="$TEST_TMP/sites"
  assert_equals "docs-example-org" "$(gitsite_slug 'Docs.Example.org, www.example.org')" "git: the checkout folder is named after the domain"
  assert_equals "https://***@git.example.org/a.git" "$(gitsite_mask <<<'https://user:token@git.example.org/a.git')" "git: credentials are hidden in log output"

  local url
  url=$(make_repository)
  use_options ".simple.sites = [{\"domain\": \"docs.example.org\", \"type\": \"git\", \"target\": \"$url\", \"branch\": \"pages\", \"folder\": \"public\"}]"
  assert_equals "0" "$(gitsite_indexes)" "git: sites of type git are found"
  assert_equals "$FORGE_SITES_DIR/docs-example-org/public" "$(gitsite_root 0)" "git: the served folder is the chosen sub folder"

  gitsite_sync_all >/dev/null 2>&1
  assert_equals "version one" "$(cat "$FORGE_SITES_DIR/docs-example-org/public/index.html")" "git: the repository is cloned on start"

  echo "version two" >"$TEST_TMP/origin/public/index.html"
  git -C "$TEST_TMP/origin" commit -q -am two
  gitsite_sync_all >/dev/null 2>&1
  assert_equals "version two" "$(cat "$FORGE_SITES_DIR/docs-example-org/public/index.html")" "git: new commits are pulled"

  git -C "$TEST_TMP/origin" branch -q -m moved
  gitsite_sync_all >/dev/null 2>&1
  assert_equals "version two" "$(cat "$FORGE_SITES_DIR/docs-example-org/public/index.html")" "git: an unreachable branch keeps the last checkout"

  use_options '.simple.sites[0].folder = "../etc"'
  assert_fails "git: a folder outside the repository is refused" gitsite_root 0
}
