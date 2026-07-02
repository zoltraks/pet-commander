# Menu Bar UI Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/0.3/menu-bar-ui.md`.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md`.

## Documentation Updates

Update the active documentation set before any source modification:

- `PROJECT.md`: Remove FR-W2 (per-panel drive non-goal). Add new functional requirements for the menu bar, dropdown menus, status line, find feature, info windows, and per-panel drive selection. Update the key bindings in the use cases. Update the Current State and Known Limitations sections.
- `ARCHITECTURE.md`: Add a Menu module to the module table. Update the Screen drawing module entry labels (replace `draw_title_bar`/`draw_help_bar` with `draw_menu_bar`/`draw_status_line`, add dropdown and window routines). Update the State Domains section to add menu state and filter state. Update the Data Flow section to show menu dispatch.
- `SPECIFICATION.md`: Update the Screen Layout section to describe the new row layout (menu bar row 0, panels rows 1-23, status line row 24). Update the Keyboard and Input Bindings table. Add sections for Menu System, Dropdown Menus, Info Windows, Find Feature, and Status Line content. Update the Startup Sequence and Known Limitations sections.

## Step by Step Implementation

### Step 1: New constants and state variables

Add layout constants for the menu bar, dropdown windows, and info windows. Add state variables for menu navigation and find filtering.

Section in `src/commander.asm`: after the existing layout constants (line ~78) and after the per-panel state (line ~176).

New constants:

    ; ---- Menu layout constants ----------------------------
    MENU_BAR_ROW   = 0             ; menu bar screen row
    STATUS_ROW     = 24            ; status line screen row
    MENU_COUNT     = 3             ; number of menus (File, Disk, Help)
    MENU_FILE      = 0
    MENU_DISK      = 1
    MENU_HELP      = 2
    DROP_WIDTH     = 12            ; dropdown interior width (items area)
    DROP_COLS      = 14            ; dropdown total width including borders

New state variables:

    ; ---- Menu state ---------------------------------------
    menu_active:   byte 0          ; 0 = panel mode, 1 = menu mode
    menu_idx:      byte 0          ; current menu (0=File, 1=Disk, 2=Help)
    menu_sel:      byte 0          ; selected item within current dropdown

    ; ---- Find/filter state --------------------------------
    p_filter:      byte 0, 0       ; nonzero = filter active per panel
    p_filter_str:  ds 32, 0        ; 16-char filter string per panel (2 panels)
    p_filter_len:  byte 0, 0       ; filter string length per panel

New PETSCII key constant:

    K_RVS_OFF = $92               ; RVS OFF key (OFF RVS on PET keyboard)

### Step 2: Replace draw_title_bar with draw_menu_bar

Replace the `draw_title_bar` routine and `title_str` data with `draw_menu_bar`. The menu bar is row 0, 40 columns, reverse-video with half-block borders.

Section in `src/commander.asm`: replace `draw_title_bar` (line ~520) and `title_str` (line ~544).

    draw_menu_bar:
            ldx #0
            jsr row_addr_sp
            ; Left border
            ldy #0
            lda #HB_RLEFT          ; $E1 reversed left half-block
            sta (sp_lo),y
            ; Right border
            ldy #39
            lda #HB_LEFT           ; $61 left half-block
            sta (sp_lo),y
            ; Fill cols 1-38 with reversed space
            ldy #1
            lda #$A0               ; reversed space
    dmb_fill:
            sta (sp_lo),y
            iny
            cpy #39
            bne dmb_fill
            ; Write menu titles at fixed positions
            ; FILE at cols 3-6, DISK at cols 9-12, '-' at col 35
            ; When menu_active, the current menu's title is normal video
            ldx menu_idx
            lda menu_col,x         ; column of current menu title
            sta dmb_cur_col
            ; Write FILE
            ldy #3
            lda #$06               ; 'F' screen code
            ldx menu_active
            beq dmb_file_rev
            lda menu_idx
            cmp #MENU_FILE
            bne dmb_file_rev
            lda #$06               ; normal video (no bit 7)
            jmp dmb_file_store
    dmb_file_rev:
            ora #$80               ; reverse
    dmb_file_store:
            sta (sp_lo),y
            ; ... (I, L, E for FILE, similar for DISK and '-')

The menu bar data table provides the screen codes and column positions for each title. The active menu title is rendered without bit 7; inactive titles have bit 7 set.

### Step 3: Replace draw_help_bar with draw_status_line

Replace the `draw_help_bar` routine and `help_str` data with `draw_status_line`. The status line is row 24, showing the selected file's info.

Section in `src/commander.asm`: replace `draw_help_bar` (line ~658) and `help_str` (line ~672).

    draw_status_line:
            ldx #24
            jsr row_addr_sp
            ; Left border
            ldy #0
            lda #HB_RLEFT
            sta (sp_lo),y
            ; Right border
            ldy #39
            lda #HB_LEFT
            sta (sp_lo),y
            ; Fill cols 1-38 with reversed space
            ldy #1
            lda #$A0
    dsl_fill:
            sta (sp_lo),y
            iny
            cpy #39
            bne dsl_fill
            ; If status_msg is set, overlay the status buffer
            lda status_msg
            bne dsl_status
            ; Otherwise, show selected file info
            jsr draw_status_fileinfo
            jmp dsl_done
    dsl_status:
            ; Copy status_buf into the reversed bar
            ldy #1
            ldx #0
    dsl_stat_loop:
            lda status_buf,x
            beq dsl_done
            ora #$80
            sta (sp_lo),y
            inx
            iny
            cpy #39
            bne dsl_stat_loop
    dsl_done:
            rts

`draw_status_fileinfo` reads the selected entry via `selected_entry_sp`, copies the 16-char name into the status line (cols 1-16, reversed), formats the block count via `print_num3` into a 5-digit field (right-justified ending at col 37), and writes the type character at col 38. If no entry is selected, the bar stays as reversed spaces.

### Step 4: Update full_redraw and redraw_panels

Update `full_redraw` to call `draw_menu_bar` instead of `draw_title_bar`, and `draw_status_line` instead of `draw_help_bar`. Update `redraw_panels` to call `draw_status_line` instead of `draw_status` (the status overlay logic moves into `draw_status_line`).

Section in `src/commander.asm`: `full_redraw` (line ~465), `redraw_panels` (line ~473).

    full_redraw:
            jsr clear_screen
            jsr draw_menu_bar
            jsr draw_frames
            jsr draw_status_line
            ; fall through

    redraw_panels:
            lda #0
            jsr draw_panel
            lda #1
            jsr draw_panel
            jsr draw_status_line
            jsr present_screen
            rts

### Step 5: Update dispatch_key for new panel-level bindings

Remove D, N, C, L from panel-level dispatch. Add M (menu open) and RVS OFF (panel switch). Keep V, Q, RUN/STOP, cursor keys, HOME, RETURN, TAB.

Section in `src/commander.asm`: `dispatch_key` (line ~333).

    dispatch_key:
            lda key_val
            cmp #CH_Q
            beq do_quit
            cmp #K_STOP
            beq do_quit
            cmp #CH_V
            beq do_view
            cmp #CH_M
            beq do_menu_open
            cmp #K_RVS_OFF
            beq do_switch
            cmp #K_TAB
            beq do_switch
            cmp #K_RETURN
            beq do_switch
            cmp #K_UP
            beq do_up
            cmp #K_DOWN
            beq do_down
            cmp #K_HOME
            beq do_home
            rts

Add `CH_M = $4D` to the PETSCII characters section.

### Step 6: Implement menu loop and dropdown rendering

Add a `menu_loop` routine that handles menu navigation keys and renders the dropdown. When `menu_active` is set, `main_loop` routes to `menu_loop` instead of `dispatch_key`.

Section in `src/commander.asm`: new section after `dispatch_key`.

    menu_loop:
            jsr draw_menu_bar      ; redraw with active highlight
            jsr draw_dropdown      ; draw the current dropdown
            jsr present_screen
    ml_wait:
            jsr GETIN
            beq ml_wait
            sta key_val
            ; Route menu keys
            cmp #CH_M
            beq do_menu_close
            cmp #K_RVS_OFF
            beq do_menu_close
            cmp #K_STOP
            beq do_menu_close
            cmp #K_RETURN
            beq do_menu_activate
            cmp #K_LEFT
            beq do_menu_prev
            cmp #K_RIGHT
            beq do_menu_next
            cmp #K_UP
            beq do_menu_up
            cmp #K_DOWN
            beq do_menu_down
            cmp #CH_F
            beq do_menu_file
            cmp #CH_D
            beq do_menu_disk
            cmp #CH_H
            beq do_menu_help
            jmp ml_wait

`draw_dropdown` draws a bordered box below the active menu title. The box uses center-line characters (`$70`/`$6E`/`$6D`/`$7D`/`$40`/`$5D`). The top border is omitted (the menu bar serves as the top). The selected item is highlighted in reverse video.

Menu item tables define the items per menu:

    menu_file_items:
            byte "VIEW", 0,  'V'
            byte "COPY", 0,  'C'
            byte "RENAME", 0, 'N'
            byte "DELETE", 0, 'D'
            byte "INFO", 0,  'I'
            byte "FIND", 0,  'F'
            byte "QUIT", 0,  'Q'
    menu_file_count = 7

    menu_disk_items:
            byte "CHANGE", 0, 'C'
            byte "REFRESH", 0, 'R'
    menu_disk_count = 2

    menu_help_items:
            byte "ABOUT", 0, 'A'
    menu_help_count = 1

Each item is a fixed-width record: label string (null-terminated, padded to a fixed width) + shortcut key byte. The dropdown width is `DROP_COLS` (14 columns including borders).

### Step 7: Implement menu item activation

`do_menu_activate` reads `menu_idx` and `menu_sel` to determine which item was selected, then jumps to the corresponding handler.

    do_menu_activate:
            lda menu_idx
            cmp #MENU_FILE
            beq dfa_file
            cmp #MENU_DISK
            beq dfa_disk
            jmp dfa_help
    dfa_file:
            ldx menu_sel
            ; Jump table for file menu items
            cpx #0
            beq dfa_view
            cpx #1
            beq dfa_copy
            cpx #2
            beq dfa_rename
            cpx #3
            beq dfa_delete
            cpx #4
            beq dfa_info
            cpx #5
            beq dfa_find
            cpx #6
            beq dfa_quit
            rts
    dfa_view:
            jsr do_menu_close
            jmp op_view
    dfa_copy:
            jsr do_menu_close
            jmp op_copy
    ; ... etc

`do_menu_close` clears `menu_active` and calls `full_redraw` to restore the panels.

### Step 8: Implement info windows (INFO, ABOUT, CHANGE)

Add three modal window routines. Each draws a bordered window over the screen, waits for a key, then restores via `full_redraw`.

`op_info`: Opens a window showing the selected file's details. Uses `selected_entry_sp` to read the entry record, formats the fields, and displays them.

`op_about`: Opens a window showing program name, version, and target machine. Static content.

`op_change`: Opens a window with a text prompt for a drive number. Uses a simplified `prompt_text` variant that accepts digits only. On commit, writes the new drive to `p_drive[active_panel]` and calls `load_panel`.

Each window routine:
1. Save the current screen state (not needed if `full_redraw` can restore).
2. Draw the window border and content into `BUFFER`.
3. Call `present_screen`.
4. Wait for a key (or text input for CHANGE).
5. Call `full_redraw` to restore the panels.

### Step 9: Implement find/filter feature

Add `op_find` that opens a `FIND:` prompt on the status line. The user types a search string (up to 16 chars). On RETURN:

- If the string is empty, clear the filter (`p_filter[active_panel] = 0`).
- If non-empty, copy the string to `p_filter_str[active_panel*16]`, set `p_filter_len[active_panel]`, and set `p_filter[active_panel] = 1`.

Update `draw_panel_rows` to skip entries that do not match the filter when `p_filter` is active. The matching is a case-insensitive substring search: for each entry, scan the 16-char name for the filter string, comparing bytes with case folding (convert both to uppercase before comparing).

The selection and scroll logic needs adjustment: `p_count` should reflect the filtered count, not the raw count. This can be done by computing the filtered count during `draw_panel_rows` and storing it, or by maintaining a separate filtered count variable. The simpler approach: when the filter is active, `cursor_down` and `cursor_up` skip non-matching entries.

Alternative simpler approach: build a filtered index array. When the filter is set, scan the entry table and write matching indices into a `p_filtered` array (up to MAX_ENTRY bytes per panel). `p_count` is set to the filtered count. All navigation and drawing use the filtered array. This is cleaner but uses 128 bytes of RAM for the two arrays.

Use the filtered-index approach: add `p_filtered_p0: ds MAX_ENTRY, 0` and `p_filtered_p1: ds MAX_ENTRY, 0` (64 bytes each, 128 total). When the filter is set or cleared, rebuild the filtered index and update `p_count`. Navigation and drawing index through the filtered array.

### Step 10: Update main_loop for menu state

Update `main_loop` to check `menu_active` and route to `menu_loop` or `dispatch_key` accordingly.

Section in `src/commander.asm`: `main_loop` (line ~194).

    main_loop:
            lda menu_active
            bne ml_dispatch
            jsr GETIN
            beq main_loop
            sta key_val
            jsr dispatch_key
            lda quit_flag
            bne do_exit
            jmp main_loop
    ml_dispatch:
            jsr menu_loop
            lda quit_flag
            bne do_exit
            jmp main_loop

### Step 11: Update startup sequence

Update `start` to initialize the new state variables (`menu_active = 0`, `p_filter = 0, 0`). No change to the panel loading logic.

Section in `src/commander.asm`: `start` (line ~182) and `init` (line ~259).

### Step 12: Update clear_status and set_status

`clear_status` now calls `draw_status_line` instead of `draw_help_bar`. `set_status` calls `draw_status_line` instead of `draw_help_bar` + `draw_status`. The status overlay logic is inside `draw_status_line`.

Section in `src/commander.asm`: `clear_status` (line ~705), `set_status` (line ~717).

## Implementation Order

1. Update documentation (`PROJECT.md`, `ARCHITECTURE.md`, `SPECIFICATION.md`).
2. Add new constants and state variables (Step 1).
3. Replace `draw_title_bar` with `draw_menu_bar` (Step 2).
4. Replace `draw_help_bar` with `draw_status_line` (Step 3).
5. Update `full_redraw` and `redraw_panels` (Step 4).
6. Update `dispatch_key` (Step 5).
7. Implement `menu_loop` and dropdown rendering (Step 6).
8. Implement menu item activation (Step 7).
9. Implement info windows (Step 8).
10. Implement find/filter feature (Step 9).
11. Update `main_loop` (Step 10).
12. Update startup sequence (Step 11).
13. Update `clear_status` and `set_status` (Step 12).
14. Refresh the example disk if fixtures change.
15. Run the verification loop.

## Testing Strategy

**Build verification**

- Assemble with `./build.sh`. Expect `Complete. (0)` with zero errors and zero warnings.
- Confirm the PRG load address is `$0401`.
- The PRG size will increase by roughly 1-2 KB due to the new menu, dropdown, window, and find routines. The total should remain well under 32 KB.

**Behaviour checks**

Exercise these flows against the D64 fixture with a graphical `xpet` run:

1. **Startup**: The menu bar shows `FILE  DISK  ...  -` on row 0. The panels show the directory. The status line shows the first file's info on row 24.
2. **Menu open/close**: Press `M`. The File dropdown appears below `FILE`. Press `M` again. The dropdown closes.
3. **Menu navigation**: Open the menu. Press cursor right to switch to Disk. Press cursor right again to switch to Help. Press cursor left to go back to Disk, then File.
4. **Menu item navigation**: Open the File menu. Press cursor down to move through VIEW, COPY, RENAME, DELETE, INFO, FIND, QUIT. Press cursor up to go back.
5. **Menu activation**: Open the File menu, select VIEW, press RETURN. The viewer opens. Close the viewer with E. The menu is closed and panels are restored.
6. **Panel switch**: Press RVS OFF. The active panel switches. Press RETURN. The panel switches again.
7. **Status line update**: Move the selection up and down. The status line updates to show the selected file's name, size, and type.
8. **Change drive**: Open Disk menu, select CHANGE, press RETURN. The change-drive window appears. Type `8`, press RETURN. The panel reloads from drive 8 (no visible change but confirms the flow).
9. **Find**: Open File menu, select FIND, press RETURN. Type a search string, press RETURN. The panel filters to matching entries. Open FIND again, press RETURN with empty string. The filter clears.
10. **About**: Open Help menu, select ABOUT, press RETURN. The about window appears showing `PET COMMANDER v0.3`. Press any key to close.
11. **Info**: Open File menu, select INFO, press RETURN. The file info window appears with the selected file's details. Press any key to close.
12. **Quit**: Open File menu, select QUIT, press RETURN. The program exits to BASIC. Also verify pressing `Q` during panel navigation still quits.
13. **Viewer**: Press `V` during panel navigation. The viewer opens. Verify all viewer keys still work. Close with E.

**Headless smoke run**

Run under `xpet -warp -limitcycles 100000000` and confirm no crash or runaway writes.

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp`.
- Graphical behaviour check for the changed features (all 13 behaviour checks above).
