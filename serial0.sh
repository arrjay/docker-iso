#!/usr/bin/env bash

newfiles=$(mktemp -d)
cd="$(pwd)/${1}"

mkdir -p "${newfiles}/boot/grub"
isoinfo -x '/BOOT/GRUB/GRUB.CFG;1' -i "${cd}" | sed -e 's/console=ttyS1,115200/console=ttyS0,115200/' > "${newfiles}/boot/grub/grub.cfg"
mkdir -p "${newfiles}/isolinux"
isoinfo -x '/ISOLINUX/SYSLINUX.CFG;1' -i "${cd}" | sed -e 's/serial 1 115200/serial 0 115200/' -e 's/console=ttyS1,115200/console=ttyS0,115200/' > "${newfiles}/isolinux/syslinux.cfg"

cd "${newfiles}"
xorriso -indev "${cd}" -outdev "${cd}" -as mkisofs -isohybrid-mbr . -partition_cyl_align 0 -partition_hd_cyl 0 -partition_hd_cyl 0 -partition_sec_hd 0 -c '/boot/boot.cat' -b '/isolinux/isolinux.bin' -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e '/boot/efiboot.img' -no-emul-boot -boot-load-size 24576 -isohybrid-gpt-basdat -eltorito-alt-boot -e '/boot/macboot.img' -no-emul-boot -boot-load-size 60 -isohybrid-gpt-basdat -- -add "boot/grub/grub.cfg" "isolinux/syslinux.cfg"
