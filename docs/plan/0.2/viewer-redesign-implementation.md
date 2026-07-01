# Redesign Viewer Screen Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/0.2/viewer-redesign.md`.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md`. Consult `docs/skill/commodore-pet-skill/system/graphics.md` for box-drawing character codes and `docs/skill/commodore-pet-skill/system/keyboard.md` for PETSCII key codes.

## Documentation Updates

Update the active documentation set before any source modification:

- `PROJECT.md`: Update FR-M13, FR-M14, FR-M15 to reflect the new viewer layout, E exit key, and page scrolling. Update NFR-Footprint build size if it changes.
- `ARCHITECTURE.md`: Update the Viewer module entry labels and the viewer state domain. No new memory-map entries needed (no new buffers).
- `SPECIFICATION.md`: Update viewer constants (`VIEW_ROWS`, `VIEW_TEXT_COLS`), key bindings table, viewer rendering section, viewer scrolling section, and viewer state table.
- `README.md`: Update the viewer keys table and source layout if needed.
- `TESTING.md`: Update the coverage targets for the new viewer keys and page scrolling behaviour.

## Step by Step Implementation

### Step 1: Update Constants and Equates

Add new equates and modify existing viewer layout constants in the equates section near line 70 of `src/commander.asm`.

Section: `; ---- Viewer layout constants ---`

    VIEW_ROWS      = 21             ; was 22; content rows 2..22 inside frame
    VIEW_TEXT_COLS = 38             ; was 40; columns 1..38 inside frame
    VIEW_HEX_COLS  = 8              ; unchanged; 8 data bytes per hex row
    VIEW_CHUNK     = 2048           ; unchanged
    VIEW_LFN       = 3              ; unchanged

Add new box-drawing constants near the existing `BOX_*` block (line 86):

    BOX_TJD   = $72           ; T-junction down (┬): h-both + v-down
    BOX_TJU   = $71           ; T-junction up (┴): h-both + v-up
    HB_LEFT   = $61           ; left half block (left 4px filled)
    HB_RLEFT  = $E1           ; reversed left half block (right 4px filled)

Add new PETSCII character constant near the existing `CH_*` block (line 114):

    CH_E     = $45            ; 'E' key for viewer exit

### Step 2: Update view_set_mode_params

Update `view_set_mode_params` (line 2481) to use the new `VIEW_ROWS` and `VIEW_TEXT_COLS` values. The screen size calculations change:

- Text mode: `view_screen_size = 21 * 38 = 798`
- Hex mode: `view_screen_size = 21 * 8 = 168` (was `22 * 8 = 176`)

Also add a `view_page_size` word variable and set it alongside `view_screen_size`:

- Text mode: `view_page_size = 20 * 38 = 760` (VIEW_ROWS - 1 rows, overlap)
- Hex mode: `view_page_size = 21 * 8 = 168` (VIEW_ROWS rows, no overlap)

Section: `view_set_mode_params`

### Step 3: Update view_loop Key Dispatch

Update `view_loop` (line 2962) to add cursor left/right as page up/down and replace Q with E.

    view_loop:
            jsr view_render
    vl_wait:
            jsr GETIN
            beq vl_wait
            cmp #CH_H
            beq vl_hex
            cmp #CH_T
            beq vl_text
            cmp #K_UP
            beq vl_up
            cmp #K_DOWN
            beq vl_down
            cmp #K_LEFT
            beq vl_pgup
            cmp #K_RIGHT
            beq vl_pgdn
            cmp #K_HOME
            beq vl_home
            cmp #CH_E
            beq vl_quit
            cmp #K_STOP
            beq vl_quit
            jmp vl_wait

Add `vl_pgup` and `vl_pgdn` dispatch labels calling new `view_page_up` and `view_page_down` routines.

Remove the `cmp #CH_Q` / `beq vl_quit` lines.

### Step 4: Implement view_page_down and view_page_up

Add two new routines after `view_scroll_down` / `view_scroll_up` (around line 3100).

`view_page_down` advances `view_top` by `view_page_size` and reloads the chunk if the new window extends past the chunk. Clamp at EOF by reverting if the new `view_top` would leave no visible data.

`view_page_up` retreats `view_top` by `view_page_size`, clamped at 0. Reload the chunk if the new `view_top` falls below `view_chunk_base`.

Both routines reuse the existing chunk reload pattern from `view_scroll_down` / `view_scroll_up` but use `view_page_size` instead of `view_row_size`.

### Step 5: Redesign view_render Header

Rewrite the header rendering section of `view_render` (lines 2614-2688) to draw the new header bar.

The header is row 0, 40 columns:
- Col 0: `$E1` (HB_RLEFT)
- Cols 1-38: content, all reversed (bit 7 set)
  - Cols 1-2: reversed space (`$A0`)
  - Cols 3-6: `VIEW` in reversed screen codes (`$96 $89 $85 $97`)
  - Cols 7-8: reversed space
  - Cols 9-(9+fname_len-1): filename in reversed screen codes
  - Fill to col 35 with reversed space (`$A0`)
  - Cols 33-35 (hex) or 32-35 (text): mode string in reversed screen codes
  - Cols 36-38: reversed space
- Col 39: `$61` (HB_LEFT)

Build the row in BUFFER using `row_addr_sp` for row 0, then OR each byte with `$80` for the content portion. The borders at cols 0 and 39 are not reversed.

### Step 6: Redesign view_render Footer

Rewrite the help bar rendering section of `view_render` (lines 2697-2726) to draw the new footer bar.

The footer is row 24, 40 columns:
- Col 0: `$E1` (HB_RLEFT)
- Cols 1-38: content with mixed reverse/normal video
  - Col 1: `$14` (T, normal video)
  - Cols 2-4: `$85 $98 $94` (EXT, reversed)
  - Col 5: `$A0` (reversed space)
  - Col 6: `$08` (H, normal video)
  - Cols 7-8: `$85 $98` (EX, reversed)
  - Cols 9-34: `$A0` (reversed space padding)
  - Col 35: `$05` (E, normal video)
  - Cols 36-38: `$98 $89 $94` (XIT, reversed)
- Col 39: `$61` (HB_LEFT)

Build the footer as a static 40-byte table (like `title_str` and `help_str`) since the content is fixed. Store as `view_footer_str` with 40 screen codes.

### Step 7: Draw Content Frame Borders

Add a new routine `view_draw_frame` called from `view_render` after the header and before the content rows.

In hex mode, draw:
- Row 1 (top border): `$70` at col 0, `$40` at cols 1-4, `$72` at col 5, `$40` at cols 6-16, `$72` at col 17, `$40` at cols 18-28, `$72` at col 29, `$40` at cols 30-33, `$71` at col 34, `$40` at cols 35-38, `$6E` at col 39.
- Row 23 (bottom border): `$6D` at col 0, `$40` at cols 1-4, `$71` at col 5, `$40` at cols 6-16, `$71` at col 17, `$40` at cols 18-28, `$71` at col 29, `$40` at cols 30-33, `$71` at col 34, `$40` at cols 35-38, `$7D` at col 39.
- Rows 2-22: `$5D` at cols 0, 5, 17, 29, 34, 39 (vertical borders and dividers).

In text mode, draw:
- Row 1: `$70`, `$40` x 38, `$6E`.
- Row 23: `$6D`, `$40` x 38, `$7D`.
- Rows 2-22: `$5D` at cols 0 and 39 only (no internal dividers).

### Step 8: Redesign view_render_hex

Rewrite `view_render_hex` (lines 2818-2956) to render into the new column layout.

For each content row (rows 2-22, 21 rows):
- Set `sp` to the row address via `row_addr_sp`.
- Col 0: already has `$5D` from `view_draw_frame`.
- Cols 1-4: write 4-digit hex address (big-endian: high byte first, then low byte) using `write_hex_byte`.
- Col 5: already has `$5D` from frame.
- Cols 6-16: write 4 hex bytes as `HH HH HH HH` (byte 0 at cols 6-7, space at 8, byte 1 at 9-10, space at 11, etc.). Use `write_hex_byte` for each byte, spaces between.
- Col 17: already has `$5D` from frame.
- Cols 18-28: write next 4 hex bytes in the same format.
- Col 29: already has `$5D` from frame.
- Cols 30-33: write 4 raw bytes as screen codes directly (store the byte value as-is, no conversion).
- Col 34: already has `$5D` from frame.
- Cols 35-38: write next 4 raw bytes as screen codes.
- Col 39: already has `$5D` from frame.

The ASCII columns do NOT use `petscii_to_screen` and do NOT substitute dots. The raw byte is stored directly. Bytes past EOF or chunk end are padded with `$20` (space).

Advance `dp` by `VIEW_HEX_COLS` (8) and `vr_fileoff` by 8 per row, same as current.

### Step 9: Redesign view_render_text

Rewrite `view_render_text` (lines 2732-2811) to render into the bordered content area.

For each content row (rows 2-22, 21 rows):
- Set `sp` to the row address via `row_addr_sp`.
- Start at column 1 (Y=1), end at column 38 (Y=38). Cols 0 and 39 already have `$5D` from frame.
- Render up to 38 bytes per row (was 40). Convert each byte with `petscii_to_screen`; substitute `$2E` (dot) for bytes below `$20` or at/above `$7F`.
- Pad with `$20` (space) for bytes past EOF or chunk end.

Advance `dp` by `VIEW_TEXT_COLS` (38) per row instead of 40.

### Step 10: Update view_render Structure

Rewrite the top-level `view_render` (lines 2611-2726) to call the new sub-routines in order:

1. `clear_screen` (clear BUFFER)
2. Draw header (row 0)
3. `view_draw_frame` (top border, bottom border, side borders, dividers)
4. `view_render_text` or `view_render_hex` depending on mode
5. Draw footer (row 24) from `view_footer_str`
6. `present_screen`

Remove the old `view_title_str`, `view_mode_text_str`, `view_mode_hex_str`, and `view_help_str` data. Add `view_footer_str` (40 bytes) and `view_header_prefix` data.

### Step 11: Update Viewer State Variables

Add `view_page_size` (2 bytes) to the viewer state section (line 3123). Set it in `view_set_mode_params` alongside `view_screen_size`.

Update `view_screen_size` to reflect the new dimensions:
- Text: 21 * 38 = 798
- Hex: 21 * 8 = 168

### Step 12: Update Viewer Strings

Remove old strings (lines 3152-3155):
- `view_title_str`
- `view_mode_text_str`
- `view_mode_hex_str`
- `view_help_str`

Add new data:
- `view_footer_str`: 40 bytes, the static footer with mixed reverse/normal video.
- `view_hdr_view_str`: 4 bytes, `VIEW` in screen codes (`$16 $09 $05 $17`).

## Implementation Order

1. Update documentation (`PROJECT.md`, `ARCHITECTURE.md`, `SPECIFICATION.md`, `README.md`, `TESTING.md`).
2. Update equates and layout constants (Step 1).
3. Update viewer state variables (Step 11).
4. Update `view_set_mode_params` (Step 2).
5. Update `view_loop` key dispatch (Step 3).
6. Implement `view_page_down` and `view_page_up` (Step 4).
7. Implement `view_draw_frame` (Step 7).
8. Redesign `view_render` structure (Step 10).
9. Redesign header rendering (Step 5).
10. Redesign footer rendering (Step 6).
11. Redesign `view_render_hex` (Step 8).
12. Redesign `view_render_text` (Step 9).
13. Update viewer strings (Step 12).
14. Run the verification loop.

## Testing Strategy

**Build verification**

- `./build.sh` produces `Complete. (0)` with zero errors and zero warnings.
- `build/commander.prg` load address is `$0401`.
- Build size should stay close to the current ~8.8 KB. The new footer table is 40 bytes; the old strings are removed. Net change should be small.

**Behaviour checks**

- Open the viewer on a PRG file and a SEQ file from the fixture.
- Hex mode: verify the framed layout with header, top border with T-junctions at cols 5/17/29/34, content rows with address/hex/ASCII columns, bottom border, and footer.
- Hex mode: verify the ASCII column shows raw screen codes (byte `$00` shows as `@`, not a dot).
- Text mode: verify the framed layout with header, plain top/bottom borders (no T-junctions), content filling cols 1-38, and footer.
- Press T and H to switch modes. Verify the header mode label changes.
- Press cursor down/up: verify single-row scroll.
- Press cursor right in hex mode: verify the view advances by 21 rows (168 bytes) with no overlap.
- Press cursor left in text mode: verify the view retreats by 20 rows (760 bytes) with 1-line overlap.
- Press E: verify the viewer closes and panels reappear.
- Press Q in the viewer: verify nothing happens (Q is ignored).
- Press Q in the main program: verify it still quits to BASIC.
- Press RUN/STOP in the viewer: verify it exits the viewer.
- Press HOME: verify the view jumps to the start of the file.
- Verify the footer shows T, H, E in normal video and the rest in reverse video.
- Verify the header shows VIEW, filename, and mode all in reverse video with half-block borders.

**Clean BASIC exit**

After exiting the viewer with E and then quitting with Q, verify `READY.` appears and `PRINT FRE(0)` works.

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp`.
- Graphical behaviour check for the viewer redesign.
