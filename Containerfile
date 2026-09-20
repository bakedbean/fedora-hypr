FROM ghcr.io/ublue-os/base-main:44

# Image-owned files: scripts, defaults, themes, units, skel
COPY system/ /

# Build scripts run with the repo's build/ dir mounted at /ctx
RUN --mount=type=bind,source=build,target=/ctx \
    --mount=type=cache,dst=/var/cache/dnf \
    /ctx/10-packages.sh && \
    /ctx/20-services.sh

RUN bootc container lint
