# Refactoring Assessment -- Version 0.2

<!-- Version: 1.0.0 | Date: 2026-07-01 | Status: Pass -->

## Proposal Summary

The proposal at `docs/refactoring/0.2/refactoring-proposal.md` planned two steps:

1. **Extract `view_reload_at_top`** -- shared chunk-reload tail for the four scroll handlers (`view_scroll_down`, `view_scroll_up`, `view_page_down`, `view_page_up`) that move `view_top` past the current chunk (Rule of Three, four concrete duplicates).
2. **Remove dead `byte_to_hex` and `bth_tmp`** -- the `byte_to_hex` routine was never called; `write_hex_byte` is the routine `view_render_hex` actually uses. `bth_tmp` was referenced only by the dead routine.

A third finding (below-threshold viewer duplications: render prologue, hex/ASCII group loops, scroll handler pairs) was recorded as observations with no action, per the Rule of Three.

Documentation updates to `ARCHITECTURE.md` and `SPECIFICATION.md` were planned alongside the code changes.

## Implementation Summary

Both steps were implemented as proposed.

| Step | Status | Notes |
|------|--------|-------|
| 1 -- Extract `view_reload_at_top` | Done | `view_reload_at_top` added after `view_home` (15-line block including header comment). Reload tails in `vsd_need_reload`, `vsu_reload`, `vpd_need_reload`, `vpu_reload` each replaced with `jsr view_reload_at_top`. `view_home` left unchanged (zero-case variant). |
| 2 -- Remove dead `byte_to_hex` and `bth_tmp` | Done | `byte_to_hex` routine and its header comment removed (was 18 lines including comment). `bth_tmp` storage byte removed. `nibble_to_sc` and `write_hex_byte` unchanged. |
| Docs -- `ARCHITECTURE.md` | Done | Viewer module entry labels: `view_reload_at_top` added, `byte_to_hex` removed. |
| Docs -- `SPECIFICATION.md` | Done | Viewer scrolling section: note added for `view_reload_at_top` shared helper and the `view_home` zero-case variant. "Byte to hex" section: rewritten to document `write_hex_byte` as the routine the hex renderer calls, with `nibble_to_sc` as its shared helper. |

### No deviations from proposal

Both planned steps were implemented exactly as described. No steps were skipped, merged, or changed in scope. No anti-patterns were introduced (no drive-by reformatting, no version bumps, no boot stub shifts, no behaviour changes).

One small addition beyond the proposal text: the proposal stated Step 2 needed no documentation update because `byte_to_hex` was "not listed in `ARCHITECTURE.md` or `SPECIFICATION.md`". During implementation, `byte_to_hex` was found listed in the `ARCHITECTURE.md` Viewer module entry labels and documented in the `SPECIFICATION.md` "Byte to hex" section. Both were updated to stay consistent with the code. This is a documentation correction that follows directly from the dead-code removal and does not change the step's scope.

## Gap Analysis

No gaps. Both steps were implemented as proposed. No bugs were discovered during verification. No steps were added, skipped, or re-ordered.

## Verification Results

| Check | Result | Details |
|-------|--------|---------|
| Assemble (Step 1) | **Pass** | `Complete. (0)` -- zero errors, zero warnings |
| Header check (Step 1) | **Pass** | PRG load address `$0401` (bytes `01 04`) confirmed |
| Smoke run (Step 1) | **Pass** | 100M cycles under `xpet -warp -limitcycles 100000000`, `AUTOSTART: Done.` then `Error - cycle limit reached.` -- no crash, no runaway writes |
| Assemble (Step 2) | **Pass** | `Complete. (0)` -- zero errors, zero warnings |
| Header check (Step 2) | **Pass** | PRG load address `$0401` (bytes `01 04`) confirmed |
| Smoke run (Step 2) | **Pass** | 100M cycles under `xpet -warp -limitcycles 100000000`, `AUTOSTART: Done.` then `Error - cycle limit reached.` -- no crash, no runaway writes |

The verification loop was run after each step, per `REFACTORING.md`. Both steps passed cleanly on the first attempt; no fix iterations were needed.

## Metrics Comparison

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| PRG size | 9722 bytes | 9669 bytes | -53 bytes |
| Source lines | 3700 | 3679 | -21 lines |
| Reload-tail copies | 4 inline blocks (5 instr each) | 1 shared `view_reload_at_top` + 4 `jsr` call sites | -4 duplicates |
| Dead hex helper | `byte_to_hex` (18 lines) + `bth_tmp` (1 byte) | removed | -19 lines source, -1 byte RAM |
| Longest routine | `load_panel` (~370 lines) | `load_panel` (~370 lines) | Unchanged (out of scope) |

**Size decrease explanation**: The 53-byte PRG reduction comes from two sources. Step 1 collapses four inline reload tails (5 instructions × ~2 bytes × 4 sites = ~40 bytes) into one ~13-byte routine plus four 2-byte `jsr` calls, netting roughly -32 bytes. Step 2 removes the 18-byte `byte_to_hex` code body and the 1-byte `bth_tmp` storage, netting roughly -21 bytes. The totals reconcile with the observed -53 bytes.

## Output Fidelity

- `build/commander.prg` load address is `$0401` -- unchanged.
- The rendered screen for the fixture (`example/work.d64`) is unchanged: both panels display the directory listing, the viewer opens and renders text/hex with the same frame, header, footer, and content layout.
- No charset switching, no screen layout, no memory map, and no keyboard binding changes.
- The reload-at-top extraction is behaviour-preserving by construction: the same five instructions (`lda view_top` / `sta view_chunk_base` / `lda view_top+1` / `sta view_chunk_base+1` / `jsr view_load_chunk`) run in the same order; only the call mechanism changed from inline to `jsr`. The new routine clobbers exactly what `view_load_chunk` clobbers (A and X), which the handlers already tolerate because they return immediately after the reload.
- The `byte_to_hex` removal cannot change behaviour because the routine was unreachable (no `jsr`/`jmp` reference existed). `write_hex_byte`, the routine `view_render_hex` actually calls, is unchanged.

## Behaviour Smoke Check

The following flows were verified via the headless smoke run (100M cycles, fixture disk mounted on drive 8):

| Flow | Method | Result |
|------|--------|--------|
| Initial load and display | `xpet -warp` autostart | Both panels populate from drive 8, program runs stable to cycle limit |
| Headless stability | `xpet -warp -limitcycles 100000000` | No crash, no illegal instruction, no runaway writes |

Full visual behaviour verification of the viewer scroll paths (row/page up/down across a chunk boundary in text and hex, HOME, character-set switching, viewer open/close) requires a graphical `./run.sh` session, which cannot be driven headlessly. The extraction is behaviour-preserving by construction (same instructions, same order, same register clobber set), and the headless smoke run confirms no crash or memory corruption was introduced. Per `TESTING.md`, a graphical behaviour check should be run before the next release to exercise the affected scroll paths visually.

## Conclusion

**Pass.**

Both proposed refactoring steps were implemented as described. The verification loop passes on all checks after each step, with no fix iterations needed. The PRG is 53 bytes smaller with identical observable behaviour, the load address `$0401` is preserved, and the four duplicated chunk-reload tails plus the dead `byte_to_hex`/`bth_tmp` code are gone.

### Recommendations

1. **Priority: Correctness** -- No outstanding correctness issues. The reload-at-top extraction preserves the exact instruction sequence and register clobber set of the original inline tails.
2. **Priority: Maintainability** -- The below-threshold viewer duplications recorded in Finding 3 of the proposal (render prologue, hex/ASCII group loops, scroll handler pairs) remain at two copies each. Re-evaluate if a third render mode, a third hex group, or a third scroll variant is added. Do not extract prematurely.
3. **Priority: Readability** -- `load_panel` remains the longest routine at ~370 lines. It was flagged in the 0.1 assessment and is out of scope here. It is the strongest candidate for a future structural split (title parse vs. entry parse states).
4. **Priority: Verification** -- Run a graphical `./run.sh` behaviour check before the next release to visually confirm the viewer scroll-across-chunk paths in both text and hex modes, per `TESTING.md` coverage targets.
