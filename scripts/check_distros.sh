#!/usr/bin/env bash
# Runs the release archive from dist/ on the oldest Linux distros it claims,
# with a real HTTPS round trip: the bundled libstdc++ and OpenSSL must load and
# the distro's CA bundle must be found. example.com answers the JSON-RPC POST
# with something that is not JSON, which is the point. Needs docker.
#
#   pixi run check-distros
set -euo pipefail
cd "$(dirname "$0")/.."

for img in rockylinux:9 ubuntu:22.04 debian:12; do
  echo "== $img"
  docker run --rm -v "$PWD/dist:/dist:ro" "$img" sh -ec '
    if command -v apt-get >/dev/null; then
      apt-get -qq update >/dev/null && apt-get -qq install -y ca-certificates >/dev/null
    fi
    mkdir /t && tar xzf /dist/eva-*.tar.gz -C /t
    eva=$(ls -d /t/eva-*/bin/eva)
    "$eva" --version
    out=$(EVA_URL=https://example.com EVA_API_KEY=x "$eva" call Ping.ping 2>&1 || true)
    echo "$out"
    case "$out" in *"cannot reach"*|*"could not find libssl"*) exit 1 ;; esac
  '
done
