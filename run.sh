#!/bin/bash

action=$(basename $0)
if [ "$action" = "shell" ]; then
  docker run --rm -ti -v "/tmp:/out" -v "$PWD:/build" pellcorp/creality-firmware /build/actions/shell.sh
else
  if [ -f "$1" ]; then
    fqn=$(realpath $1)
    originals=$(dirname $fqn)

    docker run --rm -v "/tmp:/out" -v "$PWD:/build" -v "$originals:/originals" pellcorp/creality-firmware /build/actions/${action}.sh $1 $2
  else
    docker run --rm -v "$PWD:/build" pellcorp/creality-firmware /build/actions/${action}.sh
  fi
fi
