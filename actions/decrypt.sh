#!/bin/bash

if [ ! -f /.dockerenv ]; then
  echo "FATAL: Must be run from docker"
  exit 1
fi

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"

commands="7z unsquashfs mksquashfs mkpasswd"
for command in $commands; do
    command -v "$command" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Command $command not found"
        exit 1
    fi
done

if [ $# -eq 0 ]; then
  echo "Usage: $(basename $0) <downloaded image>"
  exit 1
fi

old_image_name=/originals/$(basename $1)

# Board names may themselves contain underscores (for example, Ender-3_V3_KE_F005).
filename=$(basename $old_image_name)
if [[ $filename =~ ^(.+)_ota_img_V([^.]+(\.[^.]+)*)\.img$ ]]; then
  BOARD_NAME=${BASH_REMATCH[1]}
  BOARD_SHORT_NAME=${BOARD_NAME#Ender-3_V3_KE_}
  CREALITY_VERSION=${BASH_REMATCH[2]}
else
  echo "Invalid image filename: $old_image_name" >&2
  exit 1
fi

if [ ! -f $old_image_name ]; then
  echo "Error: File $1 is not valid"
  exit 1
fi

# thanks to Neon for showing me how to derive the password
FIRMWARE_PASSWORD=$(mkpasswd -m md5 "${BOARD_SHORT_NAME}C3_7e_bz" -S cxswfile)

version="${CREALITY_VERSION}"

old_directory="${BOARD_NAME}_ota_img_V${CREALITY_VERSION}"
old_sub_directory="ota_v${CREALITY_VERSION}"
directory="${BOARD_NAME}_ota_img_V${version}"
sub_directory="ota_v${version}"

if [ -d /tmp/$old_directory ]; then
    rm -rf /tmp/$old_directory
fi

7z x $old_image_name -p"$FIRMWARE_PASSWORD" -o/tmp
rootfs_filename=$(basename $old_image_name | sed 's/\.img/.rootfs.squashfs/g')
ls /tmp/$old_directory/$old_sub_directory/
mkdir -p /out/${BOARD_NAME}
cat /tmp/$old_directory/$old_sub_directory/rootfs.squashfs.* > /out/${BOARD_NAME}/rootfs.squashfs
cat /tmp/$old_directory/$old_sub_directory/xImage.* > /out/${BOARD_NAME}/xImage
cat /tmp/$old_directory/$old_sub_directory/zero.bin.* > /out/${BOARD_NAME}/zero.bin

echo "Resulting rootfs is /tmp/${BOARD_NAME}/"

rm -rf /tmp/$old_directory
