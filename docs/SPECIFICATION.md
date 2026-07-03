# Specification

This file is the authoritative source for how PET Commander works internally.
It cross-references `src/commander.asm` rather than duplicating large code blocks.

## Data Models

### Entry record

Each directory entry is a 20-byte record containing block count, file type, and a 16-character PETSCII name. Records are addressed by index with a multiply-by-20 helper.

### State domains

- **Global UI state**: active panel, quit request, status message override, and last key value.
- **Per-panel state**: drive number, entry count, selection index, scroll position, and disk title for each panel.
- **Scratch buffers**: transient buffers owned by the operation in progress (DOS command, prompt input, saved source name, status string).
- **Viewer state**: display mode, character set, scroll offset, chunk boundaries, and a partial-load buffer. Some flags persist across viewer opens; per-open state resets each time.

The exact field names, sizes, and constants are defined in `src/commander.asm`.

## Algorithms

### Directory parsing

`load_panel` opens the directory file `$` on the panel's drive, skips the BASIC load header, and walks the listing one logical line at a time. A state machine extracts the block count, file name, and type for each entry, stopping at EOF or when the entry cap is reached. Open failure produces the `DRIVE NOT READY` message.

### Navigation and scrolling

Navigation keeps the selected index inside the visible window. Cursor up/down adjust the selection and scroll position, clamping at the ends. HOME resets to the first entry. Only the affected panel is redrawn after a move; a panel switch redraws both highlight states.

### Rendering and blit

All drawing composes into a back buffer in RAM. `present_screen` waits for VBLANK, flushes any staged PCR charset write, and copies the back buffer to screen RAM in one atomic pass. This eliminates flicker during navigation, reloads, scrolling, and prompt input. The VBLANK poll is bounded so it never hangs under emulators that do not expose the retrace signal.

### Viewer

The viewer loads file data in fixed-size chunks from a sequential read channel. Scrolling within the current chunk needs no disk I/O; scrolling past the chunk boundary reloads from the new offset. Because CBM-DOS sequential files have no backward seek, scrolling up past the chunk re-opens the file and skips forward to the target offset.

The viewer renders inside a bordered frame with a header and footer. Text mode supports SCREEN (raw screen codes) and ASCII (translated screen codes) render modes. Hex mode shows an offset, hex byte pairs, and raw bytes. Non-printable ASCII bytes render as a dot placeholder. The header and footer labels are rendered so they stay uppercase in either character set.

### Character-set switching

The viewer switches between UPPER and LOWER character sets via the VIA PCR register. The PCR write is staged and flushed during the same VBLANK as the back-buffer copy, so the content and the charset appear together. The original PCR bits are saved on viewer entry and restored on exit so the machine returns to the uppercase set.

### ASCII translation

`ascii_to_screen` maps ASCII file bytes to PET screen codes for the active character set. Lowercase letters in the uppercase set become reverse-video uppercase so they remain visible.

## Keyboard and Input Bindings

Keys are read with `GETIN` and compared against PETSCII constants.

| Key               | Action                                        |
|-------------------|-----------------------------------------------|
| TAB / RETURN      | Switch the active panel.                      |
| Cursor up/down    | Move selection.                               |
| HOME              | Jump to first entry.                          |
| DEL               | Backspace in a text prompt.                   |
| RUN/STOP          | Quit, or cancel a prompt/confirmation.        |
| L                 | Re-load the active panel.                     |
| D                 | Delete the selected file.                     |
| N                 | Rename the selected file.                     |
| C                 | Copy the selected file.                       |
| Q                 | Quit to BASIC.                                |
| Y                 | Confirm in the delete prompt.                 |
| V                 | Open the viewer on the selected file.         |
| H                 | Switch the viewer to hex display.             |
| T                 | Switch the viewer to text display.            |
| A                 | Switch the viewer text mode to ASCII render.  |
| S                 | Switch the viewer text mode to SCREEN render. |
| L                 | Switch the viewer character set to LOWER.     |
| U                 | Switch the viewer character set to UPPER.     |
| E                 | Exit the viewer, restore panels.              |
| Cursor left/right | Viewer page up / page down.                   |

Text prompts accept up to 16 PETSCII characters; DEL backspaces, RETURN commits, RUN/STOP cancels. The yes/no prompt treats RETURN or `Y` as confirm; any other key cancels. `Q` is ignored inside the viewer because it is reserved for quitting the main program.

## DOS Command Construction

File operations build a CBM-DOS command string into `cmd_buf`, then call `send_dos_cmd`.

- **Delete**: `S0:NAME` (scratch). Built by `op_delete`.
- **Rename**: `R0:NEW=OLD`. Built by `op_rename` (`op_ren_build` assembles new and old names around `=`).
- **Copy**: `C0:DST=SRC`. Built by `op_copy` (`op_cp_build`).

`send_dos_cmd` opens logical file 15 on the panel drive with secondary address 15, writes the command, and closes. `read_dos_status` then reads the status channel into `status_buf` and `set_status` stages it for the bottom row.

After a successful mutating operation, the active panel is reloaded so the display reflects the change.

## Error Catalogue

Errors are surfaced as on-screen messages, never as silent failures.

| Condition                  | Message shown        |
|----------------------------|----------------------|
| Directory open failed      | `DRIVE NOT READY`    |
| Status channel read failed | `STATUS READ FAILED` |
| Any DOS result             | raw `NN,TEXT,TT,SS`  |
| Delete prompt              | `DELETE? Y/N`        |
| Rename prompt label        | `NEW NAME`           |
| Copy prompt label          | `COPY TO`            |
| Viewer open failed         | `VIEW OPEN FAILED`   |

The status string is the drive's own channel-15 response, e.g. `00,OK,00,00`, `01,FILES SCRATCHED,01,00`, or `63,FILE EXISTS,00,00`.

## Startup Sequence

- BASIC enters the program at `$0401` via `SYS 1038`.
- Initialise state, save borrowed zero-page bytes, and load both panels from drive 8.
- Draw the full screen and enter the main loop.

## Shutdown Sequence

- A quit key exits the main loop.
- Restore borrowed zero-page bytes and return to BASIC.

## Known Limitations

- Both panels are pinned to drive 8 (FR-W2).
- No Move command; on a single drive Move equals Rename (FR-W3).
- The viewer is read-only; no editing, search, or goto-offset (FR-W1, FR-W4).
- No line-wrap in the viewer text mode; long lines are clipped to `VIEW_TEXT_COLS` (FR-W5).
- Maximum 64 entries per panel (`MAX_ENTRY`).
- The name column shows up to 12 characters; the full 16-character name is kept internally for DOS commands.
- ROM entry-point addresses are PET-3032-specific.
