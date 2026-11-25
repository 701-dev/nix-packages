# Smoke test: the emulators start, say the expected version, have the
# machines the users start and carry Espressif's ROM images.
{ runCommand, qemu-espressif }:

runCommand "qemu-espressif-test" { nativeBuildInputs = [ qemu-espressif ]; } ''
  set -eu
  xtensa=${qemu-espressif}/bin/qemu-system-xtensa
  riscv32=${qemu-espressif}/bin/qemu-system-riscv32

  for emulator in $xtensa $riscv32; do
    $emulator --version > version
    grep -qF 'QEMU emulator version 9.2.2 (${qemu-espressif.pkgversion})' version \
      || { echo "$emulator says:"; cat version; exit 1; }
  done

  $xtensa -machine help > xtensa-machines
  $riscv32 -machine help > riscv32-machines
  for machine in sim esp32 esp32s3; do
    grep -q "^$machine " xtensa-machines || { echo "xtensa machine $machine missing"; exit 1; }
  done
  for machine in esp32c3 sifive_e; do
    grep -q "^$machine " riscv32-machines || { echo "riscv32 machine $machine missing"; exit 1; }
  done

  for rom in esp32-v3-rom.bin esp32-v3-rom-app.bin esp32s3_rev0_rom.bin esp32c3-rom.bin; do
    test -s ${qemu-espressif}/share/qemu/$rom || { echo "ROM $rom missing"; exit 1; }
  done

  # The sim machine boots far enough to wait for a debugger and quits on request.
  echo quit | $xtensa -M sim -cpu esp32 -m 64M -nographic -monitor stdio -serial none -S > /dev/null

  touch $out
''
