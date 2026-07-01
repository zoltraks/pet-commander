# Deployment

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file describes how PET Commander is built and delivered. There is no server or web hosting; "deployment" here means producing a runnable program and a bootable disk image.

## Build Output

The build assembles `src/commander.asm` into `build/commander.prg`.

```
./build.sh
```

`build.sh` prefers the `dasm` Docker image and falls back to a local `dasm` binary in `PATH`. It assembles with DASM output format `-f1` (PRG), so the file carries the load address `$0401` in its first two bytes. It then refreshes `example/work.d64` so the on-disk copy of the program stays current.

Output:

- `build/commander.prg` - the program, load address `$0401`, about 8.8 KB.

## Disk Image Delivery

The program is delivered inside a D64 disk image so it can autostart reliably.

```
example/build-work-d64.sh
```

This formats `example/work.d64` with `c1541` (ships with VICE) and writes `commander.prg` plus a small set of mixed-type sample files. `build.sh` calls it automatically after a successful assemble.

The program is autostarted from disk rather than injected as a bare PRG because VICE Inject mode does not reliably initialise BASIC pointers for a `$0401` PRG, which yields `?SYNTAX ERROR IN 10`. Disk autostart uses BASIC's real LOAD path. See `README.md` for the full rationale.

## Running

```
./run.sh                 # autostart example/work.d64 on drive 8
./run.sh some-other.d64  # a different image that contains commander.prg
```

The underlying invocation is:

```
xpet -model 3032 -drive8type 2031 -autostart work.d64
```

For a native PET D80 image use `-drive8type 8050`.

## Real Hardware

To run on a real PET 3032:

- Build `build/commander.prg`.
- Write it (and optional sample files) to a real disk with a compatible drive, or transfer `example/work.d64` to physical media using a suitable hardware tool.
- On the PET, `LOAD"COMMANDER",8` then `RUN`, or `LOAD"*",8` from the work disk.

## Toolchain

- **DASM**: 6502 macro assembler. Either the `dasm` Docker image or a local `dasm` in `PATH`. See `docs/skill/commodore-pet-skill/utility/dasm-assembler.md` for setup.
- **VICE 3.7+**: provides `xpet` and `c1541`. VICE 3.7+ finds ROMs automatically from the bindist directory (Windows) or system/user paths (Linux); no manual ROM setup is needed with a standard install. See `docs/skill/commodore-pet-skill/utility/vice-emulator.md` for manual ROM setup if required.

## Environment Variables

None. The build and run scripts take no environment configuration. The optional Docker path is selected automatically when a `dasm` image is present.

## Performance and Size

The deliverable is a single small PRG. There is no compression, bundling, or CDN step. Keep an eye on build size as a regression signal, as noted in `TESTING.md`.
