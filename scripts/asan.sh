#!/usr/bin/env bash
# The unit tests and the end-to-end suite under AddressSanitizer: eva talks to
# libc, OpenSSL, the Keychain and libsecret through raw pointers, and this is
# where a mistake in that code shows up as an error instead of a quiet bug.
#
# Mojo instruments with its own LLVM, which is newer than the ASan runtime of
# Xcode's clang, so linking goes through clang and compiler-rt from conda-forge.
#
#   pixi run asan
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=$PWD
OUT=$ROOT/build/asan
ENV=${CONDA_PREFIX:?run this through pixi}
mkdir -p "$OUT"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1

extra=()
[ "$(uname -s)" = Darwin ] && extra=(-s ld64)
with_clang() {
  # shellcheck disable=SC2016  # $CONDA_PREFIX and $@ expand in the inner sh
  pixi exec -c conda-forge -s clang -s compiler-rt "${extra[@]}" -- \
    env MODULAR_HOME="$ENV/share/max" sh -c 'PATH="$CONDA_PREFIX/bin:$PATH" "$@"' sh "$@"
}

status=0
for test in tests/test_*.mojo; do
  name=$(basename "$test" .mojo)
  with_clang "$ENV/bin/mojo" build --sanitize address -I "$ROOT/src" "$ROOT/$test" -o "$OUT/$name" >/dev/null
  if "$OUT/$name" >"$OUT/$name.log" 2>&1; then
    echo "ok   $name: $(grep -E '^Summary' "$OUT/$name.log" | sed 's/^Summary \[[^]]*\] //')"
  else
    echo "FAIL $name"; grep -E 'ERROR: AddressSanitizer|SUMMARY|FAIL' -A3 "$OUT/$name.log" | head -30
    status=1
  fi
done

with_clang "$ENV/bin/mojo" build --sanitize address -I "$ROOT/src" "$ROOT/src/main.mojo" -o "$OUT/eva" >/dev/null
if EVA_BIN=$OUT/eva bash tests/e2e.sh >"$OUT/e2e.log" 2>&1; then
  echo "ok   e2e: $(grep -c '^ok' "$OUT/e2e.log") checks"
else
  echo "FAIL e2e"; grep -E 'FAIL|AddressSanitizer' -A6 "$OUT/e2e.log" | head -40
  status=1
fi
exit $status
