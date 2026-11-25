# nix-packages

Nix recipes for the external tools that 701-dev's projects build and test
with. Each tool is built from its upstream source and served, signed, from
our own binary cache, together with the sources it was built from. A
machine with Nix fetches it from there. A machine or CI job without Nix
downloads a plain archive built from the same recipe.

The first user is [Landin](https://github.com/701-dev/Landin), whose
emulator lanes run firmware on these QEMUs and debug it with this GDB.

## Packages

| Flake output | What it is | Systems |
|---|---|---|
| `packages.<system>.qemu-espressif` | [Espressif's QEMU fork](https://github.com/espressif/qemu) 9.2.2-20260417, headless: `qemu-system-xtensa` (machines `sim`, `esp32`, `esp32s3`) and `qemu-system-riscv32` (`esp32c3`, `sifive_e`), with Espressif's ROM images. Dynamically linked. | x86_64-linux, aarch64-linux, aarch64-darwin |
| `packages.<system>.qemu-espressif-static` | The same, fully static (musl). Runs on any Linux distribution. | x86_64-linux, aarch64-linux |
| `exports.<system>.qemu-espressif` | The static build as a relocatable `.tar.xz` for hosts without Nix | x86_64-linux, aarch64-linux |
| `packages.<system>.qemu-arm` | [QEMU](https://www.qemu.org) 10.0.13, `qemu-system-arm` with only the Cortex-M machines `microbit` and `mps2-an385`/`-an386`/`-an500`/`-an505`/`-an511`/`-an521` (and `none`), headless, with TCG plugins and `include/qemu-plugin.h`. Dynamically linked, because a plugin is loaded with `dlopen`. | x86_64-linux, aarch64-linux |
| `exports.<system>.qemu-arm` | The same as a relocatable `.tar.xz` that carries its shared libraries and glibc's loader: `bin/qemu-system-arm` runs `libexec/qemu-system-arm` through them | x86_64-linux, aarch64-linux |
| `packages.<system>.gdb` | [GDB](https://www.sourceware.org/gdb/) 16.3 for the host, Arm and RISC-V targets, with Python 3.13; without debuginfod, babeltrace, Intel PT, source-highlight, Guile, the TUI, the simulators and gdbserver. Dynamically linked. | x86_64-linux, aarch64-linux |
| `packages.<system>.gdb-static` | The same, fully static (musl), with Python linked in and its standard library beside it under `lib/python3.13`, found relative to the executable | x86_64-linux, aarch64-linux |
| `exports.<system>.gdb` | The static build as a relocatable `.tar.xz` | x86_64-linux, aarch64-linux |
| `checks.<system>.*` | A smoke test per package, and per export run unpacked outside the store: version string, machines or architectures, ROMs, a start of the `sim` machine, a TCG plugin loaded, GDB's Python and its library | x86_64-linux, aarch64-linux; aarch64-darwin for `qemu-espressif` |

There is no static build or export for macOS: macOS has no static system
library to link against, and Macs fetch the package with Nix.

## Using the binary cache

The cache is `https://701-nix-packages.nbg1.your-objectstorage.com`. It is
public; nothing is needed to read it but the public key:

```
701-nix-packages-1:Nb/iOvlOiXg+1FzHGZyyNI4nE5pxNuQybb8WIhuW85Y=
```

To use it for everything, add both lines to `nix.conf` (on NixOS, to
`nix.settings`):

```
extra-substituters = https://701-nix-packages.nbg1.your-objectstorage.com
extra-trusted-public-keys = 701-nix-packages-1:Nb/iOvlOiXg+1FzHGZyyNI4nE5pxNuQybb8WIhuW85Y=
```

The flake announces the same two settings in its `nixConfig`, so
`nix build github:701-dev/nix-packages#qemu-espressif` asks once whether
to trust them. A user who is not trusted by the Nix daemon has to add them
to the system's configuration instead; the question is then not asked.

Every package is uploaded with its whole runtime closure, glibc
included on Linux, so a machine configured with only this cache needs no
other. On macOS the closure links only against the system's own libraries
and frameworks (`libSystem`, CoreFoundation, IOKit) beyond it.

To fetch one path without changing any configuration:

```sh
nix copy --from https://701-nix-packages.nbg1.your-objectstorage.com \
  --trusted-public-keys '701-nix-packages-1:Nb/iOvlOiXg+1FzHGZyyNI4nE5pxNuQybb8WIhuW85Y=' \
  /nix/store/HASH-NAME
```

(On a multi-user install the daemon only accepts these flags from a trusted
user; anyone else configures the cache as above.)

## Without Nix

Each export is a `.tar.xz` with one top-level directory holding `bin/`, a
`SOURCES` file and what the program needs beside it (`share/`, `lib/`,
`libexec/`). It needs nothing outside itself, glibc included, and can be
unpacked anywhere:

```
https://701-nix-packages.nbg1.your-objectstorage.com/exports/NAME/NAME.tar.xz
https://701-nix-packages.nbg1.your-objectstorage.com/exports/NAME/NAME.tar.xz.sha256
https://701-nix-packages.nbg1.your-objectstorage.com/exports/NAME/SOURCES.txt
```

where `NAME` is, for example, `qemu-espressif-9.2.2-20260417-x86_64-linux`.
Check the archive against its `.sha256`, or better against a hash you
recorded yourself, before you use it.

## Building

```sh
nix build .#qemu-espressif-static     # for this machine's system
nix flake check                       # the smoke tests
nix build .#exports.x86_64-linux.qemu-espressif
```

A build on a machine that trusts the cache fetches the result instead of
building it. [docs/builders.md](docs/builders.md) says which machine builds
which system and how to set up the aarch64-linux and aarch64-darwin
builders.
[docs/uploading.md](docs/uploading.md) is the procedure for signing and
uploading by hand.

## Licences

The recipes, scripts and documents here are dual-licensed MIT OR
Apache-2.0; see [LICENSE](LICENSE). The programs they build keep their own
licences, named in each recipe's `meta.license`. QEMU is GPL-2.0, GDB
GPL-3.0-or-later; the `qemu-arm` archive also carries glibc (LGPL-2.1) and
the libraries QEMU links.
[docs/sources.md](docs/sources.md) says how the corresponding source of
everything in the cache stays available.
