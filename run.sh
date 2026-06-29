#!/bin/sh
# Run the program in VICE xpet.
# Usage:  ./run.sh [path-to-disk.d64]
#
# With no argument, mounts example/work.d64 on drive 8 as a 1541 image.
#
# If the system VICE PET ROM directory is missing the actual *.bin ROM
# images, symlink them from a known local copy into ~/.local/share/vice/PET
# so VICE finds them without needing to override its data root (which
# would also disrupt shader lookup under /usr/share/vice/GLSL).

set -e

PRG=build/commander.prg
[ -f "$PRG" ] || ./build.sh

DISK=${1:-example/work.d64}

ensure_roms() {
    SYSTEM_PET=/usr/share/vice/PET
    SYSTEM_DRIVES=/usr/share/vice/DRIVES
    USER_BASE=$HOME/.local/share/vice
    FALLBACK_BASE=/home/desktop/VIRTUAL/COMMODORE/EMULATOR/GTK3VICE-3.7-win64

    pet_ok=1
    [ -f "$SYSTEM_PET/characters-2.901447-10.bin" ] || \
        [ -f "$USER_BASE/PET/characters-2.901447-10.bin" ] || pet_ok=0

    drive_ok=1
    [ -f "$SYSTEM_DRIVES/dos2031-901484-03+05.bin" ] || \
        [ -f "$USER_BASE/DRIVES/dos2031-901484-03+05.bin" ] || drive_ok=0

    [ "$pet_ok" = 1 ] && [ "$drive_ok" = 1 ] && return 0

    if [ ! -d "$FALLBACK_BASE" ]; then
        echo "Error: VICE ROMs not found." >&2
        exit 1
    fi

    if [ "$pet_ok" = 0 ]; then
        echo "Linking PET ROMs into $USER_BASE/PET/ ..."
        mkdir -p "$USER_BASE/PET"
        for rom in characters-2.901447-10.bin \
                   basic-2.901465-01-02.bin \
                   edit-2-n.901447-24.bin \
                   kernal-2.901465-03.bin; do
            ln -sf "$FALLBACK_BASE/PET/$rom" "$USER_BASE/PET/$rom"
        done
    fi

    if [ "$drive_ok" = 0 ]; then
        echo "Linking drive ROMs into $USER_BASE/DRIVES/ ..."
        mkdir -p "$USER_BASE/DRIVES"
        for rom in dos2031-901484-03+05.bin; do
            ln -sf "$FALLBACK_BASE/DRIVES/$rom" "$USER_BASE/DRIVES/$rom"
        done
    fi
}

ensure_roms

exec xpet -model 3032 \
          -drive8type 2031 \
          -autostart "$DISK"
