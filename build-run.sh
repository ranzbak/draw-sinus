#!/bin/bash
if [[ -f sinusstuff.prg ]]; then
  rm sinusstuff.prg
fi

# Build the object
java -jar ../../KickAss.jar sinusstuff.asm

if [[ -f sinusstuff.prg ]]; then
  x64 sinusstuff.prg
fi
