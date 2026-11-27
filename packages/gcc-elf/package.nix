# A bare-metal GCC with its binutils and newlib, for one ELF target:
# `arm-eabi` (Cortex-M and Cortex-R, the rmprofile multilibs) or
# `riscv64-elf` (RV32 and RV64 multilibs, medany by default).
#
# Built the way alire-project/GNAT-FSF-builds builds its `gnat-arm-elf` and
# `gnat-riscv64-elf` archives (specs/{binutils,gcc,newlib}.anod at tag
# gnat-16.1.0-1), with the same versions, configure arguments and newlib
# patch, so that the code it generates and the libgcc it links are the
# same; but for the C language only (the Ada front end and runtimes of
# those archives are left out), without GDB (packages/gdb serves these
# targets), and with this repository's package version string.
#
# Upstream:  https://gcc.gnu.org/  https://www.gnu.org/software/binutils/
#            https://sourceware.org/newlib/
# Licence:   GPL-3.0-or-later with the GCC Runtime Library Exception
#            (GCC, libgcc); GPL-3.0-or-later (binutils); newlib is under
#            several free licences, BSD-style for the most part (its
#            COPYING.NEWLIB).
#
# Called from pkgsStatic this gives static (musl) executables that need
# nothing from /nix/store at run time: GCC finds its programs, libraries and
# headers relative to its own executable, so the output can be moved and used
# without Nix (lib/export-archive.nix). A static build has no plugins, and
# so no link-time optimization, which needs GCC's linker plugin; nothing
# this serves uses it.
{
  lib,
  stdenv,
  fetchurl,
  gmp,
  mpfr,
  libmpc,
  isl,
  zlib,
  zstd,
  perl,
  texinfo,
  target ? "arm-eabi",
}:

let
  isStatic = stdenv.hostPlatform.isStatic;
  isDarwin = stdenv.hostPlatform.isDarwin;
  version = "16.1.0";
  binutilsVersion = "2.46.1";
  newlibVersion = "4.4.0.20231231";

  # GNAT-FSF-builds' per-target arguments (gcc.anod, configure_args).
  targetArgs =
    {
      arm-eabi = [
        "--enable-multilib"
        "--with-multilib-list=rmprofile"
      ];
      riscv64-elf = [
        "--enable-multilib"
        "--with-specs=%{!mcmodel=*:-mcmodel=medany}"
      ];
    }
    .${target};

  # gcc.anod's cross_commons.
  crossCommon = [
    "--disable-decimal-float"
    "--disable-libffi"
    "--disable-libgomp"
    "--disable-libmudflap"
    "--disable-libquadmath"
    "--disable-libssp"
    "--disable-libstdcxx-pch"
    "--disable-nls"
    "--disable-shared"
    "--disable-threads"
    "--disable-tls"
    "--with-newlib"
  ];
  # A static program cannot load a shared object, and GCC's LTO support
  # needs its linker plugin, one.
  pluginArgs =
    if isStatic then
      [
        "--disable-plugin"
        "--disable-lto"
      ]
    else
      [
        "--enable-plugins"
        "--enable-lto"
      ];

  gccArgs =
    languages:
    [
      "--prefix=${placeholder "out"}"
      "--target=${target}"
      "--with-build-time-tools=${placeholder "out"}/bin"
      "--enable-languages=${languages}"
      "--disable-libada"
      "--with-pkgversion=701-dev nix-packages"
      "--with-bugurl=https://github.com/701-dev/nix-packages/issues"
      "--disable-nls"
      "--without-libiconv-prefix"
      "--disable-libstdcxx-pch"
      "--with-gnu-ld"
      "--with-gnu-as"
      "--with-gmp=${gmp.dev}"
      "--with-gmp-lib=${lib.getLib gmp}/lib"
      "--with-mpfr=${mpfr.dev}"
      "--with-mpfr-lib=${lib.getLib mpfr}/lib"
      "--with-mpc=${libmpc}"
      "--with-isl=${isl}"
      "--with-system-zlib"
    ]
    ++ pluginArgs
    ++ crossCommon
    ++ targetArgs;
in
stdenv.mkDerivation {
  pname = "gcc-${target}";
  inherit version target;

  src = fetchurl {
    url = "mirror://gcc/releases/gcc-${version}/gcc-${version}.tar.xz";
    hash = "sha256-UO+02Uwzl6/zsNYaWr10i03THZ0/Kre+BbFx02pRD3k=";
  };
  binutils = fetchurl {
    url = "mirror://gnu/binutils/binutils-${binutilsVersion}.tar.xz";
    hash = "sha256-4SenCcuiTHbeiTbLcIPddo8ozTfrAQSS4vGbcesSlOQ=";
  };
  newlib = fetchurl {
    url = "https://sourceware.org/pub/newlib/newlib-${newlibVersion}.tar.gz";
    hash = "sha256-DBZqOeG/CVHfr81olJ/g5LbTZYCB1igvOa7vxjEPLxM=";
  };
  newlibPatch = ./patches/newlib-fix-arm-eh_frame.patch;

  nativeBuildInputs = [
    perl
    texinfo
  ];
  buildInputs = [
    gmp
    mpfr
    libmpc
    isl
    zlib
    zstd
  ];

  strictDeps = true;
  enableParallelBuilding = true;
  # Host programs only; the target libraries are built by the new xgcc,
  # which no wrapper touches.
  hardeningDisable = [ "format" ];

  # Three source trees, each configured in its own build directory, all
  # installed into $out one after the other, as GNAT-FSF-builds merges them.
  unpackPhase = ''
    runHook preUnpack
    mkdir src && cd src
    tar xf $src && mv gcc-${version} gcc
    tar xf $binutils && mv binutils-${binutilsVersion} binutils
    tar xf $newlib && mv newlib-${newlibVersion} newlib
    (cd newlib && patch -p0 < $newlibPatch)
    patchShebangs --build gcc binutils newlib
    runHook postUnpack
  '';
  sourceRoot = ".";

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    jobs=$NIX_BUILD_CORES
    export PATH=$out/bin:$PATH

    # binutils.anod
    mkdir -p build/binutils && cd build/binutils
    ../../binutils/configure --prefix=$out --target=${target} \
      --disable-nls --disable-shared --disable-werror --with-system-zlib \
      --without-zstd --disable-compressed-debug-sections \
      --disable-separate-code --disable-gdb --disable-gdbserver --disable-sim \
      --disable-libquadmath --disable-readline --enable-multilib \
      ${if isStatic then "--disable-plugins --disable-lto" else "--enable-lto"}
    make -j$jobs
    make install-strip
    cd ../..

    # gcc.anod's bootstrap qualifier: C only, no target libraries.
    mkdir -p build/gcc-bootstrap && cd build/gcc-bootstrap
    ../../gcc/configure ${lib.escapeShellArgs (gccArgs "c")}
    make -j$jobs all-gcc
    make install-gcc
    cd ../..

    # newlib.anod, with the bootstrap compiler.
    mkdir -p build/newlib && cd build/newlib
    ../../newlib/configure --prefix=$out --target=${target} \
      --enable-newlib-io-long-long --enable-newlib-io-c99-formats \
      --enable-newlib-register-fini --enable-newlib-retargetable-locking \
      --disable-newlib-supplied-syscalls --disable-nls
    make -j$jobs
    make install-target-newlib
    cd ../..

    # The compiler itself, its libgcc built against newlib's headers.
    mkdir -p build/gcc && cd build/gcc
    ../../gcc/configure ${lib.escapeShellArgs (gccArgs "c")}
    make -j$jobs all
    make ${if isDarwin then "install" else "install-strip"}
    cd ../..
    runHook postBuild
  '';

  dontInstall = true;
  # install-strip stripped the host programs with the host's strip and the
  # target libraries with the target's; the fixup's strip knows only the
  # host's and would damage the target's archives. On Darwin libtool's
  # install-strip hands Apple's strip an option it refuses for Mach-O, so
  # GCC is installed unstripped there and the fixup strips the host
  # programs alone: the target libraries are not in these directories.
  dontStrip = !isDarwin;
  ${if isDarwin then "stripDebugList" else null} = [
    "bin"
    "libexec"
    "${target}/bin"
  ];

  postFixup = ''
    # Nothing of the build: manuals other than the man pages, and libtool
    # archives, which name build directories.
    rm -rf $out/share/info $out/share/locale
    find $out -name '*.la' -delete
  '';

  passthru = {
    inherit binutilsVersion newlibVersion;
  };

  meta = {
    description = "GCC ${version}, binutils ${binutilsVersion} and newlib for ${target}";
    homepage = "https://gcc.gnu.org/";
    license = with lib.licenses; [
      gpl3Plus
      lgpl3Plus
      bsd3
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "${target}-gcc";
  };
}
