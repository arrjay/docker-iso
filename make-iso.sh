#!/usr/bin/env bash

set -ex

docker run -i --name newfs docker.io/redjays/xenial:bootable bash -exs << _EOF_
apt-get install -q -y dracut-core
cat << _THERE_ > /etc/fstab.sys
tmpfs   /var            tmpfs   size=256m       0 0
tmpfs   /tmp            tmpfs   size=64m        0 0
tmpfs   /etc/ssh        tmpfs   size=1m         0 0
_THERE_
cat << _THERE_ > /etc/dracut.conf
filesystems+=" iso9660 "
use_fstab="yes"
add_dracutmodules+=" fstab-sys "
omit_dracutmodules+=" dash "
_THERE_
cat << _THERE_ > /etc/udev/rules.d/61-blkid-cdroms.rules
KERNEL=="sr*", IMPORT{program}="/sbin/blkid -o udev -p -u noraid \\\$tempnode"
ENV{ID_FS_USAGE}=="filesystem|other", ENV{ID_FS_LABEL_ENC}=="?*", SYMLINK+="disk/by-label/\\\$env{ID_FS_LABEL_ENC}"
_THERE_
mkdir -p /usr/lib/dracut/modules.d/49blkid-cdrom
cat << _THERE_ > /usr/lib/dracut/modules.d/49blkid-cdrom/module-setup.sh
#!/bin/sh

depends() {
  return 0
}

install() {
  inst_rules 61-blkid-cdroms.rules
}
_THERE_
chmod +x /usr/lib/dracut/modules.d/49blkid-cdrom/module-setup.sh
find /usr/src/iomemory-* /var/lib/dkms/iomemory-vsl/ -type d -exec chmod a+rx {} \;
for i in /boot/initrd.img* ; do
  v="\${i#/boot/initrd.img-}"
  dracut -f "\${i}" "\${v}"
done
_EOF_

scratch=$(mktemp -d /var/tmp/newfs.XXXXXX)
isolinux=$(mktemp -d /var/tmp/isolinux.XXXXXX)

cp /usr/share/syslinux/*.c32 /usr/share/syslinux/isolinux.bin /usr/share/syslinux/isohd*.bin "${isolinux}"

docker export newfs | tar xf - -C "${scratch}" '--exclude=dev/*'

cat "${scratch}/etc/udev/rules.d/61-blkid-cdroms.rules"

docker rm newfs

cp pam-login "${scratch}/etc/pam.d/login"

cat << _EOF_ > "${scratch}/etc/tmpfiles.d/livecd.conf"
d /run/ubuntu-release-upgrader 0755 root root -
_EOF_

ln -s /run/ubuntu-release-upgrader "${scratch}/var/lib/ubuntu-release-upgrader/"

cp -R "${scratch}/boot" "${isolinux}/boot"

cat << _EOF_ > "${isolinux}/syslinux.cfg"
serial 0 115200
prompt 1
timeout 3600
_EOF_

sed -e 's/console=tty0/console=ttyS0,115200/g' \
    -e 's/root=UNSET/root=LABEL=boottest/g' \
      "${scratch}/isolinux/syslinux.cfg.tpl" >> "${isolinux}/syslinux.cfg"
for k in "${isolinux}/boot"/vmlinuz* "${isolinux}/boot"/initrd.img* ; do
  d="${k##*/}"
  ln "${k}" "${isolinux}/${d}"
done

xorriso --report_about HINT -as xorrisofs -U -A boottest -V boottest -volset boottest -J -joliet-long -r -rational-rock -o boottest.iso \
  -graft-points "/isolinux=${isolinux}" \
  -partition_cyl_align off -partition_offset 0 -apm-block-size 2048 -iso_mbr_part_type 0x00 \
  -b isolinux/isolinux.bin -c boot/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
  -isohybrid-mbr "${scratch}/isolinux/isohdpfx.bin" --protective-msdos-label "${scratch}" \
  -eltorito-alt-boot -e /boot/efiboot.img -no-emul-boot -isohybrid-gpt-basdat \
  -eltorito-alt-boot -e /boot/macboot.img -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus

#isohybrid boottest.iso

rm -rf "${scratch}" "${isolinux}"
