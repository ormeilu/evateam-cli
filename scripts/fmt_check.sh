#!/usr/bin/env bash
# Fails if `mojo format` would change any file in src/ or tests/. Formats a
# copy, so the working tree is never touched.
#
#   pixi run fmt-check
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R src tests "$tmp/"
mojo format -q "$tmp/src" "$tmp/tests" >/dev/null
if ! diff -ru src "$tmp/src" || ! diff -ru tests "$tmp/tests"; then
  echo "mojo format would change the files above; run: pixi run fmt" >&2
  exit 1
fi
