# Add File Viewer with Text and Hex Modes Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/0.2/viewer.md`.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md`.

All addresses and KERNAL routines are PET 3032 specific. Do not substitute C64 addresses. The PET has no `SETNAM`/`SETLFS`; use the project's `pet_setnam`/`pet_setlfs` wrappers and `pet_open`/`pet_close`.

## Documentation Updates

Update the active documentation set before any source modification.

- `PROJECT.md`: move the file viewer out of the Won't section. Add functional requirements for the viewer, the mode toggle, scrolling, and partial load.
- `ARCHITECTURE.md`: add a Viewer module row to the module table. Note that the viewer is a modal overlay, not a panel, and that it owns its own state and chunk buffer.
- `SPECIFICATION.md`: add the new key constants (`CH_V`, `CH_H`, `CH_T`), the viewer state table, the chunk buffer, the new module entry labels, and the partial-load algorithm. Remove the `V` key from Known Limitations.
- `TESTING.md`: add behaviour checks for open, mode toggle, scroll, close-restore, and open-failure.

## Step by Step Implementation

**Add key constants and dispatch wiring**

Add `CH_V = $56`, `CH_H = $48`, `CH_T = $54` to the PETSCII characters block. Add a branch in `dispatch_key` that calls `op_view` on `V`.

Section in `src/commander.asm`: PETSCII characters block, `dispatch_key`.

    CH_V    = $56
    CH_H    = $48
    CH_T    = $54

**Add viewer state and chunk buffer**

Add a new banner section for viewer state, placed after the prompts data and before the entry tables. State fields:

- `view_mode`: 0 = text, 1 = hex.
- `view_top`: 16-bit byte offset of the top visible row.
- `view_chunk_base`: 16-bit byte offset of the first byte in the chunk buffer.
- `view_chunk_len`: number of valid bytes in the chunk buffer.
- `view_file_len`: 16-bit file length, accumulated during read (best-effort; CBM-DOS does not report SEQ length up front).
- `view_lfn`: logical file number used by the viewer (a constant, e.g. 2).

Add a chunk buffer `view_chunk` of `VIEW_CHUNK` bytes (start with 256; shrink if memory is tight). Add a screen-save buffer `view_saved` large enough to hold the covered screen region, or re-render the panels on close via `full_redraw` (preferred, to avoid a large save buffer).

Section in `src/commander.asm`: new Viewer state section.

    view_mode:      byte 0
    view_top:       word 0
    view_chunk_base: word 0
    view_chunk_len:  byte 0
    view_file_len:  word 0
    view_chunk:     ds 256, 0

**Implement op_view**

`op_view` locates the selected entry, copies its name into a viewer-owned filename buffer, calls `view_open`, then `view_loop`, then `view_close`. On any error it sets a status message and returns to `main_loop` without entering the loop.

Section in `src/commander.asm`: new Viewer module section, after prompts.

    op_view:
            ; locate selected entry, copy name, call view_open/view_loop/view_close

**Implement view_open**

`view_open` sets up `pet_setnam`/`pet_setlfs` with the file name, LFN = `view_lfn`, the panel's drive, and SA = 2 (sequential read). Calls `pet_open`. On carry set, sets `VIEW OPEN FAILED` status and returns with an error flag. On success calls `CHKIN`, then reads the first chunk into `view_chunk` via `view_read_chunk`, sets `view_top` = 0, `view_chunk_base` = 0, `view_mode` = 0 (text).

Section in `src/commander.asm`: Viewer module.

**Implement view_read_chunk**

Reads up to `VIEW_CHUNK` bytes from the current input channel into `view_chunk` using `CHRIN`, checking `STATUS` after each byte. Sets `view_chunk_len` to the count read. Updates `view_file_len` as bytes are read. Stops on EOF or error (STATUS non-zero). This routine is the only place that calls `CHRIN` for the viewer.

Section in `src/commander.asm`: Viewer module.

**Implement view_loop**

`view_loop` renders the current view, then reads keys with `GETIN` and dispatches:

- `H` -> set `view_mode` = 1, re-render.
- `T` -> set `view_mode` = 0, re-render.
- Cursor down -> `view_scroll_down`, re-render.
- Cursor up -> `view_scroll_up`, re-render.
- `HOME` -> `view_home`, re-render.
- `Q` or RUN/STOP -> exit loop.

Section in `src/commander.asm`: Viewer module.

**Implement view_scroll_down**

Advance `view_top` by one row's worth of bytes. If the new top falls outside `[view_chunk_base, view_chunk_base + view_chunk_len)`, read the next chunk: call `CLRCHN`, `pet_close`, re-open the file, skip forward to the new offset by reading and discarding bytes, then `view_read_chunk`. Clamps at end of file.

Section in `src/commander.asm`: Viewer module.

**Implement view_scroll_up**

Decrease `view_top` by one row's worth of bytes, clamped at 0. If the new top falls below `view_chunk_base`, re-open the file and skip forward to the new offset (no backward seek), then `view_read_chunk`. This is the documented trade-off: upward scroll past the buffer is expensive.

Section in `src/commander.asm`: Viewer module.

**Implement view_home**

Set `view_top` = 0. Re-open the file from the start and `view_read_chunk`.

Section in `src/commander.asm`: Viewer module.

**Implement view_render**

Clear the viewer region of the screen. Render a title line showing the file name and current mode. Render the visible rows from `view_chunk`:

- Text mode: for each visible row, copy bytes from the chunk buffer at the row's offset, convert each byte with `petscii_to_screen`, render control characters as a placeholder, clip to viewer width.
- Hex mode: for each visible row, render the offset as hex, then a fixed count of hex byte pairs using a new `byte_to_hex` helper, then an ASCII rendering of the same bytes.

Use `row_addr_sp` for screen addressing. Do not scatter `row*40 + $8000` math.

Section in `src/commander.asm`: Viewer module, drawing helpers.

**Implement byte_to_hex helper**

Convert the byte in A to two hex screen-code digits in A (high nibble) and Y (low nibble), using a nibble-to-hex table. Place this in the number/text format module section near `print_num3`.

Section in `src/commander.asm`: number/text format module.

    byte_to_hex:
            ; A -> A=high digit screen code, Y=low digit screen code

**Implement view_close**

Call `CLRCHN` to restore keyboard input. If the viewer's logical file is open, call `pet_close` with `view_lfn`. Restore the screen by calling `full_redraw` (preferred over a save buffer to keep memory low). Return to `main_loop`.

Section in `src/commander.asm`: Viewer module.

**Update SPECIFICATION.md key bindings**

Add the viewer keys to the keyboard bindings table.

| Key            | Constant   | Action                                  |
| -------------- | ---------- | --------------------------------------- |
| `V`            | `CH_V $56` | Open the viewer on the selected file.   |
| `H`            | `CH_H $48` | Switch the viewer to hex mode.          |
| `T`            | `CH_T $54` | Switch the viewer to text mode.         |

Cursor up/down and HOME inside the viewer scroll the file. `Q`/RUN/STOP close the viewer.

## Implementation Order

Execute the steps above in this sequence.

1. Update documentation (`PROJECT.md`, `ARCHITECTURE.md`, `SPECIFICATION.md`, `TESTING.md`).
2. Add `CH_V`, `CH_H`, `CH_T` constants.
3. Add viewer state and the chunk buffer.
4. Implement `byte_to_hex` helper.
5. Implement `view_open`, `view_read_chunk`, `view_close`.
6. Implement `view_render` (text then hex).
7. Implement `view_loop`, `view_scroll_down`, `view_scroll_up`, `view_home`.
8. Implement `op_view` and wire it into `dispatch_key`.
9. Run the verification loop.

## Testing Strategy

**Build verification**

`./build.sh` reports `Complete. (0)` with zero errors and zero warnings. `build/commander.prg` is produced with load address `$0401`. Build size grows by the viewer code plus the 256-byte chunk buffer; the new size is recorded as the new expected baseline.

**Behaviour checks**

Exercise against `example/work.d64` in a graphical `xpet` session:

- Select a PRG file, press `V`, confirm the viewer opens in text mode showing the start of the file.
- Press `H`, confirm hex mode renders offsets and byte pairs.
- Press `T`, confirm text mode returns at the same offset.
- Press cursor down repeatedly, confirm scrolling advances and reads new chunks when needed.
- Press HOME, confirm the viewer returns to the start.
- Press `Q`, confirm the panels reappear unchanged.
- Select a SEQ file, repeat the open/toggle/scroll/close cycle.
- Select a file, press `V`, then RUN/STOP, confirm clean close.
- With no disk mounted (or a forced open failure), press `V`, confirm a readable status message and return to panels with no file left open.

**Headless smoke**

`xpet -warp -limitcycles 100000000` completes without crashing or runaway writes.

**Channel-leak check**

After each viewer session, verify via the VICE monitor that no logical file remains open (the viewer must close on every path).

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp`.
- Graphical behaviour check for the changed feature.
