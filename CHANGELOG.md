# Changes

## Version 0.2

Box-drawing fix, refactoring, and quit-on-restart bug fix.

- **Fixed** **box-drawing characters** to use the center-line style from the `commodore-pet-skill` guidelines, replacing incorrect screen codes that produced checkerboard and diagonal-fill glyphs instead of box corners and lines. T-junctions now connect the two panels at the divider.
- **Fixed** **quit-on-restart bug** where re-running the program from BASIC after quitting with Q caused immediate exit on the first key press, because `quit_flag` was not cleared during initialization.
- **Changed** **post-operation redraw** to use `redraw_panels` instead of `full_redraw` after delete, rename, copy, and reload, eliminating unnecessary full screen clears and frame redraws.
- **Refactored** **entry-table addressing** by extracting a shared `panel_entry_sp` routine, replacing three copies of the same base-selection and multiply logic in `entry_record_sp`, `selected_entry_sp`, and `draw_entry`.
- **Refactored** **file-operation cancel path** by extracting a shared `op_cancel` label, replacing three identical cleanup blocks.
- **Refactored** **`draw_panel`** by splitting it into `draw_panel_header` and `draw_panel_rows` for readability.
- **Added** **`PANEL_WIDTH` and `PANEL_INNER` constants** to replace magic numbers in frame and panel drawing code.
- **Removed** **redundant store** in the directory type parser where a raw PETSCII byte was stored and immediately overwritten by its screen-code conversion.

## Version 0.1

Initial documented version of PET Commander, a two-panel file manager for the Commodore PET 3032.

- Added **two-panel directory browser** that loads and displays drive 8 in both panels on startup, with a highlighted, scrollable selection.
- Added **file operations** for delete, rename, and copy, each driven by a single key and surfaced through CBM-DOS commands on channel 15.
- Added **drive status reporting** so the bottom row shows the drive response after every DOS command.
- Added **clean BASIC exit** that restores borrowed zero-page bytes so the machine stays usable after Q or RUN/STOP.
- Added **disk-image autostart** via `example/work.d64` to work around unreliable VICE PRG injection at `$0401`.
