# Custom Firmware

A script to create custom firmware providing firmware for the k1 that has been pre-rooted, ssh-enabled and 
my emergency firmware factory reset feature installed.  This is very minimal changes on top of the default
firmware it is not to compete with the pre-rooted firmware from Destinal which includes Moonraker, Fluidd, etc

**I WILL NOT BE HELD RESPONSIBLE IF YOU BRICK YOUR PRINTER - CREATING AND INSTALLING CUSTOM FIRMWARE IS RISKY**

## Why I did it?

I mostly did this so I could iterate my Simple AF K1 Klipper project, because factory resetting, configuring WIFI,
 then enabling root takes at least 1 minute.   With my `S58factoryreset` process it leaves the wifi configuration
 alone.

 I was considering packaging my Simple AF K1 Klipper as a firmware image, but I actually don't think that is such
 a good idea, as all you can do is create a `/etc/init.d` file that gets triggered on startup to actually
 do the install, and the user has no idea whether it succeeded or not!

## Creating

Then you can create a new firmware file, currently without any customisations just to test things work with:

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
