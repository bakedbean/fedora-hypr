# Both FROMs are pinned by digest (tools/bump-base.sh, run weekly by CI, or `make bump-base`):
# CI's registry layer cache keys on the parent image, and base-main:44 rebuilds daily, so
# an unpinned base would miss the cache on nearly every push. The tag stays for `TAG`.

# --- Stage 1: Rust binaries not packaged in Fedora (wsx, waybar-docker).
# Only the final stage ships; this one is dropped. Bump WSX_REF to update wsx.
FROM registry.fedoraproject.org/fedora:44@sha256:40005ed606ff7bbdc5344f3625e043f64493358b3dfaf2cc6b1995282189f3f5 AS rust-build
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
FROM registry.fedoraproject.org/fedora:44@sha256:40005ed606ff7bbdc5344f3625e043f64493358b3dfaf2cc6b1995282189f3f5 AS ngrok-fetch
ARG NGROK_VERSION=3.39.11
ARG NGROK_SHA256=e51aa234283bcf20a777e21a624b2a3501b058b3d5a1faec59106311dbe30395
RUN dnf install -y binutils tar xz && dnf clean all \
    && curl -fsSLo /tmp/ngrok.deb "https://ngrok-agent.s3.amazonaws.com/pool/main/n/ngrok/ngrok_${NGROK_VERSION}-0_amd64.deb" \
    && echo "${NGROK_SHA256}  /tmp/ngrok.deb" | sha256sum -c - \
    && ar p /tmp/ngrok.deb data.tar.xz | tar -xJf - -C /tmp ./usr/local/bin/ngrok \
    && install -Dm755 /tmp/usr/local/bin/ngrok /out/bin/ngrok

# --- Stage 3: tether (iPhone bridge, github.com/zackb/tether), not packaged for Fedora.
# Pinned upstream release RPM, hash-checked; installed (with its deps) by build/12-tether.sh.
# Bump: version + "digest" of tether-<ver>-1.x86_64.rpm from `gh release view v<ver> -R zackb/tether --json assets`
FROM registry.fedoraproject.org/fedora:44@sha256:40005ed606ff7bbdc5344f3625e043f64493358b3dfaf2cc6b1995282189f3f5 AS tether-fetch
ARG TETHER_VERSION=0.2.37
ARG TETHER_SHA256=a798e9aac96922a7230105ff62308ff6e0c4a607aec2711226701956df6d0e06
RUN curl -fsSLo /tmp/tether.rpm "https://github.com/zackb/tether/releases/download/v${TETHER_VERSION}/tether-${TETHER_VERSION}-1.x86_64.rpm" \
    && echo "${TETHER_SHA256}  /tmp/tether.rpm" | sha256sum -c - \
    && install -Dm644 /tmp/tether.rpm /out/tether.rpm

# --- Stage 4: the image
FROM ghcr.io/ublue-os/base-main:44@sha256:b863a9f3ba8264903e470428dd9056b82bb60874471d9097569b4ce767fb3781

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

# tether in its own layer so a version bump does not re-run the package layer
COPY --from=tether-fetch /out/tether.rpm /ctx/tether.rpm
RUN --mount=type=cache,dst=/var/cache/dnf /ctx/12-tether.sh

# Initramfs rebuild (Plymouth theme must be inside it) needs only the theme + plymouthd.conf,
# so copy just those first: the ~1 min dracut layer then caches across all other system/ edits.
COPY system/etc/plymouth/ /etc/plymouth/
COPY system/usr/share/plymouth/ /usr/share/plymouth/
RUN /ctx/15-initramfs.sh

# Image-owned files: scripts, defaults, themes, units, skel
COPY system/ /

RUN /ctx/20-services.sh && rm -rf /ctx

RUN bootc container lint
