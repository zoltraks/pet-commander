# Workflow

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for the day-to-day development process.

## Pre-Work Self-Check

Before any change, and again whenever the model or session changes:

- Read `README.md`, then `GUIDELINES.md`, then every file in its Sources of Truth list.
- Read `standard/asm-6502-development.md` before writing code.
- Consult the relevant `docs/skill/commodore-pet-skill/` sections before writing code.
- Do not assume prior context.

## Standard Workflow Cycle

**Analysis**

- Use search to find the relevant section of `src/commander.asm`.
- Read `PROJECT.md`, `ARCHITECTURE.md`, and `SPECIFICATION.md` for the affected area.
- Identify the register and zero-page contracts the change must preserve.

**Planning**

- For a non-trivial change, create a change request and an implementation plan (see the version-based cycle below).
- Wait for user confirmation before writing code.

**Documentation first**

- Update `PROJECT.md` for new or changed requirements.
- Update `ARCHITECTURE.md` for structural or memory-map changes.
- Update `SPECIFICATION.md` for implementation details, constants, or bindings.

**Implementation**

- Make the smallest change that satisfies the plan.
- Keep tidy edits (renames, comments) separate from behaviour changes.
- Preserve borrowed zero-page save/restore and the `$0401` load address.

**Build and smoke test**

- Run the verification loop in `TESTING.md`: assemble, header/size check, headless smoke run.

**Bug fixing and diagnostics**

- Reproduce the issue with a known D64 fixture.
- Use the VICE monitor to inspect registers, entry tables, and screen RAM.
- Add temporary diagnostics only if needed, and remove them before finishing.

**Verification**

- Run a graphical behaviour check for any visible change.
- Final review against the plan and the active documentation.

## Version-Based Implementation Cycle

This project uses ASE workflow directories. The current version is read from `VERSION_MAJOR` and `VERSION_MINOR` in `src/commander.asm` (currently `0.1`) and is used for the `change/`, `plan/`, and `refactoring/` path segments. See `VERSIONING.md`.

A version bump does not move existing documents and does not create a new version directory by itself.

### Cycle Stages

**Concept**

Optional. Capture early ideation in a free-form note, then distil it into one or more change requests.

**Change Request**

State what should change and why, not how. One document per change in `docs/change/<version>/`, named in kebab-case after the change. Use `template/change-request-template.md`.

**Implementation Plan**

Describe how the change will be implemented. Create it in `docs/plan/<version>/`, named after the change request with an `-implementation` suffix. Use `template/implementation-plan-template.md`. Reference the change request and `standard/asm-6502-development.md`.

**Implementation**

Update affected documentation first, then implement the code. Follow the plan. If the plan proves wrong, stop, update the plan, and continue.

**Refactoring Proposal**

After implementation, propose behaviour-preserving improvements in `docs/refactoring/<version>/refactoring-proposal.md`. The focus is selected autonomously from analysis. See `REFACTORING.md`.

**Refactoring Assessment**

After refactoring, evaluate the result in `docs/refactoring/<version>/refactoring-assessment.md`. This assessment is mandatory.

### Artifact Locations

- Change requests: `docs/change/<version>/<change-name>.md`
- Implementation plans: `docs/plan/<version>/<change-name>-implementation.md`
- Refactoring proposals: `docs/refactoring/<version>/refactoring-proposal.md`
- Refactoring assessments: `docs/refactoring/<version>/refactoring-assessment.md`
- On-demand reports: `docs/report/<report-name>.md`

### Naming Summary

| Stage                  | Location                      | File name                         |
| ---------------------- | ----------------------------- | --------------------------------- |
| Change request         | `docs/change/<version>/`      | `<change-name>.md`                |
| Implementation plan    | `docs/plan/<version>/`        | `<change-name>-implementation.md` |
| Refactoring proposal   | `docs/refactoring/<version>/` | `refactoring-proposal.md`         |
| Refactoring assessment | `docs/refactoring/<version>/` | `refactoring-assessment.md`       |

## Cycle Rules

- **No time estimates**: Plans and refactoring proposals never include time or duration estimates.
- **Document-only changes bypass verification**: Creating or updating change requests, plans, proposals, and assessments does not change source and does not require the verification loop. The loop is required only when source, build scripts, or fixtures change.
- **Confirm before implementing**: Create the change request and plan, then ask for confirmation before writing code.
- **Restricted directories**: Do not read from `change/`, `plan/`, `refactoring/`, `archive/`, `report/`, or `reference/` automatically. Read them only when the relevant work requires it or the user requests it.

## Archiving Rule

When asked to archive documents for a specific version, move the entire version directory into the matching `archive/` subdirectory, preserving structure and contents.

- Archive change requests for `0.1`: move `docs/change/0.1/` to `docs/archive/change/0.1/`.
- Archive plans for `0.1`: move `docs/plan/0.1/` to `docs/archive/plan/0.1/`.
- Archive refactoring docs for `0.1`: move `docs/refactoring/0.1/` to `docs/archive/refactoring/0.1/`.
- Archive a report: move the file from `docs/report/` to `docs/archive/report/`.

## Temporary Files

- Use the scratch area or a `work/` directory in the project root for transient files.
- Delete temporary files and any `work/` directory once the task is complete.
- Do not commit temporary files.
