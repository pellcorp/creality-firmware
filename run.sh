#!/bin/bash

if [ -f $1 ]; then
  fqn=$(realpath $1)
  originals=$(dirname $fqn)
  action=$(basename $0)
  args="--rm "
  if [ "$action" = "shell" ]; then
    args="-ti"
  fi
  docker run $args -v "/tmp:/out" -v "$PWD:/build" -v "$originals:/originals" pellcorp/creality-firmware /build/actions/${action}.sh $1
else
  echo "FATAL: File $1 not found!"
  exit 1
fi
