# Smoke test: Emacs starts in batch mode, has tree-sitter and eglot.
{ runCommand, emacs-nox }:

runCommand "emacs-nox-test" { } ''
  set -eu
  ${emacs-nox}/bin/emacs --version | grep -q '^GNU Emacs ${emacs-nox.version}$'
  ${emacs-nox}/bin/emacs --batch -Q --eval \
    '(unless (and (require (quote treesit) nil t) (treesit-available-p) (require (quote eglot) nil t)) (kill-emacs 1))'
  touch $out
''
