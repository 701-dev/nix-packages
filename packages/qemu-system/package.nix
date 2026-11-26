# QEMU for running whole guest systems headless: x86-64 under KVM and arm64
# under TCG on the virt machine, with qemu-img for disk overlays, user-mode
# networking for SSH into the guest, and the edk2 firmware an arm64 guest
# boots. nixpkgs' recipe at its version, with the display, audio, USB
# redirection, smartcard and other desktop features off.
#
# nixpkgs' `minimal` cannot be used: it also drops libslirp, and with it
# `-netdev user`.
{ qemu }:

(qemu.override {
  hostCpuTargets = [
    "x86_64-softmmu"
    "aarch64-softmmu"
  ];
  guestAgentSupport = false;
  numaSupport = false;
  seccompSupport = false;
  alsaSupport = false;
  pulseSupport = false;
  pipewireSupport = false;
  sdlSupport = false;
  jackSupport = false;
  gtkSupport = false;
  vncSupport = false;
  smartcardSupport = false;
  spiceSupport = false;
  ncursesSupport = false;
  openGLSupport = false;
  virglSupport = false;
  libiscsiSupport = false;
  tpmSupport = false;
  fuseSupport = false;
  capstoneSupport = false;
  brlttySupport = false;
  pluginsSupport = false;
  enableDocs = false;
}).overrideAttrs
  (old: {
    pname = "qemu-system";
    meta = old.meta // {
      description = "QEMU for headless x86-64 and arm64 guests, with qemu-img and edk2";
      mainProgram = "qemu-system-x86_64";
    };
  })
