# Smoke test: the compiler and assembler say their versions, the multilibs
# are exactly those of the GNAT-FSF-builds archive this recipe follows
# (multilibs-TARGET.txt, its `-print-multi-lib`), and a freestanding program
# that needs libgcc compiles and links for every multilib, newlib's headers
# found. Given `export`, the same test runs the archive for hosts without
# Nix, unpacked outside the store.
{
  lib,
  runCommand,
  gnutar,
  xz,
  gcc-elf,
  export ? null,
}:

let
  target = gcc-elf.target;
in
runCommand "gcc-${target}-${if export == null then "" else "export-"}test"
  {
    nativeBuildInputs = [
      gnutar
      xz
    ];
    expected = ./multilibs-${target}.txt;
  }
  ''
    set -eu
    ${
      if export == null then
        "root=${gcc-elf}"
      else
        ''
          tar xJf ${export}/${export.name}.tar.xz
          root=$PWD/${export.name}
        ''
    }
    bin=$root/bin/${target}

    $bin-gcc --version | head -1 > version
    grep -q '^${target}-gcc (701-dev nix-packages) ${gcc-elf.version}$' version \
      || { echo "gcc says:"; cat version; exit 1; }
    $bin-as --version | head -1 | grep -q ' ${gcc-elf.binutilsVersion}$' \
      || { echo "as says:"; $bin-as --version; exit 1; }

    $bin-gcc -print-multi-lib > multilibs
    diff -u $expected multilibs

    cat > program.c <<'END'
    #include <stdint.h>
    #include <string.h>
    uint64_t divide(uint64_t a, uint64_t b) { return a / b; }
    double scale(double x, int n) { return x * n; }
    void _start(void) { static volatile uint64_t r; r = divide(r, 7) + (uint64_t)scale(1.5, (int)strlen("ab")); for (;;) {} }
    END
    while IFS=';' read -r dir flags; do
      set -- $(echo "$flags" | sed 's/@/ -/g')
      $bin-gcc "$@" -O2 -ffreestanding -nostdlib -Wl,-e,_start \
        program.c -lc -lgcc -o program.elf
      $bin-objdump -d program.elf > /dev/null
      lib=$($bin-gcc "$@" -print-libgcc-file-name)
      case "$lib" in
        "$root"/*) ;;
        *) echo "multilib $dir: libgcc $lib is outside $root"; exit 1 ;;
      esac
    done < multilibs
    ${lib.optionalString (export != null) ''
      # Nothing in the archive but its list of sources names a store path
      # that is not nuked.
      if grep -rlaP --exclude=SOURCES '/nix/store/(?!e{32})[0-9a-z]{32}-' $root; then
        echo "the archive names store paths"; exit 1
      fi
    ''}
    touch $out
  ''
