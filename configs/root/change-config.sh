#!/bin/sh

[ "$#" -eq 2 ] || exit 1

/root/change-sn.sh "$1" "$2" || exit $?

echo "Recreating config ..."
/etc/init.d/S55klipper_service stop
rm -rf /usr/data/printer_data/config/
/etc/init.d/S55klipper_service start
