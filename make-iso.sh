#!/usr/bin/env bash

set -ex

docker run -i --name newfs docker.io/redjays/xenial:installer bash -exs << _EOF_
export TERM=dumb

cat << _THERE_ > /etc/fstab.sys
tmpfs   /var            tmpfs   size=256m       0 0
tmpfs   /tmp            tmpfs   size=64m        0 0
tmpfs   /etc/ssh        tmpfs   size=1m         0 0
tmpfs	/mnt		tmpfs	size=1m		0 0
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
mkdir -p /usr/lib/dracut/modules.d/50livecd
cat << _THERE_ > /usr/lib/dracut/modules.d/50livecd/instantiate-fs.sh
#!/bin/sh

type unpack_archive > /dev/null 2>&1 || . /lib/img-lib.sh

unpack_archive /sysroot/var.tar.xz /sysroot/var
unpack_archive /sysroot/tmp.tar.xz /sysroot/tmp
unpack_archive /sysroot/ssh.tar.xz /sysroot/etc/ssh
_THERE_
cat << _THERE_ > /usr/lib/dracut/modules.d/50livecd/module-setup.sh
#!/bin/sh

depends() {
  echo "img-lib"
  return 0
}

install() {
  inst_hook cleanup 00 "\\\$moddir/instantiate-fs.sh"
}
_THERE_

cat << _THERE_ > /etc/tmpfiles.d/livecd.conf
d /var/run/apparmor-cache 0755 root - - -
_THERE_

ln -sf /dev/null /etc/tmpfiles.d/home.conf
rm -rf /etc/apparmor.d/cache && ln -sf /var/run/apparmor-cache /etc/apparmor.d/cache

find /usr/src/iomemory-* /var/lib/dkms/iomemory-vsl/ /etc/sysconfig/ -type d -exec chmod a+rx {} \;
for i in /boot/initrd.img* ; do
  v="\${i#/boot/initrd.img-}"
  dracut -f "\${i}" "\${v}"
done

tar cpf var.tar -C /var '--exclude=ssh_host*' .
tar cpf tmp.tar -C /tmp .
tar cpf ssh.tar -C /etc/ssh .

ln -sf "../proc/self/mounts" "/etc/mtab"
_EOF_

scratch=$(mktemp -d /var/tmp/newfs.XXXXXX)
isolinux=$(mktemp -d /var/tmp/isolinux.XXXXXX)

cp /usr/share/syslinux/*.c32 /usr/share/syslinux/isolinux.bin /usr/share/syslinux/isohd*.bin "${isolinux}"

docker export newfs | tar xf - -C "${scratch}" '--exclude=dev/*' '--exclude=var/*' '--exclude=tmp/*' '--exclude=etc/ssh/*' \
  '--exclude=usr/lib/locale' '--exclude=usr/share/locale' '--exclude=lib/gconv' '--exclude=lib64/gconv' \
  '--exclude=bin/localedef'  '--exclude=sbin/build-locale-archive' '--exclude=usr/share/i18n' \
  '--exclude=usr/share/man'  '--exclude=usr/share/doc' '--exclude=usr/share/info' '--exclude=usr/share/gnome/help' \
  '--exclude=usr/share/cracklib' '--exclude=var/cache/yum' '--exclude=sbin/sln' '--exclude=var/cache/ldconfig' \
  '--exclude=var/cache/apt/archives'

docker rm newfs

cp pam-login "${scratch}/etc/pam.d/login"

pxz "${scratch}/var.tar"
pxz "${scratch}/tmp.tar"
pxz "${scratch}/ssh.tar"

cp -R "${scratch}/boot" "${isolinux}/boot"

cat << _EOF_ > "${isolinux}/syslinux.cfg"
serial 1 115200
prompt 1
timeout 3600
_EOF_

cat "${scratch}/isolinux/syslinux.cfg.tpl"

sed -e 's/console=tty0/console=ttyS1,115200/g' \
    -e 's/root=UNSET/root=LABEL=xe_installer/g' \
      "${scratch}/isolinux/syslinux.cfg.tpl" >> "${isolinux}/syslinux.cfg"

sed -e 's/console=tty0/console=ttyS1,115200/g' \
    -e 's/root=UNSET/root=LABEL=xe_installer/g' \
      "${scratch}/boot/grub/grub.cfg.tpl" >> "${scratch}/boot/grub/grub.cfg"

for k in "${isolinux}/boot"/vmlinuz* "${isolinux}/boot"/initrd.img* ; do
  d="${k##*/}"
  ln "${k}" "${isolinux}/${d}"
done

xorriso --report_about HINT -as xorrisofs -U -A xe_installer -V xe_installer -volset xe_installer -r -rational-rock -o installercore.iso \
  -graft-points "/isolinux=${isolinux}" \
  -partition_cyl_align off -partition_offset 0 -apm-block-size 2048 -iso_mbr_part_type 0x00 \
  -b isolinux/isolinux.bin -c boot/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
  -isohybrid-mbr "${scratch}/isolinux/isohdpfx.bin" --protective-msdos-label "${scratch}" \
  -eltorito-alt-boot -e /boot/efiboot.img -no-emul-boot -isohybrid-gpt-basdat \
  -eltorito-alt-boot -e /boot/macboot.img -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus

isohybrid installercore.iso

rm -rf "${scratch}" "${isolinux}"
