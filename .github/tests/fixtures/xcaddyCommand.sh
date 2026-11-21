#!/bin/sh
xcaddy build latest \
  --with github.com/caddy-dns/cloudflare \
  --with github.com/hslatman/caddy-crowdsec-bouncer \
  --with github.com/porech/caddy-maxmind-geolocation \
  --with github.com/mholt/caddy-dynamicdns
#  --with github.com/mholt/caddy-l4@ef01c22 #@31ae08c

# v2.9.1
# latest

# --with github.com/caddyserver/transform-encoder
# --with github.com/abiosoft/caddy-exec
# --with github.com/mholt/caddy-l4/modules/l4ssh
# --with github.com/gsmlg-dev/caddy-admin-ui@main
