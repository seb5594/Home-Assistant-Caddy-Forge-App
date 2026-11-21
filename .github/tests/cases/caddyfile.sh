#!/usr/bin/env bash
# shellcheck shell=bash
# Simple mode: options in, Caddyfile out.

test_caddyfile() {
  use_clean_folders
  use_options
  local output
  output=$(caddyfile_generate)

  assert_contains "$output" "email admin@example.org" "caddyfile: the contact email is set"
  assert_contains "$output" "acme_ca https://acme-staging-v02.api.letsencrypt.org/directory" "caddyfile: the staging authority is selectable"
  assert_contains "$output" "trusted_proxies static 10.0.0.0/8" "caddyfile: trusted proxies are listed"
  assert_contains "$output" $'homeassistant.local {\n\ttls internal' "caddyfile: a local site gets Caddy's own certificate"
  assert_contains "$output" "hass.example.org, www.hass.example.org {" "caddyfile: several domains share one site"
  assert_contains "$output" "@allowed client_ip 192.168.0.0/16" "caddyfile: allowed networks become a matcher"
  assert_contains "$output" 'respond "Forbidden" 403' "caddyfile: everybody else is turned away"
  assert_contains "$output" "header X-Test 1" "caddyfile: extra directives are added to the site"
  assert_contains "$output" "tls_insecure_skip_verify" "caddyfile: a self-signed upstream can be accepted"
  assert_contains "$output" 'basic_auth {' "caddyfile: a login protects the site"
  assert_not_contains "$output" "secret" "caddyfile: the plain password never reaches the file"
  assert_contains "$output" $'tls /ssl/fullchain.pem /ssl/privkey.pem' "caddyfile: custom certificates come from /ssl"
  assert_contains "$output" "root * /share/www" "caddyfile: static sites serve a folder"
  assert_contains "$output" "http://old.example.org {" "caddyfile: plain HTTP sites get the http:// prefix"
  assert_contains "$output" "redir https://new.example.org{uri} permanent" "caddyfile: redirects keep the path"
  assert_contains "$output" "root * $FORGE_SITES_DIR/docs-example-org/public" "caddyfile: git sites serve their checkout"
  assert_contains "$output" $'file_server {\n\t\thide .git' "caddyfile: the .git folder is never served"
  assert_not_contains "$output" "user:token" "caddyfile: the repository URL with its token never reaches the file"
  assert_contains "$output" "encode zstd gzip" "caddyfile: compression is on by default"
  assert_contains "$output" "Strict-Transport-Security" "caddyfile: HSTS is sent for public certificates"

  local internal_block
  internal_block=$(awk '/^homeassistant.local \{/,/^}/' <<<"$output")
  assert_not_contains "$internal_block" "Strict-Transport-Security" "caddyfile: no HSTS for certificates the browser cannot verify"

  caddyfile_write "$FORGE_CONFIG_DIR/generated.Caddyfile"
  assert_succeeds "caddyfile: Caddy understands the generated file" \
    "$FORGE_BUNDLED_CADDY" adapt --config "$FORGE_CONFIG_DIR/generated.Caddyfile" --adapter caddyfile
  assert_equals "" "$("$FORGE_BUNDLED_CADDY" fmt --diff "$FORGE_CONFIG_DIR/generated.Caddyfile" | grep -E '^[+-]' || true)" "caddyfile: the file is already formatted"

  printf '# plugin settings\n' >"$FORGE_CONFIG_DIR/global.caddy"
  printf '(extra) {\n\theader X-Extra 1\n}\n' >"$FORGE_CONFIG_DIR/sites.caddy"
  output=$(caddyfile_generate)
  assert_contains "$output" "import $FORGE_CONFIG_DIR/global.caddy" "caddyfile: global.caddy is imported into the global block"
  assert_contains "$output" "import $FORGE_CONFIG_DIR/sites.caddy" "caddyfile: sites.caddy is appended"

  use_options '.simple.dns_provider = "cloudflare" | .simple.dns_token = "token"'
  assert_contains "$(caddyfile_generate)" "acme_dns cloudflare {env.FORGE_DNS_TOKEN}" "caddyfile: DNS validation uses the token from the environment"
  use_options '.simple.dns_provider = "cloudflare"'
  assert_fails "caddyfile: a DNS provider without a token is reported" caddyfile_generate
  use_options '.simple.sites[0].target = ""'
  assert_fails "caddyfile: a site without a target is reported" caddyfile_generate
  use_options '.simple.sites = [] | .simple.security_headers = false | .simple.compression = false'
  assert_not_contains "$(caddyfile_generate)" "forge_defaults" "caddyfile: no sites, no shared snippet"

  use_options '.mode = "caddyfile"'
  caddyfile_seed_pro_mode "$FORGE_CONFIG_DIR/Caddyfile"
  assert_contains "$(cat "$FORGE_CONFIG_DIR/Caddyfile")" "Seeded by Caddy Forge" "caddyfile: Caddyfile mode starts from the simple options"
  printf '# mine\n' >"$FORGE_CONFIG_DIR/Caddyfile"
  caddyfile_seed_pro_mode "$FORGE_CONFIG_DIR/Caddyfile"
  assert_equals "# mine" "$(cat "$FORGE_CONFIG_DIR/Caddyfile")" "caddyfile: an existing Caddyfile is never overwritten"
}

# The recipes in docs/examples.md must stay valid.
test_recipes() {
  use_clean_folders
  FORGE_SITES_DIR="$TEST_TMP/sites"
  use_options '.simple.sites = [
    {"domain": "blog.example.org", "type": "static", "target": "/share/blog",
     "extra": ["php_fastcgi 192.168.1.20:9000 {", "root /var/www/html", "}"]},
    {"domain": "app.example.org", "type": "static", "target": "/share/app", "extra": ["try_files {path} /index.html"]},
    {"domain": "ha.example.org", "type": "proxy", "target": "homeassistant:8123", "extra": ["request_body {", "max_size 100MB", "}"]},
    {"domain": "docs.example.org", "type": "git", "target": "https://example.org/site.git", "branch": "gh-pages", "folder": "public", "refresh": 15}
  ]'
  caddyfile_write "$FORGE_CONFIG_DIR/recipes.Caddyfile"
  assert_succeeds "recipes: PHP-FPM, single-page apps and git sites are valid Caddyfile" \
    "$FORGE_BUNDLED_CADDY" adapt --config "$FORGE_CONFIG_DIR/recipes.Caddyfile" --adapter caddyfile
}

