# PET Commander

A two-panel file manager for the Commodore PET 3032, in the spirit of Norton Commander.

## Layout

```
 .............. PET COMMANDER -- DRIVE 8 ...............
 +--------------------+--------------------+
 | 8: DISKNAME        | 8: DISKNAME        |
 |  10 FILENAME    P  |  10 FILENAME    P  |
 |   5 ANOTHER     S  |  ...               |
 |  ...               |                    |
 +--------------------+--------------------+
 TAB-Sw N-Ren C-Cpy D-Del L-Lod Q-Quit
```

Both panels show drive 8 on startup.

## Cloning this repository

This repository uses a git submodule at `docs/skill/commodore-pet-skill` for the companion [commodore-pet-skill](https://github.com/zoltraks/commodore-pet-skill) reference material (DASM and VICE notes).

Clone with the submodule included:

```
git clone --recurse-submodules <repo-url>
```

If you already cloned without `--recurse-submodules`, initialise and fetch it afterwards:

```
git submodule update --init --recursive
```

To update `docs/skill/commodore-pet-skill` to the latest upstream commit later:

```
git submodule update --remote docs/skill/commodore-pet-skill
```

## Commands

| Key            | Action                              |
|----------------|-------------------------------------|
| TAB or RETURN  | Switch the active (highlighted) panel |
| Cursor up/down | Move selection                      |
| HOME           | Jump to first entry                  |
| L              | Re-load the active panel             |
| D              | Delete (scratch) the selected file   |
| N              | Rename the selected file             |
| C              | Copy the selected file to a new name |
| Q or RUN/STOP  | Quit back to BASIC                   |

For Delete, the program asks `Y/N`. RETURN counts as yes; any other key cancels.

For Rename and Copy, a prompt appears on the bottom line. Type up to 16 PETSCII chars; DEL backspaces; RETURN commits; RUN/STOP cancels.

After every DOS command the drive status is shown on the bottom row (e.g. `00,OK,00,00` or `63,FILE EXISTS,00,00`).

## Building

```
./build.sh
```

Uses the `dasm` Docker image if available, otherwise falls back to a local `dasm` binary in `PATH` (see `docs/skill/commodore-pet-skill/utility/dasm-assembler.md` for setup).

Output: `build/commander.prg`. PRG header carries load address `$0401`, so VICE inject-mode autostart works as-is.

## Running in VICE

```
./run.sh                 # autostarts example/work.d64
./run.sh some-other.d64  # use a different disk image (must contain commander.prg)
```

`example/work.d64` is shipped pre-built and contains the program itself plus 5 test files (2 PRG + 3 SEQ, including one with a long name) so the panels render with real entries the first time the program starts. `build.sh` refreshes the copy of `commander.prg` inside `work.d64` every time it rebuilds. Regenerate the entire disk with `example/build-work-d64.sh` if you want to add or remove sample files.

## Why autostart from disk

VICE has three autostart modes for a standalone PRG file: VirtualFS, Inject, and Disk image. The **Inject** mode writes the bytes into RAM directly and stuffs `RUN` into the keyboard buffer, but on the PET it does not initialise BASIC's text/variable pointers reliably for a PRG that lives at `$0401`, which results in `?SYNTAX ERROR IN 10` when BASIC tries to parse the injected stub.

The robust path is to embed the PRG inside the D64 and let VICE autostart the disk: VICE issues `LOAD"*",8` followed by `RUN` through BASIC's real LOAD routine, which sets every pointer correctly. As a bonus, the same disk stays mounted as drive 8 for the program to read.

`run.sh` checks that `xpet` is available in `PATH`. VICE 3.7+ finds ROMs automatically from the bindist directory (Windows) or system/user paths (Linux) -- no manual ROM setup is needed with a standard install. See `docs/skill/commodore-pet-skill/utility/vice-emulator.md` for ROM setup details if needed.

The underlying invocation is:

```
xpet -model 3032 -drive8type 2031 -autostart work.d64
```

For a native PET D80 image use `-drive8type 8050`.

## Verified

- Clean DASM assembly (`Complete. (0)`), output size ~5.5 KB.
- PRG header carries load address `$0401`; `SYS 1038` ($040E) lands on a `JMP start` instruction.
- Runs for >100M cycles in `xpet -warp` with a real D64 mounted on drive 8 without crashing or runaway memory writes.

Full visual verification requires a graphical xpet session.

## Source layout

`src/commander.asm` is a single DASM source file. Major sections in order:

- KERNAL and hardware equates
- BASIC stub at `$0401`
- Global state and per-panel arrays
- `start` / `main_loop` / `dispatch_key`
- Cursor + scroll handling
- Screen drawing (frames, title bar, help bar, panel render)
- `load_panel` (open `$`, parse CBM-DOS directory)
- `op_delete`, `op_rename`, `op_copy`
- `send_dos_cmd`, `read_dos_status`
- `prompt_text`, `prompt_yn`
- Entry table buffers

The program runs from `$0401` (BASIC stub `10 SYS1038`) and falls back to BASIC on Q / RUN/STOP.

## Known limitations (this revision)

- Both panels are pinned to drive 8.
- No file viewer (V key not implemented).
- No Move command; on a single drive Move would be Rename, and the dest panel always shows drive 8 anyway.
- Maximum 64 entries per panel.
- Filename column shows up to 12 chars (full name kept internally for DOS commands).

## Project Rules

- When working on the project, always adhere to the rules listed in the `docs/GUIDELINES.md` file.
- Project documentation is located in the `docs/` directory. Read the active set in the order defined in `docs/GUIDELINES.md` ("Sources of Truth") before making any change.

This section is the entry point for any AI coding agent working on this repository, not just one specific tool. The authoritative rules live in `docs/GUIDELINES.md` and the active documentation set it lists.

### Read Before Any Change

Read the full active set, in this order, before making any change. Never assume a subset is enough.

1. `README.md` (this file)
2. `docs/GUIDELINES.md` (and its Sources of Truth list)
3. `docs/PROJECT.md`, `docs/ARCHITECTURE.md`, `docs/SPECIFICATION.md`
4. `docs/TESTING.md`, `docs/WORKFLOW.md`, `docs/REFACTORING.md`, `docs/VERSIONING.md`
5. `docs/COPYRIGHTS.md`, `docs/DEPLOYMENT.md`, `docs/IGNORE.md`, `docs/REFERENCES.md`
6. `docs/standard/asm-6502-development.md` before writing any code

### Key Rules

- **Documentation first**: update the relevant docs before changing `src/commander.asm`.
- **Verification loop**: after every code change, assemble with `./build.sh` (expect `Complete. (0)`), confirm the PRG loads at `$0401`, and smoke-run under `xpet -warp`. See `docs/TESTING.md`.
- **Output stability**: keep load address `$0401` and the `SYS 1038` -> `jmp start` entry intact.
- **Preserve CRLF line endings and ASCII encoding. Do not change version numbers unless instructed.**
- **Restricted directories**: do not read `docs/change/`, `docs/plan/`, `docs/refactoring/`, `docs/report/`, `docs/archive/`, `docs/reference/`, or `docs/skill/` automatically. See `docs/IGNORE.md`.
- **Model or session change**: repeat the pre-work self-check and re-read the active set.

### Workflow

For non-trivial changes, follow the version-based cycle in `docs/WORKFLOW.md`: change request, then implementation plan, then confirm before implementing. The current version is `VERSION_MAJOR`/`VERSION_MINOR` in `src/commander.asm`. See `docs/VERSIONING.md`.
