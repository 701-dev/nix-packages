# An archive of one package for hosts that do not use Nix: a reproducible
# tar.xz whose single top-level directory holds the package's bin/ and
# share/. It works only for packages that are relocatable and need nothing
# from /nix/store at run time, such as a static build.
#
# Beside the archive the derivation writes SOURCES, which names the store
# paths of the sources the package was built from; they are in the same
# binary cache as the package (see docs/sources.md).
{
  lib,
  runCommand,
  buildPackages,
}:

{
  package,
  name ? "${package.pname}-${package.version}-${package.stdenv.hostPlatform.system}",
  sources ? [ ],
}:

runCommand "${name}.tar.xz-export"
  {
    nativeBuildInputs = [
      buildPackages.gnutar
      buildPackages.xz
      buildPackages.nukeReferences
    ];
    passthru = { inherit package name; };
    # The archive must not refer to any store path: it is used without Nix.
    disallowedReferences = [ package ];
  }
  ''
    mkdir -p $out work/${name}
    cp -r ${package}/bin ${package}/share work/${name}/
    chmod -R u+w work
    find work -type f -exec nuke-refs {} +
    cat > work/${name}/SOURCES <<'END'
    ${name} was built by https://github.com/701-dev/nix-packages from
    ${builtins.unsafeDiscardStringContext package.drvPath}
    Its own sources are these store paths. They, and the sources of every
    library linked into it, are in the binary cache
    https://701-nix-packages.nbg1.your-objectstorage.com (docs/sources.md
    in the repository says how to fetch them):
    ${lib.concatMapStrings (s: "  ${s}\n") sources}
    END
    sed -i 's/^    //' work/${name}/SOURCES
    tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
        --format=gnu -C work -cf - ${name} | xz -9e -T1 > $out/${name}.tar.xz
    (cd $out && sha256sum ${name}.tar.xz > ${name}.tar.xz.sha256)
  ''
