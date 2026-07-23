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
docker build . -t pellcorp/creality-firmware
./create ~/Downloads/CR4CU220812S11_ota_img_V1.3.3.8.img
```

This now works via Docker to ensure that the same tools are used for every firmware file

**NOTE:** You will be required to enter your `sudo` password

The resulting img file will be located at `/tmpCR4CU220812S11_ota_img_V6.1.3.3.8.img`

### Testing

It's very important to test this in the safest way possible, luckily creality has provided a way to test
a new firmware image from the cli rather than relying on the display server

```
/etc/ota_bin/local_ota_update.sh /tmp/udisk/sda1/CR4CU220812S11_ota_img_V6.1.3.3.8.img
```

### What is the Root Password?

- For NEBULA it's `creality`
- For Ender 3 V3 KE it's `Creality2023`
- For K1 variants it's `creality_2023`
- For others it's whatever the default is!

## Decrypting

Want access to the rootfs without having to stuff around, I added a decrypt action to extract the firmware and produce a .rootfs.squashfs that you
can mount via an image mounter

```
docker build . -t pellcorp/creality-firmware
./decrypt ~/Downloads/CR4CU220812S11_ota_img_V1.3.3.8.img
```

The resulting file will be located at `/tmp/CR4CU220812S11_ota_img_V1.3.3.8.rootfs.squashfs`

## Thanks

Thanks for destinal for providing information about testing the image and thanks to Neon for showing me how to derive the password for the different firmware variants.
