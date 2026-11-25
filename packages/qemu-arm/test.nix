# Smoke test: the emulator starts, says its version, holds the machines the
# Cortex-M lanes start, and loads a TCG plugin. Given `export`, the same
# test runs the archive for hosts without Nix, unpacked outside the store.
{
  lib,
  runCommand,
  stdenv,
  pkg-config,
  glib,
  gnutar,
  xz,
  qemu-arm,
  export ? null,
}:

runCommand "qemu-arm-${if export == null then "" else "export-"}test"
  {
    nativeBuildInputs = [
      stdenv.cc
      pkg-config
      gnutar
      xz
    ];
    buildInputs = [ glib ];
  }
  ''
    set -eu
    ${
      if export == null then
        "root=${qemu-arm}"
      else
        ''
          tar xJf ${export}/${export.name}.tar.xz
          root=$PWD/${export.name}
        ''
    }
    qemu=$root/bin/qemu-system-arm

    $qemu --version > version
    grep -q '^QEMU emulator version ${qemu-arm.version}$' version \
      || { echo "qemu-system-arm says:"; cat version; exit 1; }

    $qemu -machine help > machines
    for machine in none microbit mps2-an385 mps2-an500 mps2-an505; do
      grep -q "^$machine " machines || { echo "machine $machine missing"; cat machines; exit 1; }
    done

    # A plugin that counts nothing: it is found, loaded and installed.
    cat > plugin.c <<'END'
    #include <qemu-plugin.h>
    QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;
    QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id, const qemu_info_t *info,
                                               int argc, char **argv)
    { return 0; }
    END
    cc -shared -fPIC $(pkg-config --cflags glib-2.0) -I$root/include -o plugin.so plugin.c
    echo quit | $qemu -M microbit -display none -monitor stdio -serial none -S \
      -plugin ./plugin.so > run.log 2>&1 || { cat run.log; exit 1; }

    touch $out
  ''
