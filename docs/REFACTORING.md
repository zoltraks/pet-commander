# Refactoring

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This file is the authoritative source for how refactoring is proposed, executed, and assessed in PET Commander.

## Objective

Refactoring keeps `src/commander.asm` readable, sectioned, and easy to extend without changing what the program does. On an 8-bit target with hand-managed registers and a fixed memory map, an uncontrolled "improvement" can silently break a register contract or shift the binary layout. This document makes refactoring a managed, auditable process.

## Definition

Refactoring is a behaviour-preserving change to internal structure. The same input must produce the same output, and the same observable behaviour must remain. A change that alters behaviour belongs in `docs/change/<version>/`, not in a refactoring.

**Tidy**: Safe preparatory edits - label renames, dead-code removal, comment fixes, banner-comment formatting.

**Refactor**: Structural changes that preserve behaviour - extract a routine, inline a routine, move a section, split or merge a block.

**Behaviour Change**: Out of scope. Route through a change request.

Do not mix these three in a single step. If a step reveals a required behaviour change, stop and route it through a change request before continuing.

## General Rules

- Preserve existing behaviour unless a defect is being corrected.
- Distinguish refactoring from functional changes at every step.
- Favour clarity over clever instruction packing.
- Preserve register and zero-page contracts documented in `SPECIFICATION.md`.
- Every recommendation must include a justification.
- Do not modify a working critical path unless it is the explicit target of the proposal.
- Preserve all diagnostic and status output.
- Do not bump the version as part of a refactoring.

## Autonomous Analysis

When asked for a proposal, do not ask the user what to refactor.

Analyse recent changes, the current implementation in `src/commander.asm`, this standard, and good 6502 practice. Select the primary focus and document the analysis in the proposal's Problem section.

The analysis must trace execution flow from `main_loop` through the affected handlers, map which routines read or write the shared zero-page pointers and entry tables, and note side effects on screen RAM and the DOS channel. It must identify duplication - exact, functional, and intentional - and unused code - dead labels, half-finished paths, and bypassed legacy code. Verify that no `jmp`, `jsr`, or branch targets a label before recommending its removal.

## Rule of Three

Do not extract a shared subroutine until at least three concrete duplicates exist. Write the routine to match the real call sites, not a hypothetical one. Recommend extraction only when it improves maintainability without costing clarity or critical-path cycles.

## Proposal Document

A refactoring proposal is created as `docs/refactoring/<version>/refactoring-proposal.md`. Use `<version>` from `VERSION_MAJOR`/`VERSION_MINOR` in `src/commander.asm`.

Each proposal contains the following sections.

**Problem**: The code smell, duplication, standard violation, or structural issue. Include label names and short quoted fragments from `src/commander.asm`. State which sections the refactoring would touch. Document the analysis that led to this focus.

**Goal**: The desired end state. What is the new shape of the sections, routines, or data layout?

**Findings**: A catalogue of individual issues, each in the Finding Structure below, ordered by risk level (highest first).

**Plan**: Steps in execution order. Each step must leave the program assembling cleanly and running. Keep tidy steps separate from structural steps. When a change crosses a seam (navigation, drawing, I/O), introduce the new routine alongside the old, migrate call sites one at a time, then remove the old routine.

**Step Granularity**: Each step must be small enough that a regression is obvious from that step's verification output. Split any step that mixes a rename with an extraction or touches many sections.

**Risk**: What could go wrong? Which routines are most likely to regress? Which behaviour checks cover the affected code? Identify thinly covered routines that need a characterisation check first.

**Acceptance Criteria**: Identical observable behaviour, the `$0401` load address preserved, a clean assemble, and a clean headless smoke run.

## Finding Structure

Every identified issue must include the following parts.

**Issue**: Describe the observed problem. Include the label and a short quoted fragment.

**Impact**: Explain the consequence - incorrect behaviour, reliability risk, reduced maintainability, wasted cycles on the critical path, or structural inconsistency.

**Recommendation**: Describe the proposed improvement and the rationale.

**Risk Level**: Critical, Major, Minor, or Suggestion.

**Breaking Change Assessment**: No Breaking Change, Internal Breaking Change, Output Layout Change, or User-Facing Behaviour Change.

**Example**: A before-and-after fragment showing the issue and the proposed solution.

## Areas to Review

Review the code across these areas when producing a proposal. Add project-specific areas as needed.

**Correctness**: Register clobbering, missing carry/flag handling, off-by-one in entry indexing, boundary errors at `MAX_ENTRY`, and incorrect zero-page restore.

**Architecture and Design**: Whether responsibilities stay within their module seam - navigation does not do I/O, drawing does not mutate data, operations do not draw directly.

**Duplication and Maintainability**: Repeated screen-addressing math, repeated DOS-command assembly, repeated entry-pointer setup. Apply the Rule of Three before extracting.

**Readability**: Routine length, branch nesting, label naming, and section comments. Prefer code whose control flow is obvious.

**Performance**: Cycles on the navigation and redraw paths. Avoid premature optimisation; justify any cycle-driven change with the affected path.

**Resource Management**: Logical-file numbers and channels opened by `send_dos_cmd` and `load_panel` must be closed on every path, including error paths.

**Error Handling**: Drive-not-ready, status-read-failure, and DOS error paths must remain reachable and must still set a visible message.

**Testability**: Whether a routine can be exercised against the D64 fixture and observed via the monitor.

**Documentation**: Whether `ARCHITECTURE.md` and `SPECIFICATION.md` still match the code after the change.

## Prioritization

Order recommendations: correctness, reliability, security, maintainability, architecture, performance, readability.

## Severity Classification

- **Critical**: May cause incorrect results, a crash, runaway writes, or a corrupted binary layout.
- **Major**: Significantly impacts reliability, maintainability, architecture, or critical-path performance.
- **Minor**: Affects readability or consistency without technical risk.
- **Suggestion**: Optional improvement.

## Project-Specific Constraints

These constraints are non-negotiable. Every refactoring must respect them without exception.

- **Output stability**: The assembled PRG must keep load address `$0401`, and `SYS 1038` (`$040E`) must remain `jmp start`. Do not insert code or data ahead of the boot stub that would shift these.
- **Zero-page borrow contract**: `$FB`-`$FE` and `BLNSW` must be saved in `init` and restored in `restore_zp` on every exit path.
- **PET ROM coupling**: PET internal entry points (`$F524`, `$F2AC`) and the OPEN/CLOSE zero-page parameters are PET-3032-specific. Do not replace them with C64-style `SETNAM`/`SETLFS`.
- **Channel hygiene**: Every `OPEN` must have a matching `CLOSE`, including on error and cancel paths.
- **Entry-table layout**: The 20-byte record layout and `MAX_ENTRY` cap are assumed by `mul20` and the draw routines. Changing them is a behaviour change, not a refactoring.
- **Screen fidelity**: The rendered 40x25 layout must remain byte-for-byte equivalent for the fixture disk.

## Executing a Refactoring

Run the full verification loop before the first step to establish a known-good baseline. Do not modify code until the baseline assembles and smoke-runs cleanly.

Follow the plan step by step. After each step, run the verification loop in `TESTING.md`. Do not proceed until the current step passes.

If a step reveals an issue not covered by the plan, stop and update the proposal before continuing.

A refactoring that changes section shape or label names must update `ARCHITECTURE.md` and `SPECIFICATION.md` before the code change in that step.

## Testing Requirements

- Before refactoring a routine, confirm a behaviour check covers it against the fixture.
- If coverage is thin, capture a characterisation snapshot (entry tables, screen RAM) first so a regression is visible.
- Run the verification loop after each step.
- Verify no branch or jump targets a label before removing it.

## Anti-Patterns

The following are forbidden.

- Premature abstraction and speculative generality.
- Drive-by reformatting mixed into a structural step.
- A single step that mixes a rename with an extraction or touches many sections at once.
- Rewriting a check to hide a regression.
- Time or duration estimates in proposals or assessments.
- Version bumps as part of a refactoring.
- Shifting the boot stub or load address.

## Assessment

Creating an assessment is mandatory after every refactoring.

Create it at `docs/refactoring/<version>/refactoring-assessment.md`.

The assessment must include:

- Proposal summary - what was planned.
- Implementation summary - what was actually done.
- Gap analysis - what was missed, changed, or added.
- Verification results - assemble, header/size check, and smoke run, each with explicit pass or fail.
- Metrics comparison - before/after where applicable, such as routine count, longest routine, or build size. Explain any growth.
- Output fidelity - confirmation that `build/commander.prg` keeps load address `$0401` and that the rendered screen for the fixture is unchanged.
- Behaviour smoke check - confirmation that observable behaviour matches the pre-refactoring baseline. List the flows verified.
- Conclusion - pass or fail, with recommendations.

Refactoring proposals and assessments do not include time estimates. Creating them is a document-only change and does not require the verification loop.

## Expected Outcome

Recommendations must prioritise, in order: correctness, reliability, security, maintainability, architecture, performance, and readability. All recommendations must be practical, evidence-based, and proportional to the value they provide.
