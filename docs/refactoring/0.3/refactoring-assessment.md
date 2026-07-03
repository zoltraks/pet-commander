# Refactoring Assessment: Documentation Distillation

## Proposal Summary

Review the project documentation and remove content that is duplicated across files, obvious from the current implementation in `src/commander.asm`, or tied to a specific build (version numbers, file sizes, dates). Leave the README and the commodore-pet-skill submodule untouched.

## Implementation Summary

Removed from every guideline file:

- Version/date/status HTML comment headers that become stale and are tracked by git instead.

Removed from `GUIDELINES.md`:

- Duplicate "Read All Guidelines Before Any Change" section (WORKFLOW.md is authoritative).
- Duplicate "Verification" section (TESTING.md is authoritative).
- Overly prescriptive documentation-style rules.

Removed from `PROJECT.md`:

- Current build size (9.2 KB).

Removed from `ARCHITECTURE.md`:

- Entry-labels column from the module-boundaries table; labels are obvious from the source.
- Detailed viewer state-variable list; replaced with a high-level summary.

Removed from `SPECIFICATION.md`:

- Full constants table (values are in `src/commander.asm`).
- KERNAL/PET ROM symbol list (addresses are in `src/commander.asm`).
- Detailed state-variable tables (replaced with prose summaries).
- Overly detailed algorithm descriptions (directory parsing, scrolling, rendering, chunk loading, PCR switching, ASCII translation) replaced with high-level summaries.
- Hex constants and routine names from the keyboard-bindings table.
- Source-label column from the error catalogue.
- Routine-specific detail from startup/shutdown sequences.

Removed from `TESTING.md`:

- Current build size (9.4 KB).
- Exhaustive key-by-key coverage checklist; replaced with qualitative coverage principles.

Removed from `DEPLOYMENT.md`:

- Current build size (8.8 KB).

Removed from `WORKFLOW.md`:

- Redundant Naming Summary table (duplicated Artifact Locations).
- Specific version numbers in the archiving examples and the version-based cycle description.

## Gap Analysis

No functional requirements were changed. The remaining documentation describes intent, architecture, and constraints; exact addresses, variable names, and byte offsets now live in the source code as the single source of truth. The `README.md` and skill submodule were not modified, as requested.

## Verification Results

This is a documentation-only change; it does not alter source, build scripts, or fixtures. The verification loop is not required by `WORKFLOW.md` for document-only changes, but the source was assembled to confirm no accidental edits to `src/commander.asm` beyond the earlier ABOUT-modal change:

- `./build.sh` completed with `Complete. (0)`.
- `build/commander.prg` load address remains `$0401`.

## Metrics Comparison

- Net documentation reduction: approximately 348 lines removed, 114 lines added across the guideline files.
- No change to program code or binary layout.

## Output Fidelity

- `build/commander.prg` load address is still `$0401`.
- `SYS 1038` still lands on `jmp start`.
- Rendered screen output is unchanged because no source code was modified.

## Behaviour Smoke Check

No code behaviour was changed. The earlier ABOUT-modal T-junction change (separate commit) was already smoke-run successfully; this documentation-only cleanup does not affect runtime behaviour.

## Conclusion

Pass. The documentation set is now leaner, with duplicated and obvious implementation detail removed. The remaining docs describe what the system does and why, while the source remains the authoritative reference for exact constants, addresses, and routine-level behaviour.
