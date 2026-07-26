# Creating updated .ingenic files

Get hold of an existing .ingenic from Creality, extract that and then just replace the rootfs.squashfs with a later version 

For example, you can grab the existing Ender 3 V3 KE .ingenic and just replace the images/rootfs.squashfs and then just rezip the archive

https://github.com/CrealityOfficial/Ender-3_V3_KE_Klipper/releases/download/V1.1.0.12/Ender-3_V3_KE_1.1.0.12.ingenic

For example I did this to produce a new Ender-3_V3_KE_1.1.0.15.ingenic I did something like this:

```
wget https://github.com/CrealityOfficial/Ender-3_V3_KE_Klipper/releases/download/V1.1.0.12/Ender-3_V3_KE_1.1.0.12.ingenic -O /tmp/Ender-3_V3_KE_1.1.0.12.ingenic
./extract ~/Development/downloads/creality/firmware/originals/Ender-3_V3_KE_F005_ota_img_V1.1.0.15.img
mkdir -p /tmp/ingenic-$$
unzip /tmp/Ender-3_V3_KE_1.1.0.12.ingenic -d /tmp/ingenic-$$
cp /tmp/Ender-3_V3_KE_F005/rootfs.squashfs /tmp/ingenic-$$/images/
cd /tmp/ingenic-$$
zip -r /tmp/Ender-3_V3_KE_1.1.0.15.ingenic *
```

And the `/tmp/Ender-3_V3_KE_1.1.0.15.ingenic` is your updated .ingenic file based on the latest firmware, however please note its **not** prerooted!

You can also use the existing `Ender-3_V3_KE_1.1.0.15.ingenic` to create an .ingenic file for an entirely different target, such as NEBULA

You just have to grab the zero.bin, xImage and rootfs.squashfs from the firmware via the ./extract action

**Note:** I am not entirely sure what the `u-boot-with-spl-mbr-gpt.bin` is for, so trying to build an .ingenic image for a K1 from Ender 3 V3 KE .ingenic
might be problematic.

Thanks for destinal for providing advice on creating updated .ingenic images, including confirming all he did to create the https://www.openk1.org/cfw/NEBULA_1.1.0.26.ingenic was
to replace the 3 files in the images/ directory and rezip.
