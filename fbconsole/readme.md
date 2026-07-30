# A basic fbconsole tool

So I can display installer output directly to the screen

## Terminus Font 

Fonts from https://sourceforge.net/projects/terminus-font/files/terminus-font-4.49/terminus-font-4.49.1.tar.gz/download

So for example:

```
curl -fL \
  'https://sourceforge.net/projects/terminus-font/files/terminus-font-4.49/terminus-font-4.49.1.tar.gz/download' \
  -o terminus-font-4.49.1.tar.gz

tar xzf terminus-font-4.49.1.tar.gz
./bdf2gfxfont.py terminus-font-4.49.1/ter-u12n.bdf Terminus12 > Terminus12.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u14n.bdf Terminus14 > Terminus14.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u18n.bdf Terminus18 > Terminus18.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u20n.bdf Terminus20 > Terminus20.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u22n.bdf Terminus22 > Terminus22.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u24n.bdf Terminus24 > Terminus24.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u28n.bdf Terminus28 > Terminus28.h
./bdf2gfxfont.py terminus-font-4.49.1/ter-u32n.bdf Terminus32 > Terminus32.h
```

## Usage

```
root@Ender3V3KE-33E6 /root [#] ./fbtext 
Usage:
  ./fbtext [-f /dev/fb0] [-r 0|90|180|270] clear RRGGBB
  ./fbtext [-f /dev/fb0] [-r 0|90|180|270] rect X Y WIDTH HEIGHT RRGGBB
  ./fbtext [-f /dev/fb0] [-r 0|90|180|270] text X Y SCALE RRGGBB TEXT...
  ./fbtext [-f /dev/fb0] [-r 0|90|180|270] console [FONT [SCALE [FOREGROUND [BACKGROUND]]]]
  ./fbtext [-f /dev/fb0] [-R 0|1|2|3] clear RRGGBB
  ./fbtext [-f /dev/fb0] [-R 0|1|2|3] rect X Y WIDTH HEIGHT RRGGBB
  ./fbtext [-f /dev/fb0] [-R 0|1|2|3] text X Y SCALE RRGGBB TEXT...
  ./fbtext [-f /dev/fb0] [-R 0|1|2|3] console [FONT [SCALE [FOREGROUND [BACKGROUND]]]]

Examples:
  ./fbtext clear 000000
  ./fbtext -r 90 clear 000000
  ./fbtext -R 3 clear 000000
  ./fbtext rect 10 10 100 40 ff0000
  ./fbtext text 10 10 2 ffffff "Hello world"
  ./install.sh 2>&1 | ./fbtext console terminus
  ./install.sh 2>&1 | ./fbtext -r 270 console term14 2 ffffff 000000
  ./install.sh 2>&1 | ./fbtext -R 3 console term14 2 ffffff 000000

Console defaults:
  ROTATION   0
  FONT       terminus
  SCALE      1
  FOREGROUND ffffff
  BACKGROUND 000000
```
