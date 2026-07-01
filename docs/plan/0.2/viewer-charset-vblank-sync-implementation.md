# Synchronize Viewer Character-Set Switch With VBLANK Blit Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/0.2/viewer-charset-vblank-sync.md`.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md`. Preserve CRLF line endings and tab-aligned mnemonics. Keep the PCR read-modify-write pattern that preserves CB2. Consult `docs/skill/commodore-pet-skill/system/screen.md` for the PCR charset bits and `docs/skill/commodore-pet-skill/code/standard.md` for flag semantics.

## Documentation Updates

Update the active documentation set before any source modification:

- `SPECIFICATION.md`: document the new `view_pcr_pending` and `view_pending_pcr_cs` state bytes; update the "Character set switching", "Present and blit", and viewer state table sections to describe the deferred flush.
- `ARCHITECTURE.md`: update the Present/blit module responsibility to include the deferred PCR flush during VBLANK; update the viewer state domain list and AD-8 to record the synchronized switch.
- `PROJECT.md`: no functional requirement change; the fix preserves FR-M19 through FR-M23 behaviour. Add a note under NFR-FlickerFree that the character-set switch is also VBLANK-synchronized.
- `TESTING.md`: add a coverage target confirming `L`/`U`, viewer entry, and viewer exit are flicker-free.

## Step by Step Implementation

**Add pending-PCR state bytes**

Declare two new viewer state bytes next to `saved_pcr_cs`.

Section in `src/commander.asm`: viewer state block near `view_char_offset` / `saved_pcr_cs`.

    view_pcr_pending:   byte 0      ; nonzero = a PCR charset write is staged
    view_pending_pcr_cs: byte 0     ; staged PCR bits 3:1 to OR into PCR on flush

**Split view_set_pcr_charset into stage + flush**

`view_set_pcr_charset` currently reads PCR, clears bits 3:1, ORs in `PCR_U`/`PCR_L`, writes PCR, and sets `view_char_offset`. Change it so the PCR write is staged instead of immediate. `view_char_offset` is still set now because `view_draw_header` and `view_draw_footer` read it while composing `BUFFER`.

Section in `src/commander.asm`: `view_set_pcr_charset`.

    view_set_pcr_charset:

            ldx view_charset
            beq vspc_upper
            lda #PCR_L             ; LOWER bits to stage
            ldx #$40
            bne vspc_store
    vspc_upper:

            lda #PCR_U             ; UPPER bits to stage
            ldx #$00
    vspc_store:

            sta view_pending_pcr_cs ; stage the PCR write (do not touch PCR yet)
            stx view_char_offset    ; set offset now for label rendering
            lda #$ff
            sta view_pcr_pending    ; mark a write as pending
            rts

Add the flush routine immediately after it. It performs the deferred read-modify-write and clears the flag. It is a no-op when nothing is staged.

    view_flush_pcr:

            lda view_pcr_pending
            beq vfp_done
            lda PCR
            and #$F1               ; clear bits 3:1
            ora view_pending_pcr_cs ; apply staged bits
            sta PCR
            lda #0
            sta view_pcr_pending
    vfp_done:

            rts

**Flush staged PCR inside present_screen**

Insert the flush between `wait_vblank` and `copy_buffer` so the charset change and the content blit share one VBLANK window. When the flag is clear (all main-program presents) the cost is one load plus one branch.

Section in `src/commander.asm`: `present_screen`.

    present_screen:

            jsr wait_vblank
            jsr view_flush_pcr      ; apply staged PCR charset during VBLANK
            jsr copy_buffer
            rts

**Stage the restore on viewer exit**

`view_restore_charset` currently reads PCR, clears bits 3:1, ORs in `saved_pcr_cs`, and writes PCR directly. Replace the direct write with staging so `full_redraw`'s present flushes it during VBLANK.

Section in `src/commander.asm`: `view_restore_charset`.

    view_restore_charset:

            lda saved_pcr_cs
            sta view_pending_pcr_cs ; stage the restore
            lda #$ff
            sta view_pcr_pending
            rts

**Clear the pending flag on viewer open**

Add `view_pcr_pending` to the per-open zeroing in `op_view` so a stale flag from a prior session cannot survive into a new open. `view_apply_charset` sets it again right after, but the explicit clear is defensive.

Section in `src/commander.asm`: `op_view` per-open init block.

            lda #0
            sta view_pcr_pending    ; no staged PCR write at open

**Confirm view_apply_charset needs no code change**

`view_apply_charset` saves PCR bits into `saved_pcr_cs` then calls `view_set_pcr_charset`. After the split, `view_set_pcr_charset` stages the switch instead of writing PCR. The save still happens immediately, which is correct: the original bits must be captured before any flush. No edit is needed beyond verifying the call still composes correctly.

## Implementation Order

1. Update `SPECIFICATION.md`, `ARCHITECTURE.md`, `PROJECT.md`, and `TESTING.md`.
2. Add the `view_pcr_pending` and `view_pending_pcr_cs` state bytes.
3. Split `view_set_pcr_charset` and add `view_flush_pcr`.
4. Insert the flush call in `present_screen`.
5. Convert `view_restore_charset` to staging.
6. Clear `view_pcr_pending` in the `op_view` per-open init.
7. Run the verification loop.

## Testing Strategy

**Build verification**

- `./build.sh` finishes with `Complete. (0)` and zero warnings.
- `build/commander.prg` is produced with load address `$0401`.
- Build size is within the expected range (two new state bytes plus a small flush routine; growth of well under 50 bytes).

**Behaviour checks**

Exercise against `example/work.d64` in a graphical `xpet` session:

- Open `README.TXT` with `V`, press `A`, press `L`: the transition to the lowercase set is flicker-free; the new content and the new character set appear together.
- Press `U`: the transition back to the uppercase set is flicker-free.
- Set `A` + `L`, close with `E`, reopen with `V` on another file: the viewer opens in ASCII + LOWER with no panel flash in the lowercase set on entry, and the panels reappear in the uppercase set with no viewer-frame flash on exit.
- Press `E` after a LOWER session: the panels reappear in the uppercase set atomically.
- After `E`, press `Q`: `READY.` appears; `PRINT FRE(0)` and `A$="TEST"` succeed, confirming PCR and zero page were restored and the `$7C00` back-buffer region did not corrupt BASIC RAM.
- Viewer state persistence still holds: `A` + `L`, close, reopen starts in ASCII + LOWER with offset zero.
- Open-failure path still renders `VIEW OPEN FAILED` in the uppercase set (PCR unchanged because `view_apply_charset` is not reached).

**Headless smoke**

- `xpet -model 3032 -drive8type 2031 -warp -autostart example/work.d64` runs for tens of millions of cycles without crashing or runaway writes.

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp`.
- Graphical behaviour check for the `L`/`U` flicker-free transition, entry, and exit.
