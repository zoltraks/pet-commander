# Specification

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for how PET Commander works internally.
It cross-references `src/commander.asm` rather than duplicating large code blocks.

## Data Models

### Entry record

Each directory entry is a fixed `ENT_SIZE` = 20-byte record. See the `entries_p0` / `entries_p1` tables in `src/commander.asm`.

| Offset | Field    | Size | Meaning                                   |
| ------ | -------- | ---- | ----------------------------------------- |
| 0      | blo      | 1    | Block count, low byte.                    |
| 1      | bhi      | 1    | Block count, high byte.                   |
| 2      | type     | 1    | File-type character (e.g. `P`, `S`).      |
| 3..18  | name[16] | 16   | File name, PETSCII, space-padded.         |
| 19     | pad      | 1    | Padding to keep the record 20 bytes wide. |

Records are addressed by `record = table_base + index * 20`. The multiply-by-20 helper is `mul20`; record and entry pointer setup is in `entry_record_sp` and `selected_entry_sp`.

### Per-panel state

Two-element parallel arrays, index 0 = left, 1 = right. Defined near the top of `src/commander.asm`.

| Symbol    | Size      | Meaning                                  |
| --------- | --------- | ---------------------------------------- |
| `p_drive` | 2 bytes   | Device number per panel. Both start `8`. |
| `p_count` | 2 bytes   | Number of valid entries in the panel.    |
| `p_sel`   | 2 bytes   | Selected entry index.                    |
| `p_top`   | 2 bytes   | Index of the first visible row (scroll). |
| `p_title` | 32 bytes  | Disk-name header text per panel.         |

### Global UI state

| Symbol         | Meaning                                              |
| -------------- | ---------------------------------------------------- |
| `active_panel` | `0` = left, `1` = right.                             |
| `quit_flag`    | Nonzero requests exit from `main_loop`.              |
| `status_msg`   | Nonzero means `status_buf` overrides the help row.   |
| `key_val`      | Last key read from `GETIN`.                          |

### Scratch buffers

| Symbol       | Size     | Owner                         |
| ------------ | -------- | ----------------------------- |
| `cmd_buf`    | 48 bytes | DOS command being assembled.  |
| `prompt_buf` | 17 bytes | Text the user is typing.      |
| `savename`   | 16 bytes | Saved source name for ops.    |
| `status_buf` | 41 bytes | Drive status string to show.  |

### Viewer state

Owned by the viewer module. Separate from panel state. Discarded on viewer close.

| Symbol             | Size     | Meaning                                              |
| ------------------ | -------- | ---------------------------------------------------- |
| `view_mode`        | 1 byte   | `0` = text display, `1` = hex display.               |
| `view_top`         | 2 bytes  | Byte offset of the top-left visible byte.            |
| `view_chunk_base`  | 2 bytes  | Byte offset of the first byte in the chunk buffer.   |
| `view_chunk_len`   | 2 bytes  | Number of valid bytes in the chunk buffer.           |
| `view_at_eof`      | 1 byte   | Nonzero if the last chunk read reached end of file.  |
| `view_row_size`    | 1 byte   | Bytes per visible row (`VIEW_TEXT_COLS` or `VIEW_HEX_COLS`). |
| `view_screen_size` | 2 bytes  | Total bytes per screen (`VIEW_ROWS * view_row_size`). |
| `view_page_size`   | 2 bytes  | Bytes per page scroll. Text: `(VIEW_ROWS-1) * VIEW_TEXT_COLS = 760`. Hex: `VIEW_ROWS * VIEW_HEX_COLS = 168`. |
| `view_fname`       | 16 bytes | Copy of the file name being viewed.                  |
| `view_fname_len`   | 1 byte   | Length of the file name in `view_fname`.             |
| `view_chunk`       | 2048 bytes | Chunk buffer for partial file loading.             |

## Constants

These values must not be hard-coded ad hoc elsewhere. They are defined once at the top of `src/commander.asm`.

| Constant     | Value   | Meaning                                          |
| ------------ | ------- | ------------------------------------------------ |
| `SCREEN`     | `$8000` | Base of 40x25 screen RAM. Destination of the blit. |
| `BUFFER`     | `$7C00` | 1000-byte back buffer, page-aligned. Target of all drawing. |
| `VIA_PORTB`  | `$E840` | VIA port B; bit 5 carries the VBLANK signal.     |
| `RETRACE_BIT`| `$20`   | Mask for VIA PB5 (VBLANK: LOW = blank, HIGH = active). |
| `PANEL_ROWS` | `20`    | Visible directory rows per panel.                |
| `PANEL_WIDTH`| `20`    | Columns per panel including frame borders.       |
| `PANEL_INNER`| `18`    | Inner content columns (excluding frame borders). |
| `MAX_ENTRY`  | `64`    | Maximum entries per panel.                       |
| `ENT_SIZE`   | `20`    | Bytes per entry record.                          |
| `VIEW_ROWS`  | `21`    | Visible content rows in the viewer (rows 2-22 inside frame). |
| `VIEW_TEXT_COLS` | `38` | Columns per text-mode row (cols 1-38 inside frame). |
| `VIEW_HEX_COLS`  | `8`  | Bytes per hex-mode row in the viewer.           |
| `VIEW_CHUNK` | `2048`  | Chunk buffer size for partial file loading.      |
| `VIEW_LFN`   | `3`     | Logical file number used by the viewer.          |
| `sp_lo/hi`   | `$FB/$FC` | Borrowed primary indirect pointer.             |
| `dp_lo/hi`   | `$FD/$FE` | Borrowed secondary indirect pointer.           |

### KERNAL and PET ROM symbols

KERNAL jump-table vectors used: `OPEN $FFC0`, `CLOSE $FFC3`, `CHKIN $FFC6`, `CHKOUT $FFC9`, `CLRCHN $FFCC`, `CHRIN $FFCF`, `CHROUT $FFD2`, `GETIN $FFE4`, `CLALL $FFE7`.

PET internal entry points and zero-page locations used by the OPEN/CLOSE wrappers: `PET_OPEN_LOGIC $F524`, `PET_CLOSE_LOGIC $F2AC`, `PET_FNLEN $D1`, `PET_LA $D2`, `PET_SA $D3`, `PET_DEV $D4`, `PET_FNADR_LO $DA`, `PET_FNADR_HI $DB`. KERNAL ZP mirrors: `STATUS $0096`, `BLNSW $00A7`.

The PET has no `SETNAM` or `SETLFS`. The wrappers `pet_setnam` and `pet_setlfs` set the zero-page parameters directly, then call the internal logic. Treat these addresses as PET-3032-specific; they are a portability constraint recorded in `ARCHITECTURE.md`.

## Algorithms

### Directory parse state machine

`load_panel` opens the directory file `$` on the panel's drive, skips the BASIC-style load header, then walks the directory listing one logical line at a time. A small state machine (`lp_state` with the `lp_t_*` and `lp_b_*` blocks) extracts, per entry:

- the leading block count (used as `blo`/`bhi`),
- the quoted file name (copied into `name[16]`, space-padded),
- the trailing type characters (reduced to a single type character).

Parsing stops at end of file or when `MAX_ENTRY` records are filled (`lp_room` guards the cap). On open failure the routine sets the `DRIVE NOT READY` message and returns.

### Selection and scrolling

Navigation keeps the selected index inside the visible window of `PANEL_ROWS` rows.

- `cursor_up` / `cursor_down` adjust `p_sel`, clamping at the ends, and adjust `p_top` so the selection stays visible.
- `do_home` resets `p_sel` and `p_top` to the first entry.
- Only the affected panel is redrawn after a move (`redraw_active`); a panel switch redraws both highlight states.

### Record indexing

`mul20` multiplies an entry index by `ENT_SIZE` (20) using shift-and-add (`index*16 + index*4`) to produce the byte offset into an entry table. `entry_record_sp` and `selected_entry_sp` set the `sp_lo/sp_hi` pointer to a specific record.

### Number formatting

`print_num3` renders a 16-bit block count (`num_lo`/`num_hi`) as a right-justified three-digit field by repeated subtraction of hundreds and tens. Leading zeros are blanked.

### PETSCII to screen code

`petscii_to_screen` converts a PETSCII byte to the screen-code value poked into screen RAM. The PET screen does not use PETSCII directly; the conversion maps the relevant ranges (the `p2s_sub40` path handles the offset range).

### Screen addressing

`row_addr_sp` computes the back-buffer address of a given text row into the `sp` pointer so draw routines can write a row without recomputing `row*40 + $7C00` inline. Its base is `BUFFER`, not `SCREEN`: all `sp`-based drawing composes into the back buffer. The routines that write row 0 or row 24 directly (`draw_title_bar`, `draw_help_bar`, `draw_status`, `draw_prompt_label`, `show_prompt_buf`) and `clear_screen` also target `BUFFER`.

### Present and blit

`present_screen` is called at the end of every redraw entry point and after every interactive row-24 update. It waits for VBLANK then copies the back buffer to screen RAM in one atomic pass.

- `wait_vblank` polls VIA PORT B bit 5 (`$E840` bit 5). The signal is LOW during VBLANK and HIGH during active display. A bounded two-phase wait syncs to the start of VBLANK: phase 1 skips any remaining VBLANK (wait while LOW), phase 2 waits for active display to end (wait while HIGH). Each phase is bounded to 256 iterations so the routine never hangs if the retrace bit is not toggling (e.g. under VICE 3.7 xpet, which does not mirror VBLANK onto VIA PB5). On real hardware the bound is never reached and the routine returns at the start of VBLANK. This is polling, not an IRQ handler; no CINV vector is installed.
- `copy_buffer` copies 1000 bytes from `BUFFER` to `SCREEN` using a page-strided loop (3 full pages of 256 bytes plus a 232-byte tail), mirroring the `clear_screen` pattern. The tail loop uses `txa` before `bne` to test the loop counter (X), not the loaded byte, because `lda` between `dex` and `bne` would overwrite the Z flag. It is the only writer of `SCREEN`.

The 1000-byte copy takes roughly 6000 cycles at 1 MHz, which fits inside the PET VBLANK period.

Present points:

- `full_redraw` (startup, viewer close).
- `redraw_panels` (after file operations and reload).
- `redraw_active` (after cursor moves and panel switch).
- `view_render` (each viewer frame).
- After `draw_status` and `clear_status` (status row updates).
- After `draw_prompt_label`, after each `show_prompt_buf` in the `prompt_text` loop, and after the `prompt_yn` confirmation display (prompt input visibility).

`BUFFER` is at a fixed high-RAM address and is not part of the PRG image, so it is uninitialized on load. `init` clears it (via `clear_screen`, which targets `BUFFER`) before the first `full_redraw`.

### Viewer chunk loading

`view_load_chunk` opens the file named in `view_fname` on the active panel's drive using `pet_setnam`/`pet_setlfs` (LFN = `VIEW_LFN`, SA = 0), calls `CHKIN`, skips `view_chunk_base` bytes by repeated `CHRIN`, then reads up to `VIEW_CHUNK` bytes into `view_chunk` via `CHRIN`, checking `STATUS` after each byte. It sets `view_chunk_len` to the count read and `view_at_eof` if `STATUS` became non-zero before `VIEW_CHUNK` bytes. It then calls `CLRCHN` and `pet_close`. The file is closed on every call, so no channel stays open between renders.

### Viewer scrolling

The chunk buffer covers `VIEW_CHUNK` (2048) bytes starting at `view_chunk_base`. The visible window starts at `view_top` and spans `view_screen_size` bytes. Scrolling within the chunk (the common case) requires no disk I/O.

- `view_scroll_down` adds `view_row_size` to `view_top`. If the window extends past the chunk and the file is not at EOF, it reloads the chunk at the new `view_top`. If at EOF, it clamps `view_top` back.
- `view_scroll_up` subtracts `view_row_size` from `view_top`, clamped at 0. If `view_top` falls below `view_chunk_base`, it reloads the chunk at the new `view_top`.
- `view_page_down` adds `view_page_size` to `view_top`. In text mode, `view_page_size = (VIEW_ROWS - 1) * VIEW_TEXT_COLS = 760` (20 rows, 1-line overlap). In hex mode, `view_page_size = VIEW_ROWS * VIEW_HEX_COLS = 168` (21 rows, no overlap). Reload and clamp logic matches `view_scroll_down`.
- `view_page_up` subtracts `view_page_size` from `view_top`, clamped at 0. Reload logic matches `view_scroll_up`.
- `view_home` sets `view_top` and `view_chunk_base` to 0 and reloads.

Because CBM-DOS sequential files have no backward seek, scrolling up past the chunk re-opens the file and skips forward byte-by-byte. This is the documented trade-off for chunk-based loading.

### Viewer rendering

`view_render` clears the screen, draws a header bar on row 0, draws a content frame (top border row 1, side borders rows 2-22, bottom border row 23), renders `VIEW_ROWS` (21) content rows (rows 2-22), and draws a footer bar on row 24.

- **Header bar (row 0)**: Reverse-video bar with half-block borders (`$E1` left, `$61` right). Shows `VIEW`, the filename, and the current mode (`TEXT` or `HEX`) right-aligned. All content is reversed (bit 7 set).
- **Footer bar (row 24)**: Reverse-video bar with half-block borders. Shows shortcut labels: `T`EXT, `H`EX, `E`XIT. The shortcut letters T, H, E are in normal video; the rest is reversed.
- **Content frame**: Center-line box drawing. Corners `$70`/`$6E` (top), `$6D`/`$7D` (bottom). Horizontal `$40`, vertical `$5D`. In hex mode, T-junctions `$72` (down) at columns 5, 17, 29 and `$71` (up) at column 34 on the top border; `$71` (up) at 5, 17, 29, 34 on the bottom border; vertical dividers `$5D` at 5, 17, 29, 34 on content rows. In text mode, no internal dividers.
- **Text mode**: each content row renders `VIEW_TEXT_COLS` (38) bytes from the chunk buffer at columns 1-38, converting each byte with `petscii_to_screen`. Bytes below `$20` or at/above `$7F` render as a dot placeholder. Bytes past the chunk or EOF render as spaces.
- **Hex mode**: each content row shows a 4-digit hex address at cols 1-4, two groups of 4 hex byte pairs at cols 6-16 and 18-28 (via `write_hex_byte`), and two groups of 4 raw bytes as screen codes at cols 30-33 and 35-38. The ASCII columns store the raw byte value directly (no `petscii_to_screen`, no dot substitution). Bytes past the chunk or EOF render as spaces.

### Byte to hex

`byte_to_hex` converts a byte in A to two hex-digit screen codes: A = high nibble, Y = low nibble. `nibble_to_sc` maps 0-9 to `$30`-`$39` and 10-15 to `$01`-`$06` (screen codes for `A`-`F`).

## Keyboard and Input Bindings

Keys are read with `GETIN` and compared against PETSCII constants. Bindings:

| Key            | Constant   | Action                                  |
| -------------- | ---------- | --------------------------------------- |
| TAB            | `K_TAB $09` | Switch the active panel.                |
| RETURN         | `K_RETURN $0D` | Switch the active panel.             |
| Cursor up      | `K_UP $91` | Move selection up.                      |
| Cursor down    | `K_DOWN $11` | Move selection down.                   |
| HOME           | `K_HOME $13` | Jump to first entry.                  |
| DEL            | `K_DEL $14` | Backspace in a text prompt.            |
| RUN/STOP       | `K_STOP $03` | Quit, or cancel a prompt/confirmation.|
| `L`            | `CH_L $4C` | Re-load the active panel.               |
| `D`            | `CH_D $44` | Delete the selected file.               |
| `N`            | `CH_N $4E` | Rename the selected file.               |
| `C`            | `CH_C $43` | Copy the selected file.                 |
| `Q`            | `CH_Q $51` | Quit to BASIC.                          |
| `Y`            | `CH_Y $59` | Confirm in the delete prompt.           |
| `V`            | `CH_V $56` | Open the viewer on the selected file.   |
| `H`            | `CH_H $48` | Switch the viewer to hex display.       |
| `T`            | `CH_T $54` | Switch the viewer to text display.      |
| `E`            | `CH_E $45` | Exit the viewer, restore panels.        |
| Cursor left    | `K_LEFT $9D` | Viewer page up.                       |
| Cursor right   | `K_RIGHT $1D` | Viewer page down.                    |

Text prompts (`prompt_text`): accept up to 16 PETSCII characters into `prompt_buf`, DEL backspaces, RETURN commits, RUN/STOP cancels.

Yes/no prompt (`prompt_yn`): RETURN or `Y` confirms; any other key cancels.

Viewer keys (`view_loop`): `H` switches to hex, `T` to text, cursor up/down scroll one row, cursor left/right scroll one page, HOME jumps to top, `E`/RUN/STOP closes the viewer. `Q` is ignored in the viewer (reserved for main program quit). The viewer reads keys with `GETIN` from the keyboard (default input after `CLRCHN`).

## DOS Command Construction

File operations build a CBM-DOS command string into `cmd_buf`, then call `send_dos_cmd`.

- **Delete**: `S0:NAME` (scratch). Built by `op_delete`.
- **Rename**: `R0:NEW=OLD`. Built by `op_rename` (`op_ren_build` assembles new and old names around `=`).
- **Copy**: `C0:DST=SRC`. Built by `op_copy` (`op_cp_build`).

`send_dos_cmd` opens logical file 15 on the panel drive with secondary address 15, writes the command, and closes. `read_dos_status` then reads the status channel into `status_buf` and `set_status` stages it for the bottom row.

After a successful mutating operation, the active panel is reloaded so the display reflects the change.

## Error Catalogue

Errors are surfaced as on-screen messages, never as silent failures.

| Condition                  | Message shown          | Source label      |
| -------------------------- | ---------------------- | ----------------- |
| Directory open failed      | `DRIVE NOT READY`      | `msg_no_disk`     |
| Status channel read failed | `STATUS READ FAILED`   | `msg_status_err`  |
| Any DOS result             | raw `NN,TEXT,TT,SS`    | `read_dos_status` |
| Delete prompt              | `DELETE? Y/N`          | `msg_confirm_del` |
| Rename prompt label        | `NEW NAME`             | `msg_new_name`    |
| Copy prompt label          | `COPY TO`              | `msg_copy_to`     |
| Viewer open failed         | `VIEW OPEN FAILED`     | `msg_view_err`    |

The status string is the drive's own channel-15 response, e.g. `00,OK,00,00`, `01,FILES SCRATCHED,01,00`, or `63,FILE EXISTS,00,00`.

## Startup Sequence

- BASIC enters at `$0401`; `SYS 1038` (`$040E`) executes `jmp start`.
- `start` calls `init`: save `BLNSW` and `$FB`-`$FE`, clear global and per-panel state, set both `p_drive` to 8.
- Load both panels with `load_panel`.
- `full_redraw`: clear screen, draw the title bar, frames, help bar, and both panels.
- Enter `main_loop`.

## Shutdown Sequence

- A quit key sets `quit_flag`; `main_loop` falls through to `do_exit` / `exit_program`.
- `restore_zp` writes the saved `BLNSW` and `$FB`-`$FE` values back.
- Control returns to BASIC, which prints `READY.`

## Known Limitations

- Both panels are pinned to drive 8 (FR-W2).
- No Move command; on a single drive Move equals Rename (FR-W3).
- The viewer is read-only; no editing, search, or goto-offset (FR-W1, FR-W4).
- No line-wrap in the viewer text mode; long lines are clipped to `VIEW_TEXT_COLS` (FR-W5).
- Maximum 64 entries per panel (`MAX_ENTRY`).
- The name column shows up to 12 characters; the full 16-character name is kept internally for DOS commands.
- ROM entry-point addresses are PET-3032-specific.
