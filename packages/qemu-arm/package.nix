# Upstream QEMU, system emulation for 32-bit Arm only, holding just the
# machines Landin's Cortex-M lanes start: microbit (Cortex-M0) and the MPS2
# boards (mps2-an385, -an386, -an500, -an505, -an511, -an521), plus `none`.
# TCG plugins stay on: a lane counts instructions with one.
#
# Upstream:  https://www.qemu.org
# Licence:   GPL-2.0-only (QEMU), with parts under other GPL-compatible licences.
#
# A plugin is loaded with dlopen, so this build is dynamically linked; the
# archive for hosts without Nix (lib/bundle-archive.nix) carries its loader
# and libraries with it.
{
  lib,
  stdenv,
  fetchurl,
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
  dtc,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "qemu-arm";
  version = "10.0.13";

  # The release tarball, which already holds the meson subprojects QEMU's
  # build would otherwise download (keycodemapdb, berkeley-softfloat-3, ...).
  src = fetchurl {
    url = "https://download.qemu.org/qemu-${finalAttrs.version}.tar.xz";
    hash = "sha256-Slm3Tax+rYsWKnxFldy77r6Ym5DInP5rtN7FRHNC9vo=";
  };

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
    dtc
  ];

  # QEMU's configure script drives meson itself.
  dontUseMesonConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaCheck = true;
  dontUseNinjaInstall = true;

  postPatch = ''
    # The machines this build holds; every other board and device is left out.
    cat > configs/devices/arm-softmmu/landin.mak <<'END'
    CONFIG_MICROBIT=y
    CONFIG_MPS2=y
    END
  '';

  preConfigure = ''
    unset CPP
    patchShebangs .
    # A file named VERSION shadows the C++ <version> header on case-insensitive
    # file systems and confuses some toolchains; nixpkgs' QEMU renames it too.
    mv VERSION QEMU_VERSION
    substituteInPlace configure --replace-fail '$source_path/VERSION' '$source_path/QEMU_VERSION'
    substituteInPlace Makefile --replace-fail '$(SRC_PATH)/VERSION' '$(SRC_PATH)/QEMU_VERSION'
    substituteInPlace meson.build --replace-fail "'VERSION'" "'QEMU_VERSION'"
  '';

  configureFlags = [
    "--target-list=arm-softmmu"
    "--without-default-devices"
    "--with-devices-arm=landin"
    "--without-default-features"
    "--enable-tcg"
    "--enable-plugins"
    "--enable-fdt=system"
    "--disable-docs"
    "--disable-tools"
    "--disable-user"
    "--disable-werror"
    "--disable-download"
    "--disable-strip"
    "--cross-prefix=${stdenv.cc.targetPrefix}"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    test -x $out/bin/qemu-system-arm
    test -f $out/include/qemu-plugin.h
    # The machines here load no firmware, keymap or ROM image.
    rm -rf $out/share/qemu $out/share/{applications,icons} $out/libexec
  '';

  meta = {
    description = "QEMU for the Cortex-M machines microbit and MPS2, headless, with TCG plugins";
    homepage = "https://www.qemu.org";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "qemu-system-arm";
  };
})
