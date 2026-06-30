# References

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

External knowledge sources for the PET Commander domain. These are consulted, not treated as project requirements.

## Hardware and ROM

- **Commodore PET 3032**: 32 KB RAM, 40x25 text display, 1 MHz MOS 6502. Memory map, screen RAM at `$8000`, and PIA/VIA I/O.
- **PET KERNAL**: jump-table vectors (`$FFC0`-`$FFE7`) and internal entry points used by the OPEN/CLOSE wrappers. The PET KERNAL has no `SETNAM`/`SETLFS`.
- **MOS 6502 instruction set**: opcodes, addressing modes, flags, and cycle counts.

## Disk and File Formats

- **CBM-DOS**: drive command syntax used by the file operations - scratch (`S0:`), rename (`R0:new=old`), copy (`C0:dst=src`) - and the channel-15 status response format `NN,TEXT,TT,SS`.
- **D64 image format**: track/sector layout of a 1541/2031-class image, as produced by `c1541`.
- **PRG format**: two-byte little-endian load address followed by program bytes.
- **PETSCII and screen codes**: the distinction between the PETSCII character set and the screen-code values written to screen RAM.

## Tooling

- **DASM**: macro assembler manual - directives, `processor 6502`, output formats (`-f1` PRG), and the `-o` flag. See also `docs/skill/commodore-pet-skill/utility/dasm-assembler.md`.
- **VICE**: emulator suite manual - `xpet` options (`-model`, `-drive8type`, `-autostart`, `-warp`), the built-in monitor, and `c1541` disk tooling. See also `docs/skill/commodore-pet-skill/utility/vice-emulator.md`.

## Project Skill Package

- **commodore-pet-skill**: the companion skill package that documents PET assembly, the DASM toolchain, VICE debugging, and disk handling. Vendored as a git submodule at `docs/skill/commodore-pet-skill` (upstream: `https://github.com/zoltraks/commodore-pet-skill`). The root `README.md` references its `utility/dasm-assembler.md` and `utility/vice-emulator.md`. Consult it for PET KERNAL addresses, headless VICE debugging recipes, and disk-image workflows. See `README.md` ("Cloning this repository") for how to fetch it.

## Usage Notes

Use these references to validate hardware assumptions, KERNAL and CBM-DOS behaviour, and toolchain invocations. When an address or behaviour in `src/commander.asm` disagrees with a reference, confirm against the actual PET 3032 ROM and the VICE monitor before changing code.
