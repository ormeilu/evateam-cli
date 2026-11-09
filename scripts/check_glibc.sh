#!/usr/bin/env bash
# Checks that build/eva needs no glibc newer than the manylinux_2_34 wheel tag
# promises. Linux only; elsewhere it says so and succeeds.
#
#   pixi run check-glibc
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != Linux ]; then
  echo "check-glibc: not Linux, skipped"
  exit 0
fi
max=$(objdump -T build/eva | grep -o 'GLIBC_[0-9.]*' | sort -V | tail -1)
echo "highest: $max"
[ "$(printf '%s\nGLIBC_2.34\n' "$max" | sort -V | tail -1)" = "GLIBC_2.34" ]
