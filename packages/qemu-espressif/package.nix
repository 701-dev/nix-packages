# Espressif's fork of QEMU, headless: system emulation for Xtensa (ESP32,
# ESP32-S3) and 32-bit RISC-V (ESP32-C3), and nothing else.
#
# Upstream:  https://github.com/espressif/qemu
# Licence:   GPL-2.0-only (QEMU), with parts under other GPL-compatible licences.
#
# Called with the ordinary package set this gives a dynamically linked build;
# called from pkgsStatic it gives a fully static (musl) one that runs on any
# Linux distribution without Nix.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchFromGitLab,
  buildPackages,
  pkg-config,
  meson,
  ninja,
  perl,
  flex,
  bison,
  python3Packages,
  glib,
  zlib,
  pixman,
  libgcrypt,
  libgpg-error,
  dtc,
  libslirp,
}:

let
  isStatic = stdenv.hostPlatform.isStatic;

  # QEMU's build downloads these meson subprojects unless they are already in
  # place. The revisions are the ones the fork's subprojects/*.wrap files name.
  subprojects = {
    keycodemapdb = fetchFromGitLab {
      owner = "qemu-project";
      repo = "keycodemapdb";
      rev = "f5772a62ec52591ff6870b7e8ef32482371f22c6";
      hash = "sha256-GbZ5mrUYLXMi0IX4IZzles0Oyc095ij2xAsiLNJwfKQ=";
    };
    berkeley-softfloat-3 = fetchFromGitLab {
      owner = "qemu-project";
      repo = "berkeley-softfloat-3";
      rev = "b64af41c3276f97f0e181920400ee056b9c88037";
      hash = "sha256-Yflpx+mjU8mD5biClNpdmon24EHg4aWBZszbOur5VEA=";
    };
    berkeley-testfloat-3 = fetchFromGitLab {
      owner = "qemu-project";
      repo = "berkeley-testfloat-3";
      rev = "e7af9751d9f9fd3b47911f51a5cfd08af256a9ab";
      hash = "sha256-inQAeYlmuiRtZm37xK9ypBltCJ+ycyvIeIYZK8a+RYU=";
    };
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "qemu-espressif";
  version = "9.2.2-20260417";

  src = fetchFromGitHub {
    owner = "espressif";
    repo = "qemu";
    rev = "esp-develop-${finalAttrs.version}";
    hash = "sha256-Ts7bpags6Srt3cX2l5LfBE5nPzwpXIe9UYXKBmJ+flw=";
  };

  # The version string Espressif's own release binaries print, so that
  # `qemu-system-xtensa --version` says the same thing whichever build runs:
  # "QEMU emulator version 9.2.2 (esp_develop_9.2.2_20260417)".
  pkgversion = "esp_develop_" + lib.replaceStrings [ "-" ] [ "_" ] finalAttrs.version;

  postUnpack = lib.concatStrings (
    lib.mapAttrsToList (name: source: ''
      cp -r ${source} $sourceRoot/subprojects/${name}
      chmod -R u+w $sourceRoot/subprojects/${name}
      if [ -d $sourceRoot/subprojects/packagefiles/${name} ]; then
        cp -r $sourceRoot/subprojects/packagefiles/${name}/. $sourceRoot/subprojects/${name}/
      fi
    '') subprojects
  );

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    perl
    flex
    bison
    python3Packages.python
    python3Packages.distlib
    python3Packages.setuptools
    python3Packages.wheel
  ];
  buildInputs = [
    glib
    zlib
    pixman
    libgcrypt
    libgpg-error
    dtc
    libslirp
  ];

  # QEMU's configure script drives meson itself.
  dontUseMesonConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaCheck = true;
  dontUseNinjaInstall = true;
  dontAddStaticConfigureFlags = true;

  preConfigure = ''
    unset CPP
  ''
  + lib.optionalString isStatic ''
    # A static link must find these through pkg-config, which knows their
    # static dependencies; meson's find_library does not.
    substituteInPlace meson.build \
      --replace-fail "cc.find_library('gpg-error', required: true)" \
                     "dependency('gpg-error', method: 'pkg-config', static: true)" \
      --replace-fail "cc.find_library('fdt', required: fdt_opt == 'system')" \
                     "dependency('libfdt', method: 'pkg-config', static: true, required: fdt_opt == 'system')"
  ''
  + lib.optionalString (!isStatic) ''
    # The fork asks pkg-config for a static libslirp; a dynamic build links the shared one.
    sed -i '/slirp_dep = dependency(.slirp./,/static: true)/ s/static: true/static: false/' meson.build
  ''
  + ''
    patchShebangs .
    # A file named VERSION shadows the C++ <version> header on case-insensitive
    # file systems and confuses some toolchains; nixpkgs' QEMU renames it too.
    mv VERSION QEMU_VERSION
    substituteInPlace configure --replace-fail '$source_path/VERSION' '$source_path/QEMU_VERSION'
    substituteInPlace Makefile --replace-fail '$(SRC_PATH)/VERSION' '$(SRC_PATH)/QEMU_VERSION'
    substituteInPlace meson.build --replace-fail "'VERSION'" "'QEMU_VERSION'"
  '';

  configureFlags = [
    "--target-list=xtensa-softmmu,riscv32-softmmu"
    "--with-pkgversion=${finalAttrs.pkgversion}"
    "--without-default-features"
    "--enable-gcrypt"
    "--enable-fdt=system"
    "--enable-tcg"
    "--enable-slirp"
    "--disable-docs"
    "--disable-tools"
    "--disable-user"
    "--disable-werror"
    "--disable-download"
    "--disable-strip"
    "--disable-plugins"
    "--cross-prefix=${stdenv.cc.targetPrefix}"
  ]
  ++ lib.optionals isStatic [
    "--static"
    # QEMU links a static build as static-pie where the compiler offers it,
    # as on aarch64; with nixpkgs' musl that binary crashes in __init_libc
    # before main, its relocations unapplied. A plain static link works.
    "--disable-pie"
  ];

  # meson's find_library('gpg-error') for a static link searches only the
  # compiler's own directories.
  env = lib.optionalAttrs isStatic { LIBRARY_PATH = "${libgpg-error.out}/lib"; };

  enableParallelBuilding = true;

  postInstall = ''
    test -x $out/bin/qemu-system-xtensa
    test -x $out/bin/qemu-system-riscv32
    # Keep the two emulators and Espressif's ROM images; drop the firmware,
    # keymaps and desktop files of machines this build does not have.
    find $out/share/qemu -maxdepth 1 -type f ! -name 'esp32*' -delete
    rm -rf $out/share/qemu/{keymaps,firmware,vhost-user} $out/share/{applications,icons} $out/libexec
  '';

  # A static binary needs nothing at run time; do not drag the static
  # libraries' store paths into its closure.
  postFixup = lib.optionalString isStatic ''
    rm -f $out/nix-support/propagated-build-inputs
  '';

  passthru = { inherit subprojects; };

  meta = {
    description = "Espressif's QEMU fork, headless, for ESP32, ESP32-S3 and ESP32-C3";
    homepage = "https://github.com/espressif/qemu";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "qemu-system-xtensa";
  };
})
