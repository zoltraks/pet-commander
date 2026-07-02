# Redesign Main UI with Menu Bar, Status Line, and Dropdown Menus

**Type:** Feature

## Summary

Redesign the main screen to replace the title bar and help bar with a menu bar (row 0) and a status line (row 24). Add dropdown menus (File, Disk, Help) activated by the `M` key or RVS OFF (`$92`), since the PET has no Esc or Tab keys. Add per-panel drive selection, a FIND search feature, and info windows (file info, about, change disk). The panels are reorganized to use rows 1-23 with the menu bar and status line as borders.

## Description

### Main Screen Layout

The main screen is redesigned to a 40-column, 25-row layout:

- **Row 0 -- Menu bar**: Reverse-video bar with half-block borders (`$E1` left, `$61` right). Shows the menu titles `FILE`, `DISK`, and `-` (Help) in reversed screen codes, separated by reversed spaces. The active menu title (when a dropdown is open) is rendered in normal video. The rest of the bar is reversed space (`$A0`).
- **Row 1 -- Panel top border**: Center-line box drawing. Left panel: `$70` (TL), `$40` (H) across cols 1-18, `$6E` (TR) at col 19. Right panel: `$70` (TL) at col 20, `$40` (H) across cols 21-38, `$6E` (TR) at col 39. Col 0 is the left edge of the menu bar's half-block border延续 -- no, col 0 is `$70` for the left panel. The two panels share a double vertical border at cols 19-20 (`$6E` + `$70` or a T-junction pattern).
- **Rows 2-22 -- Panel content**: Left panel cols 0-19, right panel cols 20-39. Each panel has vertical borders (`$5D`) at its outer edges and the center divider. Row 2 is the panel header (drive number + disk title, reversed). Rows 3-22 are the 20 directory entry rows.
- **Row 23 -- Panel bottom border**: Mirrors row 1 with `$6D` (BL) and `$7D` (BR) corners.
- **Row 24 -- Status line**: Reverse-video bar with half-block borders (`$E1` left, `$61` right). Shows the selected file's full name, size in blocks, and type character, right-aligned. Format: `[rev]LONG-FILENAME-TEXT.TXT    12528 S[/rev]` where the filename is left-justified, the block count is right-justified, and the type character follows. When no file is selected (empty panel), the status line shows reversed spaces. When a DOS status message is active, it overrides the file info display temporarily, then reverts to the file info on the next redraw.

### Menu Bar Titles

The menu bar shows three titles:

| Title  | Position (col, 0-indexed within content) | Shortcut key |
|--------|------------------------------------------|--------------|
| `FILE` | cols 3-6                                 | `F`          |
| `DISK` | cols 9-12                                | `D`          |
| `-`    | col 35 (Help, shown as a dash)           | `H`          |

Wait -- the PET has no F-key row. The shortcut keys are the letter keys: pressing `F` while the menu is open activates the File menu, `D` activates Disk, `H` activates Help. When no menu is open, these letters have their existing panel-level bindings (but see Key Bindings below for conflicts).

### Dropdown Menus

When `M` or RVS OFF (`$92`) is pressed, the menu bar activates. The first menu (File) is selected by default. Left/right cursor keys switch between File, Disk, and Help. Up/down cursor keys move the selection within the open dropdown. RETURN activates the selected item. `M` or RVS OFF or RUN/STOP closes the menu and returns to panel navigation.

Each dropdown overlays the panel content below its menu title. The dropdown is a bordered box using center-line drawing characters, with the top border replaced by the menu bar row (the dropdown appears to drop from the menu bar).

#### File Menu

Items (7), dropping from col 3:

| Item    | Shortcut | Action                              |
|---------|----------|-------------------------------------|
| VIEW    | V        | Open the viewer on the selected file. |
| COPY    | C        | Copy the selected file (existing op_copy). |
| RENAME  | N        | Rename the selected file (existing op_rename). |
| DELETE  | D        | Delete the selected file (existing op_delete). |
| INFO    | I        | Open the file info window.          |
| FIND    | F        | Open the find/search prompt.        |
| QUIT    | Q        | Quit to BASIC.                      |

Each item shows the label left-justified and the shortcut key right-justified within the dropdown width. The selected item is highlighted in reverse video.

#### Disk Menu

Items (2), dropping from col 9:

| Item    | Shortcut | Action                              |
|---------|----------|-------------------------------------|
| CHANGE  | C        | Open the change-drive window.       |
| REFRESH | R        | Re-load the active panel (existing do_reload). |

#### Help Menu

Items (1), dropping from col 35:

| Item    | Shortcut | Action                              |
|---------|----------|-------------------------------------|
| ABOUT   | A        | Open the about window.              |

### Info Windows

#### File Info Window (INFO)

A modal window showing detailed information about the selected file:

- Window title: `FILE INFORMATION`
- Fields: full filename (16 chars), file type character, block count (decimal), approximate size in bytes (blocks * 254), and the drive number the file resides on.
- Window is bordered, centered on screen, approximately 30 columns x 10 rows.
- Any key closes the window and restores the panels.

#### About Window (ABOUT)

A modal window showing program information:

- Window title: `ABOUT`
- Fields: program name (`PET COMMANDER`), version (`0.3`), target machine (`COMMODORE PET 3032`), and a one-line description.
- Window is bordered, centered, approximately 30 columns x 8 rows.
- Any key closes the window.

#### Change Drive Window (CHANGE)

A modal window for selecting the active panel's drive:

- Window title: `CHANGE DRIVE`
- Shows the current drive number and prompts for a new drive number (8, 9, 10, or 11).
- The user types a one- or two-digit number and presses RETURN, or presses RUN/STOP to cancel.
- On commit, the active panel's `p_drive` is updated and the panel is reloaded from the new drive.
- Window is bordered, centered, approximately 24 columns x 7 rows.

### Find Feature (FIND)

When FIND is activated, a bottom-line text prompt appears: `FIND:`. The user types a search string (up to 16 characters) and presses RETURN. The active panel's entry list is filtered to show only entries whose name contains the search string (case-insensitive match). A `FOUND N ENTRIES` status message appears. Pressing FIND again with an empty string clears the filter and shows all entries.

The filter is implemented by adding a `p_filter` flag and a `p_filter_str` buffer per panel. When the filter is active, `draw_panel_rows` skips entries whose name does not contain the filter string. The selection and scroll logic operates on the filtered set. The filter persists until cleared.

### Per-Panel Drive Selection

The `p_drive` array already exists (both default to 8). This change makes it user-settable via the Disk menu CHANGE option. `load_panel` already reads `p_drive` for the device number, so no change to the loader is needed. The panel header already shows the drive number. The right panel can now be set to a different drive (e.g. 10).

This removes the FR-W2 non-goal.

### Status Line Content

The status line (row 24) shows information about the currently selected file in the active panel:

- Full 16-character filename (left-justified after the left border)
- Block count as a 5-digit decimal number (right-justified before the type)
- File type character (one letter, before the right border)

When a DOS status message is active (after a file operation), the status message overrides the file info display. The file info returns on the next redraw that does not have a status message.

### Key Bindings

The key bindings change significantly. The PET has no Esc or Tab keys, so menu activation uses `M` or RVS OFF (`$92`, the OFF RVS key).

**Panel navigation (menu closed):**

| Key            | Action                                  |
|----------------|-----------------------------------------|
| Cursor up      | Move selection up.                      |
| Cursor down    | Move selection down.                    |
| HOME           | Jump to first entry.                    |
| RETURN         | Switch active panel.                    |
| RVS OFF ($92)  | Switch active panel (replaces TAB).     |
| M              | Open the menu bar (activates File menu).|
| V              | Open viewer (shortcut, same as File > VIEW). |
| Q              | Quit to BASIC.                          |
| RUN/STOP       | Quit to BASIC.                          |

Note: The existing single-key shortcuts for DELETE (D), RENAME (N), COPY (C), and RELOAD (L) are removed from panel-level dispatch. These operations are now accessed through the File and Disk menus. This avoids key conflicts with menu navigation (D = Disk menu, F = File menu, etc.) and simplifies the main loop. `V` is retained as a panel-level shortcut for the viewer because it is the most frequently used operation. `Q` is retained for quit.

Note: TAB (`$09`) is also accepted as a panel switch, since the PET 3032 graphics keyboard can produce `$09` via the OFF RVS key position. Both `$09` and `$92` (RVS OFF) switch panels. The user explicitly requested RVS OFF for panel switching.

**Menu navigation (menu open):**

| Key            | Action                                  |
|----------------|-----------------------------------------|
| Cursor left    | Switch to the previous menu (File -> Disk -> Help -> File). |
| Cursor right   | Switch to the next menu.                |
| Cursor up      | Move selection up within the dropdown.  |
| Cursor down    | Move selection down within the dropdown.|
| RETURN         | Activate the selected menu item.        |
| M              | Close the menu, return to panels.       |
| RVS OFF ($92)  | Close the menu, return to panels.       |
| RUN/STOP       | Close the menu, return to panels.       |
| F              | Jump to File menu.                      |
| D              | Jump to Disk menu.                      |
| H              | Jump to Help menu.                      |

**Viewer keys**: Unchanged from the current implementation.

## Use Cases

- When the user presses `M`, the menu bar activates with the File menu open. The dropdown appears below `FILE` in the menu bar. The first item (VIEW) is highlighted.
- When the user presses cursor right, the Disk menu dropdown replaces the File dropdown. The first item (CHANGE) is highlighted.
- When the user presses cursor down, the selection moves to the next item in the current dropdown.
- When the user presses RETURN on VIEW, the viewer opens on the selected file. When the viewer closes, the menu is closed and the panels are restored.
- When the user presses `M` again, the menu closes and the panels are fully visible again.
- When the user selects Disk > CHANGE, the change-drive window appears. The user types `10` and presses RETURN. The active panel reloads from drive 10. The panel header shows `10:` and the status line updates.
- When the user selects File > FIND, a `FIND:` prompt appears. The user types `TEST` and presses RETURN. The panel shows only entries containing `TEST`. The status line shows `FOUND 3 ENTRIES`. The user presses FIND again with an empty string to clear the filter.
- When the user selects Help > ABOUT, the about window appears showing `PET COMMANDER v0.3`. Any key closes it.
- When the user selects File > INFO, the file info window appears showing the full filename, type, block count, and byte size. Any key closes it.
- When the user presses RVS OFF during panel navigation, the active panel switches from left to right (or vice versa).
- When the user moves the selection in a panel, the status line (row 24) updates to show the newly selected file's full name, block count, and type.

## Hints

- The existing `draw_title_bar` and `draw_help_bar` routines are replaced by `draw_menu_bar` and `draw_status_line`. The `title_str` and `help_str` data tables are replaced.
- The panel frame drawing (`draw_frames`) shifts: row 1 becomes the top border (was row 1 already), rows 2-22 remain content, row 23 remains the bottom border. Row 0 changes from a title bar to a menu bar; row 24 changes from a help bar to a status line. The frame layout itself does not change row positions.
- The dropdown menus can reuse the box-drawing routines and the `row_addr_sp` helper. Each dropdown is a small bordered window drawn over the panel content.
- The info windows (INFO, ABOUT, CHANGE) are modal overlays similar to the viewer: they draw over the screen, wait for a key, then restore via `full_redraw`.
- The find feature's filtering can be implemented by scanning the entry table during `draw_panel_rows` and skipping non-matching entries, adjusting the visible index accordingly. This avoids a separate filtered entry table.
- The per-panel drive selection requires only that `p_drive` be settable; `load_panel` already reads it. The change-drive window is a small prompt that writes the new drive number to `p_drive[active_panel]` and calls `load_panel`.
- The status line content can be built from the selected entry's record (name at offset 3, type at offset 2, block count at offsets 0-1) using the existing `selected_entry_sp` and `print_num3` helpers.
- Menu state needs a new byte: `menu_active` (0 = panels, 1 = menu), `menu_idx` (0=File, 1=Disk, 2=Help), `menu_sel` (selected item within the current dropdown).

## Out of Scope

- No change to the viewer's internal layout, key bindings, or rendering. The viewer is invoked the same way (via `op_view`).
- No change to the chunk buffer size or viewer chunk loading.
- No change to the DOS command construction or status reading.
- No mouse support.
- No submenus (cascading menus).
- No menu item keyboard shortcuts that work without opening the menu first (except V for viewer and Q for quit, which remain as panel-level shortcuts).
- No persistent menu state across viewer opens; the menu closes when the viewer opens.
- No change to the entry record format or the directory parse state machine.
- No wildcard or regex in FIND; the search is a simple substring match.
- No sorting of panel entries.
