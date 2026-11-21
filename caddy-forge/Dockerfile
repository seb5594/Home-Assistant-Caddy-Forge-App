ARG BUILD_FROM=ghcr.io/seb5594/home-assistant-base:3.24-2026.11.0@sha256:d116b9e5b612e6fcd997c86642d21b61953fcbe390c39c9b03443a577ed5e2a6

# The web server ships as a ready-made binary, so a plain setup starts at once: upstream Caddy plus the two
# plugins of the admin UI, compiled below on the build machine for the target architecture. The Go toolchain
# and xcaddy stay on board for the day a custom build with more plugins is requested.
# renovate: datasource=github-releases depName=caddyserver/caddy
ARG CADDY_VERSION=2.11.9
ARG ADMIN_UI_REF=v0.0.0-20260306083403-616d1e779392
ARG REPLACE_RESPONSE_REF=v0.0.0-20250618171559-80962887e4c6
# renovate: datasource=repology depName=alpine_3_24/xcaddy
ARG XCADDY_VERSION=0.4.6-r0
# renovate: datasource=repology depName=alpine_3_24/go
ARG GO_VERSION=1.26.11-r0
# renovate: datasource=repology depName=alpine_3_24/git
ARG GIT_VERSION=2.54.1-r0

# ------------------------------------------------------------------------------
# Stage 1: compile Caddy. It runs on the build machine's own architecture and cross-compiles (plain Go,
# no C compiler), which is much faster than compiling under emulation for the 32-bit ARM targets.
# ------------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM ${BUILD_FROM} AS forge

ARG CADDY_VERSION
ARG ADMIN_UI_REF
ARG REPLACE_RESPONSE_REF
ARG XCADDY_VERSION
ARG GO_VERSION
ARG TARGETARCH
ARG TARGETVARIANT
RUN apk add --no-cache \
        xcaddy=${XCADDY_VERSION} \
        go=${GO_VERSION}
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0
RUN GOOS=linux GOARCH="${TARGETARCH}" GOARM="${TARGETVARIANT#v}" \
    xcaddy build "v${CADDY_VERSION}" \
        --with "github.com/gsmlg-dev/caddy-admin-ui@${ADMIN_UI_REF}" \
        --with "github.com/caddyserver/replace-response@${REPLACE_RESPONSE_REF}" \
        --output /caddy

# ------------------------------------------------------------------------------
# Stage 2: the app
# ------------------------------------------------------------------------------
FROM ${BUILD_FROM}

ARG ADMIN_UI_REF
ARG REPLACE_RESPONSE_REF
ARG XCADDY_VERSION
ARG GO_VERSION
ARG GIT_VERSION
RUN apk add --no-cache \
        xcaddy=${XCADDY_VERSION} \
        go=${GO_VERSION} \
        git=${GIT_VERSION}

COPY --from=forge /caddy /usr/local/bin/caddy
RUN caddy version

# Plugins are plain Go: no C compiler is needed, and a Go version newer than the installed one
# is fetched on demand. Everything a build downloads lives in a scratch folder (see builder.sh).
# Custom builds contain the same admin UI plugins at the same versions as the shipped binary.
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0 \
    FORGE_ADMIN_UI_REF=${ADMIN_UI_REF} \
    FORGE_REPLACE_RESPONSE_REF=${REPLACE_RESPONSE_REF}

ARG BUILD_VERSION=2026.11.21.9
ARG BUILD_ARCH=amd64
ENV APP_VERSION=${BUILD_VERSION}
LABEL io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.source="https://github.com/seb5594/Home-Assistant-Caddy-Forge-App"

COPY rootfs/ /
COPY run.sh entrypoint.sh /
RUN chmod a+x /run.sh /entrypoint.sh

ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]
CMD [ "/run.sh" ]
