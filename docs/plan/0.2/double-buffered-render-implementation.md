# Double-Buffered Screen Rendering Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/0.2/double-buffered-render.md`.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md`.

All addresses and KERNAL routines are PET 3032 specific. The PET has no `SETNAM`/`SETLFS`; use the project's `pet_setnam`/`pet_setlfs` wrappers and `pet_open`/`pet_close` for any I/O. The blit and VBLANK poll perform no I/O and borrow no zero page.

Consult `docs/skill/commodore-pet-skill/system/screen.md` (Double Buffering) and `docs/skill/commodore-pet-skill/system/irq.md` (VBLANK Polling) for the canonical `copy_buffer` and `wait_vblank` routines.

## Documentation Updates

Update the active documentation set before any source modification.

- `PROJECT.md`: add a non-functional requirement for flicker-free updates via double buffering and VBLANK-synced blit.
- `ARCHITECTURE.md`: add a Present/Blit module row (`present_screen`, `copy_buffer`, `wait_vblank`) to the module table. Update the Memory Map with `BUFFER = $7C00`. Add an Architectural Decision entry for double buffering (atomic-copy during VBLANK, polling not IRQ, `copy_buffer` is the sole writer of `SCREEN`). Update the Component Interaction note so the drawing module and viewer render write `BUFFER`, and only the blit writes `SCREEN`.
- `SPECIFICATION.md`: add the `BUFFER` constant and the `VIA_PORTB` / `RETRACE_BIT` constants to the constants table. Add the present/blit algorithm. Update the screen-addressing contract: `row_addr_sp` base is `BUFFER`. List the present points. Update the Memory Map entry for the back buffer.
- `TESTING.md`: add behaviour checks for flicker-free navigation, viewer scroll, prompt input visibility, and clean BASIC exit after the change (no IRQ vector installed, `READY.` shown, `PRINT FRE(0)` and a string op still work).

## Seam Analysis (Pre-Implementation Finding)

`ARCHITECTURE.md` states that only the drawing module and viewer render write screen RAM and that row addressing goes through `row_addr_sp`. The source shows the seam is wider than that. The following routines write `SCREEN` directly and must be redirected to `BUFFER`:

- `clear_screen` (page-strided clear of all 1000 bytes).
- `draw_title_bar` (row 0 direct write, plus a read-modify-write for reverse video).
- `draw_help_bar` (row 24 direct write).
- `draw_status` (row 24 direct write).
- `draw_prompt_label` (row 24 clear and label write).
- `show_prompt_buf` (row 24 input render).

Routines that write through the `sp` pointer computed by `row_addr_sp` (frames, panel header/rows, entry, viewer content rows) are redirected by changing the `row_addr_sp` base alone.

This finding is recorded here so the steps below cover every direct-write site. No source is changed in this step.

## Step by Step Implementation

**Add constants**

Add `BUFFER = $7C00`, `VIA_PORTB = $E840`, and `RETRACE_BIT = $20` to the layout/hardware constants block. Keep `SCREEN = $8000`.

Section in `src/commander.asm`: Hardware and Layout constants blocks.

    BUFFER       = $7C00          ; 1000-byte back buffer, page-aligned
    VIA_PORTB    = $E840          ; VIA port B (PB5 = VBLANK)
    RETRACE_BIT  = $20            ; PB5 mask

**Add wait_vblank**

Two-phase poll of VIA PB5: skip any remaining VBLANK (bit LOW), then wait for active display to end (bit HIGH), return at the start of VBLANK. No registers clobbered beyond A.

Section in `src/commander.asm`: new Present/Blit module section, placed after the drawing module and before the viewer module.

    wait_vblank:
            lda VIA_PORTB
            and #RETRACE_BIT
            beq wait_vblank      ; phase 1: skip remaining VBLANK
    wv_wait:
            lda VIA_PORTB
            and #RETRACE_BIT
            bne wv_wait          ; phase 2: wait for next VBLANK
            rts

**Add copy_buffer**

Page-strided copy of 1000 bytes from `BUFFER` to `SCREEN` (3 full pages plus a 232-byte tail), mirroring the existing `clear_screen` pattern.

Section in `src/commander.asm`: Present/Blit module.

    copy_buffer:
            ldx #0
    cb_loop:
            lda BUFFER,x          ; $7C00-$7CFF -> $8000-$80FF
            sta SCREEN,x
            lda BUFFER+$100,x     ; $7D00-$7DFF -> $8100-$81FF
            sta SCREEN+$100,x
            lda BUFFER+$200,x     ; $7E00-$7EFF -> $8200-$82FF
            sta SCREEN+$200,x
            inx
            bne cb_loop           ; 768 bytes done
            ldx #$E8              ; remaining 232 bytes
    cb_tail:
            dex
            lda BUFFER+$300-1,x   ; reads $7FE7..$7F00
            sta SCREEN+$300-1,x   ; writes $83E7..$8300
            bne cb_tail
            rts

**Add present_screen**

`present_screen` calls `wait_vblank` then `copy_buffer`. This is the only writer of `SCREEN`.

Section in `src/commander.asm`: Present/Blit module.

    present_screen:
            jsr wait_vblank
            jsr copy_buffer
            rts

**Redirect row_addr_sp base**

Change the base in `row_addr_sp` from `SCREEN` to `BUFFER`. This redirects every `sp`-based write (frames, panel header/rows, entry, viewer content rows) into the back buffer.

Section in `src/commander.asm`: `row_addr_sp`.

    row_addr_sp:
            lda #<BUFFER
            sta sp_lo
            lda #>BUFFER
            sta sp_hi
            ...

**Redirect clear_screen to BUFFER**

Change the four `SCREEN` writes in `clear_screen` to `BUFFER`. The back buffer is cleared to `SC_SPACE` before each full redraw.

Section in `src/commander.asm`: `clear_screen`.

    clear_screen:
            lda #SC_SPACE
            ldx #0
    cs_loop:
            sta BUFFER,x
            sta BUFFER+$100,x
            sta BUFFER+$200,x
            inx
            bne cs_loop
            ldx #$E8
    cs_tail:
            dex
            sta BUFFER+$300,x
            bne cs_tail
            rts

**Redirect draw_title_bar to BUFFER**

Change the three `SCREEN` references in `draw_title_bar` to `BUFFER` (the write of `title_str`, and the read-modify-write that sets the reverse bit). The reverse-video read now reads from `BUFFER`, which is correct because the title bytes were just written there.

Section in `src/commander.asm`: `draw_title_bar`.

**Redirect row-24 direct writes to BUFFER**

Change `SCREEN+24*40` to `BUFFER+24*40` in `draw_help_bar`, `draw_status`, `draw_prompt_label`, and `show_prompt_buf`. These are the interactive row-24 updaters.

Section in `src/commander.asm`: `draw_help_bar`, `draw_status`, `draw_prompt_label`, `show_prompt_buf`.

**Clear BUFFER at init**

`BUFFER` is at a fixed high-RAM address and is not part of the PRG image, so it is uninitialized on load. Add a call to `clear_screen` (now clearing `BUFFER`) in `init`, before the first `load_panel` and `full_redraw`, so the back buffer starts clean.

Section in `src/commander.asm`: `init`.

**Add present calls at redraw entry points**

Call `present_screen` at the end of `full_redraw`, `redraw_panels`, and `redraw_active`. After these calls, `BUFFER` holds the composed frame and `SCREEN` shows it atomically.

Section in `src/commander.asm`: `full_redraw`, `redraw_panels`, `redraw_active`.

**Add present call in view_render**

Call `present_screen` at the end of `view_render` so each viewer frame is shown atomically.

Section in `src/commander.asm`: `view_render`.

**Add present calls after interactive row-24 updates**

Call `present_screen` after `draw_status` and `clear_status` so status messages appear, and after each prompt update (`draw_prompt_label` once, and after each `show_prompt_buf` in the `prompt_text` loop, and after the `prompt_yn` confirmation display) so prompt input stays visible. These are the interactive paths where a delayed blit would hide user feedback.

Section in `src/commander.asm`: `draw_status`, `clear_status`, `prompt_text`, `prompt_yn`.

**Verify no remaining direct SCREEN writes outside the blit**

After the redirects, the only `SCREEN` references in code should be inside `copy_buffer`. Grep `src/commander.asm` for `SCREEN` outside comments and confirm all hits are in `copy_buffer`. This closes the seam.

## Implementation Order

Execute the steps above in this sequence.

1. Update documentation (`PROJECT.md`, `ARCHITECTURE.md`, `SPECIFICATION.md`, `TESTING.md`).
2. Add `BUFFER`, `VIA_PORTB`, `RETRACE_BIT` constants.
3. Add `wait_vblank`, `copy_buffer`, `present_screen` (new Present/Blit module).
4. Redirect `row_addr_sp` base to `BUFFER`.
5. Redirect `clear_screen`, `draw_title_bar`, `draw_help_bar`, `draw_status`, `draw_prompt_label`, `show_prompt_buf` to `BUFFER`.
6. Clear `BUFFER` in `init`.
7. Add `present_screen` calls at `full_redraw`, `redraw_panels`, `redraw_active`, `view_render`.
8. Add `present_screen` calls after interactive row-24 updates.
9. Grep to confirm no direct `SCREEN` writes remain outside `copy_buffer`.
10. Run the verification loop.

## Testing Strategy

**Build verification**

`./build.sh` reports `Complete. (0)` with zero errors and zero warnings. `build/commander.prg` is produced with load address `$0401` (first two bytes `01 04`). Build size grows by the new Present/Blit code only (no in-PRG buffer, since `BUFFER` is at a fixed address); the new size is recorded as the new expected baseline.

**Behaviour checks**

Exercise against `example/work.d64` in a graphical `xpet` session:

- Start the program; confirm both panels render atomically with no initial flicker.
- Hold cursor down to move the selection rapidly; confirm the active panel updates without the clear-then-redraw flicker.
- Press TAB to switch panels; confirm the highlight change is flicker-free.
- Press `L` to reload; confirm the panel repaints atomically.
- Open the viewer with `V`, scroll with cursor down and up, press HOME; confirm each viewer frame is complete with no tearing.
- Toggle `H` and `T` in the viewer; confirm the mode switch is flicker-free.
- Press `Q` in the viewer; confirm the panels reappear unchanged and atomically.
- Start a rename with `N`, type and backspace; confirm each keystroke is visible.
- Start a copy with `C`, type a name; confirm input is visible.
- Press `D` then `Y`; confirm the delete confirmation and the resulting status line both appear.
- Press `Q` to quit; confirm `READY.` appears, then type `PRINT FRE(0)` and assign a string (`A$="TEST"`) and confirm no corruption (BASIC RAM below `$8000` is intact).

**Clean exit check**

Confirm no custom IRQ vector is installed: the change uses polling only, so `CINV` is untouched. After `Q`, the machine must remain usable per UC-5.

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp` for tens of millions of cycles with the fixture mounted; confirm no crash and no runaway writes.
- Graphical behaviour check for flicker-free navigation, viewer scroll, prompt input, and clean BASIC exit.

## Risk

- **BASIC RAM collision at `$7C00`**: the back buffer sits in the region BASIC uses for its downward-growing string pool. On a fresh disk autostart no strings are allocated, so the region is free during the program run and BASIC's pointers are untouched on exit. The behaviour check above (`PRINT FRE(0)` and a string op after `Q`) guards this. If an edge case collides, the documented fallback is to lower BASIC's RAM-top pointer on entry and restore it on exit, or to fall back to an in-PRG `.ds` buffer.
- **Missed present point**: any redraw or interactive update that is not followed by `present_screen` will not appear on screen. Step 9 (grep for direct `SCREEN` writes) and the behaviour checks cover this.
- **Reverse-video read source**: `draw_title_bar` reads back the bytes it just wrote to apply the reverse bit. After the redirect it reads from `BUFFER`, which is correct because the writes target `BUFFER`. The behaviour check confirms the title bar still renders reversed.
- **VBLANK period fit**: the 1000-byte copy is roughly 6000 cycles at 1 MHz, within the PET VBLANK period per the skill. If a future change grows the copy, this must be rechecked.
