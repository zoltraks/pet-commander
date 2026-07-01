# Testing

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for how PET Commander is verified.

There is no host-side unit-test framework for this 6502 target. Verification is a build check plus emulator-based behaviour checks. The verification loop below replaces the generic typecheck/lint/build/test loop with steps that fit an assembly program for the PET.

## Clean Build Definition

A clean build means all of the following hold:

- DASM reports `Complete. (0)` with zero errors and zero warnings.
- `build/commander.prg` is produced.
- The PRG load address is `$0401` (first two bytes `01 04`).
- `SYS 1038` (`$040E`) lands on the `jmp start` instruction.

## Verification Loop

Run this loop after every code change. Repeat until every step passes.

**Assemble**

Run `./build.sh`.
The DASM run must finish with `Complete. (0)` and no errors.
`build.sh` also refreshes `example/work.d64` so the on-disk copy stays current.

**Header and size check**

Confirm the first two bytes of `build/commander.prg` are `01 04` (load address `$0401`).
Confirm the build size is in the expected range (about 9.4 KB for the current feature set, which includes the viewer with bordered frame layout, charset and render-mode controls, its 2 KB chunk buffer, and the Present/Blit module). A large unexpected change in size is a signal to investigate.

**Smoke run**

Run the program under VICE in warp mode without a display long enough to prove it does not crash or perform runaway writes:

```
xpet -model 3032 -drive8type 2031 -warp -autostart example/work.d64
```

The program must run for tens of millions of cycles with a real D64 mounted on drive 8 without crashing.

Note: VICE 3.7 xpet does not mirror VBLANK onto VIA PB5 (`$E840` bit 5). The `wait_vblank` poll is bounded to 256 iterations per phase so it does not hang under VICE. On real hardware the bound is never reached and the poll syncs to VBLANK normally.

**Behaviour check**

For changes that affect visible behaviour, run a graphical session and exercise the affected path:

```
./run.sh
```

Verify the specific feature: navigation tracks the cursor, the operation issues the right DOS command, and the status row shows the drive response.

**Fix**

Address every error and warning. Repeat the loop until clean.

This loop applies to every code modification regardless of size. Work is finished only when all steps pass.

## Test Types

- **Build verification**: the assemble and header/size checks above. Automatable and fast.
- **Headless smoke**: warp-mode run that proves stability without a display. Catches crashes and runaway memory writes.
- **Manual behaviour**: graphical `xpet` session that confirms on-screen behaviour for the changed feature. Full visual verification requires a graphical session.
- **Characterisation**: when changing a parser or formatter (`load_panel`, `print_num3`, `petscii_to_screen`), capture the before behaviour with a known D64 fixture and compare after. Use the VICE monitor to inspect entry tables and screen RAM when a visual diff is not enough.

## Fixtures

`example/work.d64` is the standard fixture. It contains the program plus sample files of mixed types (2 PRG, several SEQ including one long name, and a `README.TXT` ASCII prose file for exercising the viewer ASCII/SCREEN and UPPER/LOWER modes) so panels render real entries on first start. Regenerate it with `example/build-work-d64.sh` when sample files need to change.

## Coverage Targets

Automated line coverage is not applicable to this target. The qualitative targets are:

- Every keyboard binding in `SPECIFICATION.md` is exercised at least once during manual behaviour checks for a release.
- Every DOS operation (delete, rename, copy) is exercised against the fixture and shows a status line.
- Every viewer key (`V`, `H`, `T`, `A`, `S`, `L`, `U`, cursor up/down, cursor left/right, HOME, `E`, RUN/STOP) is exercised at least once against a PRG and a SEQ file on the fixture.
- The viewer open-failure path (`VIEW OPEN FAILED`) is reproduced at least once.
- The viewer restores the panels on close; after closing, the panel state (selection, scroll, active panel) is unchanged.
- SCREEN render mode (default): opening a file with raw screen-code content shows the bytes directly with no conversion and no dot substitution.
- ASCII render mode: opening `README.TXT`, pressing `A`, shows ASCII prose; in UPPER, lowercase letters render as inverse-video uppercase; in LOWER, lowercase letters render normally.
- Character-set switching: pressing `L` switches to the lowercase set; the `VIEW` header label and all footer shortcuts stay uppercase; the header filename shifts to lowercase. Pressing `U` returns to the uppercase set; the filename shifts back to uppercase.
- Character-set restore on exit: after `E`, the panels reappear in the uppercase set; after `Q`, `READY.` appears and `PRINT FRE(0)` and a string assignment (`A$="TEST"`) succeed, confirming PCR and ZP were restored and the `$7C00` back-buffer region did not corrupt BASIC RAM.
- Viewer state persistence: set `A` + `L`, close with `E`, reopen with `V` on another file; the viewer starts in ASCII + LOWER mode with the offset reset to zero. Set `S` + `U`, close, reopen; it starts in SCREEN + UPPER.
- The error paths (`DRIVE NOT READY`, `STATUS READ FAILED`, `FILE EXISTS`, `VIEW OPEN FAILED`) are reproduced at least once when their code is touched.
- Double-buffered rendering: navigation (cursor up/down, TAB switch, `L` reload), viewer scrolling, and prompt input (`N`, `C`, `D` confirmation) are all flicker-free; each frame appears complete with no partial-update window.
- Clean BASIC exit after double buffering: after `Q`, `READY.` appears, then `PRINT FRE(0)` and a string assignment (`A$="TEST"`) succeed, confirming the `$7C00` back-buffer region did not corrupt BASIC RAM and no IRQ vector was left installed.

## CI Configuration

There is no continuous-integration pipeline configured yet. The assemble and header/size checks are scriptable and are the natural first CI step if one is added. Record any future CI setup in this section and in `DEPLOYMENT.md`.
