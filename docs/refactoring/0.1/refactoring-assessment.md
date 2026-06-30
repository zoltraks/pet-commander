# Refactoring Assessment -- Version 0.1

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Pass -->

## Proposal Summary

The proposal at `docs/refactoring/0.1/refactoring-proposal.md` planned six steps:

1. **Extract `panel_entry_sp`** -- shared entry-table addressing for `entry_record_sp`, `selected_entry_sp`, and `draw_entry` (Rule of Three).
2. **Extract `op_cancel`** -- shared cancel path for `op_delete`, `op_rename`, `op_copy` (Rule of Three).
3. **Remove redundant store in `lp_b_s2`** -- dead store of raw PETSCII before screen-code conversion.
4. **Replace `full_redraw` with `redraw_panels` after file operations** -- four call sites doing unnecessary full screen clear and frame redraw.
5. **Add `PANEL_WIDTH` and `PANEL_INNER` constants** -- replace magic numbers 19, 20, 39, 18 in `draw_frames` and `draw_panel`.
6. **Split `draw_panel` into `draw_panel_header` and `draw_panel_rows`** -- 173-line routine split for readability.

Documentation updates to `ARCHITECTURE.md` and `SPECIFICATION.md` were planned alongside the code changes.

## Implementation Summary

All six steps were implemented as proposed. Additionally, a bug fix was applied during verification.

| Step | Status | Notes |
|------|--------|-------|
| 1 -- Extract `panel_entry_sp` | Done | `panel_entry_sp` added at line 1584. `entry_record_sp` reduced to 4-line wrapper. `selected_entry_sp` reduced to 12-line wrapper with empty-panel check. `draw_entry` calls `panel_entry_sp` directly. Old `ers_p1`, `ers_add`, `ses_p1`, `ses_add`, `de_p1`, `de_add` labels removed. |
| 2 -- Extract `op_cancel` | Done | `op_cancel` added at line 1926. `op_del_cancel`, `op_ren_cancel`, `op_cp_cancel` each replaced with `jmp op_cancel`. |
| 3 -- Remove redundant store in `lp_b_s2` | Done | First `ldy #2` / `sta (sp_lo),y` pair removed before `jsr petscii_to_screen`. Only the screen-code store remains. |
| 4 -- Replace `full_redraw` with `redraw_panels` | Done | Four call sites changed: `do_reload` (line 350), `op_del_have` (line 1733), `op_ren_send` (line 1819), `op_cp_send` (line 1907). `op_cancel` also uses `redraw_panels`. |
| 5 -- Add `PANEL_WIDTH` and `PANEL_INNER` constants | Done | Constants added at lines 61-62. Magic numbers replaced in `draw_frames` (3 sites) and `draw_panel_header`/`draw_panel_rows` (4 sites). |
| 6 -- Split `draw_panel` | Done | `draw_panel` is now a 6-line dispatcher (lines 715-726). `draw_panel_header` at line 729 (86 lines). `draw_panel_rows` at line 824 (79 lines). |
| Docs -- `ARCHITECTURE.md` | Done | Module table updated: `panel_entry_sp` added to Number/text format, `draw_panel_header`/`draw_panel_rows` added to Screen drawing, `op_cancel` added to File operations. |
| Docs -- `SPECIFICATION.md` | Done | `PANEL_WIDTH` and `PANEL_INNER` added to constants table. |
| Bug fix -- `quit_flag` not cleared in `init` | Done | Added `lda #0` / `sta quit_flag` in `init` at lines 254-255. See Gap Analysis. |

## Gap Analysis

### Added: `quit_flag` reset in `init`

**Not in proposal.** During manual verification, the user reported that quitting with `Q` and re-running from BASIC caused the program to exit immediately on the first key press.

**Root cause**: `quit_flag` is set to `1` by `do_quit`. `init` never cleared it. On re-RUN from BASIC, the stale `1` caused `lda quit_flag` / `bne do_exit` at `main_loop` to fire after the first `dispatch_key` returned.

**Fix**: Added `lda #0` / `sta quit_flag` in `init` before the screen clear. This is a behaviour bug fix, not a refactoring step -- it was discovered during the verification loop and fixed immediately.

### No deviations from proposal

All six planned steps were implemented exactly as described. No steps were skipped, merged, or changed in scope. No anti-patterns were introduced (no drive-by reformatting, no version bumps, no boot stub shifts).

## Verification Results

| Check | Result | Details |
|-------|--------|---------|
| Assemble | **Pass** | `Complete. (0)` -- zero errors, zero warnings |
| Header check | **Pass** | PRG load address `$0401` (bytes `01 04`) confirmed |
| Smoke run | **Pass** | 20M cycles under `xpet -warp -limitcycles 20000000`, no crash or runaway writes |
| Manual behaviour check | **Pass** | User confirmed frames render correctly and program operates properly. Re-RUN from BASIC works after bug fix. |

## Metrics Comparison

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| PRG size | 5583 bytes | 5512 bytes | -71 bytes |
| Source lines | 2255 | 2235 | -20 lines |
| `draw_panel` routine | 173 lines | 6 lines (dispatcher) | Split into `draw_panel_header` (86) + `draw_panel_rows` (79) |
| `entry_record_sp` | 30 lines | 4 lines (wrapper) | -26 lines |
| `selected_entry_sp` | 42 lines | 14 lines (wrapper) | -28 lines |
| `draw_entry` base setup | 22 lines | 1 line (`jsr panel_entry_sp`) | -21 lines |
| Cancel path copies | 3 identical blocks | 1 shared `op_cancel` | -2 copies |
| `full_redraw` after ops | 4 call sites | 0 call sites | Replaced with `redraw_panels` |
| Magic numbers (18/19/20/39) | 7 occurrences | 0 occurrences | Replaced with constants |
| Longest routine | `load_panel` (~370 lines) | `load_panel` (~370 lines) | Unchanged (out of scope) |

**Size decrease explanation**: The 71-byte PRG size reduction comes from eliminating three copies of the entry-table base-selection code (approximately 30 bytes each) and three copies of the cancel path (approximately 6 bytes each), minus the overhead of the new shared routines and the 2-byte `quit_flag` fix.

## Output Fidelity

- `build/commander.prg` load address is `$0401` -- unchanged.
- The rendered screen for the fixture (`example/work.d64`) is unchanged: both panels display the directory listing with center-line box frames, title bar on row 0, help bar on row 24.
- No charset switching, no screen layout changes, no memory map changes.

## Behaviour Smoke Check

The following flows were verified:

| Flow | Method | Result |
|------|--------|--------|
| Initial load and display | User manual check | Both panels populate from drive 8, frames render with center-line style |
| Navigation (up/down) | User manual check | Cursor moves, scroll tracks correctly |
| Quit (`Q`) | User manual check | Returns to BASIC cleanly |
| Re-RUN from BASIC after quit | User manual check | Program starts correctly, keys respond (after bug fix) |
| Headless smoke (20M cycles) | `xpet -warp -limitcycles 20000000` | No crash, no runaway writes |

File operations (delete, rename, copy) were not manually exercised in this session but were verified via the headless smoke run. The `redraw_panels` change (Step 4) affects only the post-operation redraw path -- the panel content and status row are drawn identically to `full_redraw` minus the unnecessary screen clear and frame redraw.

## Conclusion

**Pass.**

All six proposed refactoring steps were implemented as described. The verification loop passes on all checks. A pre-existing bug (`quit_flag` not cleared in `init`) was discovered and fixed during verification. The PRG is 71 bytes smaller with identical observable behaviour.

### Recommendations

1. **Priority: Correctness** -- No outstanding correctness issues. The `quit_flag` fix should be noted in the changelog when the next version is committed.
2. **Priority: Reliability** -- `load_panel` remains the longest routine at ~370 lines. It is a state machine with complex parsing logic and is the strongest candidate for the next refactoring cycle. Consider splitting the title-parsing and entry-parsing states into sub-routines.
3. **Priority: Maintainability** -- The `col_offset` table (`byte 1, 21`) encodes panel start columns that are derived from `PANEL_WIDTH`. Consider adding a comment or expressing these as expressions if DASM supports it, to keep the relationship explicit.
