# actionlint, nixpkgs' build at its version, without the wrapper nixpkgs puts
# around it to add pyflakes and shellcheck to its PATH: that wrapper brings a
# Python and a second shellcheck into the closure (236 MiB against 6 MiB),
# and a user who wants either pass names it with -shellcheck= or -pyflakes=.
#
# Upstream:  https://github.com/rhysd/actionlint
# Licence:   MIT
{ actionlint }:

actionlint.overrideAttrs {
  postInstall = ''
    ronn --roff man/actionlint.1.ronn
    installManPage man/actionlint.1
  '';
}
