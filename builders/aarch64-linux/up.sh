#!/usr/bin/env bash
# Build the image and start the container on the arm64 host, over SSH.
#   builders/aarch64-linux/up.sh USER@HOST [SSH-KEY]
# Idempotent: an existing image is rebuilt from cache, a running container is
# left alone. The Nix store lives in the named volume nix-packages-builder-nix,
# so a rebuilt container keeps what it built.
set -euo pipefail
host=${1:?usage: up.sh USER@HOST [SSH-KEY]}
ssh_opts=(-o BatchMode=yes)
[[ -n ${2:-} ]] && ssh_opts+=(-i "$2" -o IdentitiesOnly=yes)
here=$(cd "$(dirname "$0")" && pwd)
ssh "${ssh_opts[@]}" "$host" 'mkdir -p ~/nix-packages-builder'
tar -C "$here" -cf - Dockerfile nix-daemon | ssh "${ssh_opts[@]}" "$host" 'tar -xf - -C ~/nix-packages-builder'
ssh "${ssh_opts[@]}" "$host" bash -s <<'REMOTE'
set -euo pipefail
cd ~/nix-packages-builder
docker build --quiet -t nix-packages-builder-aarch64:latest . >/dev/null
if docker ps -a --format '{{.Names}}' | grep -qx nix-packages-builder-aarch64; then
  docker start nix-packages-builder-aarch64 >/dev/null
else
  # No --privileged, no added capability, no host path mounted, no port published.
  docker run -d --name nix-packages-builder-aarch64 --hostname nix-packages-builder-aarch64 \
    --memory=16g --memory-swap=16g --pids-limit=16384 \
    -v nix-packages-builder-nix:/nix nix-packages-builder-aarch64:latest >/dev/null
fi
docker exec nix-packages-builder-aarch64 nix --version
REMOTE
