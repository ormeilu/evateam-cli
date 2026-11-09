#!/usr/bin/env bash
# Installs the wheel from dist/ into a fresh venv and runs the e2e suite against
# it, outside the pixi environment, as a user would run it. Needs uv.
#
#   pixi run check-wheel
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
uv venv -q --python 3.12 "$tmp/venv"
uv pip install -q --python "$tmp/venv/bin/python" dist/*.whl
env -i HOME="$HOME" PATH="$tmp/venv/bin:/usr/bin:/bin" EVA_BIN="$tmp/venv/bin/eva" \
  bash tests/e2e.sh
