#!/usr/bin/env bash
# Sign and upload built packages, their runtime closures and the sources they
# were built from to the binary cache. Run it by hand on the machine that
# holds the signing key; docs/uploading.md explains it step by step.
#
#   scripts/upload.sh [--from STORE] INSTALLABLE...
#
#   INSTALLABLE   a flake output of this repository, e.g.
#                 .#packages.x86_64-linux.qemu-espressif
#   --from STORE  the outputs were built in another Nix store, such as a
#                 remote builder's ssh-ng:// store (docs/builders.md); they
#                 are copied from it to a staging cache on this machine first.
#
# Settings, from the environment:
#
#   NIX_PACKAGES_S3_ENV       file with HETZNER_S3_ACCESS_KEY, HETZNER_S3_SECRET_KEY,
#                             HETZNER_S3_ENDPOINT, HETZNER_S3_REGION, HETZNER_S3_BUCKET
#   NIX_PACKAGES_SIGNING_KEY  the cache's secret signing key (nix key generate-secret)
#   NIX_PACKAGES_STAGING      staging directory for --from (default ~/.cache/nix-packages/staging)
#
# An output that is an export (a directory holding NAME.tar.xz and
# NAME.tar.xz.sha256) is also put at exports/NAME/ in the bucket, with a
# SOURCES.txt listing every source store path of its build.
set -euo pipefail

from=
while [[ $# -gt 0 ]]; do
  case $1 in
    --from) from=${2:?--from needs a store URL}; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    --) shift; break ;;
    -*) echo "upload.sh: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[[ $# -gt 0 ]] || { echo "upload.sh: name at least one installable; --help says how" >&2; exit 2; }

: "${NIX_PACKAGES_S3_ENV:?set NIX_PACKAGES_S3_ENV to the file holding the bucket key}"
: "${NIX_PACKAGES_SIGNING_KEY:?set NIX_PACKAGES_SIGNING_KEY to the secret signing key file}"
[[ -r $NIX_PACKAGES_SIGNING_KEY ]] || { echo "upload.sh: cannot read $NIX_PACKAGES_SIGNING_KEY" >&2; exit 1; }
# shellcheck disable=SC1090
. "$NIX_PACKAGES_S3_ENV"
: "${HETZNER_S3_ACCESS_KEY:?missing in $NIX_PACKAGES_S3_ENV}" "${HETZNER_S3_SECRET_KEY:?missing in $NIX_PACKAGES_S3_ENV}"
: "${HETZNER_S3_ENDPOINT:?}" "${HETZNER_S3_REGION:?}" "${HETZNER_S3_BUCKET:?}"

export AWS_ACCESS_KEY_ID=$HETZNER_S3_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$HETZNER_S3_SECRET_KEY
host=${HETZNER_S3_ENDPOINT#https://}
cache="s3://$HETZNER_S3_BUCKET?endpoint=$host&region=$HETZNER_S3_REGION&compression=zstd&parallel-compression=true&secret-key=$NIX_PACKAGES_SIGNING_KEY"
public="https://$HETZNER_S3_BUCKET.$host"

say() { echo "upload.sh: $*" >&2; }

# 1. The outputs, in the store that built them.
store_args=()
[[ -n $from ]] && store_args=(--eval-store auto --store "$from")
mapfile -t outputs < <(nix path-info "${store_args[@]}" "$@")
mapfile -t drvs < <(nix path-info --derivation "$@")
say "${#outputs[@]} output(s) from ${from:-the local store}"

# 2. Outputs built elsewhere come to a staging cache here; nothing from the
#    builder reaches the bucket without passing through this machine.
source_store=auto
source_args=()
if [[ -n $from ]]; then
  staging=${NIX_PACKAGES_STAGING:-$HOME/.cache/nix-packages/staging}
  mkdir -p "$staging"
  nix copy --no-check-sigs --from "$from" --to "file://$staging?compression=none" "${outputs[@]}"
  source_store="file://$staging"
  source_args=(--store "$source_store")
fi

# 3. Sign and upload the outputs with their runtime closures.
nix copy --no-check-sigs --from "$source_store" --to "$cache" "${outputs[@]}"
say "outputs and closures uploaded"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fod_drvs() {  # the fixed-output derivations in the build closures of DRV...
  for drv in "$@"; do
    nix derivation show --recursive "$drv" | python3 -c 'import json, sys
d = json.load(sys.stdin)
d = d.get("derivations", d)
for path, v in d.items():
    if any("hash" in o for o in v["outputs"].values()):
        print(path if path.startswith("/") else "/nix/store/" + path)'
  done | sort -u
}
fod_paths() {  # their output paths: the sources
  fod_drvs "$@" | xargs -r nix-store --query --outputs | sort -u
}

# 4. The sources: every fixed-output path in the build closure (upstream
#    tarballs and repositories, patches, bootstrap binaries). They are
#    fetched here if this machine does not have them, then uploaded.
mapfile -t source_drvs < <(fod_drvs "${drvs[@]}")
mapfile -t sources < <(nix build --no-link --print-out-paths "${source_drvs[@]/%/^*}")
nix copy --to "$cache" "${sources[@]}"
say "${#sources[@]} source path(s) uploaded"

# 5. Exports also go under exports/NAME/ as plain files.
put() {  # put FILE KEY TYPE
  # The key goes to curl on stdin, not on its command line.
  printf 'user = "%s:%s"\n' "$HETZNER_S3_ACCESS_KEY" "$HETZNER_S3_SECRET_KEY" |
    curl -fsS -K - --aws-sigv4 "aws:amz:$HETZNER_S3_REGION:s3" \
      -H "Content-Type: $3" -T "$1" "$HETZNER_S3_ENDPOINT/$HETZNER_S3_BUCKET/$2"
  echo "$public/$2"
}
for installable in "$@"; do
  out=$(nix path-info "${store_args[@]}" "$installable")
  name=
  for f in $(nix store ls "${source_args[@]}" "$out" 2>/dev/null || true); do
    case $f in *.tar.xz) name=$(basename "$f" .tar.xz) ;; esac
  done
  [[ -n $name ]] || continue
  drv=$(nix path-info --derivation "$installable")
  nix store cat "${source_args[@]}" "$out/$name.tar.xz" > "$tmp/$name.tar.xz"
  nix store cat "${source_args[@]}" "$out/$name.tar.xz.sha256" > "$tmp/$name.tar.xz.sha256"
  (cd "$tmp" && sha256sum -c --quiet "$name.tar.xz.sha256")
  # An export is never replaced by other bytes under the same name:
  # consumers pin its SHA-256.
  if published=$(curl -fsS "$public/exports/$name/$name.tar.xz.sha256" 2>/dev/null); then
    if [[ $published == "$(cat "$tmp/$name.tar.xz.sha256")" ]]; then
      say "exports/$name is already published with these bytes"; continue
    fi
    say "exports/$name is published with other bytes; give the export a new name in flake.nix"
    exit 1
  fi
  {
    echo "Sources of $name, built from $drv."
    echo "Each line is a store path in the binary cache $public;"
    echo "nix copy --from $public PATH fetches it. Without Nix, the file"
    echo "$public/HASH.narinfo, HASH being the path's 32-character prefix,"
    echo "names the compressed NAR archive in its URL line."
    echo
    fod_paths "$drv"
  } > "$tmp/SOURCES.txt"
  put "$tmp/SOURCES.txt" "exports/$name/SOURCES.txt" "text/plain; charset=utf-8"
  put "$tmp/$name.tar.xz" "exports/$name/$name.tar.xz" application/x-xz
  put "$tmp/$name.tar.xz.sha256" "exports/$name/$name.tar.xz.sha256" "text/plain; charset=utf-8"
done
say "done; consumers use substituter $public"
