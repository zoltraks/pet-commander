# Redesign Viewer Screen with Bordered Layout and Page Scrolling

**Type:** Feature

## Summary

Redesign the file viewer to use a bordered frame with a header bar, footer bar, and column dividers. Replace the single-row scroll with page-based scrolling using cursor left/right. Change the viewer exit key from Q to E so Q is reserved for quitting the main program only.

## Description

### Screen Layout

The viewer screen is redesigned to a framed layout matching this structure (40 columns, 25 rows):

- **Row 0**: Header bar in reverse video with half-block borders. Shows `VIEW`, the filename, and the current mode (`TEXT` or `HEX`) right-aligned. All text is reversed; the left and right edges use reversed and normal left-half-block screen codes (`$E1` and `$61`).
- **Row 1**: Top border of the content frame using center-line box drawing. Corners `$70` (TL) and `$6E` (TR). Horizontal line `$40`. In hex mode, T-junctions `$72` (down) at columns 5, 17, 29 and `$71` (up) at column 34. In text mode, no T-junctions (plain horizontal line).
- **Rows 2-22**: Content area (21 rows). Left and right borders are `$5D` (vertical center line). In hex mode, internal dividers at columns 5, 17, 29, 34 are also `$5D`.
- **Row 23**: Bottom border. Corners `$6D` (BL) and `$7D` (BR). T-junctions `$71` (up) at columns 5, 17, 29, 34 in hex mode. In text mode, plain horizontal line.
- **Row 24**: Footer bar in reverse video with half-block borders (`$E1` and `$61`). Shows shortcut labels: `T`EXT, `H`EX, `E`XIT. The shortcut letters T, H, E are in normal video; the rest of each label is in reverse video.

### Hex Mode Content Row Format

Each content row in hex mode follows this column layout:

| Columns | Content                              | Width |
|---------|--------------------------------------|-------|
| 0       | Left border `$5D`                    | 1     |
| 1-4     | Address (4 hex digits, big-endian)   | 4     |
| 5       | Divider `$5D`                        | 1     |
| 6-16    | Hex group 1: 4 bytes as `HH HH HH HH`| 11    |
| 17      | Divider `$5D`                        | 1     |
| 18-28   | Hex group 2: 4 bytes as `HH HH HH HH`| 11    |
| 29      | Divider `$5D`                        | 1     |
| 30-33   | ASCII group 1: 4 raw bytes as screen codes | 4 |
| 34      | Divider `$5D`                        | 1     |
| 35-38   | ASCII group 2: 4 raw bytes as screen codes | 4 |
| 39      | Right border `$5D`                   | 1     |

Total: 40 columns. 8 data bytes per row (unchanged from current `VIEW_HEX_COLS`).

The ASCII columns display the raw byte value directly as a screen code. No PETSCII-to-screen-code conversion and no dot substitution. Byte `$00` shows as screen code `$00` (`@`), byte `$01` as `$01` (`A`), byte `$F8` as `$F8` (reversed graphics character).

### Text Mode Content Layout

Text mode uses the same outer frame (header, top border, bottom border, footer) but no internal column dividers. Text fills columns 1-38 (38 characters per row) across 21 content rows. PETSCII-to-screen-code conversion with dot substitution for bytes below `$20` or at/above `$7F` is unchanged from the current implementation.

### Key Bindings

| Key            | Action                                      |
|----------------|---------------------------------------------|
| T              | Switch to text display                      |
| H              | Switch to hex display                       |
| Cursor up      | Scroll up one row                           |
| Cursor down    | Scroll down one row                         |
| Cursor left    | Page up (scroll up by one page)             |
| Cursor right   | Page down (scroll down by one page)         |
| HOME           | Jump to start of file                       |
| E              | Exit viewer, restore panels                 |
| RUN/STOP       | Exit viewer, restore panels                 |

Q no longer exits the viewer. Q is reserved for quitting the main program only.

### Page Scrolling Rules

Cursor left and right scroll by a full page, with different overlap rules per mode:

- **Text mode page down**: The last line of the previous page becomes the first line of the new page. The scroll distance is `(VIEW_ROWS - 1) * row_size` = `20 * 38 = 760` bytes. This creates a 1-line overlap so the reader keeps context.
- **Text mode page up**: The first line of the previous page becomes the last line of the new page. Same scroll distance: `20 * 38 = 760` bytes backward.
- **Hex mode page down**: The first line of the new page is the line immediately after the last line of the previous page. No overlap. The scroll distance is `VIEW_ROWS * row_size` = `21 * 8 = 168` bytes.
- **Hex mode page up**: Same distance: `21 * 8 = 168` bytes backward. No overlap.

### Header Bar Format

The header content (38 chars between borders) is:

- Two reversed spaces (solid blocks)
- `VIEW` in reversed screen codes
- Two reversed spaces
- Filename (up to 16 chars) in reversed screen codes
- Padding with reversed spaces to fill
- Mode string right-aligned: `TEXT` (4 chars) or `HEX` (3 chars), ending at content position 35
- Two reversed spaces after the mode

All content is reversed (bit 7 set). The left border is `$E1` (reversed left-half-block) and the right border is `$61` (left-half-block).

### Footer Bar Format

The footer content (38 chars between borders) is:

- `T` (normal video) followed by `EXT` (reversed)
- One reversed space
- `H` (normal video) followed by `EX` (reversed)
- Padding with reversed spaces
- `E` (normal video) followed by `XIT` (reversed)

The shortcut letters T, H, E are in normal video (bit 7 clear). All other characters are reversed (bit 7 set). The borders match the header: `$E1` left, `$61` right.

## Use Cases

- When the user presses cursor right in hex mode, the viewer advances by 21 rows (168 bytes) with no overlap. The address column updates to reflect the new offset.
- When the user presses cursor left in text mode, the viewer retreats by 20 rows (760 bytes). The last line of the previous page appears as the first line of the new page.
- When the user presses E, the viewer closes and the panels reappear. Q does nothing in the viewer.
- When the user opens the viewer and the file contains bytes `$00`-`$FF`, the hex mode ASCII column shows each byte as its raw screen code, including non-printable bytes (no dots).

## Hints

- The existing `write_hex_byte` and `nibble_to_sc` routines can be reused for the address and hex byte columns.
- The existing `view_load_chunk` and chunk-based scrolling infrastructure can be reused; only the scroll distance and screen size constants change.
- New box-drawing constants for T-junctions (`$72`, `$71`) and half-block borders (`$61`, `$E1`) should be defined as named equates near the existing `BOX_*` constants.
- The footer requires mixed reverse/normal video within a single row. Build it byte-by-byte rather than using `highlight_row`.

## Out of Scope

- No change to the chunk buffer size (`VIEW_CHUNK` = 2048).
- No change to the viewer open/close lifecycle or error handling.
- No change to the main program key bindings (Q still quits the main program).
- No search, goto-offset, or editing in the viewer.
- No line-wrap in text mode.
