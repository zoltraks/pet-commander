#!/bin/sh
# Build PET Commander into build/commander.prg, then refresh disk/work.d64.
# Prefers dasm-container Docker image; falls back to local binaries.

set -e

SRC=src/commander.asm
OUT_DIR=build
OUT=$OUT_DIR/commander.prg

mkdir -p "$OUT_DIR"

if command -v docker >/dev/null 2>&1 && docker image inspect dasm >/dev/null 2>&1; then
    docker run --rm -v "$(pwd):/src" dasm dasm "$SRC" -f1 -o"$OUT"
elif command -v dasm >/dev/null 2>&1; then
    dasm "$SRC" -f1 -o"$OUT"
else
    echo "Error: no dasm binary found (docker dasm image or system dasm in PATH)" >&2
    exit 1
fi

echo "Built $OUT"
ls -l "$OUT"

# Refresh the disk fixture so the program inside it stays current.
if [ -x disk/build-work-d64.sh ]; then
    echo
    disk/build-work-d64.sh >/dev/null
    echo "Refreshed disk/work.d64"
fi
