# Copyrights

<!-- Version: 1.0.0 | Date: 2026-06-30 | Status: Requires review -->

This document defines copyright and licensing rules for PET Commander.

## Copyright and License Requirements

### Fundamental Rules

- All code must be original and not copied from existing solutions.
- Never copy code from other sources without proper licensing and attribution.
- Never accept AI-generated code that resembles or duplicates code from other projects. Always verify originality.
- When adding external tools or dependencies, verify license compatibility before use.
- Document the source and license of any third-party code or material used.
- Do not include copyrighted material without explicit permission.
- These rules apply to source code, documentation, disk images, and any other project assets.

### Project License

If the file `LICENSE` or `LICENSE.md` exists in the repository root, the project is released under the license specified therein.

If no license file exists, this project is considered proprietary and all rights belong to the owner. No part of this project may be copied, modified, or distributed without explicit written permission from the owner.

At the time of writing, no license file is present.

## Platform and ROM Code

PET Commander targets the Commodore PET 3032 and calls into the PET KERNAL ROM by address.

- KERNAL routine addresses, jump-table entries, and zero-page locations are facts about the hardware and ROM. They are referenced, not copied. Documenting an address such as `$FFD2` (CHROUT) is not a copyright concern.
- Do not embed disassembled or copied Commodore ROM code in this repository. Call ROM entry points by address instead.
- Commodore ROM images are not included in this repository. The user supplies them through their VICE installation.

## Toolchain Dependencies

PET Commander is assembled with DASM and run under the VICE emulator. Neither tool is bundled in this repository.

- **DASM**: open-source 6502 macro assembler. Permitted.
- **VICE**: open-source Commodore emulator suite (`xpet`, `c1541`). Permitted as an external runtime, not redistributed here.

### Permitted Dependency Licenses

If a build or tooling dependency is ever vendored, permitted open-source licenses are MIT, Apache 2.0, BSD 2-Clause, BSD 3-Clause, ISC, and Boost.

GPL-licensed code may not be copied into this project without explicit written approval. Using GPL tools such as VICE as external programs is acceptable; copying their source into this repository is not.

## Asset Licensing

- Sample files inside `example/work.d64` must be original or trivially generated test data.
- Any added artwork, character data, or media must be original or from licensed sources with compatible terms.
