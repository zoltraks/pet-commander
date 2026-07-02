# Refactoring Proposal -- Version 0.2

<!-- Version: 1.0.0 | Date: 2026-07-01 | Status: Active -->

## Problem

Analysis traced execution flow from `op_view` through `view_loop`, the four scroll handlers (`view_scroll_down`, `view_scroll_up`, `view_page_down`, `view_page_up`), `view_home`, `view_load_chunk`, and the two render routines (`view_render_text`, `view_render_hex`). It mapped the shared viewer state read and written across these routines (`view_top`, `view_chunk_base`, `view_chunk_len`, `view_at_eof`, `vr_off`, `vr_bufcur`, `dp_lo`/`dp_hi`, `sp_lo`/`sp_hi`) and catalogued duplication against the Rule of Three in `REFACTORING.md`.

The viewer is the largest module in the program (~1200 lines, `src/commander.asm:2418-3612`) and was added in version 0.2 without a refactoring pass. The 0.1 refactoring cycle cleaned the pre-viewer code; the viewer is the natural next focus.

The primary focus is **duplication of the chunk-reload tail across the scroll handlers**, with a secondary finding for dead code in the hex-conversion helpers. Several further duplications exist in the viewer but fall below the Rule-of-Three threshold and are recorded here as observations, not actions.

Sections touched: Viewer (scroll handlers, hex helpers).

## Goal

Extract a shared `view_reload_at_top` subroutine that copies `view_top` into `view_chunk_base` and calls `view_load_chunk`, eliminating four concrete duplicates of that sequence. Remove the dead `byte_to_hex` routine and its `bth_tmp` scratch byte. Record the below-threshold viewer duplications so a future cycle can revisit them if a third copy appears. No behaviour change. No memory-map change. No shift to the boot stub or load address.

## Findings

### Finding 1: Duplicate chunk-reload tail in scroll handlers

**Issue**

Four scroll handlers each end their reload path with the same five-instruction sequence that copies `view_top` into `view_chunk_base` and reloads the chunk:

`view_scroll_down` at `src/commander.asm:3444-3451`:

```asm
vsd_need_reload:
        lda view_top
        sta view_chunk_base
        lda view_top+1
        sta view_chunk_base+1
        jsr view_load_chunk
        rts
```

`view_scroll_up` at `src/commander.asm:3489-3495` repeats the same five instructions (then falls into `vsu_done` / `rts`).

`view_page_down` at `src/commander.asm:3551-3458` repeats the same five instructions plus `rts`.

`view_page_up` at `src/commander.asm:3602-3608` repeats the same five instructions (then falls into `vpu_done` / `rts`).

A fifth site, `view_home` at `src/commander.asm:3504-3512`, is a variant: it first zeroes `view_top` and `view_chunk_base`, then calls `view_load_chunk`. It does not copy `view_top` into `view_chunk_base` because both are already zero.

**Impact**

Four copies of the same 16-bit copy-plus-load sequence. Any change to how a reload is triggered (for example, invalidating a cached chunk, or adding a read-error path) must be applied in four places. Missing one would leave a scroll handler loading from the wrong base, silently showing stale data. This is the strongest Rule-of-Three candidate in the current code: four concrete duplicates of an exact sequence.

**Recommendation**

Extract a shared `view_reload_at_top` routine:

```asm
; view_reload_at_top: view_chunk_base = view_top; reload chunk
; Used by every scroll handler that moves view_top past the chunk.
; Clobbers A. view_load_chunk clobbers A/X per its own contract.
view_reload_at_top:
        lda view_top
        sta view_chunk_base
        lda view_top+1
        sta view_chunk_base+1
        jsr view_load_chunk
        rts
```

Replace the four reload tails with `jsr view_reload_at_top` (keeping each handler's existing `rts` or fall-through). `view_home` is left as-is: it is the zero-case variant and inlining the zeroing keeps its intent obvious. If desired as a separate tidy step, `view_home` could zero `view_top` then call `view_reload_at_top` (which would set `view_chunk_base = 0`); this is optional and not required for the extraction to be correct.

**Risk Level**: Major

**Breaking Change Assessment**: Internal Breaking Change -- a new label is introduced and four call sites change from inline code to `jsr`. No observable behaviour change: the same bytes are written to `view_chunk_base` and the same `view_load_chunk` call is made in the same order.

**Example**

Before (`view_scroll_down`):

```asm
vsd_need_reload:
        lda view_top
        sta view_chunk_base
        lda view_top+1
        sta view_chunk_base+1
        jsr view_load_chunk
        rts
```

After:

```asm
vsd_need_reload:
        jsr view_reload_at_top
        rts
```

### Finding 2: Dead code in hex-conversion helpers

**Issue**

`byte_to_hex` at `src/commander.asm:2428-2440` converts a byte in A to two hex-digit screen codes (A = high nibble, Y = low nibble):

```asm
byte_to_hex:
        sta bth_tmp
        and #$0F
        jsr nibble_to_sc
        tay                     ; Y = low nibble
        lda bth_tmp
        lsr
        lsr
        lsr
        lsr
        jsr nibble_to_sc        ; A = high nibble
        rts
```

A search of the source confirms no `jsr byte_to_hex` or `jmp byte_to_hex` reference exists. The routine that the hex renderer actually calls is `write_hex_byte` at `src/commander.asm:2459-2474`, which performs its own nibble extraction inline and writes the two screen codes directly to `(sp_lo),y`. `write_hex_byte` is called four times in `view_render_hex` (lines 3160, 3162, 3185, 3218).

The scratch byte `bth_tmp` at `src/commander.asm:3655` is referenced only by `byte_to_hex` (lines 2430 and 2434).

**Impact**

`byte_to_hex` and `bth_tmp` are unreachable. A reader studying the hex renderer may assume `byte_to_hex` is the conversion path used by `view_render_hex` and be misled when `write_hex_byte` does the work differently. Dead code also wastes a byte of RAM (`bth_tmp`) and a few bytes of PRG.

**Recommendation**

Remove the `byte_to_hex` routine (lines 2428-2440 including its header comment at 2423-2426) and the `bth_tmp` storage byte at line 3655. Keep `nibble_to_sc` and `write_hex_byte` unchanged. Verify after removal that no label references `byte_to_hex` or `bth_tmp` (the analysis confirms none today).

**Risk Level**: Minor

**Breaking Change Assessment**: No Breaking Change -- the removed routine is never called; observable behaviour is identical.

**Example**

Before (two conversion helpers, one unused):

```asm
byte_to_hex:
        sta bth_tmp
        ...
write_hex_byte:
        sta whb_tmp
        lsr
        ...
```

After (only the used helper remains):

```asm
write_hex_byte:
        sta whb_tmp
        lsr
        ...
```

### Finding 3: Below-threshold viewer duplication (observations, no action)

**Issue**

Three further duplications exist inside the viewer but each has only two concrete copies, below the Rule-of-Three threshold in `REFACTORING.md`. They are recorded here so a future cycle can act the moment a third copy appears.

**3a. Render prologue.** `view_render_text` at `src/commander.asm:3031-3049` and `view_render_hex` at `src/commander.asm:3130-3147` open with the same 16-line sequence: compute `vr_off = view_top - view_chunk_base`, set `dp = view_chunk + vr_off`, and copy `vr_off` into `vr_bufcur`. Two copies.

**3b. Hex-row group loops.** `view_render_hex` contains two byte-for-byte identical hex-group loops, `vrh_hex1_loop` (cols 6-16) and `vrh_hex2_loop` (cols 18-28), differing only in the starting column. It also contains two byte-for-byte identical ASCII-group loops, `vrh_ascii1_loop` (cols 30-33) and `vrh_ascii2_loop` (cols 35-38). Two copies of each loop.

**3c. Scroll handler pairs.** `view_scroll_down` and `view_page_down` share the same structure (advance `view_top` by a delta, compute `end = view_top + view_screen_size`, compute `chunkend = view_chunk_base + view_chunk_len`, 16-bit compare, reload or clamp) differing only in the addend (`view_row_size` vs `view_page_size`) and the clamp subtractand. `view_scroll_up` and `view_page_up` share the same structure (retreat `view_top` by a delta, compare against `view_chunk_base`, reload) differing only in the subtractend and the underflow clamp. Two copies of each pair.

**Impact**

Each is a maintainability latent cost: a change to the render setup, the hex row layout, or the scroll bounds logic must currently be applied in two places. None is a correctness risk today.

**Recommendation**

Do not extract now. The Rule of Three is explicit: extraction before three concrete duplicates is premature. Re-evaluate if a third render mode, a third hex group, or a third scroll variant is added. Finding 1 (the reload tail) is the exception because it already has four copies and is extracted in this proposal.

**Risk Level**: Suggestion

**Breaking Change Assessment**: No Breaking Change -- no action taken.

**Example**

Not applicable; this finding records observations for future cycles.

## Plan

Each step must leave the program assembling cleanly and running. Tidy steps are separate from structural steps. Documentation updates happen before the code change in each step.

**Step 1: Extract view_reload_at_top**

Add `view_reload_at_top` alongside the scroll handlers (after `view_home` is a natural spot, or at the end of the scroll-handler block). Replace the reload tail in `view_scroll_down` (`vsd_need_reload`), `view_scroll_up` (`vsu_reload`), `view_page_down` (`vpd_need_reload`), and `view_page_up` (`vpu_reload`) with `jsr view_reload_at_top`, preserving each handler's existing `rts` or fall-through. Leave `view_home` unchanged. Update `ARCHITECTURE.md` Viewer module entry to list `view_reload_at_top`. Update `SPECIFICATION.md` Viewer scrolling section to note the shared reload helper. Run the verification loop.

**Step 2: Remove dead byte_to_hex and bth_tmp**

Delete the `byte_to_hex` routine and its header comment (lines 2423-2440). Delete the `bth_tmp` storage byte at line 3655. Confirm the assemble is clean and that `nibble_to_sc` and `write_hex_byte` are unaffected. No documentation update is required because `byte_to_hex` is not listed in `ARCHITECTURE.md` or `SPECIFICATION.md` (it is an internal helper); if a future doc audit lists hex helpers, the remaining helper is `write_hex_byte`. Run the verification loop.

## Step Granularity

Step 1 is the structural step: it introduces one routine and edits four call sites within one module. Step 2 is a dead-code removal: it deletes one routine and one byte and touches no call site. The two steps are independent and do not touch the same lines. If Step 1 reveals an unexpected register-clobber or control-flow issue (the new `jsr` preserves the same A/X contract as the inlined sequence, since `view_load_chunk` already clobbers A/X and the handlers do not rely on A after the reload), stop and update this proposal before continuing.

## Risk

The highest-risk step is **Step 1**. It touches all four scroll handlers, which are the interactive hot path of the viewer. A regression would surface as wrong content after a scroll past the chunk boundary (text or hex), or as a clamp/reload decision firing at the wrong offset. The behaviour check must verify: text-mode row scroll down and up past a 2048-byte chunk boundary, hex-mode row scroll past the boundary, page down and page up across the boundary, and HOME. The extraction is behaviour-preserving by construction: the same five instructions run in the same order, only the call mechanism changes. The new routine clobbers exactly what `view_load_chunk` clobbers (A and X), which the handlers already tolerate because they return immediately after the reload.

Step 2 is low risk: removing unreachable code cannot change observable behaviour. The only hazard is an undetected reference to `byte_to_hex` or `bth_tmp`; the analysis confirms none, and the assemble will fail loudly if one is missed because DASM errors on undefined labels.

## Acceptance Criteria

- Identical observable behaviour: the viewer opens, scrolls (row and page, up and down, both modes) across chunk boundaries, HOME jumps to start, and closes restoring the panels. Text and hex render identically. Character-set switching and PCR restore are unaffected.
- The `$0401` load address is preserved and `SYS 1038` still lands on `jmp start`.
- A clean assemble: `./build.sh` reports `Complete. (0)` with zero errors and zero warnings.
- A clean headless smoke run: tens of millions of cycles under `xpet -model 3032 -drive8type 2031 -warp -limitcycles 100000000 -autostart example/work.d64` with no crash or runaway writes.
- The PRG size does not grow; a small decrease is expected from removing `byte_to_hex`/`bth_tmp` and collapsing four reload tails into one routine.
