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
python3 - "$TMP/hello.prg" <<'PY'
import sys
p = bytearray()
p += bytes([0x01, 0x04])                 # load address $0401
p += (0x040F).to_bytes(2, 'little')      # next-line ptr
p += (10).to_bytes(2, 'little')          # line number
p += bytes([0x99])                       # PRINT token
p += b' "HELLO PET"'
p += bytes([0x00, 0x00, 0x00])           # end-of-line + end-of-program
open(sys.argv[1], 'wb').write(p)
PY

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
