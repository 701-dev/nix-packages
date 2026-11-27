{
  description = "Tools built from source with Nix and served from our own binary cache";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/ffb3c9b700e759be2ef13237c9d8f953b32a1e46";

  # The cache. A consumer that trusts this key fetches every output, and the
  # sources it was built from, from one place. See README.md.
  nixConfig = {
    extra-substituters = [ "https://701-nix-packages.nbg1.your-objectstorage.com" ];
    extra-trusted-public-keys = [
      "701-nix-packages-1:Nb/iOvlOiXg+1FzHGZyyNI4nE5pxNuQybb8WIhuW85Y="
    ];
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      # Systems we build natively, each on its own builder (docs/builders.md).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      # A static build and its relocatable archive exist on Linux only: macOS
      # has no static system library to link, and Mac hosts use Nix.
      linuxSystems = lib.filter (lib.hasSuffix "-linux") systems;
      forAll = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      forLinux = f: lib.genAttrs linuxSystems (system: f system nixpkgs.legacyPackages.${system});

      # Our packages, added to a nixpkgs package set.
      ours = pkgs: {
        qemu-espressif = pkgs.callPackage ./packages/qemu-espressif/package.nix { };
        gcc-arm-eabi = pkgs.callPackage ./packages/gcc-elf/package.nix { target = "arm-eabi"; };
        gcc-riscv64-elf = pkgs.callPackage ./packages/gcc-elf/package.nix { target = "riscv64-elf"; };
        actionlint = pkgs.callPackage ./packages/actionlint/package.nix { };
      };
      # Those built for Linux only: what Landin's Linux lanes run.
      oursLinux = pkgs: {
        qemu-arm = pkgs.callPackage ./packages/qemu-arm/package.nix { };
        gdb = pkgs.callPackage ./packages/gdb/package.nix {
          python3 = pkgs.callPackage ./packages/gdb/python.nix { };
        };
        qemu-system = pkgs.callPackage ./packages/qemu-system/package.nix { };
        emacs-nox = pkgs.callPackage ./packages/emacs-nox/package.nix { };
      };
      # nixpkgs' own packages, unchanged, that this cache serves as well, so
      # that a consumer configured with this cache alone needs no other
      # (docs/served.md). Their store paths are nixpkgs' at this flake's
      # revision: a consumer on the same revision gets them from here.
      served =
        pkgs:
        let
          llvm = pkgs.llvmPackages_19;
        in
        {
          inherit (pkgs)
            bubblewrap
            neovim
            gdb
            tree-sitter
            shellcheck
            lychee
            ;
          clang_19 = llvm.clang;
          clang-unwrapped_19 = llvm.clang-unwrapped;
          lld_19 = llvm.lld;
          llvm_19 = llvm.llvm;
          lldb_19 = llvm.lldb;
        }
        // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
          inherit (pkgs) qemu-user;
          mingw-w64_x86_64 = pkgs.pkgsCross.mingwW64.windows.mingw_w64;
          gcc_riscv64-linux-gnu = pkgs.pkgsCross.riscv64.buildPackages.gcc;
          glibc-static_riscv64-linux-gnu = pkgs.pkgsCross.riscv64.glibc.static;
        };
    in
    {
      overlays.default =
        final: _prev: ours final // lib.optionalAttrs final.stdenv.hostPlatform.isLinux (oursLinux final);

      packages = forAll (
        system: pkgs:
        let
          static = ours pkgs.pkgsStatic // oursLinux pkgs.pkgsStatic;
        in
        ours pkgs
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
          oursLinux pkgs
          // {
            qemu-espressif-static = static.qemu-espressif;
            gdb-static = static.gdb;
            # On Linux the bare-metal compilers are the static builds alone:
            # one program serves Nix and the archive alike.
            gcc-arm-eabi = static.gcc-arm-eabi;
            gcc-riscv64-elf = static.gcc-riscv64-elf;
          }
        )
      );

      # nixpkgs' packages served unchanged from the cache, by system.
      served = forLinux (_: served);

      # Archives for hosts and CI jobs without Nix. Each is a directory
      # holding NAME.tar.xz and NAME.tar.xz.sha256; scripts/upload.sh puts
      # them under exports/ in the cache bucket.
      exports = forLinux (
        system: pkgs:
        let
          exportArchive = pkgs.callPackage ./lib/export-archive.nix { };
          bundleArchive = pkgs.callPackage ./lib/bundle-archive.nix { };
          q = self.packages.${system}.qemu-espressif-static;
          arm = self.packages.${system}.qemu-arm;
          gdb = self.packages.${system}.gdb-static;
          gccElf =
            target:
            let
              gcc = self.packages.${system}."gcc-${target}";
            in
            exportArchive {
              package = gcc;
              name = "gcc-${target}-${gcc.version}-${system}";
              dirs = [
                "bin"
                "lib"
                "libexec"
                "include"
                "share"
                target
              ];
              sources = [
                gcc.src
                gcc.binutils
                gcc.newlib
              ];
            };
        in
        {
          gcc-arm-eabi = gccElf "arm-eabi";
          gcc-riscv64-elf = gccElf "riscv64-elf";
          qemu-espressif = exportArchive {
            package = q;
            name = "qemu-espressif-${q.version}-${system}";
            sources = [ q.src ] ++ lib.attrValues q.subprojects;
          };
          # Dynamic, because a lane loads a TCG plugin into it.
          qemu-arm = bundleArchive {
            package = arm;
            programs = [ "qemu-system-arm" ];
            extraDirs = [ "include" ];
            name = "qemu-arm-${arm.version}-${system}";
            sources = [ arm.src ];
          };
          gdb = exportArchive {
            package = gdb;
            name = "gdb-${gdb.version}-${system}";
            dirs = [
              "bin"
              "share"
              "lib"
            ];
            sources = [
              gdb.src
              gdb.python3.src
            ];
          };
        }
      );

      checks = forAll (
        system: pkgs:
        let
          p = self.packages.${system};
        in
        {
          qemu-espressif = pkgs.callPackage ./packages/qemu-espressif/test.nix {
            qemu-espressif = p.qemu-espressif;
          };
          gcc-arm-eabi = pkgs.callPackage ./packages/gcc-elf/test.nix { gcc-elf = p.gcc-arm-eabi; };
          gcc-riscv64-elf = pkgs.callPackage ./packages/gcc-elf/test.nix { gcc-elf = p.gcc-riscv64-elf; };
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          qemu-espressif-static = pkgs.callPackage ./packages/qemu-espressif/test.nix {
            qemu-espressif = p.qemu-espressif-static;
          };
          qemu-arm = pkgs.callPackage ./packages/qemu-arm/test.nix { qemu-arm = p.qemu-arm; };
          qemu-arm-export = pkgs.callPackage ./packages/qemu-arm/test.nix {
            qemu-arm = p.qemu-arm;
            export = self.exports.${system}.qemu-arm;
          };
          gdb = pkgs.callPackage ./packages/gdb/test.nix { gdb = p.gdb; };
          gdb-static = pkgs.callPackage ./packages/gdb/test.nix { gdb = p.gdb-static; };
          qemu-system = pkgs.callPackage ./packages/qemu-system/test.nix {
            qemu-system = p.qemu-system;
          };
          emacs-nox = pkgs.callPackage ./packages/emacs-nox/test.nix { emacs-nox = p.emacs-nox; };
          gcc-arm-eabi-export = pkgs.callPackage ./packages/gcc-elf/test.nix {
            gcc-elf = p.gcc-arm-eabi;
            export = self.exports.${system}.gcc-arm-eabi;
          };
          gcc-riscv64-elf-export = pkgs.callPackage ./packages/gcc-elf/test.nix {
            gcc-elf = p.gcc-riscv64-elf;
            export = self.exports.${system}.gcc-riscv64-elf;
          };
          gdb-export = pkgs.callPackage ./packages/gdb/test.nix {
            gdb = p.gdb-static;
            export = self.exports.${system}.gdb;
          };
        }
      );

      formatter = forAll (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}
