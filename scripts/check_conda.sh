#!/usr/bin/env bash
# Installs the conda package from output/ with pixi global into a scratch
# PIXI_HOME and runs the e2e suite against it.
#
#   pixi run -e package check-conda
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
PIXI_HOME="$tmp/pixi" pixi global install -c "file://$PWD/output" \
  -c https://conda.modular.com/max -c conda-forge evateam-cli
/usr/bin/env -i PATH=/usr/bin:/bin python3 -m venv "$tmp/venv"
env -i HOME="$HOME" PATH="$tmp/pixi/bin:$tmp/venv/bin:/usr/bin:/bin" \
  EVA_BIN="$tmp/pixi/bin/eva" bash tests/e2e.sh
