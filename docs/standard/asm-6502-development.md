# 6502 Assembly Engineering Standards

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

## Scope

This document defines how 6502 assembly is written for PET Commander, a single-source DASM program targeting the Commodore PET 3032. It covers the assembler version, source structure, naming, coding conventions, build, and verification.

It does not cover hardware facts (KERNAL addresses, memory map) - those live in `SPECIFICATION.md` and `REFERENCES.md`. Read it before writing or modifying any code.

## Documentation

- MOS 6502 instruction-set reference: opcodes, addressing modes, flags, cycle counts.
- DASM manual: directives (`processor`, `org`, `byte`, `word`, `ds`), output formats, and command-line flags.
- Commodore PET KERNAL and CBM-DOS references (see `REFERENCES.md`).
- The `docs/skill/commodore-pet-skill/utility/` notes for DASM and VICE (commodore-pet-skill submodule).

## Language Version

- **Processor**: MOS 6502. The source begins with `processor 6502`.
- **Assembler**: DASM. Build with PRG output (`-f1`) and an explicit `-o` output path.
- **Target**: Commodore PET 3032 (32 KB RAM, 40x25 text, screen RAM at `$8000`).

No macros or conditional assembly are in use today. Introduce them only when they reduce duplication without obscuring the memory layout.

## Project Structure

```
src/
  commander.asm        # the entire program: code, data, buffers
build/
  commander.prg        # generated PRG (load address $0401)
example/
  work.d64             # generated example disk
  build-work-d64.sh    # regenerates the example disk
build.sh               # assemble + refresh example disk
run.sh                 # launch in xpet
```

The current project version is stored in `src/commander.asm` as `VERSION_MAJOR` and `VERSION_MINOR`, not in a separate file.

The whole program is one source file. Inside it, sections are separated by banner comments and ordered to match the modules in `ARCHITECTURE.md`: boot stub, lifecycle, main loop, KERNAL wrappers, navigation, drawing, formatting helpers, directory loader, file operations, DOS channel, prompts, data buffers.

Version-control exclusions: `build/` output and the generated `example/work.d64` are artifacts (see `IGNORE.md`).

## Naming Conventions

- **Labels**: lower_snake_case - `load_panel`, `draw_entry`, `send_dos_cmd`.
- **Local labels within a routine**: share a short prefix derived from the routine - `lp_` inside `load_panel`, `op_ren_` inside `op_rename`, `dp_` inside `draw_panel`. This keeps related branch targets grouped and readable.
- **Equates and constants**: UPPER_SNAKE_CASE - `SCREEN`, `PANEL_ROWS`, `MAX_ENTRY`, `ENT_SIZE`, `K_RETURN`, `CH_D`.
- **Zero-page pointer aliases**: short lower-case names - `sp_lo`, `sp_hi`, `dp_lo`, `dp_hi`.
- **Data and buffers**: descriptive lower_snake_case - `entries_p0`, `cmd_buf`, `status_buf`, `p_drive`.
- **Abbreviations**: allowed when they are conventional for the platform (`lo`, `hi`, `ptr`, `sp`, `dp`, `zp`, `dos`, `sa` for secondary address). Avoid inventing new cryptic abbreviations.

## Code Conventions

**Control flow and errors**

- 6502 has no exceptions. Signal success or failure through the carry flag or a documented register, and branch on it.
- Document each routine's contract in a leading comment: inputs (registers, zero page), outputs, and which registers it clobbers.
- Keep error paths reachable. Every routine that can fail must set a visible status message or return a flag the caller checks.

**Registers and zero page**

- Treat A, X, Y as scratch unless a routine documents that it preserves one. State preservation explicitly.
- Borrowed zero-page bytes (`$FB`-`$FE`) and `BLNSW` are saved in `init` and restored in `restore_zp`. Any new borrow of KERNAL/BASIC zero page must follow the same save/restore discipline.
- Use the named pointer aliases for indirect indexed addressing rather than raw addresses.

**I/O discipline**

- All disk I/O goes through the KERNAL wrappers and the DOS channel routines. Do not open ad-hoc channels elsewhere.
- Every `OPEN` has a matching `CLOSE` on all paths, including errors and cancels.

**Screen writes**

- Only the drawing module writes screen RAM. Compute row addresses with `row_addr_sp`; do not scatter `row*40 + $8000` math through the code.
- Convert PETSCII to screen codes with `petscii_to_screen`; never poke PETSCII straight into `$8000`.

**Forbidden patterns**

- Do not insert code or data ahead of the boot stub that would move the `$0401` entry or `SYS 1038` target.
- Do not self-modify code on the critical path without a comment justifying it and a note in `SPECIFICATION.md`.
- Do not replace the PET internal OPEN/CLOSE logic with C64-style `SETNAM`/`SETLFS`.
- Do not leave a channel open on an error path.
- Do not clobber a register a caller relies on without updating its documented contract.

## Formatting and Linting

There is no separate linter for assembly. The assembler is the gate.

- Indent instructions under their label consistently with the surrounding code (the existing file uses tab-aligned mnemonics).
- One instruction per line. Inline comments start with `;` and explain intent, not the opcode.
- Separate major sections with a banner comment block.
- Keep label and mnemonic columns aligned within a section so the listing reads cleanly.
- Preserve CRLF line endings and ASCII encoding.

## Testing

There is no host-side unit-test framework for this target. Verification is build plus emulator behaviour checks, defined in `TESTING.md`.

- **Build verification**: `./build.sh` must report `Complete. (0)`; the PRG must load at `$0401`.
- **Headless smoke**: `xpet -warp` run that proves stability.
- **Behaviour check**: graphical `xpet` session exercising the changed binding or operation against `example/work.d64`.
- **Characterisation**: for parser/formatter changes, snapshot entry tables and screen RAM via the VICE monitor before and after.

## Build

- Development and release build: `./build.sh` (Docker `dasm` image preferred, local `dasm` fallback).
- Direct invocation: `dasm src/commander.asm -f1 -o build/commander.prg`.
- Refresh the example disk: `example/build-work-d64.sh` (run automatically by `build.sh`).

## Dependencies

This project vendors no libraries. External tools are required at build and run time only.

| Tool   | Role                                  | Notes                                  |
| ------ | ------------------------------------- | -------------------------------------- |
| DASM   | Assemble `src/commander.asm` to PRG   | Docker image `dasm` or local binary.   |
| VICE   | `xpet` to run, `c1541` to build disks | 3.7+ recommended; auto-finds ROMs.     |
| Docker | Optional container host for DASM      | Used only if the `dasm` image exists.  |

Do not add vendored dependencies without a need and a license check per `COPYRIGHTS.md`.

## PET and 6502 Specific Rules

- **Endianness**: 6502 is little-endian. Store 16-bit values low byte first (`word` directive handles this; manual pairs are `lo` then `hi`).
- **Block-count and index math**: use the existing helpers (`mul20`, `print_num3`) rather than re-deriving multiplication or decimal conversion.
- **Entry record layout**: the 20-byte record (`blo, bhi, type, name[16], pad`) and `MAX_ENTRY` cap are assumed across `mul20`, the loader, and the draw routines. Changing them is a behaviour change, not a tidy edit.
- **PET vs C64**: the PET KERNAL lacks `SETNAM`/`SETLFS`, and its `OPEN`/`CLOSE` vectors include BASIC parameter parsing. Use the project's `pet_setnam`/`pet_setlfs` wrappers and the internal `PET_OPEN_LOGIC`/`PET_CLOSE_LOGIC` entry points.
- **PETSCII vs screen codes**: keep the two encodings distinct; convert at the boundary with `petscii_to_screen`.
- **Cycle awareness**: the navigation and redraw paths run on a 1 MHz CPU. Prefer clear code, but avoid adding obvious waste (redundant full redraws, recomputed addresses) on those paths.
