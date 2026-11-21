ARG BUILD_FROM=ghcr.io/seb5594/home-assistant-base:3.24-2026.11.0@sha256:d116b9e5b612e6fcd997c86642d21b61953fcbe390c39c9b03443a577ed5e2a6

# The web server ships as a ready-made binary, so a plain setup starts at once. The Go toolchain and
# xcaddy stay on board for the day a custom build with plugins is requested.
# renovate: datasource=repology depName=alpine_3_24/caddy
ARG CADDY_VERSION=2.11.9-r0
# renovate: datasource=repology depName=alpine_3_24/xcaddy
ARG XCADDY_VERSION=0.4.6-r0
# renovate: datasource=repology depName=alpine_3_24/go
ARG GO_VERSION=1.26.11-r0
# renovate: datasource=repology depName=alpine_3_24/git
ARG GIT_VERSION=2.54.1-r0

FROM ${BUILD_FROM}

ARG CADDY_VERSION
ARG XCADDY_VERSION
ARG GO_VERSION
ARG GIT_VERSION
RUN apk add --no-cache \
        caddy=${CADDY_VERSION} \
        xcaddy=${XCADDY_VERSION} \
        go=${GO_VERSION} \
        git=${GIT_VERSION}

# Plugins are plain Go: no C compiler is needed, and a Go version newer than the installed one
# is fetched on demand. Everything a build downloads lives in a scratch folder (see builder.sh).
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0

ARG BUILD_VERSION=2026.11.21.4
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
