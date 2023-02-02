#!/bin/sh

set -x

zig build -Doptimize=ReleaseSafe &> /dev/null

if [ $? -ne 0 ]; then
  echo "Older zig version\n"
  zig build -Drelease-safe &> /dev/null
fi
