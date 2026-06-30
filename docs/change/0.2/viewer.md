# Add File Viewer with Text and Hex Modes

**Type:** Feature

## Summary

Add a `V` key that opens a modal file viewer over the panels. The viewer shows the selected file's content in text or hexadecimal form, supports scrolling, and loads file data in chunks from disk rather than reading the whole file into RAM at once.

## Description

Pressing `V` on a selected entry opens a modal viewer that covers the panel area. The viewer reads the file as a sequential stream from the panel's drive and renders a window of bytes onto the screen.

The viewer has two display modes.

- **Text mode**: bytes are rendered as PETSCII characters via the existing `petscii_to_screen` conversion. Control characters render as a placeholder (e.g. a dot or space) so the layout stays stable.
- **Hex mode**: each visible row shows a byte offset, a fixed number of hex byte pairs, and an ASCII rendering of the same bytes. A new nibble-to-hex helper supports this.

The user toggles modes with `T` (text) and `H` (hex). The viewer remembers the current byte offset when switching so the same region of the file stays in view.

Scrolling moves the visible window through the file. Cursor up and cursor down move by one row; HOME jumps to the start of the file. Scrolling past the end of the file clamps at the last row.

Because CBM-DOS sequential files have no backward seek, the viewer loads the file in fixed-size chunks from the current read position. A chunk buffer holds the currently visible region plus a margin. Scrolling down past the buffer end reads the next chunk. Scrolling up past the buffer start re-opens the file and skips forward to the desired offset, since the drive cannot seek backward. The plan documents this trade-off.

The viewer is a modal overlay, not a third panel. It does not mutate panel state. On close it restores the screen contents that were hidden and returns to `main_loop` with the panels exactly as they were.

`Q` or RUN/STOP closes the viewer and returns to the panels. The viewer closes cleanly on every exit path, including open failure, read failure, and user cancellation. Every opened logical file is closed on every exit path.

## Use Cases

- When the user selects a file and presses `V`, the viewer opens showing the start of the file in text mode.
- When the user presses `H`, the display switches to hex mode at the same byte offset.
- When the user presses `T`, the display switches back to text mode at the same byte offset.
- When the user presses cursor down past the bottom visible row, the window scrolls down by one row, reading a new chunk from disk if needed.
- When the user presses HOME, the viewer re-opens the file and shows the start.
- When the user presses `Q` or RUN/STOP, the viewer closes and the panels reappear unchanged.
- When the selected file cannot be opened, the viewer shows a readable status message on the bottom row and returns to the panels without opening.

## Hints

- Reuse the existing KERNAL wrappers (`pet_setnam`, `pet_setlfs`, `pet_open`, `pet_close`) and `CHKIN`/`CHRIN`/`CLRCHN`. Do not open ad-hoc channels.
- Reuse `petscii_to_screen` for text mode. Add a small nibble-to-hex helper for hex mode.
- Reuse the borrowed `$FB`-`$FE` zero-page pointers. Do not borrow new zero page without a save/restore pair.
- Keep the viewer as a new banner section in `src/commander.asm`, placed after the prompts section per the module order in `ARCHITECTURE.md`.
- The entry record already carries the file name; no panel data change is needed.

## Out of Scope

- No editing of file contents. The viewer is read-only.
- No search or goto-offset command in this version.
- No line-wrap in text mode. Long lines are clipped to the viewer width.
- No support for REL (random-access) files. Only PRG and SEQ sequential files are viewed.
- No saving of the last view position between viewer sessions.
