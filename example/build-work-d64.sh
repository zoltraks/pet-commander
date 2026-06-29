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

printf 'PET COMMANDER TEST DISK\nUSE ARROW KEYS\n' > "$TMP/readme.txt"
printf 'A few notes for testing.\n'               > "$TMP/notes.txt"

c1541 -format "pet commander,01" d64 work.d64 \
      -write ../build/commander.prg "commander,p" \
      -write "$TMP/hello.prg"       "hello,p" \
      -write "$TMP/readme.txt"      "readme,s" \
      -write "$TMP/notes.txt"       "notes,s" \
      -write "$TMP/hello.prg"       "hello2,p" \
      -write "$TMP/readme.txt"      "longname-test,s"

echo
echo "Built work.d64:"
c1541 work.d64 -list
