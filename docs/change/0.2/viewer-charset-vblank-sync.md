# Synchronize viewer character-set switch with VBLANK blit

**Type:** Fix

## Summary

Switching the viewer character set with `L`/`U` flickers because the VIA PCR register is written immediately while the new screen content is only blitted later during VBLANK. This change defers the PCR write so it happens in the same VBLANK window as the back-buffer-to-screen blit, eliminating the partial-update window.

## Description

### Problem

The viewer switches the PET character set by read-modify-writing VIA PCR bits 3:1 via `view_set_pcr_charset`. Today this routine writes PCR directly. When the user presses `L` or `U`, the sequence is:

1. `view_set_pcr_charset` writes PCR. The live screen now shows the OLD frame rendered with the NEW character set.
2. `view_loop` calls `view_render`, which composes the new frame into `BUFFER`.
3. `present_screen` waits for VBLANK and copies `BUFFER` to `SCREEN`.

Between steps 1 and 3 the user sees the previous frame in the wrong character set. This is a visible flash on every `L`/`U` press.

The same mismatch affects two other transitions:

- **Viewer entry**: `view_apply_charset` switches PCR before the first viewer frame is blitted, so the panels flash in the viewer's persisted character set for one frame.
- **Viewer exit**: `view_restore_charset` restores PCR to the uppercase set before `full_redraw` blits the panels, so the viewer frame flashes in the uppercase set for one frame.

### Requirement

The character-set switch and the screen-content update must be atomic from the display's perspective. The PCR write must happen during the same VBLANK period as the `BUFFER`-to-`SCREEN` blit, never outside it.

This applies to all three transitions: in-viewer `L`/`U` switching, viewer entry, and viewer exit.

### Approach

Introduce a pending-PCR mechanism that queues a charset write and flushes it inside the present/blit path during VBLANK:

- A pending flag (`view_pcr_pending`) and a staged-bits byte (`view_pending_pcr_cs`) record that a PCR write is waiting.
- `view_set_pcr_charset` no longer writes PCR directly. It sets `view_char_offset` immediately (needed to compose the header and footer labels into `BUFFER` with the correct screen codes) and stages the PCR write by storing the target charset bits and setting the flag.
- A new `view_flush_pcr` routine performs the read-modify-write on PCR and clears the flag. It is a no-op when nothing is staged.
- `present_screen` calls `view_flush_pcr` between `wait_vblank` and `copy_buffer`. The charset change and the content blit therefore both occur inside the VBLANK window.

Because every visible update goes through `present_screen`, this single hook covers all three transitions:

- `L`/`U`: stage the switch, then `view_render`'s present flushes it.
- Entry: `view_apply_charset` saves the original PCR bits immediately (still needed for restore) and stages the switch; the first `view_render` present flushes it.
- Exit: `view_restore_charset` stages the restore; `full_redraw`'s present flushes it.

The pending flag is viewer-owned state. During normal main-program operation it is always clear, so the only cost on non-viewer present calls is a single load-and-branch test.

### Constraints preserved

- The PCR read-modify-write still preserves CB2 (IEEE-488 NDAC) bits.
- `view_char_offset` is still set before any label rendering, so header and footer labels compose correctly into `BUFFER`.
- The charset switch is still applied only while the viewer is interactively displayed, not during `view_load_chunk`. An open failure still leaves PCR unchanged and the failure status still renders in the uppercase set, because `view_apply_charset` is not reached on open failure.
- On viewer exit the machine still returns to the uppercase set.
- `view_mode`, `view_charset_mode`, and `view_charset` still persist across viewer opens within one program run.
- The present/blit module remains the only writer of `SCREEN`. `copy_buffer` is unchanged. The new PCR write is a display-control-register flush, not a screen-RAM write.

## Use Cases

- The user presses `L` in the viewer. The frame transitions to the lowercase set with no flash: the new content and the new character set appear together in one VBLANK.
- The user presses `U`. Same atomic transition back to the uppercase set.
- The user opens the viewer when the persisted charset is LOWER. The panels disappear and the viewer frame appears in the lowercase set in one atomic transition, with no panel flash in the lowercase set.
- The user presses `E`. The viewer frame disappears and the panels reappear in the uppercase set in one atomic transition, with no viewer-frame flash in the uppercase set.

## Hints

- Keep `view_char_offset` set immediately; only the PCR store is deferred.
- The flush belongs in `present_screen` so that entry, exit, and in-viewer switching all share one synchronized path.
- The pending flag must be clear whenever the main program calls `present_screen`. The viewer always flushes before returning to the main loop (exit flushes via `full_redraw`).

## Out of Scope

- No change to which character sets are available or to the PCR bit values.
- No change to label rendering, the filename side effect, or persistence semantics.
- No change to the double-buffered blit itself (`copy_buffer`, `wait_vblank`).
- No IRQ-based charset switching; the mechanism stays polling-based to preserve the clean BASIC exit path.
