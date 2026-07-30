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

