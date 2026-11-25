# The Python GDB links: nixpkgs' 3.13 without its optional libraries
# (OpenSSL, SQLite, Tk, ...), keeping the config directory that holds
# libpython. GDB's recipe drops what it does not ship of the standard
# library.
#
# A static Python builds its extension modules into libpython, but three of
# them link archives of CPython's own (libmpdec for _decimal, its bundled
# expat for pyexpat, HACL* for _sha2) that stay in its build tree, and
# python-config does not name them; an embedder such as GDB then fails to
# link. Their objects are appended to the installed libpython here.
#
# The bundled expat renames its API to PyExpat_* (Modules/expat/pyexpatns.h)
# so that it can sit beside another expat, but a few of its newer global
# symbols escaped that list, and GDB links nixpkgs' expat for itself: those
# are renamed here the same way, throughout libpython.
{ lib, python313 }:

(python313.override {
  # Scalar arguments only: nixpkgs passes these on to the Python that runs on
  # the build machine during a cross build, and no list or derivation.
  withMinimalDeps = true;
  stripConfig = false;
  stripIdlelib = false;
  stripTests = false;
  stripTkinter = false;
}).overrideAttrs
  (old: {
    # The kept config directory's Makefile names the build's shell; GDB,
    # which links libpython statically, keeps no reference to it.
    allowedReferences = null;
    postInstall =
      (old.postInstall or "")
      + lib.optionalString python313.stdenv.hostPlatform.isStatic ''
        library=$(echo $out/lib/python3.13/config-*/libpython3.13.a)
        for archive in $(find Modules -name '*.a' | sort); do
          objects=$(mktemp -d)
          (cd $objects && $AR x $OLDPWD/$archive)
          if [ "$(basename $archive)" = libexpat.a ]; then
            $NM --defined-only -g $objects/*.o | awk 'NF == 3 && $3 !~ /^PyExpat_/ { print $3, "PyExpat_" $3 }' \
              | sort -u > $NIX_BUILD_TOP/expat-renames
          fi
          $AR q $library $objects/*.o
        done
        # In pyexpat's callers as well as in expat's own objects.
        $OBJCOPY --redefine-syms=$NIX_BUILD_TOP/expat-renames $library
        $RANLIB $library
      '';
  })
