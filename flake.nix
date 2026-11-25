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
      };
      # Those built for Linux only: what Landin's Linux lanes run.
      oursLinux = pkgs: {
        qemu-arm = pkgs.callPackage ./packages/qemu-arm/package.nix { };
        gdb = pkgs.callPackage ./packages/gdb/package.nix {
          python3 = pkgs.callPackage ./packages/gdb/python.nix { };
        };
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
          }
        )
      );

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
        in
        {
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
          gdb-export = pkgs.callPackage ./packages/gdb/test.nix {
            gdb = p.gdb-static;
            export = self.exports.${system}.gdb;
          };
        }
      );

      formatter = forAll (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}
