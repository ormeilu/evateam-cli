#!/usr/bin/env bash
# Installs the release archive from dist/ with install.sh into a scratch HOME
# and runs the e2e suite against it. The archive brings its own Mojo runtime
# and OpenSSL; the venv on PATH only runs the mock server. Needs uv.
#
#   pixi run check-archive
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
uv venv -q --python 3.12 "$tmp/venv"
mkdir "$tmp/home"
archive=$(ls dist/eva-*.tar.gz)
env -i HOME="$tmp/home" PATH="$tmp/venv/bin:/usr/bin:/bin" EVA_ARCHIVE="$PWD/$archive" \
  sh install.sh
env -i HOME="$tmp/home" PATH="$tmp/venv/bin:/usr/bin:/bin" EVA_BIN="$tmp/home/.local/bin/eva" \
  bash tests/e2e.sh
