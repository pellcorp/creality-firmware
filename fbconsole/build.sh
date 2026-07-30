#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"

PRINTER_IP=
PASSWORD=Creality2023

while true; do
    if [ "$1" = "--printer" ]; then
        shift
        PRINTER_IP=$1
        shift
    elif [ "$1" = "--password" ]; then
        shift
        PASSWORD=$1
        shift
    else
        break
    fi
done

mkdir -p build
ARGS="-std=c11 -O2 -Wall -Wextra -Werror -EL -march=mips32r2 -mhard-float -mfp64 -mnan=2008 -mno-mips16 -mno-micromips -s fbtext.c -o build/fbtext"
docker run --rm --entrypoint /bin/bash -v $PWD:$PWD pellcorp/k1-klipper-fw-build -c "cd $PWD && mips-linux-gnu-gcc $ARGS"

if [ -n "$PRINTER_IP" ]; then
  echo "Uploading to root@$PRINTER_IP ..."
  sshpass -p $PASSWORD scp build/fbtext root@$PRINTER_IP:
fi