FROM ghcr.io/ublue-os/base-main:44

# Packages first: this layer only changes when build/ changes, so config-only
# rebuilds (system/ changes) reuse it from cache instead of reinstalling.
RUN --mount=type=bind,source=build,target=/ctx \
    --mount=type=cache,dst=/var/cache/dnf \
    /ctx/10-packages.sh

# Image-owned files: scripts, defaults, themes, units, skel
COPY system/ /

RUN --mount=type=bind,source=build,target=/ctx \
    /ctx/20-services.sh

RUN bootc container lint
