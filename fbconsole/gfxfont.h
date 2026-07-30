#ifndef GFXFONT_H
#define GFXFONT_H

#include <stdint.h>

typedef struct {
    uint16_t bitmapOffset;
    uint8_t width;
    uint8_t height;
    uint8_t xAdvance;
    int8_t xOffset;
    int8_t yOffset;
} GFXglyph;

typedef struct {
    uint8_t *bitmap;
    GFXglyph *glyph;
    uint16_t first;
    uint16_t last;
    uint8_t yAdvance;
} GFXfont;

/*
 * Arduino normally defines these. They are unnecessary on Linux,
 * so define them as nothing.
 */
#ifndef PROGMEM
#define PROGMEM
#endif

#endif
