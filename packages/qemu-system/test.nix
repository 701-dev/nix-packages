# Smoke test: both emulators start and hold the machines a guest boots on,
# qemu-img makes an overlay, user networking is built in, and the arm64
# firmware is installed beside the emulator.
{ runCommand, qemu-system }:

runCommand "qemu-system-test" { } ''
  set -eu
  bin=${qemu-system}/bin
  $bin/qemu-system-x86_64 --version | grep -q '^QEMU emulator version ${qemu-system.version}$'
  $bin/qemu-system-aarch64 --version | grep -q '^QEMU emulator version ${qemu-system.version}$'
  $bin/qemu-system-x86_64 -machine help | grep -q '^q35 '
  $bin/qemu-system-aarch64 -machine help | grep -q '^virt '
  $bin/qemu-system-aarch64 -cpu help | grep -q 'max'
  $bin/qemu-system-x86_64 -netdev help | grep -qx 'user'
  $bin/qemu-system-x86_64 -device help | grep -q '"virtio-net-pci"'
  $bin/qemu-system-x86_64 -device help | grep -q '"virtio-blk-pci"'
  test -s ${qemu-system}/share/qemu/edk2-aarch64-code.fd
  $bin/qemu-img create -q -f raw base.raw 1M
  $bin/qemu-img create -q -f qcow2 -F raw -b $PWD/base.raw overlay.qcow2
  $bin/qemu-img info overlay.qcow2 | grep -q 'file format: qcow2'
  echo quit | $bin/qemu-system-aarch64 -M virt -cpu max -bios ${qemu-system}/share/qemu/edk2-aarch64-code.fd \
    -display none -monitor stdio -serial none -S -netdev user,id=n0 -device virtio-net-pci,netdev=n0 > run.log 2>&1 \
    || { cat run.log; exit 1; }
  touch $out
''
