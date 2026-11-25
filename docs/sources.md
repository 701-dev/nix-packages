# Where the sources are

Several of the programs in the binary cache are under the GPL: QEMU is
GPL-2.0, and future packages such as GCC and GDB are GPL-3.0. Whoever
distributes their binaries must also make the corresponding source
available. This is how this repository does that.

## What is uploaded

When a package is uploaded (`scripts/upload.sh`, see
[uploading.md](uploading.md)), three things go to the same cache:

1. The package itself and its runtime closure, signed.
2. Every fixed-output path in its build closure: the upstream tarballs and
   repository snapshots, the patches, and the bootstrap binaries Nix
   starts from. These are the sources of the package and of every library
   linked into it. Together with this repository at the commit that built
   it, they are everything needed to rebuild the binary.
3. For an export, a file `exports/NAME/SOURCES.txt` that lists those
   source paths. The archive itself carries a short `SOURCES` file naming
   the derivation and the package's own sources.

The sources are offered from the same place as the binaries, on the same
terms (public, no account). They are not deleted while any binary built
from them is still in the cache.

## Fetching them

With Nix, a source path is fetched like any other path:

```sh
nix copy --from https://701-nix-packages.nbg1.your-objectstorage.com \
  /nix/store/HASH-source
```

or, for everything a package was built from, in a checkout of this
repository at the commit that built it:

```sh
nix derivation show --recursive .#qemu-espressif-static
```

lists the derivations; those with a `hash` field are the sources.

Without Nix, take the path's 32-character hash and fetch
`https://701-nix-packages.nbg1.your-objectstorage.com/HASH.narinfo`. Its
`URL:` line names the compressed NAR file beside it, and its `Compression:`
line the compression (zstd). A NAR is Nix's archive format; `nix-store
--restore DIR < FILE.nar` unpacks it, as does any of several independent
NAR readers.

## The recipes' own licence

The recipes and scripts in this repository are MIT OR Apache-2.0
([LICENSE](../LICENSE)). That licence does not change the licence of what
they build.
