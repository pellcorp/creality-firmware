#!/usr/bin/env bash
# Replace the first K1 480x800 RTOS boot-logo candidate in zero.bin.
# The input zero.bin is never modified; the output is a patched copy.

set -euo pipefail

readonly EXPECTED_ZERO_SIZE=452408
readonly LOGO_OFFSET=344656       # 0x54250; 480x800 candidate
readonly LOGO_SLOT_SIZE=25411

usage() {
  cat <<'EOF'
Usage: patch-k1-zero-bin.sh INPUT_ZERO_BIN INPUT_JPEG OUTPUT_ZERO_BIN

Creates OUTPUT_ZERO_BIN by replacing the first K1 480x800 boot-logo candidate.
The JPEG must be baseline, 480x800, RGB, and no larger than 25,411 bytes.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ $# -eq 3 ]] || { usage >&2; exit 2; }
input_bin=$1
input_jpeg=$2
output_bin=$3

for required in dd sha256sum wc mktemp cp; do
  command -v "$required" >/dev/null || die "Missing required command: $required"
done

[[ -f "$input_bin" ]] || die "zero.bin not found: $input_bin"
[[ -f "$input_jpeg" ]] || die "JPEG not found: $input_jpeg"
[[ ! -e "$output_bin" ]] || die "Refusing to overwrite existing output: $output_bin"

bin_size=$(wc -c < "$input_bin")
[[ $bin_size -eq $EXPECTED_ZERO_SIZE ]] || \
  die "Expected the $EXPECTED_ZERO_SIZE-byte K1 zero.bin; got $bin_size bytes."

if command -v identify >/dev/null; then
  geometry=$(identify -format '%w %h %[colorspace] %[interlace]' "$input_jpeg" 2>/dev/null) || \
    die "Cannot read JPEG: $input_jpeg"
  [[ $geometry == "480 800 sRGB None" || $geometry == "480 800 RGB None" ]] || \
    die "Expected a baseline 480x800 RGB JPEG; got: $geometry"
fi

jpeg_size=$(wc -c < "$input_jpeg")
(( jpeg_size <= LOGO_SLOT_SIZE )) || \
  die "JPEG is $jpeg_size bytes; this logo allocation is $LOGO_SLOT_SIZE bytes."

output_dir=$(dirname -- "$output_bin")
[[ -d "$output_dir" ]] || die "Output directory does not exist: $output_dir"
temp_bin=$(mktemp "$output_dir/.k1-zero.bin.XXXXXX")
trap 'rm -f -- "$temp_bin"' EXIT

cp -- "$input_bin" "$temp_bin"
dd if=/dev/zero of="$temp_bin" bs=1 seek="$LOGO_OFFSET" count="$LOGO_SLOT_SIZE" conv=notrunc status=none
dd if="$input_jpeg" of="$temp_bin" bs=1 seek="$LOGO_OFFSET" conv=notrunc status=none

[[ $(wc -c < "$temp_bin") -eq $EXPECTED_ZERO_SIZE ]] || die "Patched file size changed unexpectedly."
source_hash=$(sha256sum "$input_jpeg" | awk '{print $1}')
embedded_hash=$(dd if="$temp_bin" bs=1 skip="$LOGO_OFFSET" count="$jpeg_size" status=none | sha256sum | awk '{print $1}')
[[ $source_hash == "$embedded_hash" ]] || die "Verification failed: embedded JPEG differs from input."

mv -- "$temp_bin" "$output_bin"
trap - EXIT
echo "Created: $output_bin"
echo "Patched 480x800 candidate at offset $LOGO_OFFSET (0x$(printf '%x' "$LOGO_OFFSET")); JPEG size: $jpeg_size bytes"
