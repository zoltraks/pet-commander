# Project Specification

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for what PET Commander must do.

## Vision

PET Commander is a two-panel disk file manager for the Commodore PET 3032, in the spirit of Norton Commander.
It gives the user a fast, keyboard-driven way to view a disk directory and to delete, rename, and copy files without typing CBM-DOS commands by hand.

The program is a single 6502 assembly source assembled to a `$0401` PRG and launched from a D64 disk image under the VICE `xpet` emulator or on real hardware.

## Goals and Non-Goals

### Goals

- Show a disk directory in two side-by-side panels with a selectable, highlighted entry.
- Provide single-key file operations: delete, rename, copy, and re-load.
- Surface drive status after every DOS operation so the user always sees the result.
- Fit and run within PET 3032 constraints: 32 KB RAM, 40x25 text screen, 1 MHz 6502.
- Restore BASIC cleanly on exit so the machine stays usable.

### Non-Goals

- No Move command. On a single drive, Move equals Rename.
- No support for two physical drives or for switching panels to different drive numbers.
- No mouse, no graphics mode, no sound.
- No cross-machine portability beyond PET text-screen models in this version.

## Target Audience

- Commodore PET owners and retro-computing enthusiasts who manage disks on real or emulated hardware.
- Developers studying a complete, non-trivial 6502 assembly application.

## Glossary

- **PET 3032**: Commodore PET model with 32 KB RAM and a 40-column text display.
- **KERNAL**: The Commodore operating-system ROM. Exposes I/O routines via a jump table and internal entry points.
- **CBM-DOS**: The disk operating system running inside the Commodore drive (e.g. 2031, 4040, 8050).
- **PETSCII**: Commodore character encoding. Distinct from the screen-code values poked into screen RAM.
- **Screen code**: The byte value written to screen RAM at `$8000` to display a glyph. Differs from PETSCII.
- **PRG**: A Commodore program file. First two bytes are the load address, little-endian.
- **D64**: A disk-image file representing a 1541/2031-class 5.25-inch floppy.
- **SEQ**: A sequential (text-style) CBM file type.
- **Panel**: One of the two directory views. Each has its own drive, entry list, selection, and scroll position.
- **Zero page**: The first 256 bytes of memory (`$00`-`$FF`). Cheap, fast addressing; partly owned by KERNAL/BASIC.
- **DASM**: The macro assembler used to build the project.
- **VICE**: The emulator suite. `xpet` runs the PET; `c1541` builds disk images.

## Functional Requirements

Requirements use MoSCoW prioritisation. Each has a unique ID.

### Must

- **FR-M1**: The program loads and runs from `$0401` via the BASIC stub `10 SYS1038`.
- **FR-M2**: On startup, both panels load and display the directory of drive 8.
- **FR-M3**: Each panel shows the disk name header and a scrollable list of entries with block count, file name, and type.
- **FR-M4**: One panel is active. Its selected entry is highlighted (reverse video).
- **FR-M5**: TAB or RETURN switches the active panel.
- **FR-M6**: Cursor up/down moves the selection; the list scrolls when selection leaves the visible window. HOME jumps to the first entry.
- **FR-M7**: `L` re-loads the active panel from disk.
- **FR-M8**: `D` deletes (scratches) the selected file after a `Y/N` confirmation.
- **FR-M9**: `N` renames the selected file using a bottom-line text prompt.
- **FR-M10**: `C` copies the selected file to a new name using a bottom-line text prompt.
- **FR-M11**: After every DOS command, the drive status channel is read and shown on the bottom row.
- **FR-M12**: `Q` or RUN/STOP quits to BASIC with the machine left usable.
- **FR-M13**: `V` opens a modal viewer for the selected file. The viewer shows file content in text or hex display.
- **FR-M14**: `H` switches the viewer to hexadecimal display; `T` switches back to text display. The current byte offset is preserved across the switch.
- **FR-M15**: Cursor up/down scrolls the viewer content one row at a time. HOME jumps to the start of the file. Scrolling clamps at the end of the file.
- **FR-M16**: The viewer loads file data in fixed-size chunks from disk. Scrolling within the chunk does not require disk I/O. Scrolling past the chunk boundary reloads from disk.

### Should

- **FR-S1**: Text prompts accept up to 16 PETSCII characters, support DEL backspacing, commit on RETURN, and cancel on RUN/STOP.
- **FR-S2**: Delete confirmation treats RETURN as yes and any other key as cancel.
- **FR-S3**: A drive-not-ready or directory-open failure shows a readable status message instead of hanging.
- **FR-S4**: The viewer opens the file for sequential reading and closes it on every exit path, including open failure, read failure, and user cancellation.
- **FR-S5**: The viewer restores the panel display on close, leaving panel state unchanged.

### Could

- **FR-C1**: Display up to 64 entries per panel.
- **FR-C2**: Keep the full 16-character file name internally even when the column shows fewer characters.

### Won't

- **FR-W1**: No file editing in the viewer; it is read-only.
- **FR-W2**: No second physical drive or per-panel drive selection in this version.
- **FR-W3**: No Move command in this version.
- **FR-W4**: No search or goto-offset in the viewer.
- **FR-W5**: No line-wrap in the viewer text mode; long lines are clipped to the viewer width.

## Non-Functional Requirements

- **NFR-Performance**: The main loop must stay responsive on a 1 MHz 6502. Screen redraws must not introduce visible lag during navigation.
- **NFR-FlickerFree**: Screen updates must be flicker-free. All drawing composes into a back buffer in RAM; a single atomic copy transfers the complete frame to screen RAM during VBLANK. The user never sees a partially updated screen during navigation, file operations, viewer scrolling, or prompt input.
- **NFR-Footprint**: The assembled program plus its buffers must fit comfortably in PET 3032 RAM. Current build is about 8.8 KB of code and data, including the viewer, its 2 KB chunk buffer, and the Present/Blit module. The 1000-byte back buffer lives at a fixed high-RAM address (`$7C00`) outside the PRG.
- **NFR-Stability**: The program must not perform runaway memory writes. It must run for tens of millions of cycles under warp without crashing.
- **NFR-Reentrancy of BASIC**: Borrowed zero-page bytes must be saved on entry and restored on exit so BASIC remains usable.
- **NFR-Output stability**: The PRG load address must remain `$0401` and `SYS 1038` must land on the start vector.
- **NFR-Readability**: Source must follow `standard/asm-6502-development.md` for labels, sections, and comments.

## Use Cases

- **UC-1 Browse a disk**: The user starts the program. Both panels show drive 8. The user moves the selection and scrolls through entries. Expected: the highlighted entry tracks the cursor and the list scrolls smoothly.
- **UC-2 Delete a file**: The user selects a file and presses `D`. The program asks `DELETE? Y/N`. On RETURN the file is scratched, the panel reloads, and the status row shows `01,FILES SCRATCHED,01,00` or an error. 
- **UC-3 Rename a file**: The user selects a file, presses `N`, types a new name, and presses RETURN. The program issues the DOS rename, reloads the panel, and shows status.
- **UC-4 Copy a file**: The user selects a file, presses `C`, types a destination name, and presses RETURN. The program issues the DOS copy, reloads the panel, and shows status.
- **UC-5 Quit cleanly**: The user presses `Q`. The program restores borrowed zero page and returns to BASIC with `READY.`
- **UC-6 View a file**: The user selects a file and presses `V`. The viewer opens showing the start of the file in text mode. The user presses `H` to switch to hex, scrolls with cursor keys, presses `T` to return to text, and presses `Q` to close. The panels reappear unchanged.

## Quality Targets

- **QT-1**: DASM assembly reports `Complete. (0)` with zero errors and zero warnings.
- **QT-2**: The program survives a warp-mode run of at least 100 million cycles in `xpet` with a real D64 mounted, without crashing.
- **QT-3**: `SYS 1038` (`$040E`) lands on the `jmp start` instruction.
- **QT-4**: Every DOS operation results in a visible status line.

## Code Conventions

Authoritative coding rules live in `standard/asm-6502-development.md`. Summary:

- **Labels**: lower_snake_case. Local labels within a routine share a short prefix (e.g. `lp_` inside `load_panel`).
- **Equates and constants**: UPPER_SNAKE_CASE for hardware and layout constants (e.g. `SCREEN`, `PANEL_ROWS`, `ENT_SIZE`).
- **Sections**: Separated by banner comments. Each major section matches a logical module listed in `ARCHITECTURE.md`.
- **Comments**: Explain hardware contracts, register usage, and intent. Do not restate the instruction.

## Current State

- **Completed**: Directory listing, two-panel navigation, delete, rename, copy, file viewer with text and hex modes, DOS status reporting, clean BASIC exit.
- **Known limitations**: Both panels pinned to drive 8, no Move, max 64 entries, 12-character name column, viewer is read-only with no search or line-wrap. See `SPECIFICATION.md` "Known Limitations".
