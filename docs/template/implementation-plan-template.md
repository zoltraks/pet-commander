# [Short Imperative Title] Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/<version>/<filename>.md`.

Create the plan in `docs/plan/<version>/`, named after the change request with an `-implementation` suffix. Use the version from `VERSION_MAJOR`/`VERSION_MINOR` in `src/commander.asm`. Do not include time estimates.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md`.

## Documentation Updates

Update the active documentation set before any source modification:

- `PROJECT.md` for new requirements or behavioural changes.
- `ARCHITECTURE.md` for structural or memory-map changes.
- `SPECIFICATION.md` for implementation details, constants, or bindings.

## Step by Step Implementation

Define one bold-headed step per logical unit of change.

**[Step name]**

Describe what changes and why.

Section or label in `src/commander.asm`: `[label]`.

    ; code fragment showing the structural change

## Implementation Order

Execute the steps above in this sequence.

1. Update documentation.
2. Update equates and layout constants.
3. Update data layout (entry record, per-panel arrays, buffers) if affected.
4. Implement or modify routines.
5. Update screen drawing if the layout changes.
6. Refresh the example disk if fixtures change.
7. Run the verification loop.

## Testing Strategy

**Build verification**

State the expected assemble result and any header/size expectations.

**Behaviour checks**

State which key bindings, DOS operations, and error paths must be exercised against the D64 fixture, and what the expected on-screen result is.

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp`.
- Graphical behaviour check for the changed feature.
