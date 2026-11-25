# GDB for Arm and RISC-V targets, with the Python its scripts run, and
# without what nothing here uses: debuginfod (and its curl, Kerberos, LDAP
# and OpenSSL), babeltrace, Intel PT, source-highlight, xxhash, Guile, the
# TUI, the simulators, gdbserver and native language support.
#
# Upstream:  https://www.sourceware.org/gdb/
# Licence:   GPL-3.0-or-later (GDB), with parts under other GPL-compatible licences.
#
# Called from pkgsStatic this gives one static (musl) executable with Python
# linked in. Python's standard library is installed beside it under
# lib/python3.X, and GDB finds it relative to its own executable, so the
# output can be moved and used without Nix (lib/export-archive.nix).
{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  removeReferencesTo,
  pkg-config,
  perl,
  texinfo,
  bison,
  flex,
  zlib,
  expat,
  readline,
  ncurses,
  gmp,
  mpfr,
  python3,
  # The targets besides the host's; "all" is what Debian's gdb-multiarch
  # builds. The Linux ones give each architecture the handler for the host's
  # default OS ABI, GNU/Linux: without them `set architecture armv7e-m`, with
  # no file loaded, warns that none is built in.
  targets ? [
    "arm-none-eabi"
    "arm-linux-gnueabihf"
    "riscv64-unknown-elf"
    "riscv64-linux-gnu"
  ],
}:

let
  isStatic = stdenv.hostPlatform.isStatic;
  pythonLib = "lib/${python3.libPrefix}";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gdb";
  version = "16.3";

  src = fetchurl {
    url = "mirror://gnu/gdb/gdb-${finalAttrs.version}.tar.xz";
    hash = "sha256-vPzQlVKKmHkXrPn/8/FnIYFpSSbMGNYJyZ0AQsACJMU=";
  };

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [
    removeReferencesTo
    pkg-config
    perl
    texinfo
    bison
    flex
  ];
  buildInputs = [
    zlib
    expat
    readline
    ncurses
    gmp
    mpfr
    python3
  ];

  strictDeps = true;
  enableParallelBuilding = true;
  env.NIX_CFLAGS_COMPILE = "-Wno-format-nonliteral";

  preConfigure = ''
    # The precompiled manuals mention paths this build does not use.
    rm gdb/doc/*.info* gdb/doc/*.5 gdb/doc/*.1 gdb/doc/GDBvn.texi
    # GDB is built out of tree.
    mkdir _build
    cd _build
  '';
  configureScript = "../configure";

  configureFlags = [
    "--enable-targets=${lib.concatStringsSep "," targets}"
    "--disable-werror"
    "--enable-64-bit-bfd"
    "--disable-shared"
    "--enable-static"
    "--disable-install-libbfd"
    "--disable-tui"
    "--without-curses"
    "--disable-sim"
    "--disable-gdbserver"
    "--disable-inprocess-agent"
    "--disable-gprofng"
    "--disable-nls"
    "--disable-source-highlight"
    "--without-debuginfod"
    "--without-babeltrace"
    "--without-intel-pt"
    "--without-xxhash"
    "--without-guile"
    "--without-lzma"
    "--without-zstd"
    "--with-system-zlib"
    # GDB 16.3's own copy of readline predates C23, GCC 15's default.
    "--with-system-readline"
    "--with-expat"
    "--with-libexpat-prefix=${expat.dev}"
    "--with-gmp=${gmp.dev}"
    "--with-mpfr=${mpfr.dev}"
    # The Python to link, asked for its flags by GDB's python-config.py. It
    # runs on the build machine: a static Python for the build's own CPU does.
    "--with-python=${python3}/bin/python3"
    # Where GDB looks for Python's standard library. Under GDB's own prefix,
    # so GDB resolves it relative to its executable.
    "--with-python-libdir=${placeholder "out"}/lib"
    "--with-system-gdbinit=/etc/gdb/gdbinit"
    "--with-system-gdbinit-dir=/etc/gdb/gdbinit.d"
  ];

  postInstall = ''
    # The standard library, without what GDB's scripts cannot use.
    mkdir -p $out/${pythonLib}
    cp -r ${python3}/${pythonLib}/. $out/${pythonLib}/
    chmod -R u+w $out/${pythonLib}
    rm -rf $out/${pythonLib}/{test,idlelib,tkinter,turtledemo,ensurepip,lib2to3,site-packages,config-*}
    rm -f $out/${pythonLib}/ctypes/macholib/fetch_macholib
    # nixpkgs points subprocess's shell at its own bash; this library is
    # also used outside the store, where the shell is /bin/sh.
    sed -i "s|else '/nix/store/[^']*/bin/sh')|else '/bin/sh')|" $out/${pythonLib}/subprocess.py
    grep -q "else '/bin/sh')" $out/${pythonLib}/subprocess.py
    # Bytecode for it and for GDB's own Python, made once here rather than by
    # each GDB that starts: without it every start compiles what it imports.
    # Checked against the source's hash, not its time, so it stays valid in
    # an unpacked archive whatever times the files get.
    ${python3}/bin/python3 -m compileall -q -j0 --invalidation-mode unchecked-hash \
      $out/${pythonLib} $out/share/gdb/python
    # Info pages that binutils' own packages provide.
    rm -rf $out/share/info $out/share/man $out/include
    rm -f $out/lib/*.a $out/lib/*.la
  ''
  + lib.optionalString isStatic ''
    # gcore, gstack and gdb-add-index are shell scripts around GDB; they
    # would need a shell from the store.
    find $out/bin -type f ! -name gdb -delete
  '';

  # A static GDB needs nothing at run time: drop the static libraries from
  # its closure (the propagated inputs) and the static Python's prefix,
  # which GDB's configure compiled in and its standard library's
  # sysconfig data name but nothing opens.
  postFixup = lib.optionalString isStatic ''
    rm -f $out/nix-support/propagated-build-inputs
    rmdir --ignore-fail-on-non-empty $out/nix-support
    find $out -type f -exec remove-references-to -t ${python3} {} +
  '';
  # The static ncurses names its terminfo directory, which GDB's readline
  # reads; outside the store it falls back to /etc/terminfo.
  allowedReferences =
    if isStatic then
      [
        "out"
        ncurses.out
      ]
    else
      null;

  passthru = {
    inherit python3;
    pythonVersion = python3.pythonVersion;
  };

  meta = {
    description = "GDB for Arm and RISC-V targets, with Python, without debuginfod";
    homepage = "https://www.sourceware.org/gdb/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "gdb";
  };
})
