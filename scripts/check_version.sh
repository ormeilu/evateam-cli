#!/usr/bin/env bash
# Checks that a release tag matches the version in pixi.toml, src/main.mojo and
# recipe/recipe.yaml.
#
#   pixi run check-version v0.12.0
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "$1" >&2
  exit 1
}

tag=${1:?usage: check_version.sh vX.Y.Z}
v=$(sed -n 's/^version = "\([^"]*\)".*/\1/p' pixi.toml | head -1)
[ "$tag" = "v$v" ] || fail "tag $tag != pixi.toml $v"
grep -q "comptime VERSION = \"$v\"" src/main.mojo || fail "src/main.mojo VERSION != $v"
grep -qE "^  version: \"?$v\"?\$" recipe/recipe.yaml || fail "recipe/recipe.yaml version != $v"
echo "version $v matches $tag"
