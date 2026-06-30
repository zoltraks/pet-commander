# Project Guidelines

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

These guidelines govern AI-assisted and human development of PET Commander.

## Sources of Truth

- **Primary Entry Point**: The root `README.md` is the starting point for understanding the project.
- **Guidelines**: This file (`GUIDELINES.md`) is the central source of truth for development rules.
- **Specific Documentation**: Refer to the following files for detailed specifications:
  - `COPYRIGHTS.md`: Copyright and license requirements.
  - `PROJECT.md`: Functional and non-functional requirements, glossary, use cases.
  - `ARCHITECTURE.md`: System architecture, module boundaries, memory map.
  - `SPECIFICATION.md`: Implementation details, data models, algorithms, constants.
  - `TESTING.md`: Testing strategy and the verification loop.
  - `WORKFLOW.md`: Day-to-day development process and the version-based cycle.
  - `REFACTORING.md`: Refactoring proposal and assessment process.
  - `VERSIONING.md`: Version numbering and changelog maintenance.
  - `DEPLOYMENT.md`: How the program is built and delivered as a PRG and D64.
  - `IGNORE.md`: Files and directories AI must not modify or treat as authoritative.
  - `REFERENCES.md`: External hardware, KERNAL, and tooling references.

- **Engineering Standard**: `standard/asm-6502-development.md` is authoritative for how 6502 assembly is written in this project. Read it before writing or modifying any code.

- **Output Stability**: The assembled `build/commander.prg` must keep load address `$0401` and a working `SYS 1038` entry. This is a non-negotiable constraint recorded in `SPECIFICATION.md` and `REFACTORING.md`.

- **ASE Workflow**: `WORKFLOW.md` and `VERSIONING.md` define how to use the `change/`, `plan/`, `refactoring/`, `report/`, and `archive/` directories.

When a guideline file is added, removed, or changes purpose, update this section.

## Read All Guidelines Before Any Change

Reading the entire active documentation set before any change is a hard rule, not a recommendation.

Before making any change, read every file listed in Sources of Truth.
Never assume a subset is sufficient, no matter how small the change.

## Reading Order

- `README.md`: Locate the guidelines directory and entry point.
- `GUIDELINES.md`: Understand all rules and the Sources of Truth list.
- All files referenced in Sources of Truth.
- `standard/asm-6502-development.md` before writing any code.

## General Workflow

- Always keep current with `README.md` and the active documentation set.
- Code conventions live in `PROJECT.md` and `standard/asm-6502-development.md`. Refer to those files for naming and language rules.
- Follow the documentation-first approach: update the relevant docs before writing code.

## Development Principles

### Code Quality

- **Clarity Over Cleverness**: Assembly is already terse. Favour readable label names and section comments over packed tricks.
- **Single Responsibility**: Each routine does one thing. A label block has one clear purpose.
- **Comment the Why**: Comment intent, hardware quirks, and register contracts. Do not narrate obvious instructions.
- **Self-Documenting Labels**: Use descriptive, prefixed labels (e.g. `lp_` for load_panel locals) so control flow reads clearly.

### Pragmatic Constraints

- This is an 8-bit target. Memory, cycles, and the 6502 instruction set bound every decision.
- Keep core routines on the critical path small and predictable.
- Preserve register and zero-page contracts documented in `SPECIFICATION.md`.

## Documentation Style

- Write short sentences.
- Use explicit line breaks.
- Put exactly one empty line before and after every list.
- Use standard ASCII characters.
- Keep Markdown tables readable as plain text. Align columns by padding to the widest cell.
- Keep section names short.
- Do not put qualifiers in section names using parentheses. Put "mandatory" or "do not repeat" in the body instead.
- For process or workflow steps, use bold headers separated by empty lines instead of numbered lists.

### Formatting Rules

- **Hex and byte values**: Enclosed in backticks (e.g. `$0401`, `$FF`).
- **Key terms**: Bold definitions (**Term**: Definition).
- **Addresses and labels**: Use backticks for source labels and addresses (e.g. `start`, `$8000`).

## Verification

After every code change, run the verification loop in `TESTING.md` until clean.

- **Assemble**: `./build.sh` completes with `Complete. (0)` and zero errors.
- **Size check**: Output `build/commander.prg` is produced with load address `$0401`.
- **Smoke run**: The program runs in `xpet` under warp without crashing or runaway writes.
- **Fix**: Address every error and warning. Repeat the loop until clean.

This applies to every code modification regardless of size.

## File Maintenance

### Editing Existing Files

- Maintain existing style and naming conventions.
- **Critical**: Preserve line endings. All project files use CRLF.
- **Critical**: Preserve UTF-8 / ASCII encoding.
- **Critical**: Do not change version numbers unless explicitly instructed.

### Creating Files

- Place new documents under the directory that matches their responsibility.
- New reference material goes in `reference/`. New skill packages go in `skill/`.

## Knowledge Exploration Boundaries

- Treat files and directories listed in `IGNORE.md` as excluded from analysis unless explicitly instructed.
- Do not read from `change/`, `plan/`, `refactoring/`, `report/`, `archive/`, `reference/`, or `skill/` automatically. Read them only when the relevant work requires it or the user requests it.
- `build/` and `example/work.d64` are generated artifacts. They are not authoritative ground truth.

## Memorization Convention

When the user says "memorize" or "remember", update the most relevant guideline file with the new rule.

- Documentation structure or language changes go to `GUIDELINES.md`.
- Project scope or requirements go to `PROJECT.md`.
- Architecture or memory-map changes go to `ARCHITECTURE.md`.
- Implementation details go to `SPECIFICATION.md`.
- Workflows go to `WORKFLOW.md`.
- Testing goes to `TESTING.md`.
- Refactoring goes to `REFACTORING.md`.
- Assembly coding rules go to `standard/asm-6502-development.md`.

If no specialised file is appropriate, update `GUIDELINES.md`. Always confirm the rule was added to the correct file.

## Model Change / New Conversation Rule

If the model changes or a new session starts, repeat the pre-work self-check before doing any work.

Do not assume prior context.
Re-read all active documentation files before making any change.
