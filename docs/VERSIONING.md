# Versioning

<!-- Version: 0.1 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for version numbering and changelog maintenance.

## Version Source of Truth

The current project version is stored in `src/commander.asm` as two equates near the top of the file, under the "Version" banner comment:

```
VERSION_MAJOR = 0
VERSION_MINOR = 1
```

There is no separate `VERSION` file. Read these two equates from `src/commander.asm` to determine the current version before creating any cycle artifact. The version is written `MAJOR.MINOR`, e.g. `0.1`.

This value resolves the `<version>` segment of the ASE workflow directories (`docs/change/<version>/`, `docs/plan/<version>/`, `docs/refactoring/<version>/`) and their archive mirrors.

## Version Number Format

This project uses a two-part scheme: **MAJOR.MINOR**

- **MAJOR**: `VERSION_MAJOR`. No upper limit.
- **MINOR**: `VERSION_MINOR`. Runs `0`-`9`.

There is no patch digit. A fix and a feature are both a MINOR increment; reserve MAJOR for breaking changes.

## Version Increment Rules

MINOR behaves like an odometer digit against MAJOR.

- Increment `VERSION_MINOR` by 1 for each new version.
- If `VERSION_MINOR` would exceed `9`, increment `VERSION_MAJOR` by 1 instead and reset `VERSION_MINOR` to `0`.
- A breaking change to behaviour, the user-facing key map, or the target platform set increments `VERSION_MAJOR` and resets `VERSION_MINOR` to `0`, even if `VERSION_MINOR` had not reached `9`.

**Examples**

- `0.1` -> `0.2` (fix the directory parser)
- `0.8` -> `0.9` (add a file viewer)
- `0.9` -> `1.0` (next increment after `.9` rolls MAJOR over)
- `9.9` -> `10.0` (MAJOR has no upper limit)
- `1.4` -> `2.0` (change the key map in an incompatible way)

Do not change the version unless explicitly instructed. Version increments are deliberate decisions made during release preparation. A version bump does not retroactively move existing ASE documents and does not create a new `docs/change/<version>/` directory by itself.

## Changelog Location

`CHANGELOG.md` lives in the project root.

## Changelog Structure

- Use H2 headers (`## Version MAJOR.MINOR`) per version, ordered newest first.
- Add a one-line summary after each version header describing what changed since the previous version.
- Use bullet points with bold feature names to highlight what was added, changed, fixed, or removed.
- Each entry explains what changed, why it matters, and how it affects the user.

## Changelog Maintenance

Do not change version information unless specifically instructed. Version changes occur only as part of a release or when explicitly requested.

When preparing a new version:

- Review commit history since the previous version with `git log`.
- Categorise changes as Added, Changed, Fixed, or Removed.
- Add a new version entry at the top of `CHANGELOG.md`.
- Match the existing markdown style, header format, and date format.
- Preserve the newest-first order of existing entries.

## Commit History Review

Use `git log <previous-tag>..HEAD` to enumerate changes. Translate commit subjects into user-facing changelog bullets rather than copying commit messages verbatim.

## Release Steps

- Determine the new version per the increment rules.
- Update `VERSION_MAJOR` and `VERSION_MINOR` in `src/commander.asm`.
- Update `CHANGELOG.md` with the new version entry.
- Commit the version and changelog update.
- Tag the release (e.g. `git tag v0.2`).
