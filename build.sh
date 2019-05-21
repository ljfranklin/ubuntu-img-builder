#!/bin/bash

set -eu -o pipefail

: "${IMAGE_NAME:="ubuntu-18.04-cloud-init"}"
: "${INPUT_DIR:=/input}"
: "${OUTPUT_DIR:=/output}"

img_dir="$(mktemp -d)"
squashfs_dir="$(mktemp -d)"
cleanup_dirs() {
  rm -rf "${squashfs_dir}" "${img_dir}"
}
trap cleanup_dirs EXIT

# extract img files and nested casper root fs
iso_path="$(ls ${INPUT_DIR}/*.iso)"
osirrox -indev "${iso_path}" -extract / "${img_dir}"
dd if="${iso_path}" bs=512 count=1 of="${img_dir}/isolinux/isohdpfx.bin"
rm -r "${squashfs_dir}" # ensure dest doesn't exist
unsquashfs -dest "${squashfs_dir}" "${img_dir}/casper/filesystem.squashfs"

# allow internet access in chroot
cp /etc/resolv.conf "${squashfs_dir}/etc/"

# chroot into casper squashfs
mount --bind /dev/ "${squashfs_dir}/dev"
unmount_dirs() {
  umount "${squashfs_dir}/dev"
}
trap '{ unmount_dirs && cleanup_dirs; }' EXIT

chroot "${squashfs_dir}" /bin/bash -x <<EOF
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
trap '{ umount /proc /sys /dev/pts; }' EXIT

export HOME=/root
export LC_ALL=C
apt-get update
dbus-uuidgen > /var/lib/dbus/machine-id
dpkg-divert --local --rename --add /sbin/initctl

# Install new packages
apt-get install --yes cloud-init

rm /var/lib/dbus/machine-id
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
apt-get clean
rm -rf /tmp/*
rm /etc/resolv.conf
EOF

# repack squashfs
chroot "${squashfs_dir}" dpkg-query -W --showformat='${Package} ${Version}\n' | \
  tee "${img_dir}/casper/filesystem.manifest"
cp -v "${img_dir}/casper/filesystem.manifest" "${img_dir}/casper/filesystem.manifest-desktop"
packages_to_remove='ubiquity ubiquity-frontend-gtk ubiquity-frontend-kde casper lupin-casper live-initramfs user-setup discover1 xresprobe os-prober libdebian-installer4'
for i in ${packages_to_remove}; do
  sed -i "/${i}/d" "${img_dir}/casper/filesystem.manifest-desktop"
done
mksquashfs "${squashfs_dir}" "${img_dir}/casper/filesystem.squashfs" -b 1048576

# regenerate filesystem size
printf "$(du -sx --block-size=1 "${squashfs_dir}" | cut -f1)" > \
  "${img_dir}/casper/filesystem.size"

pushd "${img_dir}" > /dev/null
  # regenerate md5sum
  rm md5sum.txt
  find -type f -print0 | \
    xargs -0 md5sum | \
    grep -v isolinux/boot.cat > md5sum.txt

  # build new iso
  xorriso \
    -as mkisofs \
    -isohybrid-mbr isolinux/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -volid "${IMAGE_NAME}" \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${OUTPUT_DIR}/${IMAGE_NAME}.iso" .

  # sanity check for bootable partition
  fdisk -lu "${OUTPUT_DIR}/${IMAGE_NAME}.iso"
popd > /dev/null
