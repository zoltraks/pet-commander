# Double-Buffered Screen Rendering

**Type:** Feature

## Summary

Introduce a software back buffer and VBLANK-synchronised blit so the screen is never seen half-updated. All panel drawing and viewer rendering compose into a back buffer in RAM; a single atomic copy transfers the complete frame to screen RAM during vertical blank. This removes the flicker visible when navigating panels and scrolling the viewer.

## Description

Today every redraw writes directly to screen RAM at `$8000` while the display is being drawn. A redraw that clears, then repaints, then flips reverse video produces a visible flicker window. This is most noticeable on `redraw_active` (cursor moves), `redraw_panels` (after file operations), and `view_render` (viewer scrolling).

The change adds a 1000-byte back buffer in RAM, redirects all drawing to it, and copies the finished frame to screen RAM in one pass during VBLANK. The user never sees a partially updated screen.

### Buffer placement and naming

The back buffer occupies the space just before the end of RAM, aligned to a 256-byte page boundary. The standard address is `$7C00`, leaving a 1024-byte gap below screen RAM.

- `SCREEN = $8000` remains the screen RAM constant and the sole destination of the blit.
- `BUFFER = $7C00` is the back buffer and the sole target of all drawing.

These conventions are recorded in `docs/skill/commodore-pet-skill/system/screen.md` (Double Buffering section).

### VBLANK synchronisation

The blit runs during vertical blank. The PET 3032 exposes VBLANK on VIA PORT B bit 5 (`$E840` bit 5): LOW during VBLANK, HIGH during active display. A two-phase poll syncs to the start of VBLANK. This is polling, not an IRQ handler, so no CINV vector is installed and the clean BASIC exit path is unchanged.

The 1000-byte copy takes roughly 6000 cycles at 1 MHz, which fits inside the PET VBLANK period.

### Drawing seam

All screen writes are redirected to `BUFFER`. This includes the routines that currently write `SCREEN` directly (`clear_screen`, `draw_title_bar`, `draw_help_bar`, `draw_status`, `draw_prompt_label`, `show_prompt_buf`) and the routines that write through `row_addr_sp` (whose base moves from `SCREEN` to `BUFFER`). After the change, `copy_buffer` is the only writer of `SCREEN`.

### Present points

A `present_screen` routine (wait for VBLANK, then copy `BUFFER` to `SCREEN`) is called at the end of every redraw entry point and after every interactive row-24 update:

- `full_redraw` (startup, viewer close).
- `redraw_panels` (after file operations and reload).
- `redraw_active` (after cursor moves and panel switch).
- `view_render` (each viewer frame).
- After status row updates (`draw_status`, `clear_status`).
- After each prompt update (`draw_prompt_label`, `show_prompt_buf` in the `prompt_text` loop, and the `prompt_yn` confirmation display).

### Constraints preserved

- Load address `$0401` and `SYS 1038` -> `jmp start` unchanged.
- Borrowed zero page `$FB`-`$FE` and `BLNSW` save/restore unchanged. No new zero page is borrowed.
- Channel hygiene unchanged. The blit and VBLANK poll perform no I/O.
- Only the drawing module, the viewer render, and the new blit touch screen RAM or the back buffer. Navigation and file operations still do not draw directly.

## Use Cases

- When the user holds cursor down to move the selection rapidly, the active panel updates without the visible clear-then-redraw flicker.
- When the user scrolls the viewer with cursor down, each frame appears complete with no tearing.
- When the user presses `L` to reload, the panel repaints atomically.
- When the user quits with `Q`, BASIC returns with `READY.` and the machine stays usable (no IRQ vector left installed, no zero page corruption).
- When the user types in a rename or copy prompt, each keystroke is shown after a blit, so input stays visible and responsive.

## Hints

- Reuse the project's existing screen-addressing helper `row_addr_sp`; change only its base constant.
- The page-strided copy pattern already used by `clear_screen` (3 full pages plus a 232-byte tail) is the model for `copy_buffer`.
- Consult `docs/skill/commodore-pet-skill/system/screen.md` (Double Buffering) and `docs/skill/commodore-pet-skill/system/irq.md` (VBLANK Polling) for the canonical routines.
- Keep `present_screen` small and call it at the end of redraw entry points; do not scatter VBLANK waits inside leaf draw routines.

## Out of Scope

- No dirty-row or region-based partial blit. Every present copies the full 1000 bytes.
- No IRQ-based VBLANK handler and no CINV replacement. Synchronisation is by polling VIA PB5.
- No change to the 40x25 layout, the panel geometry, or the rendered content. The fixture screen must remain byte-for-byte equivalent.
- No change to the viewer's chunk loading or scrolling logic; only its render target moves to `BUFFER`.
- No second physical display or hardware double buffer; the PET has none.
