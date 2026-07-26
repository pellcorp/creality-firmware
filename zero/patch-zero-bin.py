#!/usr/bin/env python3
"""Patch a JPEG asset discovered inside a Creality zero.bin RTOS image."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import struct
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Jpeg:
    offset: int
    end: int  # exclusive
    width: int
    height: int
    sof_marker: int
    label: str | None = None

    @property
    def size(self) -> int:
        return self.end - self.offset


def fail(message: str) -> None:
    raise ValueError(message)


def parse_jpeg(data: bytes, start: int) -> Jpeg:
    """Return the enclosing JPEG boundaries and dimensions at *start*.

    Segment lengths are honoured, so an EXIF thumbnail's JPEG markers are not
    mistaken for the end of the enclosing image.
    """
    if data[start : start + 2] != b"\xff\xd8":
        fail(f"No JPEG SOI at offset {start}")

    pos = start + 2
    width = height = 0
    sof_marker = 0
    in_scan = False

    while pos < len(data):
        if in_scan:
            marker_pos = data.find(b"\xff", pos)
            if marker_pos < 0 or marker_pos + 1 >= len(data):
                fail("Truncated JPEG scan")
            pos = marker_pos + 1
            while pos < len(data) and data[pos] == 0xFF:
                pos += 1
            if pos >= len(data):
                fail("Truncated JPEG marker")
            marker = data[pos]
            pos += 1
            if marker == 0x00 or 0xD0 <= marker <= 0xD7:
                continue
            in_scan = False
        else:
            if data[pos] != 0xFF:
                fail("Invalid JPEG marker")
            pos += 1
            while pos < len(data) and data[pos] == 0xFF:
                pos += 1
            if pos >= len(data):
                fail("Truncated JPEG marker")
            marker = data[pos]
            pos += 1

        if marker == 0xD9:
            if not width or not height:
                fail("JPEG has no frame header")
            return Jpeg(start, pos, width, height, sof_marker)
        if marker in (0x01,) or 0xD0 <= marker <= 0xD7:
            continue
        if pos + 2 > len(data):
            fail("Truncated JPEG segment length")
        length = int.from_bytes(data[pos : pos + 2], "big")
        if length < 2 or pos + length > len(data):
            fail("Invalid JPEG segment length")
        if marker in tuple(range(0xC0, 0xC4)) + tuple(range(0xC5, 0xC8)) + tuple(range(0xC9, 0xCC)) + tuple(range(0xCD, 0xD0)):
            if length < 8:
                fail("Invalid JPEG frame header")
            height = int.from_bytes(data[pos + 3 : pos + 5], "big")
            width = int.from_bytes(data[pos + 5 : pos + 7], "big")
            sof_marker = marker
        pos += length
        if marker == 0xDA:
            in_scan = True

    fail("Truncated JPEG")


def symbol_label(data: bytes, base_address: int | None, offset: int) -> str | None:
    """Resolve the RTOS symbol-index label associated with a JPEG data range."""
    if base_address is None:
        return None
    address = struct.pack("<I", base_address + offset)
    position = data.find(address)
    while position >= 0 and position + 8 <= len(data):
        name_address = struct.unpack_from("<I", data, position + 4)[0]
        name_offset = name_address - base_address
        if 0 <= name_offset < len(data):
            end = data.find(b"\0", name_offset)
            if end >= 0:
                try:
                    name = data[name_offset:end].decode("ascii")
                except UnicodeDecodeError:
                    name = ""
                if name.endswith("Data"):
                    return name[:-4]
        position = data.find(address, position + 1)
    return None


def find_jpegs(data: bytes) -> list[Jpeg]:
    found: list[Jpeg] = []
    start = 0
    while True:
        start = data.find(b"\xff\xd8", start)
        if start < 0:
            break
        try:
            found.append(parse_jpeg(data, start))
        except ValueError:
            pass
        start += 2

    # Exclude EXIF thumbnails and any other JPEG contained within a larger one.
    top_level = [item for item in found if not any(other.offset < item.offset < other.end for other in found)]
    base_address = struct.unpack_from("<I", data, 16)[0] if len(data) >= 20 and data[8:12] == b"RTOS" else None
    return sorted((Jpeg(item.offset, item.end, item.width, item.height, item.sof_marker, symbol_label(data, base_address, item.offset)) for item in top_level), key=lambda item: item.offset)


def read_one_jpeg(path: Path) -> Jpeg:
    data = path.read_bytes()
    slots = find_jpegs(data)
    if len(slots) != 1 or slots[0].offset != 0 or slots[0].end != len(data):
        fail(f"Expected one complete JPEG file: {path}")
    return slots[0]


def print_slots(slots: list[Jpeg]) -> None:
    print("slot  offset      size (bytes)  dimensions  encoding  label")
    for index, slot in enumerate(slots, start=1):
        encoding = "baseline" if slot.sof_marker == 0xC0 else f"SOF{slot.sof_marker:02X}"
        print(f"{index:>4}  0x{slot.offset:06x}  {slot.size:>8}  {slot.width}x{slot.height:<4}  {encoding:<8}  {slot.label or '-'}")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list discovered JPEG slots and exit")
    parser.add_argument("--slot", type=int, help="1-based slot number from --list")
    parser.add_argument("zero_bin", type=Path)
    parser.add_argument("jpeg", type=Path, nargs="?")
    parser.add_argument("output", type=Path, nargs="?")
    args = parser.parse_args()

    if not args.zero_bin.is_file():
        fail(f"zero.bin not found: {args.zero_bin}")
    zero_data = args.zero_bin.read_bytes()
    slots = find_jpegs(zero_data)
    if not slots:
        fail("No complete top-level JPEG assets found in zero.bin")

    if args.list:
        if args.jpeg or args.output or args.slot:
            fail("--list only accepts ZERO_BIN")
        print_slots(slots)
        return 0

    if not args.jpeg or not args.output:
        fail("JPEG and OUTPUT are required unless --list is used")
    if not args.jpeg.is_file():
        fail(f"JPEG not found: {args.jpeg}")
    if args.output.exists():
        fail(f"Refusing to overwrite existing output: {args.output}")
    if not args.output.parent.is_dir():
        fail(f"Output directory does not exist: {args.output.parent}")

    source_jpeg = args.jpeg.read_bytes()
    source = read_one_jpeg(args.jpeg)
    if source.sof_marker != 0xC0:
        fail("The replacement must be a baseline JPEG (SOF0), not progressive")

    matching = [slot for slot in slots if (slot.width, slot.height) == (source.width, source.height) and source.size <= slot.size]
    if args.slot is not None:
        if not 1 <= args.slot <= len(slots):
            fail(f"Slot must be between 1 and {len(slots)}")
        slot = slots[args.slot - 1]
        if (slot.width, slot.height) != (source.width, source.height):
            fail(f"Slot {args.slot} is {slot.width}x{slot.height}; replacement is {source.width}x{source.height}")
        if source.size > slot.size:
            fail(f"Replacement is {source.size} bytes; slot {args.slot} holds {slot.size} bytes")
    elif len(matching) == 1:
        slot = matching[0]
    elif not matching:
        fail("No discovered JPEG slot matches the replacement dimensions and size")
    else:
        print_slots(slots)
        fail("Several slots match; rerun with --slot NUMBER")

    descriptor = slots.index(slot) + 1
    fd, temp_name = tempfile.mkstemp(prefix=".zero.bin.", dir=args.output.parent)
    os.close(fd)
    temp_path = Path(temp_name)
    try:
        shutil.copyfile(args.zero_bin, temp_path)
        with temp_path.open("r+b") as output:
            output.seek(slot.offset)
            output.write(b"\x00" * slot.size)
            output.seek(slot.offset)
            output.write(source_jpeg)
            output.flush()
            os.fsync(output.fileno())
        patched = temp_path.read_bytes()
        if len(patched) != len(zero_data):
            fail("Patched file size changed unexpectedly")
        if sha256_bytes(patched[slot.offset : slot.offset + source.size]) != sha256_bytes(source_jpeg):
            fail("Verification failed: embedded JPEG differs from input")
        os.replace(temp_path, args.output)
    finally:
        temp_path.unlink(missing_ok=True)

    print(f"Created: {args.output}")
    print(f"Patched slot {descriptor}: offset 0x{slot.offset:x}, capacity {slot.size} bytes, {slot.width}x{slot.height}")
    print(f"Replacement: {source.size} bytes, SHA-256 {sha256_bytes(source_jpeg)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
