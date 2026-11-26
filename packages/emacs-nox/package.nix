# Emacs for a terminal, with tree-sitter and nothing a batch session does
# not use: no native compilation (it alone brings GCC and libgccjit, about
# 400 MiB of closure), D-Bus, GPM, SELinux, systemd, mailutils or SQLite.
# Its built-in eglot is the LSP client.
{ emacs-nox }:

emacs-nox.override {
  withNativeCompilation = false;
  withDbus = false;
  withGpm = false;
  withSelinux = false;
  withSystemd = false;
  withMailutils = false;
  withSQLite3 = false;
  withWebP = false;
}
