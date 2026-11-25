# A Nix builder for aarch64-linux: Debian 13 with single-user Nix, owned by
# an unprivileged user. It holds no keys; the machine that drives it signs
# and uploads. See README.md beside this file.
FROM debian:trixie-slim
ARG NIX_VERSION=2.31.2
ARG NIX_SHA256=64db528412096d718b4bf8f78f85e5ac2b714b774e5005500dee37d23f560456
RUN apt-get update \
 && apt-get install --no-install-recommends --yes ca-certificates curl xz-utils procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 --shell /bin/bash builder \
 && mkdir -m 0755 /nix && chown builder /nix
USER builder
WORKDIR /home/builder
RUN curl -fsSL -o nix.tar.xz https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-aarch64-linux.tar.xz \
 && echo "$NIX_SHA256  nix.tar.xz" | sha256sum -c - \
 && tar -xJf nix.tar.xz && ./nix-${NIX_VERSION}-aarch64-linux/install --no-daemon --no-channel-add --no-modify-profile \
 && rm -rf nix.tar.xz nix-${NIX_VERSION}-aarch64-linux \
 && mkdir -p .config/nix \
 && printf '%s\n' 'experimental-features = nix-command flakes' 'sandbox = false' \
      'max-jobs = auto' 'cores = 0' > .config/nix/nix.conf
ENV PATH=/home/builder/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin USER=builder
CMD ["sleep", "infinity"]
