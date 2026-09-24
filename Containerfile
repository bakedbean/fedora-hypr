# Both FROMs are pinned by digest (tools/bump-base.sh, run weekly by CI, or `make bump-base`):
# CI's registry layer cache keys on the parent image, and base-main:44 rebuilds daily, so
# an unpinned base would miss the cache on nearly every push. The tag stays for `TAG`.

# --- Stage 1: Rust binaries not packaged in Fedora (wsx, waybar-docker).
# Only the final stage ships; this one is dropped. Bump WSX_REF to update wsx.
FROM registry.fedoraproject.org/fedora:44@sha256:dee2b968c71a167b08a6e0027db0380fc2f037796aeed620556a4fcbc6a1ed7f AS rust-build
ARG WSX_REF=2044830ee4fea6cc1e0d7df75d7a6f24dfef89c2
RUN dnf install -y cargo rust gcc git && dnf clean all && rustc --version
# wsx needs rust >= 1.85 (edition 2024); rusqlite "bundled" compiles SQLite with gcc.
RUN git clone https://github.com/bakedbean/workspacex /src/wsx \
    && git -C /src/wsx checkout "$WSX_REF"
WORKDIR /src/wsx
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/src/wsx/target \
    cargo build --release --locked \
    && install -Dm755 target/release/wsx /out/bin/wsx \
    && cargo install waybar-docker --version 0.1.2 --locked --root /out

# --- Stage 2: ngrok, not packaged for Fedora. Pinned .deb from ngrok's apt repo (the
# tarball URL is unversioned); a static Go binary, so only /usr/local/bin/ngrok is kept.
# Bump: pick Version/SHA256 from https://ngrok-agent.s3.amazonaws.com/dists/buster/main/binary-amd64/Packages
FROM registry.fedoraproject.org/fedora:44@sha256:dee2b968c71a167b08a6e0027db0380fc2f037796aeed620556a4fcbc6a1ed7f AS ngrok-fetch
ARG NGROK_VERSION=3.39.11
ARG NGROK_SHA256=e51aa234283bcf20a777e21a624b2a3501b058b3d5a1faec59106311dbe30395
RUN dnf install -y binutils tar xz && dnf clean all \
    && curl -fsSLo /tmp/ngrok.deb "https://ngrok-agent.s3.amazonaws.com/pool/main/n/ngrok/ngrok_${NGROK_VERSION}-0_amd64.deb" \
    && echo "${NGROK_SHA256}  /tmp/ngrok.deb" | sha256sum -c - \
    && ar p /tmp/ngrok.deb data.tar.xz | tar -xJf - -C /tmp ./usr/local/bin/ngrok \
    && install -Dm755 /tmp/usr/local/bin/ngrok /out/bin/ngrok

# --- Stage 3: the image
FROM ghcr.io/ublue-os/base-main:44@sha256:e8c5e861c28245f9cbe669e40a68ba167d405a67a3f1fa519dd85d879f78341e

# build/ is COPYed (not bind-mounted) so its content is part of the layer key: CI's
# registry cache (--cache-from) ignores bind-mount sources and reused a stale package
# layer after a packages.txt edit. Removed again in the last RUN.
COPY build/ /ctx/

# Packages first: this layer only changes when build/ changes, so config-only
# rebuilds (system/ changes) reuse it from cache instead of reinstalling.
RUN --mount=type=cache,dst=/var/cache/dnf /ctx/10-packages.sh

# Rust binaries from the build stage (right after packages: config-only rebuilds stay fast)
COPY --from=rust-build /out/bin/wsx /usr/bin/wsx
COPY --from=rust-build /out/bin/waybar-docker /usr/bin/waybar-docker
COPY --from=ngrok-fetch /out/bin/ngrok /usr/bin/ngrok

# Initramfs rebuild (Plymouth theme must be inside it) needs only the theme + plymouthd.conf,
# so copy just those first: the ~1 min dracut layer then caches across all other system/ edits.
COPY system/etc/plymouth/ /etc/plymouth/
COPY system/usr/share/plymouth/ /usr/share/plymouth/
RUN /ctx/15-initramfs.sh

# Image-owned files: scripts, defaults, themes, units, skel
COPY system/ /

RUN /ctx/20-services.sh && rm -rf /ctx

RUN bootc container lint
