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
./bdf2gfxfont.py terminus-font-4.49.1/ter-u14n.bdf Terminus14 > Terminus14.h 
```

## Usage

```
root@Ender3V3KE-33E6 /root [#] ./fbtext 
Usage:
  ./fbtext [-f /dev/fb0] clear RRGGBB
  ./fbtext [-f /dev/fb0] rect X Y WIDTH HEIGHT RRGGBB
  ./fbtext [-f /dev/fb0] text X Y SCALE RRGGBB TEXT...
  ./fbtext [-f /dev/fb0] console [FONT [SCALE [FOREGROUND [BACKGROUND]]]]

Examples:
  ./fbtext clear 000000
  ./fbtext rect 10 10 100 40 ff0000
  ./fbtext text 10 10 2 ffffff "Hello world"
  ./install.sh 2>&1 | ./fbtext console terminus
  ./install.sh 2>&1 | ./fbtext console term14 2 ffffff 000000

Console defaults:
  FONT       terminus
  SCALE      1
  FOREGROUND ffffff
  BACKGROUND 000000
```
