#!/bin/sh
# Run the program in VICE xpet.
# Usage:  ./run.sh [path-to-disk.d64]
#
# With no argument, mounts disk/work.d64 on drive 8 as a 2031 image.
#
# VICE 3.7+ finds ROMs automatically from the bindist directory (Windows)
# or system/user paths (Linux). If ROMs are missing, see the skill docs
# in utility/vice-emulator.md for manual setup instructions.

set -e

PRG=build/commander.prg
[ -f "$PRG" ] || ./build.sh

DISK=${1:-disk/work.d64}

if ! command -v xpet >/dev/null 2>&1; then
    echo "Error: xpet not found in PATH" >&2
    exit 1
fi

exec xpet -model 3032 \
          -drive8type 2031 \
          -autostart "$DISK"
