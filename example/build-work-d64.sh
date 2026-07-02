#!/bin/sh
# Rebuild the example fixture disks for screen-RAM verification.
# work.d64  (drive 8) : "PRIMARY DISK" with a few sample files.
# another.d64 (drive 10) : "ANOTHER DISK" with a long-filename test file.
# Requires c1541 (ships with VICE).

set -e

cd "$(dirname "$0")"

# Ensure the program is built first
( cd .. && [ -f build/commander.prg ] || ./build.sh )

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Tiny PRG: 10 PRINT "HELLO PET"
printf '\x01\x04\x0f\x04\x0a\x00\x99 "HELLO PET"\x00\x00\x00' > "$TMP/hello.prg"

printf 'PRIMARY DISK\nUSE ARROW KEYS\n' > "$TMP/intro.txt"
printf 'A few notes for testing.\n'   > "$TMP/notes.txt"
printf 'PET Commander\n\nThis disk image is a test fixture for the viewer.\n' > "$TMP/rdoc.txt"

c1541 -format "primary disk,01" d64 work.d64 \
      -write ../build/commander.prg "commander,p" \
      -write "$TMP/hello.prg"       "hello,p" \
      -write "$TMP/intro.txt"       "intro,s" \
      -write "$TMP/notes.txt"       "notes,s" \
      -write "$TMP/hello.prg"       "hello2,p" \
      -write "$TMP/intro.txt"       "longname-test,s" \
      -write "$TMP/rdoc.txt"        "zreadme,s"

printf 'attach work.d64\nrename zreadme README\nquit\n' | c1541

# Long-filename test file for drive 10 (CBM DOS max 16 chars)
python3 -c "open('$TMP/longfile.txt','wb').write(b'A' * 12528)"
c1541 -format "another disk,01" d64 another.d64 \
      -write "$TMP/longfile.txt"    "long-filename.te,s"

echo
echo "Built work.d64:"
c1541 work.d64 -list
echo
echo "Built another.d64:"
c1541 another.d64 -list
