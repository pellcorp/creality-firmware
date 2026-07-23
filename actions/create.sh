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

version="7.${CREALITY_VERSION}"
old_directory="${BOARD_NAME}_ota_img_V${CREALITY_VERSION}"
old_sub_directory="ota_v${CREALITY_VERSION}"
directory="${BOARD_NAME}_ota_img_V${version}"
sub_directory="ota_v${version}"
image_name="${BOARD_NAME}_ota_img_V${version}".img
# for the decrypted rootfs
rootfs_filename="${BOARD_NAME}_ota_img_V${version}.rootfs.squashfs"
build_dir=$(mktemp -d "/tmp/create-${BOARD_SHORT_NAME}-${CREALITY_VERSION}.XXXXXX") || {
    echo "FATAL: Unable to create build directory" >&2
    exit 1
}
extracted_dir="$build_dir/extracted"
work_dir="$build_dir/work"
original_dir="$extracted_dir/$old_directory"

function fail() {
    echo "FATAL: $*" >&2
    exit 1
}

function require_file() {
    [ -f "$1" ] || fail "Expected file not found: $1"
}

function validate_rootfs() {
    local rootfs="$1"
    local label="$2"

    unsquashfs -s "$rootfs" > /dev/null || fail "$label is not a valid SquashFS image"
    unsquashfs -ll "$rootfs" root | grep -q '^drwx------ root/root.* squashfs-root/root$' || \
        fail "$label does not contain /root with root-only permissions"
}

function validate_rebuilt_rootfs() {
    local rootfs="$1"

    validate_rootfs "$rootfs" "Rebuilt rootfs"
    unsquashfs -s "$rootfs" | grep -Eq '^(Xattrs are not stored|Number of xattr ids 0)$' || \
        fail "Rebuilt rootfs contains xattrs, which prevent OverlayFS copy-up on this printer"
}

function validate_ota_image() {
    local ota_image="$1"
    local validation_dir="$work_dir/validation"
    local validation_payload_dir="$validation_dir/$directory/$sub_directory"
    local validation_rootfs="$validation_dir/rootfs.squashfs"
    local -a rootfs_parts
    local part
    local expected_part_md5
    local actual_part_md5
    local part_number=1

    rm -rf "$validation_dir"
    mkdir -p "$validation_dir" || fail "Unable to create OTA validation directory"
    7z x -y "$ota_image" -p"$FIRMWARE_PASSWORD" "-o$validation_dir" > /dev/null || \
        fail "Unable to extract the newly created OTA image"

    require_file "$validation_payload_dir/ota_update.in"
    require_file "$validation_payload_dir/ota_md5_rootfs.squashfs.${rootfs_md5}"

    shopt -s nullglob
    rootfs_parts=("$validation_payload_dir"/rootfs.squashfs.*)
    shopt -u nullglob
    [ "${#rootfs_parts[@]}" -gt 0 ] || fail "New OTA image contains no rootfs parts"

    cat "${rootfs_parts[@]}" > "$validation_rootfs" || fail "Unable to reassemble rootfs from OTA image"
    [ "$(md5sum "$validation_rootfs" | awk '{print $1}')" = "$rootfs_md5" ] || \
        fail "Reassembled rootfs checksum does not match the build output"
    [ "$(stat -c%s "$validation_rootfs")" = "$rootfs_size" ] || \
        fail "Reassembled rootfs size does not match the build output"

    grep -qx "img_md5=$rootfs_md5" "$validation_payload_dir/ota_update.in" || \
        fail "ota_update.in has an incorrect rootfs checksum"
    grep -qx "img_size=$rootfs_size" "$validation_payload_dir/ota_update.in" || \
        fail "ota_update.in has an incorrect rootfs size"

    for part in "${rootfs_parts[@]}"; do
        expected_part_md5=$(md5sum "$part" | awk '{print $1}')
        actual_part_md5=$(sed -n "${part_number}p" "$validation_payload_dir/ota_md5_rootfs.squashfs.${rootfs_md5}")
        [ "$expected_part_md5" = "$actual_part_md5" ] || \
            fail "Rootfs part checksum chain is invalid for $(basename "$part")"
        part_number=$((part_number + 1))
    done
    [ "$(wc -l < "$validation_payload_dir/ota_md5_rootfs.squashfs.${rootfs_md5}")" -eq "${#rootfs_parts[@]}" ] || \
        fail "Rootfs part checksum manifest has an unexpected number of entries"

    validate_rootfs "$validation_rootfs" "Reassembled rootfs"
    rm -rf "$validation_dir"
}

function write_ota_info() {
    echo "ota_version=${version}" > "$work_dir/ota_info"
    echo "ota_board_name=${BOARD_SHORT_NAME}" >> "$work_dir/ota_info"
    echo "ota_compile_time=$(date '+%Y %m.%d %H:%M:%S')" >> "$work_dir/ota_info"
    echo "ota_site=http://192.168.43.52/ota/board_test" >> "$work_dir/ota_info"
    sudo cp "$work_dir/ota_info" "$work_dir/squashfs-root/etc/"
}

function customise_rootfs() {
    write_ota_info
    [ -d $CURRENT_DIR/opt ] && rm -rf $CURRENT_DIR/opt
    sudo cp $PARENT_DIR/etc/init.d/* "$work_dir/squashfs-root/etc/init.d/"

    # I am not sure if for other boards setting a password will cause a boot loop, so im just doing it for nebula for now
    if [ "$BOARD_SHORT_NAME" = "NEBULA" ]; then
      root_hash='root:$1$C91t0g0z$MH9VBdqKSXjvrKNEw7wqG/:19562::::::'
      sudo sed -i "/^root/c\\$(printf '%s\n' "$root_hash")" "$work_dir/squashfs-root/etc/shadow"
    fi
}

function update_rootfs() {
    pushd "$work_dir" > /dev/null
    sudo unsquashfs orig_rootfs.squashfs
    customise_rootfs
    # Host SELinux labels become security.selinux xattrs during repacking. The
    # printer's OverlayFS cannot copy those xattrs to its ext4 upper layer.
    sudo mksquashfs squashfs-root rootfs.squashfs -no-xattrs || exit $?
    sudo rm -rf squashfs-root
    sudo chown developer: rootfs.squashfs
}

mkdir -p "$extracted_dir"
7z x "$old_image_name" -p"$FIRMWARE_PASSWORD" "-o$extracted_dir"

require_file "$original_dir/$old_sub_directory/ota_update.in"
shopt -s nullglob
original_rootfs_parts=("$original_dir/$old_sub_directory"/rootfs.squashfs.*)
shopt -u nullglob
[ "${#original_rootfs_parts[@]}" -gt 0 ] || fail "Original OTA image contains no rootfs parts"

mkdir -p "$work_dir/$directory/$sub_directory"

cat "${original_rootfs_parts[@]}" > "$work_dir/orig_rootfs.squashfs"
validate_rootfs "$work_dir/orig_rootfs.squashfs" "Original rootfs"
orig_rootfs_md5=$(md5sum "$work_dir/orig_rootfs.squashfs" | awk '{print $1}')
orig_rootfs_size=$(stat -c%s "$work_dir/orig_rootfs.squashfs")

# do the changes here
update_rootfs || exit $?
validate_rebuilt_rootfs "$work_dir/rootfs.squashfs"

if unsquashfs -cat "$work_dir/orig_rootfs.squashfs" etc/mount_mmc_ext4_overlay.sh > /dev/null 2>&1; then
    unsquashfs -cat "$work_dir/rootfs.squashfs" etc/mount_mmc_ext4_overlay.sh | \
        grep -q 'mount_mmc_ext4.sh rootfs_data' || \
        fail "Rebuilt rootfs is missing the vendor OverlayFS mount configuration"
fi

rootfs_md5=$(md5sum "$work_dir/rootfs.squashfs" | awk '{print $1}')
rootfs_size=$(stat -c%s "$work_dir/rootfs.squashfs")

echo "current_version=$version" > "$work_dir/$directory/ota_config.in"
echo "" > "$work_dir/$directory/$sub_directory/ota_v${version}.ok"

cp "$original_dir/$old_sub_directory/ota_update.in" "$work_dir/$directory/$sub_directory/"
cp "$original_dir/$old_sub_directory"/ota_md5_xImage* "$work_dir/$directory/$sub_directory/"
cp "$original_dir/$old_sub_directory"/ota_md5_zero.bin* "$work_dir/$directory/$sub_directory/"
cp "$original_dir/$old_sub_directory"/zero.bin.* "$work_dir/$directory/$sub_directory/"
cp "$original_dir/$old_sub_directory"/xImage.* "$work_dir/$directory/$sub_directory/"

pushd "$work_dir/$directory/$sub_directory" > /dev/null
split -d -b 1048576 -a 4 "$work_dir/rootfs.squashfs" rootfs.squashfs.
popd > /dev/null

part_md5=
shopt -s nullglob
rootfs_parts=("$work_dir/$directory/$sub_directory"/rootfs.squashfs.*)
shopt -u nullglob
[ "${#rootfs_parts[@]}" -gt 0 ] || fail "Unable to split rebuilt rootfs"
for i in "${rootfs_parts[@]}"; do
    file=$(basename $i)
    if [ -z "$part_md5" ]; then
        id=$rootfs_md5
    else
        id=$part_md5
    fi
    mv "$work_dir/$directory/$sub_directory/$file" "$work_dir/$directory/$sub_directory/${file}.${id}"
    part_md5=$(md5sum "$work_dir/$directory/$sub_directory/${file}.${id}" | awk '{print $1}')
    echo "$part_md5" >> "$work_dir/$directory/$sub_directory/ota_md5_rootfs.squashfs.${rootfs_md5}"
done

sed -i "s/ota_version=$CREALITY_VERSION/ota_version=$version/g" "$work_dir/$directory/$sub_directory/ota_update.in"
sed -i "s/img_md5=$orig_rootfs_md5/img_md5=$rootfs_md5/g" "$work_dir/$directory/$sub_directory/ota_update.in"
sed -i "s/img_size=$orig_rootfs_size/img_size=$rootfs_size/g" "$work_dir/$directory/$sub_directory/ota_update.in"

pushd "$work_dir" > /dev/null
7z a ${image_name}.7z -p"$FIRMWARE_PASSWORD" $directory
popd > /dev/null

staged_image=$(mktemp "/out/.${image_name}.XXXXXX") || fail "Unable to create OTA staging file"
cp "$work_dir/${image_name}.7z" "$staged_image" || fail "Unable to stage OTA image"
validate_ota_image "$staged_image"
staged_rootfs=$(mktemp "/out/.${rootfs_filename}.XXXXXX") || fail "Unable to create rootfs staging file"
cp "$work_dir/rootfs.squashfs" "$staged_rootfs" || fail "Unable to stage decrypted rootfs"
mv "$staged_rootfs" "/out/${rootfs_filename}" || fail "Unable to publish decrypted rootfs"
mv "$staged_image" "/out/${image_name}" || fail "Unable to publish OTA image"

echo "Resulting decrypted rootfs is /tmp/$rootfs_filename"

# assuming we call this docker with /tmp:/out
echo "The image is /tmp/${image_name}"
