# Patching a Creality `zero.bin` boot logo

`patch-zero-bin.py` replaces an embedded JPEG logo in a Creality RTOS
`zero.bin`. It does not modify the input file; it creates a new patched file.

## List available logo slots

```sh
./patch-zero-bin.py --list zero-k1.bin
```

The output shows each logo's slot number, label, resolution, offset, and
maximum JPEG size.

## Create a patched image

```sh
./patch-zero-bin.py --slot 4 zero-k1.bin my-logo.jpg zero-k1-patched.bin
```

Use `--slot` when more than one embedded image has the same dimensions. The
K1's confirmed boot logo is slot `4`, labelled
`creality_landscape_rot180_480x800`.

For the Nebula Pad, a 480x272 JPEG has one matching slot, so no slot number is
needed:

```sh
./patch-zero-bin.py zero-nebula.bin my-logo.jpg zero-nebula-patched.bin
```

The replacement must be a baseline JPEG, have the same dimensions as its
chosen slot, and be no larger than that slot's listed size.

The output `zero.bin` can then be written to the printer's `rtos` partition
using `write-rtos.sh`.
