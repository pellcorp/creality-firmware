#!/usr/bin/env python3
"""
Convert printable ASCII glyphs (0x20-0x7e) from a BDF bitmap font into an
Adafruit GFXfont-compatible C header.

Usage:
    ./bdf2gfxfont.py input.bdf FontSymbol > FontSymbol.h

The generated header expects GFXglyph, GFXfont and PROGMEM to already be
defined, as they are in fbtext.c.
"""

import re
import sys
from dataclasses import dataclass


FIRST = 0x20
LAST = 0x7E


@dataclass
class Glyph:
    encoding: int = -1
    dwidth: int = 0
    width: int = 0
    height: int = 0
    x_offset: int = 0
    y_offset: int = 0
    rows: list[int] | None = None


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"bdf2gfxfont: {message}")


def parse_bdf(path: str) -> tuple[dict[int, Glyph], int, int, int]:
    glyphs: dict[int, Glyph] = {}
    font_ascent: int | None = None
    font_descent: int | None = None
    default_advance = 0

    current: Glyph | None = None
    reading_bitmap = False

    with open(path, "r", encoding="ascii", errors="strict") as source:
        for line_number, raw_line in enumerate(source, 1):
            line = raw_line.strip()

            if not line:
                continue

            if current is None:
                if line.startswith("FONT_ASCENT "):
                    font_ascent = int(line.split()[1])
                elif line.startswith("FONT_DESCENT "):
                    font_descent = int(line.split()[1])
                elif line.startswith("FONTBOUNDINGBOX "):
                    values = line.split()
                    if len(values) != 5:
                        fail(f"{path}:{line_number}: malformed FONTBOUNDINGBOX")
                    if default_advance == 0:
                        default_advance = int(values[1])
                elif line.startswith("STARTCHAR"):
                    current = Glyph(rows=[])
                    reading_bitmap = False
                continue

            if reading_bitmap:
                if line == "ENDCHAR":
                    if len(current.rows or []) != current.height:
                        fail(
                            f"{path}:{line_number}: bitmap has "
                            f"{len(current.rows or [])} rows, expected "
                            f"{current.height}"
                        )
                    if FIRST <= current.encoding <= LAST:
                        glyphs[current.encoding] = current
                    current = None
                    reading_bitmap = False
                    continue

                try:
                    row = int(line, 16)
                except ValueError:
                    fail(f"{path}:{line_number}: invalid bitmap row {line!r}")

                assert current.rows is not None
                current.rows.append(row)
                continue

            fields = line.split()

            if fields[0] == "ENCODING" and len(fields) >= 2:
                current.encoding = int(fields[1])
            elif fields[0] == "DWIDTH" and len(fields) >= 3:
                current.dwidth = int(fields[1])
                if default_advance == 0 and current.dwidth > 0:
                    default_advance = current.dwidth
            elif fields[0] == "BBX" and len(fields) == 5:
                current.width = int(fields[1])
                current.height = int(fields[2])
                current.x_offset = int(fields[3])
                current.y_offset = int(fields[4])
                if current.width < 0 or current.height < 0:
                    fail(f"{path}:{line_number}: negative BBX dimensions")
            elif line == "BITMAP":
                reading_bitmap = True
            elif line == "ENDCHAR":
                if FIRST <= current.encoding <= LAST:
                    glyphs[current.encoding] = current
                current = None

    if current is not None:
        fail(f"{path}: unexpected end of file inside glyph")
    if font_ascent is None or font_descent is None:
        fail(f"{path}: FONT_ASCENT or FONT_DESCENT is missing")
    if not 1 <= default_advance <= 255:
        fail(f"{path}: could not determine a valid character advance")

    return glyphs, font_ascent, font_descent, default_advance


def bitmap_bit(row: int, width: int, x: int) -> int:
    # BDF rows are padded on the right to a whole number of bytes.
    padded_width = ((width + 7) // 8) * 8
    return (row >> (padded_width - 1 - x)) & 1


def pack_bitmap(glyph: Glyph) -> bytes:
    if glyph.width == 0 or glyph.height == 0:
        return b""

    rows = glyph.rows or []
    bits: list[int] = []

    for row in rows:
        for x in range(glyph.width):
            bits.append(bitmap_bit(row, glyph.width, x))

    output = bytearray()
    value = 0
    used = 0

    for bit in bits:
        value = (value << 1) | bit
        used += 1

        if used == 8:
            output.append(value)
            value = 0
            used = 0

    if used:
        output.append(value << (8 - used))

    return bytes(output)


def include_guard(symbol: str) -> str:
    return "BDF2GFXFONT_" + re.sub(r"[^A-Za-z0-9]", "_", symbol).upper() + "_H"


def emit_header(
    symbol: str,
    glyphs: dict[int, Glyph],
    font_ascent: int,
    font_descent: int,
    default_advance: int,
) -> None:
    bitmap = bytearray()
    metrics: list[tuple[int, int, int, int, int, int]] = []

    for encoding in range(FIRST, LAST + 1):
        offset = len(bitmap)
        glyph = glyphs.get(encoding)

        if glyph is None:
            metrics.append((offset, 0, 0, default_advance, 0, 0))
            continue

        if not 0 <= glyph.width <= 255:
            fail(f"glyph 0x{encoding:02x} width does not fit GFXglyph")
        if not 0 <= glyph.height <= 255:
            fail(f"glyph 0x{encoding:02x} height does not fit GFXglyph")
        if not 0 <= glyph.dwidth <= 255:
            fail(f"glyph 0x{encoding:02x} advance does not fit GFXglyph")
        if not -128 <= glyph.x_offset <= 127:
            fail(f"glyph 0x{encoding:02x} x offset does not fit GFXglyph")

        # BDF y_offset is the bitmap bottom relative to the baseline.
        # GFXfont yOffset is the bitmap top relative to the baseline.
        gfx_y_offset = -(glyph.y_offset + glyph.height)

        if not -128 <= gfx_y_offset <= 127:
            fail(f"glyph 0x{encoding:02x} y offset does not fit GFXglyph")

        metrics.append(
            (
                offset,
                glyph.width,
                glyph.height,
                glyph.dwidth,
                glyph.x_offset,
                gfx_y_offset,
            )
        )
        bitmap.extend(pack_bitmap(glyph))

    if len(bitmap) > 0xFFFF:
        fail("bitmap data exceeds GFXfont's 16-bit glyph offsets")

    y_advance = font_ascent + font_descent
    if not 1 <= y_advance <= 255:
        fail("FONT_ASCENT + FONT_DESCENT does not fit GFXfont")

    guard = include_guard(symbol)

    print("/* Generated from a BDF font by bdf2gfxfont.py. */")
    print(f"#ifndef {guard}")
    print(f"#define {guard}")
    print()
    print(f"static const uint8_t {symbol}Bitmaps[] PROGMEM = {{")

    for index in range(0, len(bitmap), 12):
        chunk = bitmap[index : index + 12]
        suffix = "," if index + len(chunk) < len(bitmap) else ""
        print("    " + ", ".join(f"0x{value:02x}" for value in chunk) + suffix)

    print("};")
    print()
    print(f"static const GFXglyph {symbol}Glyphs[] PROGMEM = {{")

    for encoding, metric in zip(range(FIRST, LAST + 1), metrics):
        offset, width, height, advance, x_offset, y_offset = metric
        display = chr(encoding)
        if display in {"\\", "'"}:
            display = "."
        print(
            f"    {{ {offset:5d}, {width:3d}, {height:3d}, "
            f"{advance:3d}, {x_offset:4d}, {y_offset:4d} }}, "
            f"/* 0x{encoding:02x} '{display}' */"
        )

    print("};")
    print()
    print(f"static const GFXfont {symbol} PROGMEM = {{")
    print(f"    (uint8_t *){symbol}Bitmaps,")
    print(f"    (GFXglyph *){symbol}Glyphs,")
    print(f"    0x{FIRST:02x},")
    print(f"    0x{LAST:02x},")
    print(f"    {y_advance}")
    print("};")
    print()
    print(f"#endif /* {guard} */")


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"usage: {sys.argv[0]} input.bdf FontSymbol > FontSymbol.h")

    path, symbol = sys.argv[1], sys.argv[2]

    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", symbol) is None:
        fail("FontSymbol must be a valid C identifier")

    glyphs, ascent, descent, advance = parse_bdf(path)
    emit_header(symbol, glyphs, ascent, descent, advance)


if __name__ == "__main__":
    main()
