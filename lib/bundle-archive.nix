# An archive of a dynamically linked package for hosts that do not use Nix.
# export-archive.nix suits a static build; a program that must stay dynamic,
# such as a QEMU that loads TCG plugins with dlopen, travels with its own
# shared libraries and dynamic loader instead:
#
#   NAME/bin/PROGRAM      a launcher: runs the program through NAME/lib's loader
#   NAME/libexec/PROGRAM  the program itself
#   NAME/lib/             every shared library it loads, glibc included
#   NAME/SOURCES          where its sources are
#
# Nothing in it names /nix/store, so it runs from any directory of any Linux
# distribution of the same CPU, whatever that distribution's own libc is.
# A library the program opens itself (a plugin) is loaded by the same
# loader, and finds the bundled libc already in place.
{
  lib,
  runCommand,
  buildPackages,
  stdenv,
}:

{
  package,
  programs,
  # Further top-level directories of the package to copy, such as include.
  extraDirs ? [ ],
  name ? "${package.pname}-${package.version}-${package.stdenv.hostPlatform.system}",
  sources ? [ ],
}:

let
  ldd = "${lib.getBin stdenv.cc.libc}/bin/ldd";
in
runCommand "${name}.tar.xz-export"
  {
    nativeBuildInputs = [
      buildPackages.gnutar
      buildPackages.xz
      buildPackages.nukeReferences
      buildPackages.patchelf
    ];
    passthru = { inherit package name programs; };
    disallowedReferences = [ package ];
  }
  ''
    set -eu
    top=work/${name}
    mkdir -p $out $top/bin $top/libexec $top/lib
    ${lib.concatMapStrings (dir: "cp -r ${package}/${dir} $top/\n") extraDirs}

    for program in ${lib.escapeShellArgs programs}; do
      cp ${package}/bin/$program $top/libexec/$program
      loader=$(patchelf --print-interpreter ${package}/bin/$program)
      cp -L $loader $top/lib/
      # Each library the loader resolves, under the name the program asks for.
      ${ldd} ${package}/bin/$program | while read -r soname arrow path rest; do
        case "$arrow $path" in
          "=> /nix/store/"*)
            soname=$(basename $soname)
            [ -e $top/lib/$soname ] || cp -L $path $top/lib/$soname ;;
        esac
      done
      cat > $top/bin/$program <<END
    #!/bin/sh
    # Runs ../libexec/$program with the loader and libraries in ../lib.
    here=\$(cd -P -- "\$(dirname -- "\$0")/.." && pwd)
    exec "\$here/lib/$(basename $loader)" --library-path "\$here/lib" --argv0 "\$0" \\
      "\$here/libexec/$program" "\$@"
    END
      sed -i 's/^    //' $top/bin/$program
      chmod 755 $top/bin/$program
    done

    chmod -R u+w work
    find $top/libexec $top/lib -type f -exec patchelf --remove-rpath {} \; 2>/dev/null || true
    find work -type f -exec nuke-refs {} +
    if grep -rlaP '/nix/store/(?!e{32})[0-9a-z]{32}-' work | grep . ; then
      echo "these files still name a store path"; exit 1
    fi

    cat > $top/SOURCES <<'END'
    ${name} was built by https://github.com/701-dev/nix-packages from
    ${builtins.unsafeDiscardStringContext package.drvPath}
    It carries the shared libraries it loads, glibc among them, in lib/.
    Its own sources are these store paths. They, and the sources of every
    library in lib/, are in the binary cache
    https://701-nix-packages.nbg1.your-objectstorage.com (docs/sources.md
    in the repository says how to fetch them):
    ${lib.concatMapStrings (s: "  ${s}\n") sources}
    END
    sed -i 's/^    //' $top/SOURCES
    tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
        --format=gnu -C work -cf - ${name} | xz -9e -T1 > $out/${name}.tar.xz
    (cd $out && sha256sum ${name}.tar.xz > ${name}.tar.xz.sha256)
  ''
