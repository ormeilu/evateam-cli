#!/bin/sh
# Install or update eva, the EvaTeam CLI:
#
#   curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
#
# Running it again updates to the latest release; so does `eva upgrade`.
# eva is installed as a pixi global tool from the conda channel on prefix.dev,
# and pixi itself is installed first if it is missing.
#
# Environment:
#   EVA_VERSION   install this version instead of the latest (e.g. 0.2.0)
#   EVA_CHANNEL   conda channel (default https://prefix.dev/ormeilu/ormeilu)
set -eu

CHANNEL=${EVA_CHANNEL:-https://prefix.dev/ormeilu/ormeilu}
PACKAGE=evateam-cli

PIXI_BIN="${PIXI_HOME:-$HOME/.pixi}/bin"

say() { printf '%s\n' "eva-install: $*" >&2; }

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64 | Linux-x86_64 | Linux-aarch64 | Linux-arm64) ;;
  *)
    say "no build for $(uname -s) $(uname -m); macOS arm64 and Linux x86_64/arm64 are supported"
    exit 1
    ;;
esac

if ! command -v pixi >/dev/null 2>&1; then
  if [ -x "$PIXI_BIN/pixi" ]; then
    PATH="$PIXI_BIN:$PATH"
  else
    say "installing pixi (https://pixi.sh)"
    curl -fsSL https://pixi.sh/install.sh | sh
    PATH="$PIXI_BIN:$PATH"
  fi
fi

spec=$PACKAGE
[ -n "${EVA_VERSION:-}" ] && spec="$PACKAGE==$EVA_VERSION"

# A plain reinstall resolves to the newest build, so it doubles as the update.
pixi global install --force-reinstall \
  -c "$CHANNEL" -c https://conda.modular.com/max -c conda-forge \
  "$spec" >&2

say "$("$PIXI_BIN/eva" --version) installed"
case ":$PATH:" in
  *":$PIXI_BIN:"*) ;;
  *) say "add $PIXI_BIN to PATH, or open a new shell" ;;
esac
say "next: put EVA_URL and EVA_API_KEY in ~/.config/eva-cli/env, then run: eva config"
