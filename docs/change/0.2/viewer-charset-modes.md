# Add viewer charset and render-mode controls

**Type:** Feature

## Summary

The viewer text mode currently converts file bytes from PETSCII to screen codes and substitutes a dot for non-printable bytes. This change makes raw screen-code display the default, adds an ASCII-translation mode, and adds uppercase/lowercase character-set switching with persistence across viewer opens.

## Description

### Text render modes

The viewer text mode gains a render-mode flag with two states:

- **SCREEN** (default): file bytes are written to the back buffer directly as screen codes. No PETSCII-to-screen conversion. No dot substitution. Every byte is presented as-is, including control and high-bit bytes (bit 7 yields reverse video).
- **ASCII**: file bytes are interpreted as ASCII and translated to screen codes for the currently active character set. Non-printable bytes (`$00`-`$1F`, `$7F`, and `$80`-`$FF`) are replaced with the dot placeholder. Lowercase letters in the uppercase set render as inverse-video uppercase (see ASCII-to-screen translation below).

The ASCII-to-screen translation depends on the active character set:

- ASCII `A`-`Z` (`$41`-`$5A`): uppercase set maps to screen `$01`-`$1A`; lowercase set maps to screen `$41`-`$5A` (identity).
- ASCII `a`-`z` (`$61`-`$7A`): lowercase set maps to screen `$01`-`$1A`; uppercase set has no lowercase glyphs, so these map to the uppercase letter `$01`-`$1A` with the reverse-video bit set (`$81`-`$9A`). This keeps lowercase text visible and distinguishable from real uppercase letters, instead of showing dots.
- ASCII `$20`-`$40` and the remaining punctuation ranges reuse the existing `petscii_to_screen` mapping.

Example: ASCII `a` (`$61`) becomes screen code `$01` in the lowercase set, and becomes `$81` (reversed `A`) in the uppercase set.

### Character set switching

The viewer gains a character-set flag with two states:

- **UPPER** (default): VIA PCR bits 3:1 set to `PCR_U` (`$0C`), the uppercase/graphics set.
- **LOWER**: VIA PCR bits 3:1 set to `PCR_L` (`$0E`), the lowercase/text set.

The switch uses read-modify-write on PCR to preserve CB2 (IEEE-488 NDAC) bits, per the commodore-pet-skill.

### Charset-aware label rendering

The screen codes for uppercase letters differ between the two character sets: in the uppercase set `A`-`Z` are `$01`-`$1A`, in the lowercase set `A`-`Z` are `$41`-`$5A`. The frame border codes are identical in both sets, but the fixed text labels are not.

When the character set changes, the header and footer labels (`VIEW`, `TEXT`, `HEX`, `ASCII`, `SCREEN`, `LOWER`, `UPPER`, `EXIT`) must be redrawn using the uppercase screen codes for the active set so they always read as capital letters.

The filename in the header is an exception: it is converted once via `petscii_to_screen` and is not re-translated on a charset switch. As a result a name stored as `FILE.TXT` displays as `FILE.TXT` in the uppercase set and as `file.txt` in the lowercase set. This side effect is intentional: it makes the currently selected character set visible at a glance without adding a separate indicator.

### Entry and exit contract

On viewer entry the program saves the current PCR charset bits (3:1) and applies the viewer's persisted character-set flag. On viewer exit the program restores the saved PCR charset bits. Because the program runs in the uppercase set by default, exit always returns the machine to the uppercase set.

The character-set switch is applied only while the viewer is interactively displayed. It is not applied during `view_load_chunk` (disk I/O), so an open failure leaves PCR unchanged and the failure status renders in the uppercase set.

### Persistence across opens

Three viewer flags persist across viewer opens within one program run:

- `view_mode` (TEXT/HEX) - already present, now preserved.
- `view_charset_mode` (SCREEN/ASCII) - new.
- `view_charset` (UPPER/LOWER) - new.

`view_top`, `view_chunk_base`, `view_chunk_len`, and `view_at_eof` reset to zero on each open because a different file may be viewed. The mode flags retain their last value so reopening the viewer restores the previous display configuration. On a fresh program run the flags reset to their defaults (TEXT, SCREEN, UPPER).

### New key bindings

The viewer loop adds four shortcuts after the existing `H` (HEX) and `T` (TEXT):

| Key | Action |
|-----|--------|
| `A` | Switch text render mode to ASCII |
| `S` | Switch text render mode to SCREEN (default) |
| `L` | Switch character set to LOWER |
| `U` | Switch character set to UPPER (default) |

`E` and RUN/STOP still close the viewer. `Q` remains reserved for quitting the main program.

### Footer bar

The footer bar (row 24) is updated to list all seven shortcuts. The exact 40 screen-code bytes are:

```
E1 14 85 98 94 A0 08 85 98 A0 01 93 83 89 89 A0 13 83 92 85 85 8E A0 0C 8F 97 85 92 A0 15 90 90 85 92 A0 05 98 89 94 61
```

Decoded, this reads `TEXT HEX ASCII SCREEN LOWER UPPER EXIT` with each shortcut letter in normal video and the surrounding label in reverse video, framed by the `$E1`/`$61` half-block borders. The shortcut letters are not highlighted by active state; the header bar continues to show the active TEXT/HEX mode.

### Hex mode

Hex mode is unchanged in structure. Its ASCII columns continue to show raw bytes as screen codes. The LOWER/UPPER character-set switch is global via PCR, so hex-mode glyphs follow the active character set, but no ASCII/SCREEN render-mode toggle applies to hex mode. The header and footer labels still render as uppercase in either set per the charset-aware label rule above.

## Fixture

`example/build-work-d64.sh` adds a new `README.TXT` SEQ file with ASCII prose content mixing uppercase and lowercase letters, digits, and punctuation. It is intended as the primary fixture for exercising ASCII versus SCREEN render modes and UPPER versus LOWER character sets. The existing sample files are unchanged.

## Use Cases

- The user opens a file containing raw screen-code data and presses `V`. The viewer shows the bytes directly as glyphs with no conversion (SCREEN default).
- The user presses `A` to view an ASCII text file; lowercase letters render correctly only after pressing `L` to switch to the lowercase set.
- The user presses `L`, scrolls, then presses `E` to close. The panels reappear in the uppercase set. Reopening the viewer on another file starts in LOWER/ASCII mode with the offset reset to zero.
- The user presses `U` to return to the uppercase set while still in the viewer.
- The user opens `README.TXT` in ASCII mode, presses `L`, and the prose renders in lowercase letters while the header `VIEW` label and footer shortcuts stay uppercase.

## Hints

- Reuse `petscii_to_screen` for the non-letter ASCII ranges to avoid duplicating the punctuation and digit mapping.
- Keep the PCR read-modify-write pattern from `docs/skill/commodore-pet-skill/system/screen.md`.
- The frame border codes (`BOX_*`, `HB_*`) are identical in both character sets, so the viewer frame needs no charset-specific handling.

## Out of Scope

- No active-state highlighting of the footer shortcut letters.
- No header-bar change to show ASCII/SCREEN or LOWER/UPPER state; the header keeps showing TEXT/HEX.
- No search, goto-offset, editing, or line-wrap.
- No change to hex-mode column layout or its ASCII-column render mode.
- No persistence of viewer state across program restarts; defaults apply on a fresh RUN.
