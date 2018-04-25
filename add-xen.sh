#!/usr/bin/bash

docker run -i --name newfs docker.io/redjays/xenial:xenhv /bin/true
docker export newfs > xenhv.tar
docker rm newfs
pxz xenhv.tar

rm -f xenhv_inst.iso

xorriso -indev boottest.iso -outdev xenhv_inst.iso -as mkisofs -isohybrid-mbr . -partition_cyl_align 0 -partition_hd_cyl 0 -partition_hd_cyl 0 -partition_sec_hd 0 -c '/boot/boot.cat' -b '/isolinux/isolinux.bin' -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e '/boot/efiboot.img' -no-emul-boot -boot-load-size 24576 -isohybrid-gpt-basdat -eltorito-alt-boot -e '/boot/macboot.img' -no-emul-boot -boot-load-size 60 -isohybrid-gpt-basdat -- -add xenhv.tar.xz
