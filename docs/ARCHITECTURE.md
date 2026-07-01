# Architecture

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for how PET Commander is organised.

## Overview

PET Commander is a single-binary 6502 assembly program. It runs as one cooperative loop on the PET 3032: read a key, dispatch it to a handler, mutate state, redraw the affected screen regions, and repeat until the user quits.

There is no operating system layer beyond the PET KERNAL ROM and the CBM-DOS running inside the disk drive. The program talks to the drive over the IEEE-488 bus through KERNAL I/O routines and reads or writes screen RAM directly at `$8000`.

All source lives in a single file, `src/commander.asm`. The logical modules below are sections of that file, not separate translation units.

## Runtime Topology

```
+-------------------+        IEEE-488 / KERNAL I/O        +------------------+
|  PET 3032 (6502)  | <---------------------------------> |  Disk drive      |
|                   |                                     |  (CBM-DOS 2031)  |
|  commander.prg    |  OPEN "$", read dir / send cmd /    |                  |
|  @ $0401          |  read status channel 15             |  work.d64        |
|                   |                                     |                  |
|  Screen RAM $8000 |  direct poke (40x25 screen codes)   +------------------+
+-------------------+
```

## Module Boundaries

Each module is a labelled section of `src/commander.asm`. Responsibilities are kept narrow.

| Module               | Entry labels                          | Responsibility                                                   |
| -------------------- | ------------------------------------- | --------------------------------------------------------------- |
| Boot stub            | `nextline`, `filler_40d`, `jmp start` | BASIC stub at `$0401` so `SYS 1038` enters the program.         |
| Lifecycle            | `start`, `init`, `exit_program`, `restore_zp` | Save/restore borrowed zero page, set up state, tear down.       |
| Main loop            | `main_loop`, `dispatch_key`           | Read a key, route to a handler, check the quit flag.            |
| KERNAL wrappers      | `pet_setnam`, `pet_setlfs`, `pet_open`, `pet_close` | PET-specific OPEN/CLOSE that bypass BASIC parameter parsing.    |
| Navigation           | `cursor_up`, `cursor_down`, `do_up`, `do_down`, `do_home`, `do_switch` | Move selection, scroll the window, switch active panel.        |
| Screen drawing       | `full_redraw`, `redraw_panels`, `redraw_active`, `clear_screen`, `draw_title_bar`, `draw_frames`, `draw_help_bar`, `draw_status`, `draw_panel`, `draw_panel_header`, `draw_panel_rows`, `draw_entry` | Compose the static frame and dynamic panel content into `BUFFER` (the back buffer). |
| Present / blit       | `present_screen`, `wait_vblank`, `view_flush_pcr`, `copy_buffer` | Wait for VBLANK (poll VIA PB5), flush any staged PCR charset write, and copy `BUFFER` to `SCREEN` in one atomic pass. The only writer of `SCREEN`. The PCR flush applies a staged charset change during the same VBLANK window so character-set switches and content updates appear together. |
| Number / text format | `print_num3`, `mul20`, `petscii_to_screen`, `row_addr_sp`, `panel_entry_sp` | Helpers for block counts, record indexing, and PETSCII-to-screen-code conversion. |
| Directory loader     | `load_panel`                          | Open `$`, run the directory parse state machine, fill the entry buffer. |
| File operations      | `op_delete`, `op_rename`, `op_copy`, `op_cancel`   | Build a CBM-DOS command for the selected entry and send it. Shared cancel path for all three.     |
| DOS channel          | `send_dos_cmd`, `read_dos_status`     | Send a command on channel 15 and read back the status string.   |
| Prompts              | `prompt_text`, `prompt_yn`, `draw_prompt_label`, `show_prompt_buf` | Bottom-line text entry and yes/no confirmation.                 |
| Viewer               | `op_view`, `view_load_chunk`, `view_render`, `view_draw_frame`, `view_draw_header`, `view_draw_footer`, `view_render_text`, `view_render_hex`, `view_loop`, `view_scroll_down`, `view_scroll_up`, `view_page_down`, `view_page_up`, `view_home`, `view_set_mode_params`, `view_set_pcr_charset`, `view_flush_pcr`, `view_apply_charset`, `view_restore_charset`, `ascii_to_screen`, `byte_to_hex` | Modal file viewer with bordered frame, header/footer bars, text and hex display, SCREEN/ASCII render modes, UPPER/LOWER character-set switching with deferred PCR write flushed during VBLANK, PCR save/restore, charset-aware label rendering, chunk-based partial load, row and page scrolling. |
| Data buffers         | `entries_p0`, `entries_p1`, `cmd_buf`, `prompt_buf`, `savename`, `status_buf`, `view_chunk` | Per-panel entry tables, scratch buffers, and the viewer chunk buffer.                     |

What modules must not do:

- Navigation must not perform I/O. It only mutates selection and scroll state, then asks the drawing module to redraw.
- Drawing must not change panel data. It reads state and renders; it never loads or mutates entries.
- File operations must not draw directly. They issue DOS commands and reload, then a redraw is triggered.
- The viewer is a modal overlay. It must not mutate panel state. It reads the selected entry name, opens the file, renders to the back buffer, and restores the panels on close via `full_redraw`. The viewer saves the VIA PCR charset bits on entry and restores them on exit so the machine returns to the uppercase set; the charset switch is applied only while the viewer is interactively displayed, not during `view_load_chunk`.
- The drawing module and viewer render write only `BUFFER`. Only `copy_buffer` (called by `present_screen`) writes `SCREEN`.

## State Domains

State is separated into three domains.

- **Global UI state**: `active_panel`, `quit_flag`, `status_msg`, `key_val`. Which panel is active and what the bottom row shows.
- **Per-panel state**: parallel two-element arrays `p_drive`, `p_count`, `p_sel`, `p_top`, plus the title buffer `p_title`. Index 0 is the left panel, index 1 is the right.
- **Entry data**: two fixed entry tables `entries_p0` and `entries_p1`, each `MAX_ENTRY * ENT_SIZE` bytes. One table per panel.

Scratch buffers (`cmd_buf`, `prompt_buf`, `savename`, `status_buf`) are transient and owned by whichever operation is running.

The viewer owns its own state domain: `view_mode`, `view_charset_mode`, `view_charset`, `view_char_offset`, `saved_pcr_cs`, `view_pcr_pending`, `view_pending_pcr_cs`, `view_top`, `view_chunk_base`, `view_chunk_len`, `view_at_eof`, `view_row_size`, `view_screen_size`, `view_page_size`, `view_fname`, `view_fname_len`, and the `view_chunk` buffer. This state is separate from panel state. `view_mode`, `view_charset_mode`, and `view_charset` persist across viewer opens within one program run; the rest reset on each open. `saved_pcr_cs` holds the PCR charset bits saved on entry and restored on exit. `view_pcr_pending` and `view_pending_pcr_cs` stage a deferred PCR charset write that `present_screen` flushes during VBLANK so the charset change and the content blit appear together.

## Data Flow

Primary input-to-output pipeline for a file operation:

```
key press
  -> GETIN (KERNAL)
  -> dispatch_key            (route by PETSCII value)
  -> op_delete / op_rename / op_copy
       -> selected_entry_sp  (locate the record)
       -> build command into cmd_buf
       -> send_dos_cmd       (OPEN 15, write command, CLOSE)
       -> read_dos_status    (CHKIN 15, read status string)
       -> set_status         (stage the bottom-row message)
       -> load_panel         (reload the active panel from disk)
  -> redraw_active / full_redraw
  -> screen RAM at $8000
```

Navigation skips the DOS stages: a cursor key updates `p_sel` / `p_top` and triggers only a redraw.

## Memory Map

| Region            | Address range     | Use                                                       |
| ----------------- | ----------------- | -------------------------------------------------------- |
| Borrowed ZP       | `$FB`-`$FE`       | Two indirect pointers (`sp_lo/hi`, `dp_lo/hi`). Saved and restored. |
| KERNAL ZP mirrors | `$0096`, `$00A7`  | `STATUS`, `BLNSW` (cursor-blink switch).                  |
| PET OPEN/CLOSE ZP | `$D1`-`$DB`       | Filename length, logical/secondary/device numbers, filename pointer. |
| Program load      | `$0401`           | PRG load address. BASIC stub, then code and data.         |
| Screen RAM        | `$8000`           | 40x25 = 1000 screen-code bytes. Destination of the blit.   |
| Back buffer       | `$7C00`           | `BUFFER`, 1000 bytes, page-aligned. Target of all drawing. |
| Entry tables      | within program    | `entries_p0`, `entries_p1` at the tail of the binary.     |
| Viewer chunk      | within program    | `view_chunk` (2048 bytes) at the tail of the binary.      |

The program borrows zero-page bytes `$FB`-`$FE` (KERNAL tape pointers, safe while tape is idle). Their original values are saved in `saved_fb`..`saved_fe` at start and restored at exit.

## Component Interaction

- The **main loop** is the only place that reads the keyboard. It owns control flow.
- **Handlers** are leaf operations invoked by the dispatcher. They return to the loop.
- The **directory loader**, **DOS channel**, and **viewer** are the only modules that perform IEEE-488 I/O.
- The **drawing module** and the **viewer render** write only the back buffer `BUFFER`. The **present/blit module** is the only writer of `SCREEN`, called at the end of each redraw entry point and after each interactive row-24 update.

This keeps I/O and rendering on separate, auditable seams.

## Architectural Decisions

- **AD-1 Single source file**
  - **Decision**: Keep the whole program in `src/commander.asm`.
  - **Rationale**: The program is small. DASM builds one file trivially, and a single file keeps the memory layout and label scope obvious.
  - **Trade-off**: The file is long. Mitigated by banner-comment sections that map one-to-one to the modules above.

- **AD-2 Call PET internal OPEN/CLOSE logic directly**
  - **Decision**: Use `PET_OPEN_LOGIC` (`$F524`) and `PET_CLOSE_LOGIC` (`$F2AC`) with our own `pet_setnam` / `pet_setlfs` instead of the KERNAL `OPEN`/`CLOSE` vectors.
  - **Rationale**: The PET has no `SETNAM`/`SETLFS` (those are C64-only), and its `OPEN`/`CLOSE` jump-table entries include BASIC parameter parsing that we must skip.
  - **Trade-off**: Couples the program to specific PET ROM addresses. Recorded as a portability constraint.

- **AD-3 Borrow zero page `$FB`-`$FE`**
  - **Decision**: Use the tape buffer pointers for indirect addressing.
  - **Rationale**: Indirect indexed addressing needs zero-page pointers; these bytes are free while tape is idle.
  - **Trade-off**: Must save and restore them so BASIC keeps working. Handled by `init` and `restore_zp`.

- **AD-4 Two fixed entry tables instead of dynamic allocation**
  - **Decision**: Statically reserve `entries_p0` and `entries_p1`.
  - **Rationale**: No heap on a 6502. Fixed tables make indexing (`mul20`) and bounds simple.
  - **Trade-off**: A hard cap of `MAX_ENTRY` (64) entries per panel.

- **AD-5 Autostart from a D64 image**
  - **Decision**: Ship and launch the program from inside `example/work.d64`, not as a bare PRG.
  - **Rationale**: VICE Inject mode does not reliably set BASIC pointers for a `$0401` PRG, producing `?SYNTAX ERROR IN 10`. Disk autostart uses BASIC's real LOAD path, which sets every pointer correctly and leaves the disk mounted on drive 8.
  - **Trade-off**: The build must refresh the copy of the program inside the D64. Handled by `build.sh` and `example/build-work-d64.sh`.

- **AD-6 Viewer as modal overlay with chunk-based partial load**
  - **Decision**: The viewer is a modal overlay that covers the panels, owns its own state and chunk buffer, and restores the panels via `full_redraw` on close. File data is loaded in fixed-size chunks (`VIEW_CHUNK` = 2048 bytes) from a sequential read channel.
  - **Rationale**: A modal overlay avoids mutating panel state. Chunk-based loading keeps memory bounded (one 2 KB buffer) while allowing scrolling within a chunk without disk I/O. CBM-DOS sequential files have no backward seek, so scrolling up past the chunk re-opens and skips forward.
  - **Trade-off**: Upward scroll past the chunk boundary is expensive (byte-by-byte skip from file start). The chunk is larger than one screenful (880 bytes for text, 176 for hex) so most scrolling stays within the chunk.

- **AD-7 Double-buffered rendering with VBLANK-synced blit**
  - **Decision**: All drawing composes into a 1000-byte back buffer `BUFFER` at `$7C00`. A `present_screen` routine waits for VBLANK by polling VIA PORT B bit 5, then copies `BUFFER` to `SCREEN` (`$8000`) in one atomic page-strided pass. `copy_buffer` is the sole writer of `SCREEN`.
  - **Rationale**: Writing directly to `SCREEN` while the display is drawn causes visible flicker on cursor moves, panel reloads, and viewer scrolling. Composing off-screen and blitting during VBLANK eliminates the partial-update window. Polling (not an IRQ handler) keeps the clean BASIC exit path unchanged: no CINV vector is installed.
  - **Trade-off**: Every present copies the full 1000 bytes (~6000 cycles at 1 MHz), which fits inside the PET VBLANK period. The back buffer occupies `$7C00` in the region BASIC uses for its string pool; on a fresh disk autostart no strings are allocated, so the region is free during the run and BASIC's pointers are untouched on exit.
  - **Bounded poll**: The VBLANK poll is bounded to 256 iterations per phase. VICE 3.7 xpet does not mirror VBLANK onto VIA PB5, so an unbounded poll hangs forever under VICE. The bound expires and the blit proceeds without sync -- still flicker-free because the full 1000-byte copy is atomic relative to a single `GETIN` poll. On real hardware the bound is never reached.
  - **Tail loop flag hazard**: The `copy_buffer` tail uses `txa` before `bne` to test the loop counter (X), not the loaded byte. Without `txa`, `lda` between `dex` and `bne` overwrites the Z flag; if the buffer tail contains no `$00` bytes, the loop never exits at X=0 and writes past `$83E7`, corrupting KERNAL variables and I/O registers. See `docs/skill/commodore-pet-skill/system/screen.md` and `docs/skill/commodore-pet-skill/code/standard.md` for the full flag-semantics rule.

- **AD-8 Viewer character-set and render-mode controls**
  - **Decision**: The viewer text mode defaults to SCREEN (raw screen codes, no conversion) and adds an ASCII render mode that translates file bytes to screen codes for the active character set. UPPER/LOWER character-set switching uses read-modify-write on VIA PCR (`$E84C`) bits 3:1, preserving CB2. The PCR write is deferred: `view_set_pcr_charset` sets `view_char_offset` immediately and stages the PCR bits into `view_pending_pcr_cs` with `view_pcr_pending` set; `view_flush_pcr` (called by `present_screen` between `wait_vblank` and `copy_buffer`) applies the staged write during VBLANK so the charset change and the new content appear together with no flicker. On entry `op_view` saves the PCR charset bits and stages the viewer's persisted charset flag; the first `view_render` present flushes it. On exit `view_restore_charset` stages the restore; `full_redraw`'s present flushes it, always returning to the uppercase set. The header and footer fixed labels render as uppercase in either set via a `view_char_offset` byte (`$00` UPPER, `$40` LOWER) ORed into letter screen codes; the header filename is converted once and intentionally follows the active charset as a visible indicator. `view_mode`, `view_charset_mode`, and `view_charset` persist across viewer opens.
  - **Rationale**: Raw screen-code display is the natural default for a byte viewer on a PET. ASCII translation with charset awareness lets users read text files correctly in either set. Saving and restoring PCR keeps the machine usable after exit and avoids leaving the drive's NDAC line in an unknown state. Inverse-video uppercase for lowercase ASCII letters in the uppercase set keeps lowercase text visible without adding glyphs. Deferring the PCR write to the VBLANK flush eliminates the one-frame partial-update window where the old content was shown under the new character set; this extends the double-buffering principle to the display control register.
  - **Trade-off**: The PCR save/restore and the staging seam in `op_view` must be honoured on every exit path. The `view_char_offset` mechanism assumes label letters are written as screen codes in the `$01`-`$1A` range, so any new label must apply the offset or it will misrender in LOWER. The pending flag is viewer-owned state; main-program present calls pay a single load-and-branch test to skip the no-op flush.

## Error Handling

- **Directory open failure**: `load_panel` shows `DRIVE NOT READY` instead of hanging.
- **DOS command errors**: surfaced as the raw status string read from channel 15 (e.g. `63,FILE EXISTS,00,00`).
- **Status read failure**: `read_dos_status` falls back to `STATUS READ FAILED`.
- **User cancellation**: prompts and the delete confirmation cancel cleanly on RUN/STOP or a non-yes key, leaving state unchanged.
- **Viewer open failure**: `op_view` shows `VIEW OPEN FAILED` on the status row and returns to the panels without opening the viewer.
- **Viewer read failure**: EOF and read errors during chunk loading set the `view_at_eof` flag; the viewer renders available bytes and pads the rest with spaces.

## Extensibility

- **Per-panel drive selection**: `p_drive` is already a per-panel array. A future change can let a key change a panel's drive number and reload, without touching the rendering seam.
- **Viewer search or goto-offset**: a new handler in `view_loop` that adjusts `view_top` and reloads the chunk; the chunk infrastructure already supports arbitrary offsets.
- **More entries**: raising `MAX_ENTRY` is a constants change plus a check that the entry tables still fit in RAM.

These seams are why navigation, drawing, and I/O are kept apart.
