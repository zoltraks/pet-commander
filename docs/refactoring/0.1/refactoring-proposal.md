# Refactoring Proposal -- Version 0.1

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Active -->

## Problem

Analysis traced execution flow from `main_loop` through every handler, mapped zero-page pointer usage across all routines, and catalogued duplication against the Rule of Three in `REFACTORING.md`.

The primary focus is **duplication in entry-table addressing and file-operation cancel paths**, with secondary findings for redundant stores, unnecessary full redraws, magic numbers, and routine length.

Three routines (`entry_record_sp`, `selected_entry_sp`, `draw_entry`) each independently implement the same panel-base selection and `mul20` addition pattern. Three file-operation handlers (`op_delete`, `op_rename`, `op_copy`) each end with an identical cancel block. These are the strongest candidates for extraction under the Rule of Three.

Sections touched: KERNAL wrappers, drawing, formatting helpers, directory loader, file operations.

## Goal

Extract a shared `panel_entry_sp` subroutine for entry-table address computation, eliminating three copies of the same logic. Extract a shared `op_cancel` label for the file-operation cancel path. Fix the redundant store in the directory type parser. Replace `full_redraw` calls after file operations with `redraw_panels` since frames do not change. Introduce named constants for panel column layout. Split `draw_panel` into header and row sub-routines for readability.

## Findings

### Finding 1: Duplicate entry-table base address setup

**Issue**

Three routines independently select the panel entry-table base address and add `index * 20`:

`entry_record_sp` at `src/commander.asm:1590-1619`:

```asm
entry_record_sp:
        lda cur_panel
        bne ers_p1
        lda #<entries_p0
        sta sp_lo
        lda #>entries_p0
        sta sp_hi
        jmp ers_add
ers_p1:
        lda #<entries_p1
        sta sp_lo
        lda #>entries_p1
        sta sp_hi
ers_add:
        ldx cur_panel
        lda p_count,x
        jsr mul20
        lda sp_lo
        clc
        adc m20_lo
        sta sp_lo
        lda sp_hi
        adc m20_hi
        sta sp_hi
        rts
```

`selected_entry_sp` at `src/commander.asm:1626-1667` repeats the same base-selection and `mul20` addition, differing only in using `p_sel` instead of `p_count`.

`draw_entry` at `src/commander.asm:910-939` repeats the same base-selection and `mul20` addition, using `cur_absidx`.

**Impact**

Three copies of the same logic means any change to the entry-table layout (e.g. different base addresses, different multiply) must be applied in three places. Missing one would silently corrupt addressing.

**Recommendation**

Extract a shared `panel_entry_sp` routine that takes the index in `cur_absidx` and `cur_panel`, sets up `sp_lo/sp_hi` to point at the correct record. Both `entry_record_sp` and `selected_entry_sp` become thin wrappers that load the index into `cur_absidx` and call `panel_entry_sp`. `draw_entry` calls `panel_entry_sp` directly since it already has `cur_absidx`.

**Risk Level**: Major

**Breaking Change Assessment**: Internal Breaking Change -- label names change, but no observable behaviour change.

**Example**

Before (three copies):

```asm
entry_record_sp:
        lda cur_panel
        bne ers_p1
        lda #<entries_p0
        ...
```

After (one shared routine):

```asm
; panel_entry_sp: sp = entries_pN + cur_absidx * 20
; Uses cur_panel to select table, cur_absidx as index.
panel_entry_sp:
        lda cur_panel
        bne pes_p1
        lda #<entries_p0
        sta sp_lo
        lda #>entries_p0
        sta sp_hi
        jmp pes_add
pes_p1:
        lda #<entries_p1
        sta sp_lo
        lda #>entries_p1
        sta sp_hi
pes_add:
        lda cur_absidx
        jsr mul20
        lda sp_lo
        clc
        adc m20_lo
        sta sp_lo
        lda sp_hi
        adc m20_hi
        sta sp_hi
        rts

; entry_record_sp: sp = entries_pN + p_count[N] * 20
entry_record_sp:
        ldx cur_panel
        lda p_count,x
        sta cur_absidx
        jmp panel_entry_sp

; selected_entry_sp: sp = entries_pN + p_sel[N] * 20
; Returns C=1 if panel is empty.
selected_entry_sp:
        lda active_panel
        sta cur_panel
        ldx cur_panel
        lda p_count,x
        beq ses_empty
        lda p_sel,x
        sta cur_absidx
        jsr panel_entry_sp
        clc
        rts
ses_empty:
        sec
        rts
```

### Finding 2: Duplicate cancel path in file operations

**Issue**

Three file-operation handlers end with an identical cancel block:

`op_del_cancel` at `src/commander.asm:1761-1765`:

```asm
op_del_cancel:
        jsr clear_status
        jsr full_redraw
        rts
```

`op_ren_cancel` at `src/commander.asm:1851-1855` and `op_cp_cancel` at `src/commander.asm:1941-1945` are byte-for-byte identical.

**Impact**

Three copies of a two-instruction sequence. Any change to the cancel cleanup (e.g. switching from `full_redraw` to `redraw_panels` per Finding 4) must be applied in three places.

**Recommendation**

Replace the three labels with jumps to a shared `op_cancel` label. This is a one-line change per site.

**Risk Level**: Minor

**Breaking Change Assessment**: No Breaking Change -- identical behaviour, fewer labels.

**Example**

Before:

```asm
op_del_cancel:
        jsr clear_status
        jsr full_redraw
        rts
```

After:

```asm
op_del_cancel:
        jmp op_cancel
...
op_cancel:
        jsr clear_status
        jsr redraw_panels
        rts
```

### Finding 3: Redundant store in directory type parsing

**Issue**

In `lp_b_s2` at `src/commander.asm:1497-1514`, the first type character is stored twice:

```asm
        ldy #2
        sta (sp_lo),y           ; store raw PETSCII
        jsr petscii_to_screen   ; convert A to screen code
        ldy #2
        sta (sp_lo),y           ; overwrite with screen code
```

The first store is immediately overwritten by the second. The raw PETSCII value is never read back.

**Impact**

One wasted store instruction per directory entry. Not a correctness issue, but a code clarity issue -- a reader might think the first store is intentional.

**Recommendation**

Remove the first `sta (sp_lo),y` and the preceding `ldy #2`. Keep only the screen-code store.

**Risk Level**: Suggestion

**Breaking Change Assessment**: No Breaking Change -- identical observable behaviour.

**Example**

Before:

```asm
        ldy #2
        sta (sp_lo),y
        jsr petscii_to_screen
        ldy #2
        sta (sp_lo),y
```

After:

```asm
        jsr petscii_to_screen
        ldy #2
        sta (sp_lo),y
```

### Finding 4: Unnecessary full_redraw after file operations

**Issue**

Four call sites use `full_redraw` after a file operation completes:

- `do_reload` at `src/commander.asm:345`
- `op_del_have` at `src/commander.asm:1758`
- `op_ren_send` at `src/commander.asm:1848`
- `op_cp_send` at `src/commander.asm:1938`

`full_redraw` calls `clear_screen`, `draw_title_bar`, `draw_frames`, `draw_help_bar`, then `redraw_panels`. After a file operation, the title bar, frames, and help bar have not changed. Only the panel content and status row need refreshing.

**Impact**

Each file operation performs a full screen clear and frame redraw (approximately 1000 bytes written for clear, plus 40 bytes for title, plus frame drawing) that is unnecessary. On a 1 MHz 6502, this adds visible latency after delete, rename, copy, and reload operations.

**Recommendation**

Replace `jsr full_redraw` with `jsr redraw_panels` at the four post-operation sites. `redraw_panels` draws both panels and the status row, which is sufficient. The frames, title bar, and help bar remain from the previous draw and are unchanged.

**Risk Level**: Minor

**Breaking Change Assessment**: Output Layout Change -- the screen is not fully cleared before redraw, so any stray characters outside the panel content areas would persist. However, since the previous draw was a `full_redraw` and no routine writes outside the panel content areas, title bar, help bar, or frames, there are no stray characters. The final screen state is identical.

**Example**

Before:

```asm
        jsr load_panel
        jsr full_redraw
        rts
```

After:

```asm
        jsr load_panel
        jsr redraw_panels
        rts
```

### Finding 5: Magic numbers for panel column layout

**Issue**

`draw_frames` and `draw_panel` use hardcoded column indices:

- `19` -- right edge of left panel (col 19)
- `20` -- left edge of right panel (col 20)
- `39` -- right edge of right panel (col 39)
- `18` -- inner width of each panel (cols 1..18 inside the frame)

These appear in `draw_frames` at `src/commander.asm:540-613` and in `draw_panel` at `src/commander.asm:740-846`.

**Impact**

The panel width is implicitly 20 columns (cols 0..19 for left, 20..39 for right) and the inner width is 18. Changing the panel width requires finding and updating all hardcoded values. No constant exists in the equates section for these.

**Recommendation**

Add `PANEL_WIDTH = 20` and `PANEL_INNER = 18` to the layout constants section. Replace the magic numbers in `draw_frames` and `draw_panel` with these constants. The `col_offset` table already encodes the panel start columns (1 and 21); document that `col_offset = frame_left + 1`.

**Risk Level**: Suggestion

**Breaking Change Assessment**: No Breaking Change -- constants resolve to the same values.

**Example**

Before:

```asm
        cpy #19
        bne df_top1
```

After:

```asm
        cpy #(PANEL_WIDTH-1)
        bne df_top1
```

### Finding 6: draw_panel mixes header and row rendering

**Issue**

`draw_panel` at `src/commander.asm:714-887` is 173 lines long. It handles both the header row (drive number + disk title, reverse video) and the 20 file rows (clear, draw entry, highlight selection). The header and row logic are independent -- the header is drawn once, then the row loop runs.

**Impact**

The routine is the second-longest in the file after `load_panel`. A reader must scan past the header logic to find the row loop. The header rendering and row rendering have different concerns (title formatting vs. entry rendering and highlight).

**Recommendation**

Extract the header rendering (lines 721-807) into `draw_panel_header` and the row loop (lines 809-887) into `draw_panel_rows`. `draw_panel` becomes a three-line dispatcher:

```asm
draw_panel:
        jsr draw_panel_header
        jsr draw_panel_rows
        rts
```

**Risk Level**: Suggestion

**Breaking Change Assessment**: Internal Breaking Change -- new labels, same behaviour.

**Example**

Before:

```asm
draw_panel:
        sta cur_panel
        tax
        ...173 lines...
        rts
```

After:

```asm
draw_panel:
        sta cur_panel
        jsr draw_panel_header
        jsr draw_panel_rows
        rts
```

## Plan

Each step must leave the program assembling cleanly and running. Tidy steps are separate from structural steps.

**Step 1: Extract panel_entry_sp**

Introduce `panel_entry_sp` alongside the existing `entry_record_sp`. Migrate `entry_record_sp` to call it. Migrate `selected_entry_sp` to call it. Migrate `draw_entry` to call it directly. Remove the old base-selection code from each. Update `ARCHITECTURE.md` module table to list `panel_entry_sp`.

**Step 2: Extract op_cancel**

Introduce `op_cancel` label. Replace `op_del_cancel`, `op_ren_cancel`, `op_cp_cancel` bodies with `jmp op_cancel`. Remove the old bodies.

**Step 3: Remove redundant store in lp_b_s2**

Delete the first `ldy #2` / `sta (sp_lo),y` pair before `jsr petscii_to_screen` in `lp_b_s2`.

**Step 4: Replace full_redraw with redraw_panels after file operations**

Change the four post-operation call sites (`do_reload`, `op_del_have`, `op_ren_send`, `op_cp_send`) from `jsr full_redraw` to `jsr redraw_panels`. The `op_cancel` label from Step 2 also uses `redraw_panels`.

**Step 5: Add panel layout constants**

Add `PANEL_WIDTH = 20` and `PANEL_INNER = 18` to the layout constants section. Replace magic numbers 19, 20, 39, and 18 in `draw_frames` and `draw_panel` (now `draw_panel_header` and `draw_panel_rows` if Step 6 has been done, otherwise `draw_panel`) with these constants. Update `SPECIFICATION.md` constants table.

**Step 6: Split draw_panel into header and rows**

Extract `draw_panel_header` and `draw_panel_rows` from `draw_panel`. `draw_panel` becomes a dispatcher. Update `ARCHITECTURE.md` module table to list the new routines.

## Step Granularity

Steps 1 through 6 are each self-contained. Step 1 is the largest (touches three call sites and introduces a new routine). Steps 2 and 3 are single-spot changes. Step 4 is four one-line changes. Step 5 is a constants addition plus mechanical replacement. Step 6 is a structural extraction within one routine.

If Step 1 reveals an unexpected addressing issue, stop and update this proposal before continuing.

## Risk

The highest-risk step is **Step 1** (extract `panel_entry_sp`) because it touches three routines that address entry tables. A regression in addressing would corrupt directory display or file operations. The behaviour check must verify: both panels display correctly, navigation tracks the cursor, delete/rename/copy operate on the correct file.

Step 4 (replace `full_redraw`) has a moderate risk: if any routine writes stray characters outside the panel content areas between operations, those characters would persist. The analysis confirms no routine does this -- all screen writes go through the drawing module which only writes to panel content, title bar, help bar, and frame positions.

Steps 2, 3, 5, and 6 are low risk.

## Acceptance Criteria

- Identical observable behaviour: both panels display the fixture directory, navigation works, all DOS operations produce the correct status line.
- The `$0401` load address is preserved.
- A clean assemble: `./build.sh` reports `Complete. (0)` with zero errors and zero warnings.
- A clean headless smoke run: 20 million cycles under `xpet -warp` without crashing or runaway writes.
- `ARCHITECTURE.md` and `SPECIFICATION.md` are updated to reflect new routines and constants.
