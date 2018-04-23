#!/usr/bin/env bash

set -ex

docker run -i --name newfs docker.io/redjays/xenial:bootable bash -exs << _EOF_
export TERM=dumb

cat << _THERE_ > /etc/fstab.sys
tmpfs   /var            tmpfs   size=256m       0 0
tmpfs   /tmp            tmpfs   size=64m        0 0
tmpfs   /etc/ssh        tmpfs   size=1m         0 0
_THERE_
cat << _THERE_ > /etc/dracut.conf
filesystems+=" ext2 "
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

find /usr/src/iomemory-* /var/lib/dkms/iomemory-vsl/ -type d -exec chmod a+rx {} \;
for i in /boot/initrd.img* ; do
  v="\${i#/boot/initrd.img-}"
  dracut -f "\${i}" "\${v}"
done

tar cpf var.tar -C /var '--exclude=ssh_host*' .
tar cpf tmp.tar -C /tmp .
tar cpf ssh.tar -C /etc/ssh .

xz var.tar
xz tmp.tar
xz ssh.tar

rm -rf /var /tmp /etc/ssh /usr/lib/locale /usr/share/locale /lib/gconv /lib64/gconv /bin/localedef /sbin/build-locale-archive /usr/share/i18n /usr/share/man /usr/share/doc /usr/share/info /usr/share/gnome/help /usr/share/cracklib /var/cache/yum /sbin/sln /var/cache/ldconfig /var/cache/apt/archives || true

ln -sf "../proc/self/mounts" "/etc/mtab"

sed \
    -e 's/root=UNSET/root=LABEL=boottest/g' \
      "/boot/grub/grub.cfg.tpl" >> "/boot/grub/grub.cfg"
_EOF_

truncate -s3G boottest.img

# 2048 sectors to a megabyte
guestfish -a boottest.img << _EOF_
run
part-init /dev/sda gpt
part-add /dev/sda p 2048   10240
part-add /dev/sda p 12288  102400
part-add /dev/sda p 104448 -2048
part-set-gpt-type /dev/sda 1 21686148-6449-6E6F-744E-656564454649
part-set-gpt-type /dev/sda 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B
mkfs ext2 /dev/sda3
set-e2label /dev/sda3 boottest
_EOF_

docker export newfs | guestfish -a boottest.img run : mount /dev/sda3 / : tar-in - /

docker rm newfs

guestfish -a boottest.img << _EOF_
run
mount /dev/sda3 /
copy-file-to-device /boot/efiboot.img /dev/sda2
mkdir /boot/efi
mount /dev/sda2 /boot/efi
mkdir /tmp
copy-in pam-login grub-gptalt /tmp
mv /tmp/pam-login /etc/pam.d/login
mv /tmp/grub-gptalt /boot/efi/efi/boot/grub.cfg
command "grub-install --target=i386-pc /dev/sda"
rmdir /tmp
_EOF_
