# Changes

## Version 0.1

Initial documented version of PET Commander, a two-panel file manager for the Commodore PET 3032.

- Added **two-panel directory browser** that loads and displays drive 8 in both panels on startup, with a highlighted, scrollable selection.
- Added **file operations** for delete, rename, and copy, each driven by a single key and surfaced through CBM-DOS commands on channel 15.
- Added **drive status reporting** so the bottom row shows the drive response after every DOS command.
- Added **clean BASIC exit** that restores borrowed zero-page bytes so the machine stays usable after Q or RUN/STOP.
- Added **disk-image autostart** via `example/work.d64` to work around unreliable VICE PRG injection at `$0401`.
