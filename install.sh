#!/bin/sh
# Install or update eva, the EvaTeam CLI, from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
#
# It downloads the release archive for this machine, checks its sha256,
# unpacks it into ~/.local/share/eva/<version> and links ~/.local/bin/eva to it.
# Running it again updates to the newest release; so does `eva upgrade`.
# The archive carries its own Mojo runtime and OpenSSL; nothing else is needed.
#
# Environment:
#   EVA_VERSION       install this version instead of the latest (e.g. 0.2.0)
#   EVA_INSTALL_DIR   where versions are unpacked (default ~/.local/share/eva)
#   EVA_BIN_DIR       where the eva link goes (default ~/.local/bin)
#   EVA_ARCHIVE       install this archive (path or URL) instead of a release
set -eu

REPO=ormeilu/evateam-cli
INSTALL_DIR=${EVA_INSTALL_DIR:-$HOME/.local/share/eva}
BIN_DIR=${EVA_BIN_DIR:-$HOME/.local/bin}

say() { printf '%s\n' "eva-install: $*" >&2; }
die() {
  say "$*"
  exit 1
}

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) target=aarch64-apple-darwin ;;
  Linux-x86_64) target=x86_64-unknown-linux-gnu ;;
  Linux-aarch64 | Linux-arm64) target=aarch64-unknown-linux-gnu ;;
  *) die "no build for $(uname -s) $(uname -m); macOS arm64 and Linux x86_64/arm64 are supported" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${EVA_ARCHIVE:-}" ]; then
  archive=$tmp/$(basename "$EVA_ARCHIVE")
  case "$EVA_ARCHIVE" in
    http://* | https://*) curl -fsSL "$EVA_ARCHIVE" -o "$archive" ;;
    *) cp "$EVA_ARCHIVE" "$archive" ;;
  esac
  version=$(basename "$archive" | sed -n 's/^eva-v\([^-]*\)-.*/\1/p')
  [ -n "$version" ] || die "cannot read a version from $(basename "$archive")"
else
  if [ -n "${EVA_VERSION:-}" ]; then
    version=${EVA_VERSION#v}
  else
    # /releases/latest redirects to /releases/tag/vX.Y.Z; no API token needed.
    latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")
    version=${latest##*/v}
    case "$version" in
      [0-9]*) ;;
      *) die "cannot find the latest release of $REPO" ;;
    esac
  fi
  name=eva-v$version-$target.tar.gz
  base=https://github.com/$REPO/releases/download/v$version
  say "downloading eva $version for $target"
  curl -fsSL "$base/$name" -o "$tmp/$name" || die "no $name in release v$version"
  curl -fsSL "$base/$name.sha256" -o "$tmp/$name.sha256" || die "no checksum for $name"
  want=$(cut -d' ' -f1 <"$tmp/$name.sha256")
  if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$tmp/$name" | cut -d' ' -f1)
  else
    got=$(shasum -a 256 "$tmp/$name" | cut -d' ' -f1)
  fi
  [ "$want" = "$got" ] || die "checksum mismatch for $name"
  archive=$tmp/$name
fi

# The version the link points at now, kept as a fallback after the switch.
previous=""
if [ -L "$BIN_DIR/eva" ]; then
  previous=$(basename "$(dirname "$(dirname "$(readlink "$BIN_DIR/eva")")")")
fi

dest=$INSTALL_DIR/$version
rm -rf "$dest.new"
mkdir -p "$dest.new"
tar xzf "$archive" -C "$dest.new" --strip-components 1
[ -x "$dest.new/bin/eva" ] || die "the archive has no bin/eva"
rm -rf "$dest"
mv "$dest.new" "$dest"

mkdir -p "$BIN_DIR"
ln -sfn "$dest/bin/eva" "$BIN_DIR/eva"

# Keep the version just installed and the one it replaced.
for dir in "$INSTALL_DIR"/*; do
  [ -d "$dir" ] || continue
  case "$(basename "$dir")" in
    "$version" | "$previous") ;;
    *) rm -rf "$dir" ;;
  esac
done

say "$("$BIN_DIR/eva" --version) installed in $dest"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "add $BIN_DIR to PATH" ;;
esac
say "next: eva auth login (asks for your EvaTeam address and API token, keeps them in the OS keychain)"
