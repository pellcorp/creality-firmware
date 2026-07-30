#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

/*
 * Minimal definitions required by Adafruit GFX font headers.
 *
 * These match the structures from Adafruit's gfxfont.h, but avoid requiring
 * the full Arduino/Adafruit GFX library on Linux.
 */
#ifndef PROGMEM
#define PROGMEM
#endif

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

#include "Terminus12.h"
#include "Terminus14.h"

static const GFXfont *find_font(const char *name)
{
    if (strcmp(name, "terminus") == 0 ||
        strcmp(name, "term") == 0 ||
        strcmp(name, "term12") == 0) {
        return &Terminus12;
    }

    if (strcmp(name, "term14") == 0) {
        return &Terminus14;
    }

    fprintf(
        stderr,
        "Unknown font: %s\n"
        "Available fonts: term12, term14\n",
        name);

    exit(EXIT_FAILURE);
}

struct framebuffer {
    int file_descriptor;
    uint8_t *memory;
    size_t memory_length;

    struct fb_fix_screeninfo fixed;
    struct fb_var_screeninfo variable;
};

enum escape_state {
    ESCAPE_NONE,
    ESCAPE_STARTED,
    ESCAPE_CSI,
    ESCAPE_OSC,
    ESCAPE_OSC_ESCAPE
};

static void usage(const char *program)
{
    fprintf(
        stderr,
        "Usage:\n"
        "  %s [-f /dev/fb0] clear RRGGBB\n"
        "  %s [-f /dev/fb0] rect X Y WIDTH HEIGHT RRGGBB\n"
        "  %s [-f /dev/fb0] text X Y SCALE RRGGBB TEXT...\n"
        "  %s [-f /dev/fb0] console [FONT [SCALE [FOREGROUND [BACKGROUND]]]]\n"
        "\n"
        "Examples:\n"
        "  %s clear 000000\n"
        "  %s rect 10 10 100 40 ff0000\n"
        "  %s text 10 10 2 ffffff \"Hello world\"\n"
        "  ./install.sh 2>&1 | %s console terminus\n"
        "  ./install.sh 2>&1 | %s console term14 2 ffffff 000000\n"
        "\n"
        "Console defaults:\n"
        "  FONT       terminus\n"
        "  SCALE      1\n"
        "  FOREGROUND ffffff\n"
        "  BACKGROUND 000000\n",
        program,
        program,
        program,
        program,
        program,
        program,
        program,
        program,
        program);
}

static void fatal_errno(const char *message)
{
    perror(message);
    exit(EXIT_FAILURE);
}

static int parse_int(const char *text, const char *description)
{
    char *end = NULL;
    long value;

    errno = 0;
    value = strtol(text, &end, 10);

    if (errno != 0 ||
        end == text ||
        *end != '\0' ||
        value < INT32_MIN ||
        value > INT32_MAX) {
        fprintf(
            stderr,
            "Invalid %s: %s\n",
            description,
            text);

        exit(EXIT_FAILURE);
    }

    return (int)value;
}

static uint32_t parse_rgb(const char *text)
{
    char *end = NULL;
    unsigned long value;

    if (text[0] == '#') {
        text++;
    }

    if (strlen(text) != 6u) {
        fprintf(
            stderr,
            "Colour must be six hexadecimal digits: %s\n",
            text);

        exit(EXIT_FAILURE);
    }

    errno = 0;
    value = strtoul(text, &end, 16);

    if (errno != 0 ||
        end == text ||
        *end != '\0' ||
        value > 0xfffffful) {
        fprintf(
            stderr,
            "Invalid colour: %s\n",
            text);

        exit(EXIT_FAILURE);
    }

    return (uint32_t)value;
}

static void open_framebuffer(
    struct framebuffer *framebuffer,
    const char *device)
{
    memset(framebuffer, 0, sizeof(*framebuffer));
    framebuffer->file_descriptor = -1;
    framebuffer->memory = MAP_FAILED;

    framebuffer->file_descriptor =
        open(device, O_RDWR | O_CLOEXEC);

    if (framebuffer->file_descriptor < 0) {
        fatal_errno(device);
    }

    if (ioctl(
            framebuffer->file_descriptor,
            FBIOGET_FSCREENINFO,
            &framebuffer->fixed) < 0) {
        fatal_errno("FBIOGET_FSCREENINFO");
    }

    if (ioctl(
            framebuffer->file_descriptor,
            FBIOGET_VSCREENINFO,
            &framebuffer->variable) < 0) {
        fatal_errno("FBIOGET_VSCREENINFO");
    }

    switch (framebuffer->variable.bits_per_pixel) {
    case 16:
    case 24:
    case 32:
        break;

    default:
        fprintf(
            stderr,
            "Unsupported framebuffer depth: %u bits per pixel\n",
            framebuffer->variable.bits_per_pixel);

        exit(EXIT_FAILURE);
    }

    framebuffer->memory_length =
        framebuffer->fixed.smem_len;

    if (framebuffer->memory_length == 0u) {
        framebuffer->memory_length =
            (size_t)framebuffer->fixed.line_length *
            framebuffer->variable.yres_virtual;
    }

    framebuffer->memory = mmap(
        NULL,
        framebuffer->memory_length,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        framebuffer->file_descriptor,
        0);

    if (framebuffer->memory == MAP_FAILED) {
        fatal_errno("mmap framebuffer");
    }
}

static void close_framebuffer(struct framebuffer *framebuffer)
{
    if (framebuffer->memory != MAP_FAILED) {
        if (munmap(
                framebuffer->memory,
                framebuffer->memory_length) < 0) {
            perror("munmap framebuffer");
        }

        framebuffer->memory = MAP_FAILED;
    }

    if (framebuffer->file_descriptor >= 0) {
        if (close(framebuffer->file_descriptor) < 0) {
            perror("close framebuffer");
        }

        framebuffer->file_descriptor = -1;
    }
}

static uint32_t scale_component(
    const uint8_t component,
    const uint32_t length)
{
    uint32_t maximum;

    if (length == 0u) {
        return 0u;
    }

    if (length >= 32u) {
        return component;
    }

    maximum = (1u << length) - 1u;

    return ((uint32_t)component * maximum + 127u) / 255u;
}

static uint32_t framebuffer_colour(
    const struct framebuffer *framebuffer,
    const uint32_t rgb)
{
    const uint8_t red =
        (uint8_t)((rgb >> 16u) & 0xffu);

    const uint8_t green =
        (uint8_t)((rgb >> 8u) & 0xffu);

    const uint8_t blue =
        (uint8_t)(rgb & 0xffu);

    uint32_t value = 0u;

    value |=
        scale_component(
            red,
            framebuffer->variable.red.length)
        << framebuffer->variable.red.offset;

    value |=
        scale_component(
            green,
            framebuffer->variable.green.length)
        << framebuffer->variable.green.offset;

    value |=
        scale_component(
            blue,
            framebuffer->variable.blue.length)
        << framebuffer->variable.blue.offset;

    if (framebuffer->variable.transp.length != 0u) {
        uint32_t alpha;

        if (framebuffer->variable.transp.length >= 32u) {
            alpha = UINT32_MAX;
        } else {
            alpha =
                (1u << framebuffer->variable.transp.length) -
                1u;
        }

        value |=
            alpha <<
            framebuffer->variable.transp.offset;
    }

    return value;
}

static void put_pixel(
    struct framebuffer *framebuffer,
    const int x,
    const int y,
    const uint32_t rgb)
{
    const int width =
        (int)framebuffer->variable.xres;

    const int height =
        (int)framebuffer->variable.yres;

    const size_t bytes_per_pixel =
        framebuffer->variable.bits_per_pixel / 8u;

    size_t offset;
    uint32_t value;

    if (x < 0 || y < 0 || x >= width || y >= height) {
        return;
    }

    offset =
        ((size_t)y + framebuffer->variable.yoffset) *
            framebuffer->fixed.line_length +
        ((size_t)x + framebuffer->variable.xoffset) *
            bytes_per_pixel;

    if (offset + bytes_per_pixel >
        framebuffer->memory_length) {
        return;
    }

    value = framebuffer_colour(framebuffer, rgb);

    switch (bytes_per_pixel) {
    case 2:
        {
            const uint16_t pixel = (uint16_t)value;
            memcpy(framebuffer->memory + offset, &pixel, sizeof(pixel));
        }
        break;

    case 3:
        framebuffer->memory[offset] =
            (uint8_t)(value & 0xffu);

        framebuffer->memory[offset + 1u] =
            (uint8_t)((value >> 8u) & 0xffu);

        framebuffer->memory[offset + 2u] =
            (uint8_t)((value >> 16u) & 0xffu);
        break;

    case 4:
        memcpy(
            framebuffer->memory + offset,
            &value,
            sizeof(value));
        break;

    default:
        break;
    }
}

static void fill_rect(
    struct framebuffer *framebuffer,
    int x,
    int y,
    int width,
    int height,
    const uint32_t colour)
{
    int end_x;
    int end_y;

    if (width <= 0 || height <= 0) {
        return;
    }

    end_x = x + width;
    end_y = y + height;

    if (end_x <= 0 || end_y <= 0) {
        return;
    }

    if (x >= (int)framebuffer->variable.xres ||
        y >= (int)framebuffer->variable.yres) {
        return;
    }

    if (x < 0) {
        x = 0;
    }

    if (y < 0) {
        y = 0;
    }

    if (end_x > (int)framebuffer->variable.xres) {
        end_x = (int)framebuffer->variable.xres;
    }

    if (end_y > (int)framebuffer->variable.yres) {
        end_y = (int)framebuffer->variable.yres;
    }

    for (int current_y = y;
         current_y < end_y;
         current_y++) {
        for (int current_x = x;
             current_x < end_x;
             current_x++) {
            put_pixel(
                framebuffer,
                current_x,
                current_y,
                colour);
        }
    }
}

static void clear_framebuffer(
    struct framebuffer *framebuffer,
    const uint32_t colour)
{
    fill_rect(
        framebuffer,
        0,
        0,
        (int)framebuffer->variable.xres,
        (int)framebuffer->variable.yres,
        colour);
}

static void scroll_framebuffer(
    struct framebuffer *framebuffer,
    const int pixels,
    const uint32_t background)
{
    const int screen_height =
        (int)framebuffer->variable.yres;

    const size_t bytes_per_pixel =
        framebuffer->variable.bits_per_pixel / 8u;

    const size_t visible_row_bytes =
        (size_t)framebuffer->variable.xres *
        bytes_per_pixel;

    const size_t x_offset =
        (size_t)framebuffer->variable.xoffset *
        bytes_per_pixel;

    const size_t first_row =
        framebuffer->variable.yoffset;

    if (pixels <= 0) {
        return;
    }

    if (pixels >= screen_height) {
        clear_framebuffer(framebuffer, background);
        return;
    }

    for (int y = 0; y < screen_height - pixels; y++) {
        uint8_t *destination =
            framebuffer->memory +
            (first_row + (size_t)y) *
                framebuffer->fixed.line_length +
            x_offset;

        const uint8_t *source =
            framebuffer->memory +
            (first_row + (size_t)y + (size_t)pixels) *
                framebuffer->fixed.line_length +
            x_offset;

        memmove(
            destination,
            source,
            visible_row_bytes);
    }

    fill_rect(
        framebuffer,
        0,
        screen_height - pixels,
        (int)framebuffer->variable.xres,
        pixels,
        background);
}

static unsigned char normalise_character(
    const GFXfont *font,
    unsigned char character)
{
    if (character < font->first ||
        character > font->last) {
        character = '?';
    }

    return character;
}

static const GFXglyph *font_glyph(
    const GFXfont *font,
    unsigned char character)
{
    character =
        normalise_character(font, character);

    return &font->glyph[character - font->first];
}

static int glyph_advance(
    const GFXfont *font,
    unsigned char character,
    const int scale)
{
    const GFXglyph *glyph =
        font_glyph(font, character);

    return (int)glyph->xAdvance * scale;
}

static int font_ascent(const GFXfont *font)
{
    int ascent = 0;

    for (uint16_t character = font->first;
         character <= font->last;
         character++) {
        const GFXglyph *glyph =
            &font->glyph[character - font->first];

        const int glyph_ascent =
            -(int)glyph->yOffset;

        if (glyph_ascent > ascent) {
            ascent = glyph_ascent;
        }
    }

    return ascent;
}

static void draw_character(
    struct framebuffer *framebuffer,
    const GFXfont *font,
    const int cursor_x,
    const int baseline_y,
    const int scale,
    const uint32_t colour,
    unsigned char character)
{
    const GFXglyph *glyph;
    const uint8_t *bitmap;

    int draw_x;
    int draw_y;

    uint8_t bits = 0u;
    uint8_t bits_remaining = 0u;

    character =
        normalise_character(font, character);

    glyph =
        &font->glyph[character - font->first];

    bitmap =
        font->bitmap + glyph->bitmapOffset;

    draw_x =
        cursor_x + (int)glyph->xOffset * scale;

    draw_y =
        baseline_y + (int)glyph->yOffset * scale;

    for (uint8_t y = 0u; y < glyph->height; y++) {
        for (uint8_t x = 0u; x < glyph->width; x++) {
            if (bits_remaining == 0u) {
                bits = *bitmap++;
                bits_remaining = 8u;
            }

            if ((bits & 0x80u) != 0u) {
                fill_rect(
                    framebuffer,
                    draw_x + (int)x * scale,
                    draw_y + (int)y * scale,
                    scale,
                    scale,
                    colour);
            }

            bits <<= 1u;
            bits_remaining--;
        }
    }
}

static void draw_text(
    struct framebuffer *framebuffer,
    const GFXfont *font,
    int cursor_x,
    const int top_y,
    const int scale,
    const uint32_t colour,
    const char *text)
{
    const int baseline_y =
        top_y + font_ascent(font) * scale;

    while (*text != '\0') {
        const unsigned char character =
            (unsigned char)*text;

        if (character == '\n') {
            break;
        }

        draw_character(
            framebuffer,
            font,
            cursor_x,
            baseline_y,
            scale,
            colour,
            character);

        cursor_x +=
            glyph_advance(
                font,
                character,
                scale);

        text++;
    }
}

static void console_newline(
    struct framebuffer *framebuffer,
    const GFXfont *font,
    int *cursor_x,
    int *line_top,
    const int scale,
    const uint32_t background)
{
    const int line_height =
        (int)font->yAdvance * scale;

    *cursor_x = 0;
    *line_top += line_height;

    if (*line_top + line_height >
        (int)framebuffer->variable.yres) {
        scroll_framebuffer(
            framebuffer,
            line_height,
            background);

        *line_top -= line_height;
    }
}

static void clear_console_cell(
    struct framebuffer *framebuffer,
    const GFXfont *font,
    const int cursor_x,
    const int line_top,
    unsigned char character,
    const int scale,
    const uint32_t background)
{
    int width =
        glyph_advance(
            font,
            character,
            scale);

    const int height =
        (int)font->yAdvance * scale;

    if (width < scale) {
        width = scale;
    }

    fill_rect(
        framebuffer,
        cursor_x,
        line_top,
        width,
        height,
        background);
}

static void clear_console_line(
    struct framebuffer *framebuffer,
    const int line_top,
    const int line_height,
    const uint32_t background)
{
    fill_rect(
        framebuffer,
        0,
        line_top,
        (int)framebuffer->variable.xres,
        line_height,
        background);
}

static void console_carriage_return(
    struct framebuffer *framebuffer,
    int *cursor_x,
    const int line_top,
    const int line_height,
    const uint32_t background)
{
    *cursor_x = 0;

    clear_console_line(
        framebuffer,
        line_top,
        line_height,
        background);
}

static void run_console(
    struct framebuffer *framebuffer,
    const GFXfont *font,
    const int scale,
    const uint32_t foreground,
    const uint32_t background)
{
    const int screen_width =
        (int)framebuffer->variable.xres;

    const int line_height =
        (int)font->yAdvance * scale;

    const int baseline_offset =
        font_ascent(font) * scale;

    enum escape_state escape = ESCAPE_NONE;

    int cursor_x = 0;
    int line_top = 0;
    int pending_carriage_return = 0;

    uint8_t input[1024];

    clear_framebuffer(framebuffer, background);

    while (1) {
        const ssize_t count =
            read(
                STDIN_FILENO,
                input,
                sizeof(input));

        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }

            perror("read stdin");
            return;
        }

        if (count == 0) {
            return;
        }

        for (ssize_t index = 0;
             index < count;
             index++) {
            unsigned char character =
                input[index];

            if (pending_carriage_return != 0) {
                pending_carriage_return = 0;

                if (character == '\n') {
                    console_newline(
                        framebuffer,
                        font,
                        &cursor_x,
                        &line_top,
                        scale,
                        background);

                    continue;
                }

                console_carriage_return(
                    framebuffer,
                    &cursor_x,
                    line_top,
                    line_height,
                    background);
            }

            /*
             * Discard common ANSI/VT100 escape sequences.
             */
            if (escape == ESCAPE_STARTED) {
                if (character == '[') {
                    escape = ESCAPE_CSI;
                } else if (character == ']') {
                    escape = ESCAPE_OSC;
                } else {
                    escape = ESCAPE_NONE;
                }

                continue;
            }

            if (escape == ESCAPE_CSI) {
                if (character >= 0x40u &&
                    character <= 0x7eu) {
                    escape = ESCAPE_NONE;
                }

                continue;
            }

            if (escape == ESCAPE_OSC) {
                if (character == 0x07u) {
                    escape = ESCAPE_NONE;
                } else if (character == 0x1bu) {
                    escape = ESCAPE_OSC_ESCAPE;
                }

                continue;
            }

            if (escape == ESCAPE_OSC_ESCAPE) {
                if (character == '\\') {
                    escape = ESCAPE_NONE;
                } else {
                    escape = ESCAPE_OSC;
                }

                continue;
            }

            if (character == 0x1bu) {
                escape = ESCAPE_STARTED;
                continue;
            }

            /*
             * Return to the beginning of the current line.
             *
             * Clearing the line makes simple "\rProgress..." output replace
             * the previous progress message cleanly.
             */
            if (character == '\r') {
                pending_carriage_return = 1;
                continue;
            }

            if (character == '\n') {
                console_newline(
                    framebuffer,
                    font,
                    &cursor_x,
                    &line_top,
                    scale,
                    background);

                continue;
            }

            if (character == '\t') {
                int space_width =
                    glyph_advance(
                        font,
                        ' ',
                        scale);

                int tab_width;

                if (space_width <= 0) {
                    space_width = scale;
                }

                tab_width = space_width * 4;

                cursor_x =
                    ((cursor_x / tab_width) + 1) *
                    tab_width;

                if (cursor_x >= screen_width) {
                    console_newline(
                        framebuffer,
                        font,
                        &cursor_x,
                        &line_top,
                        scale,
                        background);
                }

                continue;
            }

            /*
             * Backspace is approximate because Tom Thumb is proportional.
             * This is sufficient for typical installer logs.
             */
            if (character == '\b' ||
                character == 0x7fu) {
                int backspace_width =
                    glyph_advance(
                        font,
                        'M',
                        scale);

                if (backspace_width <= 0) {
                    backspace_width = scale;
                }

                if (cursor_x >= backspace_width) {
                    cursor_x -= backspace_width;

                    fill_rect(
                        framebuffer,
                        cursor_x,
                        line_top,
                        backspace_width,
                        line_height,
                        background);
                }

                continue;
            }

            if (character < 0x20u) {
                continue;
            }

            character =
                normalise_character(
                    font,
                    character);

            int advance =
                glyph_advance(
                    font,
                    character,
                    scale);

            if (advance <= 0) {
                advance = scale;
            }

            if (cursor_x + advance > screen_width) {
                console_newline(
                    framebuffer,
                    font,
                    &cursor_x,
                    &line_top,
                    scale,
                    background);
            }

            clear_console_cell(
                framebuffer,
                font,
                cursor_x,
                line_top,
                character,
                scale,
                background);

            draw_character(
                framebuffer,
                font,
                cursor_x,
                line_top + baseline_offset,
                scale,
                foreground,
                character);

            cursor_x += advance;
        }
    }
}

static char *join_arguments(
    const int argc,
    char **argv,
    const int first)
{
    size_t total_length = 1u;
    char *result;
    char *position;

    for (int index = first; index < argc; index++) {
        total_length += strlen(argv[index]);

        if (index + 1 < argc) {
            total_length++;
        }
    }

    result = malloc(total_length);

    if (result == NULL) {
        fatal_errno("malloc text");
    }

    position = result;

    for (int index = first; index < argc; index++) {
        const size_t length =
            strlen(argv[index]);

        memcpy(position, argv[index], length);
        position += length;

        if (index + 1 < argc) {
            *position++ = ' ';
        }
    }

    *position = '\0';

    return result;
}

int main(int argc, char **argv)
{
    struct framebuffer framebuffer;

    const char *framebuffer_device = "/dev/fb0";
    const char *command;

    int argument = 1;

    if (argc >= 3 &&
        strcmp(argv[1], "-f") == 0) {
        framebuffer_device = argv[2];
        argument = 3;
    }

    if (argument >= argc) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    command = argv[argument++];

    open_framebuffer(
        &framebuffer,
        framebuffer_device);

    if (strcmp(command, "clear") == 0) {
        uint32_t colour;

        if (argc - argument != 1) {
            usage(argv[0]);
            close_framebuffer(&framebuffer);
            return EXIT_FAILURE;
        }

        colour = parse_rgb(argv[argument]);

        clear_framebuffer(
            &framebuffer,
            colour);
    } else if (strcmp(command, "rect") == 0) {
        int x;
        int y;
        int width;
        int height;
        uint32_t colour;

        if (argc - argument != 5) {
            usage(argv[0]);
            close_framebuffer(&framebuffer);
            return EXIT_FAILURE;
        }

        x = parse_int(argv[argument], "x");
        y = parse_int(argv[argument + 1], "y");

        width =
            parse_int(
                argv[argument + 2],
                "width");

        height =
            parse_int(
                argv[argument + 3],
                "height");

        colour =
            parse_rgb(argv[argument + 4]);

        fill_rect(
            &framebuffer,
            x,
            y,
            width,
            height,
            colour);
    } else if (strcmp(command, "text") == 0) {
        int x;
        int y;
        int scale;
        uint32_t colour;
        char *text;

        if (argc - argument < 5) {
            usage(argv[0]);
            close_framebuffer(&framebuffer);
            return EXIT_FAILURE;
        }

        x = parse_int(argv[argument], "x");
        y = parse_int(argv[argument + 1], "y");

        scale =
            parse_int(
                argv[argument + 2],
                "scale");

        colour =
            parse_rgb(argv[argument + 3]);

        if (scale < 1 || scale > 32) {
            fprintf(
                stderr,
                "Scale must be between 1 and 32\n");

            close_framebuffer(&framebuffer);
            return EXIT_FAILURE;
        }

        text =
            join_arguments(
                argc,
                argv,
                argument + 4);

        draw_text(
            &framebuffer,
            &Terminus12,
            x,
            y,
            scale,
            colour,
            text);

        free(text);
    } else if (strcmp(command, "console") == 0) {
        const int remaining =
            argc - argument;

        const GFXfont *font = &Terminus12;
        int scale = 1;

        uint32_t foreground = 0xffffffu;
        uint32_t background = 0x000000u;

        if (remaining > 4) {
            usage(argv[0]);
            close_framebuffer(&framebuffer);
            return EXIT_FAILURE;
        }

        if (remaining >= 1) {
            font = find_font(argv[argument]);
        }

        if (remaining >= 2) {
            scale =
                parse_int(
                    argv[argument + 1],
                    "scale");

            if (scale < 1 || scale > 32) {
                fprintf(
                    stderr,
                    "Scale must be between 1 and 32\n");

                close_framebuffer(&framebuffer);
                return EXIT_FAILURE;
            }
        }

        if (remaining >= 3) {
            foreground =
                parse_rgb(argv[argument + 2]);
        }

        if (remaining >= 4) {
            background =
                parse_rgb(argv[argument + 3]);
        }

        run_console(
            &framebuffer,
            font,
            scale,
            foreground,
            background);
    } else {
        fprintf(
            stderr,
            "Unknown command: %s\n",
            command);

        usage(argv[0]);
        close_framebuffer(&framebuffer);
        return EXIT_FAILURE;
    }

    /*
     * No msync() call is required. Many framebuffer mappings reject it
     * with EINVAL even though framebuffer writes work correctly.
     */
    close_framebuffer(&framebuffer);

    return EXIT_SUCCESS;
}
