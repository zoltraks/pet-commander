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

## Constants

These values must not be hard-coded ad hoc elsewhere. They are defined once at the top of `src/commander.asm`.

| Constant     | Value   | Meaning                                          |
| ------------ | ------- | ------------------------------------------------ |
| `SCREEN`     | `$8000` | Base of 40x25 screen RAM.                        |
| `PANEL_ROWS` | `20`    | Visible directory rows per panel.                |
| `MAX_ENTRY`  | `64`    | Maximum entries per panel.                       |
| `ENT_SIZE`   | `20`    | Bytes per entry record.                          |
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

`row_addr_sp` computes the screen-RAM address of a given text row into the `sp` pointer so draw routines can write a row without recomputing `row*40 + $8000` inline.

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

Text prompts (`prompt_text`): accept up to 16 PETSCII characters into `prompt_buf`, DEL backspaces, RETURN commits, RUN/STOP cancels.

Yes/no prompt (`prompt_yn`): RETURN or `Y` confirms; any other key cancels.

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
- No file viewer; the `V` key is unimplemented (FR-W1).
- No Move command; on a single drive Move equals Rename (FR-W3).
- Maximum 64 entries per panel (`MAX_ENTRY`).
- The name column shows up to 12 characters; the full 16-character name is kept internally for DOS commands.
- ROM entry-point addresses are PET-3032-specific.
