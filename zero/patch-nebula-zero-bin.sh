#!/usr/bin/env bash
# Replace the initial 480x272 Nebula Pad logo embedded in zero.bin.
#
# The input zero.bin is never modified. The output is a patched copy.

set -euo pipefail

readonly LOGO_OFFSET=386316       # 0x5e50c
readonly LOGO_SLOT_SIZE=10899

usage() {
  cat <<'EOF'
Usage: patch-nebula-zero-bin.sh INPUT_ZERO_BIN INPUT_JPEG OUTPUT_ZERO_BIN

Creates OUTPUT_ZERO_BIN by replacing the embedded Nebula Pad boot-logo JPEG.
The JPEG must be baseline, 480x272, RGB, and no larger than 10,899 bytes.
EOF
}

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 2
fi

input_bin=$1
input_jpeg=$2
output_bin=$3

for required in dd sha256sum wc mktemp; do
  command -v "$required" >/dev/null || {
    echo "Missing required command: $required" >&2
    exit 1
  }
done

[[ -f "$input_bin" ]] || { echo "zero.bin not found: $input_bin" >&2; exit 1; }
[[ -f "$input_jpeg" ]] || { echo "JPEG not found: $input_jpeg" >&2; exit 1; }
[[ ! -e "$output_bin" ]] || { echo "Refusing to overwrite existing output: $output_bin" >&2; exit 1; }

if command -v identify >/dev/null; then
  geometry=$(identify -format '%w %h %[colorspace] %[interlace]' "$input_jpeg" 2>/dev/null) || {
    echo "Cannot read JPEG: $input_jpeg" >&2
    exit 1
  }
  if [[ $geometry != "480 272 sRGB None" && $geometry != "480 272 RGB None" ]]; then
    echo "Expected a baseline 480x272 RGB JPEG; got: $geometry" >&2
    exit 1
  fi
fi

jpeg_size=$(wc -c < "$input_jpeg")
if (( jpeg_size > LOGO_SLOT_SIZE )); then
  echo "JPEG is $jpeg_size bytes; the embedded logo slot is only $LOGO_SLOT_SIZE bytes." >&2
  exit 1
fi

bin_size=$(wc -c < "$input_bin")
if (( bin_size < LOGO_OFFSET + LOGO_SLOT_SIZE )); then
  echo "Input is too small to contain the known logo slot: $input_bin" >&2
  exit 1
fi

output_dir=$(dirname -- "$output_bin")
[[ -d "$output_dir" ]] || { echo "Output directory does not exist: $output_dir" >&2; exit 1; }

temp_bin=$(mktemp "$output_dir/.zero.bin.XXXXXX")
trap 'rm -f -- "$temp_bin"' EXIT

cp -- "$input_bin" "$temp_bin"
# Clear the full old JPEG allocation first, then write the shorter/new JPEG.
dd if=/dev/zero of="$temp_bin" bs=1 seek="$LOGO_OFFSET" count="$LOGO_SLOT_SIZE" conv=notrunc status=none
dd if="$input_jpeg" of="$temp_bin" bs=1 seek="$LOGO_OFFSET" conv=notrunc status=none

patched_size=$(wc -c < "$temp_bin")
if (( patched_size != bin_size )); then
  echo "Patched file size changed unexpectedly." >&2
  exit 1
fi

source_hash=$(sha256sum "$input_jpeg" | awk '{print $1}')
embedded_hash=$(dd if="$temp_bin" bs=1 skip="$LOGO_OFFSET" count="$jpeg_size" status=none | sha256sum | awk '{print $1}')
if [[ $source_hash != "$embedded_hash" ]]; then
  echo "Verification failed: embedded JPEG differs from input." >&2
  exit 1
fi

mv -- "$temp_bin" "$output_bin"
trap - EXIT

echo "Created: $output_bin"
echo "Patched JPEG: $jpeg_size bytes at offset $LOGO_OFFSET (0x$(printf '%x' "$LOGO_OFFSET"))"
echo "SHA-256: $source_hash"
