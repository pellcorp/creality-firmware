#!/bin/bash

if [ ! -f /.dockerenv ]; then
  echo "FATAL: Must be run from docker"
  exit 1
fi

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"
PARENT_DIR=$(dirname $CURRENT_DIR)

commands="7z unsquashfs mksquashfs mkpasswd"
for command in $commands; do
    command -v "$command" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Command $command not found"
        exit 1
    fi
done

# CR4CU220812S11_ota_img_V6.1.3.3.8.img
# NEBULA_ota_img_V1.1.0.29.img
# Ender-3_V3_KE_F005_ota_img_V1.1.0.15.img
# F001_ota_img_V1.2.3.28.img
# F004_ota_img_V1.2.0.20.img

if [ $# -eq 0 ]; then
  echo "Usage: $(basename $0) <downloaded image>"
  exit 1
fi

old_image_name=/originals/$(basename $1)

# all except for KE have a consistent naming scheme
filename=$(basename $old_image_name | sed 's/Ender-3_V3_KE//g')
if [[ $filename =~ ^([^_]+)_ota_img_V([^.]+(\.[^.]+)*)\.img$ ]]; then
  BOARD_SHORT_NAME=${BASH_REMATCH[1]}
  CREALITY_VERSION=${BASH_REMATCH[2]}
else
  echo "Invalid image filename: $filename" >&2
  exit 1
fi

if [ ! -f $old_image_name ]; then
  echo "Error: File $1 is not valid"
  exit 1
fi

# thanks to Neon for showing me how to derive the password
FIRMWARE_PASSWORD=$(mkpasswd -m md5 "${BOARD_SHORT_NAME}C3_7e_bz" -S cxswfile)

version="7.${CREALITY_VERSION}"
old_directory="${BOARD_SHORT_NAME}_ota_img_V${CREALITY_VERSION}"
old_sub_directory="ota_v${CREALITY_VERSION}"
directory="${BOARD_SHORT_NAME}_ota_img_V${version}"
sub_directory="ota_v${version}"
image_name="${BOARD_SHORT_NAME}_ota_img_V${version}".img

function write_ota_info() {
    echo "ota_version=${version}" > /tmp/${version}-pellcorp/ota_info
    echo "ota_board_name=${BOARD_SHORT_NAME}" >> /tmp/${version}-pellcorp/ota_info
    echo "ota_compile_time=$(date '+%Y %m.%d %H:%M:%S')" >> /tmp/${version}-pellcorp/ota_info
    echo "ota_site=http://192.168.43.52/ota/board_test" >> /tmp/${version}-pellcorp/ota_info
    sudo cp /tmp/${version}-pellcorp/ota_info /tmp/${version}-pellcorp/squashfs-root/etc/
}

function customise_rootfs() {
    write_ota_info
    [ -d $CURRENT_DIR/opt ] && rm -rf $CURRENT_DIR/opt
    sudo cp $PARENT_DIR/etc/init.d/* /tmp/${version}-pellcorp/squashfs-root/etc/init.d/

    # I am not sure if for other boards setting a password will cause a boot loop, so im just doing it for nebula for now
    if [ "$BOARD_SHORT_NAME" = "NEBULA" ]; then
      sudo sed -i "/^root/c\\$(printf '%s\n' "$root_hash")"  /tmp/${version}-pellcorp/squashfs-root/etc/shadow
    fi
}

function update_rootfs() {
    pushd /tmp/${version}-pellcorp/ > /dev/null
    sudo unsquashfs orig_rootfs.squashfs
    customise_rootfs
    sudo mksquashfs squashfs-root rootfs.squashfs || exit $?
    sudo rm -rf squashfs-root
    sudo chown developer: rootfs.squashfs
}

if [ -d /tmp/$old_directory ]; then
    rm -rf /tmp/$old_directory
fi

7z x $old_image_name -p"$FIRMWARE_PASSWORD" -o/tmp

[ -f  /out/${image_name} ] && rm  /out/${image_name}

if [ -d /tmp/${version}-pellcorp ]; then
    sudo rm -rf /tmp/${version}-pellcorp
fi
mkdir -p /tmp/${version}-pellcorp/$directory/$sub_directory

cat /tmp/$old_directory/$old_sub_directory/rootfs.squashfs.* > /tmp/${version}-pellcorp/orig_rootfs.squashfs
orig_rootfs_md5=$(md5sum /tmp/${version}-pellcorp/orig_rootfs.squashfs | awk '{print $1}')
orig_rootfs_size=$(stat -c%s /tmp/${version}-pellcorp/orig_rootfs.squashfs)

# do the changes here
update_rootfs || exit $?

rootfs_md5=$(md5sum /tmp/${version}-pellcorp/rootfs.squashfs | awk '{print $1}')
rootfs_size=$(stat -c%s /tmp/${version}-pellcorp/rootfs.squashfs)

echo "current_version=$version" > /tmp/${version}-pellcorp/$directory/ota_config.in
echo "" > /tmp/${version}-pellcorp/$directory/$sub_directory/ota_v${version}.ok

cp /tmp/$old_directory/$old_sub_directory/ota_update.in /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/ota_md5_xImage* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/ota_md5_zero.bin* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/zero.bin.* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/xImage.* /tmp/${version}-pellcorp/$directory/$sub_directory/

pushd /tmp/${version}-pellcorp/$directory/$sub_directory > /dev/null
split -d -b 1048576 -a 4 /tmp/${version}-pellcorp/rootfs.squashfs rootfs.squashfs.
popd > /dev/null

part_md5=
for i in $(ls /tmp/${version}-pellcorp/$directory/$sub_directory/rootfs.squashfs.*); do
    file=$(basename $i)
    if [ -z "$part_md5" ]; then
        id=$rootfs_md5
    else
        id=$part_md5
    fi
    mv "/tmp/${version}-pellcorp/$directory/$sub_directory/$file" "/tmp/${version}-pellcorp/$directory/$sub_directory/${file}.${id}"
    part_md5=$(md5sum /tmp/${version}-pellcorp/$directory/$sub_directory/${file}.${id} | awk '{print $1}')
    echo "$part_md5" >> "/tmp/${version}-pellcorp/$directory/$sub_directory/ota_md5_rootfs.squashfs.${rootfs_md5}"
done

sed -i "s/ota_version=$CREALITY_VERSION/ota_version=$version/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in
sed -i "s/img_md5=$orig_rootfs_md5/img_md5=$rootfs_md5/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in
sed -i "s/img_size=$orig_rootfs_size/img_size=$rootfs_size/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in

pushd /tmp/${version}-pellcorp/ > /dev/null
7z a ${image_name}.7z -p"$FIRMWARE_PASSWORD" $directory
mv ${image_name}.7z /out/${image_name}
popd > /dev/null

# assuming we call this docker with /tmp:/out
echo "The image is /tmp/${image_name}"
