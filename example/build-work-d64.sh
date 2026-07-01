#!/bin/sh
# Rebuild example/work.d64 with the commander program and a few
# sample files of mixed types.
# Requires c1541 (ships with VICE).

set -e

cd "$(dirname "$0")"

# Ensure the program is built first
( cd .. && [ -f build/commander.prg ] || ./build.sh )

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Tiny PRG: 10 PRINT "HELLO PET"
# Load address $0401, next-line $040F, line 10, PRINT token $99,
# "HELLO PET", end-of-line $00, end-of-program $00 $00
printf '\x01\x04\x0f\x04\x0a\x00\x99 "HELLO PET"\x00\x00\x00' > "$TMP/hello.prg"

printf 'PET COMMANDER TEST DISK\nUSE ARROW KEYS\n' > "$TMP/intro.txt"
printf 'A few notes for testing.\n'               > "$TMP/notes.txt"

# README.TXT: ASCII prose with mixed case for viewer ASCII/SCREEN
# and UPPER/LOWER charset testing.
# Note: c1541 (VICE 3.7) hangs if any argument to -write contains the
# substring "readme" (host filename or CBM-DOS name). We write the file
# with a safe name then rename it on the disk to README.
printf 'PET Commander\n\nThis disk image is a test fixture for the viewer.\nIt contains a PRG, a few SEQ files, and this README.\nUse the V key to open the viewer, then press A for ASCII\nor S for raw screen codes, and L or U to switch the\ncharacter set between lowercase and uppercase.\n' > "$TMP/rdoc.txt"

c1541 -format "pet commander,01" d64 work.d64 \
      -write ../build/commander.prg "commander,p" \
      -write "$TMP/hello.prg"       "hello,p" \
      -write "$TMP/intro.txt"       "intro,s" \
      -write "$TMP/notes.txt"       "notes,s" \
      -write "$TMP/hello.prg"       "hello2,p" \
      -write "$TMP/intro.txt"       "longname-test,s" \
      -write "$TMP/rdoc.txt"        "zreadme,s"

# Rename zreadme to README on the disk (c1541 rename is not affected
# by the "readme" substring bug).
printf 'attach work.d64\nrename zreadme README\nquit\n' | c1541

echo
echo "Built work.d64:"
c1541 work.d64 -list
