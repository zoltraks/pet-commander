# PET Commander Assembly Rules

## Scope

This document records what is specific to PET Commander: project structure, the build and test workflow, project conventions, and the few places where this project deliberately overrides the general standard.

General 6502, DASM, and PET conventions -- naming, formatting, comments, section banners, zero-page discipline, flag semantics, KERNAL and hardware facts -- are defined by the commodore-pet-skill, which is the source of truth for this project and is not repeated here. Consult the relevant `docs/skill/commodore-pet-skill/` sections before code analysis, implementation planning, and any code writing or modification, including document-only changes that describe code or implementation behaviour. Where a rule in this file conflicts with that general standard, the rule in this file wins for PET Commander code.

PET Commander is a single-source DASM program targeting the Commodore PET 3032. Hardware specs, PRG format, and load address conventions are defined by the skill.

## Project Structure

```
src/
  commander.asm        # the entire program: code, data, buffers
build/
  commander.prg        # generated PRG (load address $0401)
disk/
  work.d64             # generated fixture disk
  build-work-d64.sh    # regenerates the fixture disk
build.sh               # assemble + refresh disk fixture
run.sh                 # launch in xpet
```

- The whole program is one source file. Inside it, sections are separated by banner comments and ordered to match the modules in `ARCHITECTURE.md`: boot stub, lifecycle, main loop, KERNAL wrappers, navigation, drawing, formatting helpers, directory loader, file operations, DOS channel, prompts, data buffers.
- The project version lives in `src/commander.asm` as `VERSION_MAJOR` and `VERSION_MINOR`, not in a separate file.
- No macros or conditional assembly are in use today. Introduce them only when they reduce duplication without obscuring the memory layout.
- Version-control exclusions: `build/` output and the generated `disk/work.d64` are artifacts (see `IGNORE.md`).

## Project Conventions

These supplement or override the general standard for PET Commander code.

**Formatting overrides**

- Mnemonics are tab-aligned under their label, matching the existing `commander.asm`. This overrides the general 8-space-indent rule; the file predates it and is internally consistent, so do not mix the two within it.
- Preserve CRLF line endings and ASCII encoding in `src/commander.asm`.

**I/O discipline**

- All disk I/O goes through the project's KERNAL wrappers and DOS channel routines. Do not open ad-hoc channels elsewhere.
- Disk I/O uses the project's `pet_setnam`/`pet_setlfs` wrappers and the `PET_OPEN_LOGIC`/`PET_CLOSE_LOGIC` entry points.
- Do not leave a channel open on an error path.

**Screen writes**

- Only the drawing module writes `BUFFER` (the back buffer). Only `copy_buffer` (called by `present_screen`) writes `SCREEN`. Do not write `SCREEN` directly from any other module.
- Compute row addresses with `row_addr_sp`; do not scatter `row*40 + $7C00` math through the code.
- Convert PETSCII to screen codes with `petscii_to_screen`; never poke PETSCII straight into `BUFFER`.
- The `copy_buffer` tail loop must test the loop counter (X), not the loaded byte. Use `txa` before `bne`, or place `dex` after `sta`. The `clear_screen` tail is safe because `sta` does not affect flags; `copy_buffer` inserts `lda` which does. See `docs/skill/commodore-pet-skill/code/standard.md` for the flag-semantics rule.
- `wait_vblank` must be bounded. An unbounded VBLANK poll hangs under VICE 3.7 xpet because VIA PB5 does not toggle. Bound each phase to 256 iterations.

**Helpers and fixed layout**

- Use the existing math and format helpers (`mul20`, `print_num3`) rather than re-deriving multiplication or decimal conversion.
- The 20-byte directory entry record (`blo, bhi, type, name[16], pad`) and the `MAX_ENTRY` cap are assumed across `mul20`, the loader, and the draw routines. Changing them is a behaviour change, not a tidy edit.

**Forbidden**

- Do not self-modify code on the critical path without a comment justifying it and a note in `SPECIFICATION.md`.

## Build

- Development and release build: `./build.sh` (Docker `dasm` image preferred, local `dasm` fallback).
- Refresh the fixture disk: `disk/build-work-d64.sh` (run automatically by `build.sh`).
- For DASM command-line options and Docker invocation, see `docs/skill/commodore-pet-skill/utility/dasm-assembler.md`.

## Testing

Verification is defined in `TESTING.md`. Run the verification loop after every code change.

## Dependencies

This project vendors no libraries. External tools (DASM, VICE) are described in the skill. Docker is optionally used as a container host for DASM when the `dasm` image exists.

Do not add vendored dependencies without a need and a license check per `COPYRIGHTS.md`.
