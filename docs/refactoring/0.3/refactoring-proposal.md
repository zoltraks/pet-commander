# Refactoring Proposal: Documentation Distillation

## Problem

The project guideline files have grown redundant and implementation-heavy. Several sections duplicate content from other files, list every constant and variable that is already visible in `src/commander.asm`, and include build-specific numbers (version numbers, file sizes, dates) that change with every commit.

## Goal

Distil the documentation so it describes intent, architecture, and constraints, while letting the source code remain the single source of truth for exact addresses, variable names, byte offsets, and routine-level behaviour. The README and the commodore-pet-skill submodule are out of scope.

## Findings

| Issue | Impact | Risk |
|-------|--------|------|
| Version/date/status headers in every guideline file | Stale metadata that git already tracks | Minor |
| Duplicate pre-work self-check in `GUIDELINES.md` and `WORKFLOW.md` | Same rule in two places | Minor |
| Duplicate verification loop in `GUIDELINES.md` and `TESTING.md` | Same procedure in two places | Minor |
| Full constants table in `SPECIFICATION.md` | Duplicates `src/commander.asm` | Minor |
| KERNAL/PET ROM symbol list in `SPECIFICATION.md` | Duplicates source header comments | Minor |
| Detailed state-variable tables in `SPECIFICATION.md` | Obvious from `src/commander.asm` | Minor |
| Overly detailed algorithm descriptions in `SPECIFICATION.md` | Reads like annotated source | Minor |
| Entry-labels column in `ARCHITECTURE.md` module table | Duplicates source labels | Minor |
| Build-size numbers in `PROJECT.md`, `TESTING.md`, `DEPLOYMENT.md` | Change-dependent values | Minor |
| Redundant Naming Summary table in `WORKFLOW.md` | Duplicates Artifact Locations | Minor |
| Exhaustive key-by-key coverage checklist in `TESTING.md` | Hard to maintain, duplicates `SPECIFICATION.md` | Minor |

## Plan

1. Remove version/date/status headers from all guideline files.
2. Remove duplicate sections from `GUIDELINES.md` and reference the authoritative files instead.
3. Remove build-size numbers and simplify prescriptive style rules.
4. Simplify `SPECIFICATION.md` data models and algorithms to high-level summaries.
5. Remove the entry-labels column from `ARCHITECTURE.md` and simplify state-domain descriptions.
6. Simplify `WORKFLOW.md` and `TESTING.md` coverage targets.
7. Write a refactoring assessment documenting the result.

## Risk

Low. This is a documentation-only change. No code, constants, or memory layout is altered. The main risk is removing something that future readers need, but the README and the skill submodule remain untouched, and the source code is still the authoritative reference.

## Acceptance Criteria

- No source code changes.
- `./build.sh` still reports `Complete. (0)`.
- `build/commander.prg` still loads at `$0401`.
- The remaining documentation is internally consistent and references the source for implementation details.
