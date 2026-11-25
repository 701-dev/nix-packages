# Builders

Which machine builds which system, today. Nothing in the recipes depends
on a particular machine: any machine with Nix and the right system (or a
remote builder for it) builds them, and the upload procedure runs on
whichever machine holds the signing key.

| System | Built on | How |
|---|---|---|
| x86_64-linux | the maintainers' x86-64 Linux build machine | natively |
| aarch64-linux | a Docker container with Nix on an arm64 Linux machine | as a remote store over SSH, driven from the x86-64 machine |
| aarch64-darwin | not set up yet | |

There is no CI that uploads. The GitHub repository holds no keys, and no
self-hosted runner is registered for it. Uploads are done by hand, as
[uploading.md](uploading.md) describes.

## The aarch64-linux builder

The builder is a container, so nothing is installed on the arm64 machine
itself except Docker, which it already has. The recipe is in
[`builders/aarch64-linux/`](../builders/aarch64-linux):

- `Dockerfile`: Debian 13 with single-user Nix 2.31.2 (the release tarball,
  checked against its SHA-256), owned by an unprivileged user `builder`.
- `nix-daemon`: a one-line wrapper script that runs the container's
  `nix-daemon` through `docker exec`. It is the only file placed on the
  host outside Docker, under `~/nix-packages-builder/`.
- `up.sh USER@HOST [SSH-KEY]`: copies both files to the host, builds the
  image and starts the container `nix-packages-builder-aarch64` if it is
  not running.

The container runs with no `--privileged` flag, no added capability, no
host directory mounted and no port published. Its Nix store is the named
volume `nix-packages-builder-nix`, which survives the container being
removed and created again. It holds no keys: the outputs come back to the
driving machine, which signs and uploads them.

Because the container has no privileges, Nix cannot create its build
sandbox there, so `sandbox = false`. A build in it can see the container's
file system (Debian's `/usr`), unlike a sandboxed build. The smoke tests
run in the same container and catch a binary that picked up something it
should not have; a later builder with user namespaces available should
turn the sandbox back on.

### Using it

The driving machine reaches the container's store over SSH to the host,
naming the wrapper as the remote program:

```sh
builder='ssh-ng://USER@HOST?ssh-key=KEYFILE&remote-program=/home/USER/nix-packages-builder/nix-daemon'
nix store info --store "$builder"        # says Trusted: 1
nix build --eval-store auto --store "$builder" \
  .#packages.aarch64-linux.qemu-espressif-static \
  .#checks.aarch64-linux.qemu-espressif-static
```

`--eval-store auto` evaluates the flake on the driving machine and sends
only the derivations; the build runs in the container, and its results
stay in the container's store until `scripts/upload.sh --from "$builder"`
copies them back.

This route does not use Nix's `builders` setting, which the daemon accepts
only from trusted users; it works for an ordinary user of the driving
machine's Nix.

### Removing it

On the host: `docker rm -f nix-packages-builder-aarch64`, `docker volume
rm nix-packages-builder-nix`, `docker rmi nix-packages-builder-aarch64`
and `rm -r ~/nix-packages-builder`.

## Moving a builder

To build on another machine, give it Nix (or, for aarch64-linux, run
`up.sh` against it) and point the commands above at it. To move uploading
too, copy the signing key and the bucket key to the new machine by a
private channel, never through the repository, and remove them from the
old one.
