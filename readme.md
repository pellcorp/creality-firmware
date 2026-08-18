# Custom Firmware

This script takes Creality MIPS firmware for various machines including:

- K1, K1C, K1SE and K1M
- Ender 5 Max (F004)
- Ender 3 V3 (F001)
- Ender 3 V3 KE (F005)
- NEBULA

And pre-roots them, adds an emergency factory reset and a way to configure wifi via USB key for emergency reasons.

**I WILL NOT BE HELD RESPONSIBLE IF YOU BRICK YOUR PRINTER - CREATING AND INSTALLING CUSTOM FIRMWARE IS RISKY**

## Creating

To pre-root a downloaded firmware file, its very easy:

```
./create ~/Development/creality/originals/CR4CU220812S11_ota_img_V1.3.3.8.img
```

**Note:** This requires you have docker setup, we build via docker to ensure we have a consistent set of tools

The resulting img file will be located at `/tmpCR4CU220812S11_ota_img_V7.1.3.3.8.img`

### SimpleAF Base Firmware

The `--simpleaf` argument is passed to generate base firmware for installing SimpleAF, currently this is used for
Nebula Pad only, but may be extended in future to other firmware types.

### Testing

It's very important to test this in the safest way possible, luckily creality has provided a way to test
a new firmware image from the cli rather than relying on the display server

```
/etc/ota_bin/local_ota_update.sh /tmp/udisk/sda1/CR4CU220812S11_ota_img_V7.1.3.3.8.img
```

### What is the Root Password?

For all variants it will now be `Creality2023`

## Extracting

Want access to the rootfs, xImage and zero.bin without having to stuff around, I added a extract action to extract the firmware and produce a rootfs.squashfs, xImage and zero.bin.

The rootfs.squashfs you can mount via an image mounter

```
./extract ~/Downloads/CR4CU220812S11_ota_img_V1.3.3.8.img
```

The extracted files will be located at `/tmp/CR4CU220812S11_ota_img_V1.3.3.8/`

## Thanks

Thanks for destinal for providing information about testing the image and thanks to Neon for showing me how to derive the password for the different firmware variants.
