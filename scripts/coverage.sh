#!/usr/bin/env bash
# Line coverage of src/ by the unit tests and the end-to-end suite.
#
# Mojo has no coverage flag, so this goes through LLVM: `mojo build -O0 -g
# --emit llvm` gives IR with source lines, LLVM's gcov pass instruments it,
# clang links it against Mojo's runtime, and the counters of every
# binary into one report per source file (scripts/coverage_report.py).
#
# The numbers are an estimate on the generous side: a line Mojo lowers without
# a branch of its own (a `return` under an `if`, say) can count as run.
#
#   pixi run coverage            # coverage/summary.txt, coverage/missed-lines.txt
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=$PWD
OUT=$ROOT/coverage
OBJ=$OUT/obj
LIB=${CONDA_PREFIX:?run this through pixi}/lib
rm -rf "$OUT"
mkdir -p "$OBJ"

extra=()
[ "$(uname -s)" = Darwin ] && extra=(-s ld64)
tools() {
  pixi exec -c conda-forge -s llvm-tools -s clang -s compiler-rt -s python "${extra[@]}" -- "$@"
}

instrument() { # instrument NAME SOURCE: build $OBJ/NAME with gcov counters
  local name=$1 src=$2
  mojo build -O0 -g -I "$ROOT/src" --emit llvm "$ROOT/$src" -o "$OBJ/$name.ll"
  tools sh -c "
    cd '$OBJ'
    opt -passes=insert-gcov-profiling '$name.ll' -S -o '$name.cov.ll'
    clang -c -Wno-override-module '$name.cov.ll' -o '$name.o'
    clang --coverage '$name.o' -o '$name' -L'$LIB' -lKGENCompilerRTShared -ldl -lpthread -lm -Wl,-rpath,'$LIB'
  "
}

# The gcov pass records absolute .gcda paths, so counters land in $OBJ whatever
# directory a test or an e2e command runs in, and runs of one binary add up.
for test in tests/test_*.mojo; do
  name=$(basename "$test" .mojo)
  echo "== $name"
  instrument "$name" "$test"
  (cd "$OBJ" && "./$name" >"$name.log" 2>&1) || { cat "$OBJ/$name.log"; exit 1; }
  grep -E '^Summary' "$OBJ/$name.log" || true
done

echo "== e2e"
instrument eva src/main.mojo
EVA_BIN=$OBJ/eva bash tests/e2e.sh | tail -1 || true

# IR without a source file of its own; nothing to report.
rm -f "$OBJ"/'<unknown>'.gc* "$ROOT"/'<unknown>'.gc*
tools sh -c "python '$ROOT/scripts/coverage_report.py' '$OBJ' '$ROOT/src' '$OUT'"
echo "uncovered lines per file: coverage/missed-lines.txt"
