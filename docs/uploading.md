# Building, signing and uploading by hand

Until a CI workflow uploads (which needs a key in GitHub, and none is
there), packages reach the cache this way. It runs on the machine that
holds the two keys. That is currently the x86-64 build machine, but
nothing below depends on which machine it is.

## What you need

- Nix 2.18 or later with flakes enabled.
- The **signing key**: the secret half of `701-nix-packages-1`, made once with

  ```sh
  (umask 077; nix key generate-secret --key-name 701-nix-packages-1 > SECRET-FILE)
  nix key convert-secret-to-public < SECRET-FILE   # the key in README.md
  ```

  Keep it mode 600, on one machine, outside any repository. Replacing it
  means a new key name (`701-nix-packages-2`), a new public key in the
  README and the flake's `nixConfig`, and re-signing what is in the cache.
- The **bucket key**: a Hetzner Object Storage access key that can write
  the bucket `701-nix-packages` and nothing else, in a file of this shape
  (mode 600):

  ```sh
  HETZNER_S3_ACCESS_KEY=...
  HETZNER_S3_SECRET_KEY=...
  HETZNER_S3_ENDPOINT=https://nbg1.your-objectstorage.com
  HETZNER_S3_REGION=nbg1
  HETZNER_S3_BUCKET=701-nix-packages
  ```

Tell the script where both are:

```sh
export NIX_PACKAGES_SIGNING_KEY=/path/to/SECRET-FILE
export NIX_PACKAGES_S3_ENV=/path/to/s3.env
```

## 1. Build and test

For this machine's system:

```sh
nix build --no-link .#packages.x86_64-linux.qemu-espressif \
  .#packages.x86_64-linux.qemu-espressif-static \
  .#exports.x86_64-linux.qemu-espressif
nix build --no-link .#checks.x86_64-linux.qemu-espressif \
  .#checks.x86_64-linux.qemu-espressif-static
```

For aarch64-linux, on the builder container ([builders.md](builders.md)):

```sh
builder='ssh-ng://USER@HOST?ssh-key=KEYFILE&remote-program=/home/USER/nix-packages-builder/nix-daemon'
nix build --eval-store auto --store "$builder" --no-link \
  .#packages.aarch64-linux.qemu-espressif .#packages.aarch64-linux.qemu-espressif-static \
  .#exports.aarch64-linux.qemu-espressif \
  .#checks.aarch64-linux.qemu-espressif .#checks.aarch64-linux.qemu-espressif-static
```

Upload nothing whose checks failed.

## 2. Sign and upload

```sh
scripts/upload.sh .#packages.x86_64-linux.qemu-espressif \
  .#packages.x86_64-linux.qemu-espressif-static .#exports.x86_64-linux.qemu-espressif

scripts/upload.sh --from "$builder" .#packages.aarch64-linux.qemu-espressif \
  .#packages.aarch64-linux.qemu-espressif-static .#exports.aarch64-linux.qemu-espressif
```

The script

1. finds each output, in the local store or in the builder's;
2. with `--from`, copies the outputs and their closures to a staging cache
   on this machine (`~/.cache/nix-packages/staging`, or
   `$NIX_PACKAGES_STAGING`), so the builder never talks to the bucket;
3. uploads them with their runtime closures, signing each path's
   `.narinfo` as it is written (`nix copy --to 's3://…?secret-key=…'`);
4. finds every fixed-output path in each output's build closure, fetches
   any this machine lacks, and uploads them too ([sources.md](sources.md));
5. puts each export's `.tar.xz`, its `.sha256` and a `SOURCES.txt` under
   `exports/NAME/`.

Paths already in the cache are skipped, so running it again is cheap. The
bucket key reaches `nix` through `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` in the script's own environment, and `curl` on its
standard input; it is never on a command line.

## 3. Check from the outside

On a machine, or in a fresh store, that has never seen the paths, fetch
one with only the public key:

```sh
store=$(mktemp -d)
nix copy --store "$store" \
  --from https://701-nix-packages.nbg1.your-objectstorage.com \
  --option substituters '' \
  --trusted-public-keys '701-nix-packages-1:Nb/iOvlOiXg+1FzHGZyyNI4nE5pxNuQybb8WIhuW85Y=' \
  /nix/store/HASH-qemu-espressif-static-…
nix path-info --store "$store" --sigs /nix/store/HASH-qemu-espressif-static-…
```

The second command shows the signature `701-nix-packages-1:…`. A path that
was not signed, or signed by another key, is refused by the first.

For an export:

```sh
curl -fsSO https://701-nix-packages.nbg1.your-objectstorage.com/exports/NAME/NAME.tar.xz
curl -fsS https://701-nix-packages.nbg1.your-objectstorage.com/exports/NAME/NAME.tar.xz.sha256 | sha256sum -c
```

## Consumers that pin an export

A consumer that downloads an export without Nix, such as Landin's
`environments/cortex-m/tools.lock.json`, records its URL and SHA-256 itself.
An export is never replaced under the same name: `scripts/upload.sh`
refuses to upload an archive whose name is already published with other
bytes. The name carries the upstream version, so a new upstream version is
a new name anyway. A rebuild of the same version that changes the bytes (a
new nixpkgs, a recipe fix) needs a new name: give the export a suffix in
`flake.nix`, such as `qemu-espressif-9.2.2-20260417-2-x86_64-linux`.
