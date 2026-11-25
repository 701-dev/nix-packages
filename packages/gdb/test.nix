# Smoke test: GDB starts, says its version, knows the architectures the
# debugger sessions set, and runs Python with the modules they import,
# from its own standard library and not from anywhere else. Given `export`,
# the same test runs the archive for hosts without Nix, unpacked outside
# the store.
{
  runCommand,
  gnutar,
  xz,
  gdb,
  export ? null,
}:

runCommand "gdb-${if export == null then "" else "export-"}test"
  {
    nativeBuildInputs = [
      gnutar
      xz
    ];
  }
  ''
    set -eu
    export HOME=$PWD
    ${
      if export == null then
        "root=${gdb}"
      else
        ''
          tar xJf ${export}/${export.name}.tar.xz
          root=$PWD/${export.name}
        ''
    }
    gdb=$root/bin/gdb

    $gdb --version > version 2>&1 || { echo "gdb --version failed:"; cat version; exit 1; }
    grep -q '^GNU gdb (GDB) ${gdb.version}$' version || { echo "gdb says:"; cat version; exit 1; }

    # The ones Landin's debugger sessions set, and the other M profiles.
    for arch in armv6-m armv7e-m armv8-m.main riscv:rv32; do
      $gdb -q -nx -batch -ex "set architecture $arch" > arch.log 2>&1 \
        || { echo "architecture $arch failed:"; cat arch.log; exit 1; }
      grep -q "^The target architecture is set to \"$arch\"\.$" arch.log \
        && ! grep -qi "warning\|error" arch.log \
        || { echo "architecture $arch:"; cat arch.log; exit 1; }
    done

    cat > check.py <<END
    import gdb, sys, os, json, math, socket, subprocess, tempfile, threading, time, contextlib, pathlib, select
    assert sys.prefix == "$root", sys.prefix
    assert all(not m.__file__ or m.__file__.startswith("$root") for m in (os, json, socket)), [os.__file__]
    print("python", sys.version.split()[0])
    END
    $gdb -q -nx -batch -x check.py > python.log 2>&1 || { echo "python failed:"; cat python.log; exit 1; }
    grep -q '^python ${gdb.pythonVersion}' python.log || { cat python.log; exit 1; }

    touch $out
  ''
