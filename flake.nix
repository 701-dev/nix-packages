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
    in
    {
      overlays.default = final: _prev: ours final;

      packages = forAll (
        system: pkgs:
        let
          dynamic = ours pkgs;
          static = ours pkgs.pkgsStatic;
        in
        dynamic
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          qemu-espressif-static = static.qemu-espressif;
        }
      );

      # Archives for hosts and CI jobs without Nix. Each is a directory
      # holding NAME.tar.xz and NAME.tar.xz.sha256; scripts/upload.sh puts
      # them under exports/ in the cache bucket.
      exports = forLinux (
        system: pkgs:
        let
          exportArchive = pkgs.callPackage ./lib/export-archive.nix { };
          q = self.packages.${system}.qemu-espressif-static;
        in
        {
          qemu-espressif = exportArchive {
            package = q;
            name = "qemu-espressif-${q.version}-${system}";
            sources = [ q.src ] ++ lib.attrValues q.subprojects;
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
        }
      );

      formatter = forAll (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}
