#!/usr/bin/bash

docker run -i --name newfs docker.io/redjays/xenial:installer bash -exs << _EOF_
export TERM=dumb

rm -f /etc/fstab
rm -f /etc/mdadm/mdadm.conf
rm -f /etc/keys/*
rm -f /etc/crypttab
_EOF_
docker export newfs > bootable.tar
docker rm newfs
pxz bootable.tar

mkdir -p images
mv bootable.tar.xz images

rm -f bootable_inst.iso

xorriso -indev installercore.iso -outdev bootable_inst.iso -as mkisofs -isohybrid-mbr . -partition_cyl_align 0 -partition_hd_cyl 0 -partition_hd_cyl 0 -partition_sec_hd 0 -c '/boot/boot.cat' -b '/isolinux/isolinux.bin' -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e '/boot/efiboot.img' -no-emul-boot -boot-load-size 24576 -isohybrid-gpt-basdat -eltorito-alt-boot -e '/boot/macboot.img' -no-emul-boot -boot-load-size 60 -isohybrid-gpt-basdat -- -add images/bootable.tar.xz
