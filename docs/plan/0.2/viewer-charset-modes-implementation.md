# Add viewer charset and render-mode controls Implementation Plan

## Change Request Reference

This implementation plan is based on the change request at `docs/change/0.2/viewer-charset-modes.md`.

## Best Practices

Follow the engineering standard in `standard/asm-6502-development.md` and the commodore-pet-skill sections `system/screen.md` (Character Sets, Raw Screen Codes) and `code/standard.md` (flag semantics, screen-write discipline).

## Documentation Updates

Update the active documentation set before any source modification:

- `PROJECT.md`: add functional requirements for SCREEN/ASCII render modes, UPPER/LOWER charset switching, entry/exit charset contract, persistence, charset-aware label rendering, the filename-follows-charset rule, and the new key bindings; update the viewer use case.
- `ARCHITECTURE.md`: add the new viewer state symbols (`view_charset_mode`, `view_charset`, `view_char_offset`, `saved_pcr_cs`) to the Viewer state domain and the memory map notes; note the PCR save/restore seam in `op_view` and the charset-aware label rendering in the drawing module.
- `SPECIFICATION.md`: add the new constants (`PCR`, `PCR_U`, `PCR_L`, `CH_A`, `CH_U`), the new viewer state symbols, the ASCII-to-screen algorithm, the `view_char_offset` label rule, and the new footer byte layout.
- `TESTING.md`: add coverage targets for the new keys, the charset restore on exit, label uppercase rendering in LOWER, the filename-follows-charset check, the persistence across opens, and the `README.TXT` fixture.
- `README.md`: add `A`, `S`, `L`, `U` to the viewer keys table and note the SCREEN default.

## Step by Step Implementation

**Add equates and key constants**

Section: top equates block near line 84 and the PETSCII keys block near line 121.

    PCR     = $E84C          ; PET Character Set Register (VIA)
    PCR_U   = $0C            ; uppercase / graphics charset (PCR bits 3:1 = 110)
    PCR_L   = $0E            ; lowercase / text charset (PCR bits 3:1 = 111)

    CH_A    = $41
    CH_U    = $55

`CH_S` (`$53`) and `CH_L` (`$4C`) already exist.

**Add viewer state bytes**

Section: `Viewer state and buffers` near line 3409. Add two persisted flags, one derived offset byte, and one save slot. Do not reset the persisted flags in `op_view`.

    view_charset_mode: byte 0     ; 0=SCREEN (raw), 1=ASCII (translate)
    view_charset:      byte 0     ; 0=UPPER, 1=LOWER
    view_char_offset:  byte 0     ; $00 (UPPER) or $40 (LOWER); ORed into label letters
    saved_pcr_cs:      byte 0     ; saved PCR bits 3:1 on viewer entry

**Add charset helpers**

New routines near `view_set_mode_params`:

- `view_set_pcr_charset`: read-modify-write PCR bits 3:1 from `view_charset`. `and #$F1`; `ora #PCR_U` or `ora #PCR_L`; `sta PCR`. Then set `view_char_offset` to `$00` (UPPER) or `$40` (LOWER).
- `view_apply_charset`: `lda PCR; and #$0E; sta saved_pcr_cs`; then `jsr view_set_pcr_charset`.
- `view_restore_charset`: `lda PCR; and #$F1; ora saved_pcr_cs; sta PCR`.

**Add ascii_to_screen routine**

New routine near `petscii_to_screen` (line 1168). Input `A` = byte, output `A` = screen code. Uses `bit view_charset` to branch without clobbering X.

    ; $00-$1F, $7F, $80-$FF -> SC_DOT
    ; $20-$40, $5B-$60, $7B-$7E -> petscii_to_screen
    ; $41-$5A (A-Z): upper -> -$40 ; lower -> identity (already $41-$5A)
    ; $61-$7A (a-z): upper -> -$60 then ORA #$80 (inverse uppercase)
    ;                 lower -> -$60

In the uppercase branch for `a-z`, subtract `$60` to get `$01`-`$1A`, then `ora #$80` to set the reverse-video bit, yielding `$81`-`$9A`. This makes lowercase letters visible as inverse uppercase instead of dots.

**Update op_view entry/exit**

Section: `op_view` (line 2443). Stop resetting `view_mode`. Keep resetting `view_top`, `view_chunk_base`, `view_at_eof`. Call `view_set_mode_params` (reads persisted `view_mode`). After `view_load_chunk` succeeds, call `view_apply_charset`; after `view_loop` returns, call `view_restore_charset` before `full_redraw`. On open failure, do not apply charset (leave PCR unchanged).

**Update view_render_text**

Section: `view_render_text` (line 2883). Replace the conversion block:

    lda (dp_lo),y
    bit view_charset_mode
    bne vrt_ascii
    ; SCREEN: store raw byte, no dot
    jmp vrt_data_store
    vrt_ascii:
    jsr ascii_to_screen
    vrt_data_store:
    ldy vr_col
    sta (sp_lo),y

Remove the old `cmp #$20`/`cmp #$7F`/`vrt_data_dot` path.

**Make header labels charset-aware**

Section: `view_draw_header` (line 2663). The fixed labels `VIEW` (cols 3-6) and the mode label `TEXT` (cols 32-35) / `HEX` (cols 33-35) are written as hardcoded screen codes. After each label letter `lda #imm`, add `ora view_char_offset` before the `sta`. Do NOT apply the offset to the reversed-space fill (`$A0`), the border codes, or the filename path (`lda view_fname,x` / `jsr petscii_to_screen` / `ora #$80`). The filename intentionally follows the active charset.

Because `view_loop` calls `view_render` on every keypress, pressing `L` or `U` re-runs `view_draw_header` with the updated `view_char_offset`, so the labels redraw as uppercase in the new set automatically.

**Update view_loop dispatch**

Section: `view_loop` (line 3137). Add comparisons for `CH_A`, `CH_S`, `CH_L`, `CH_U` and handlers:

- `vl_ascii`: `lda #1; sta view_charset_mode; jmp view_loop`.
- `vl_screen`: `lda #0; sta view_charset_mode; jmp view_loop`.
- `vl_lower`: `lda #1; sta view_charset; jsr view_set_pcr_charset; jmp view_loop`.
- `vl_upper`: `lda #0; sta view_charset; jsr view_set_pcr_charset; jmp view_loop`.

**Replace the footer with a charset-aware render routine**

Section: `view_render` footer block (line 2640) and `view_footer_str` (line 3447). Replace the static-table copy with a `view_draw_footer` routine that writes row 24 from a 40-byte base template, applying `view_char_offset` only to letter positions.

A position is a letter when `(base & $7F)` is in `$01`-`$1A` (covers normal `$01`-`$1A` and reversed `$81`-`$9A`). Borders (`$E1`, `$61`) and reversed space (`$A0`) fail this test and are stored unchanged.

    view_draw_footer:
            ldx #24
            jsr row_addr_sp
            ldy #0
    vdf_loop:
            lda view_footer_base,y
            and #$7F
            cmp #$01
            bcc vdf_plain
            cmp #$1B
            bcs vdf_plain
            lda view_footer_base,y
            ora view_char_offset
            jmp vdf_store
    vdf_plain:
            lda view_footer_base,y
    vdf_store:
            sta (sp_lo),y
            iny
            cpy #40
            bne vdf_loop
            rts

Rename `view_footer_str` to `view_footer_base` and set it to the 40 base bytes from the change request (the uppercase-set form):

    byte $E1,$14,$85,$98,$94,$A0,$08,$85,$98,$A0
    byte $01,$93,$83,$89,$89,$A0,$13,$83,$92,$85,$85,$8E,$A0
    byte $0C,$8F,$97,$85,$92,$A0,$15,$90,$90,$85,$92,$A0
    byte $05,$98,$89,$94,$61

Call `jsr view_draw_footer` from `view_render` in place of the old `vr_footer_loop`.

**Add README.TXT fixture**

Section: `example/build-work-d64.sh`. Add a new `README.TXT` SEQ file with ASCII prose mixing uppercase and lowercase letters, digits, and punctuation. Keep the existing sample files. The new `-write` line:

    printf 'PET Commander\n\nThis disk image is a test fixture for the viewer.\nIt contains a PRG, a few SEQ files, and this README.\nUse the V key to open the viewer, then press A for ASCII\nor S for raw screen codes, and L or U to switch the\ncharacter set between lowercase and uppercase.\n' > "$TMP/README.TXT"
    ...
    -write "$TMP/README.TXT" "README,S"

Rebuild with `example/build-work-d64.sh` (also run by `build.sh`).

## Implementation Order

1. Update documentation (`PROJECT.md`, `ARCHITECTURE.md`, `SPECIFICATION.md`, `TESTING.md`, `README.md`).
2. Add equates and key constants.
3. Add viewer state bytes.
4. Add charset helper routines.
5. Add `ascii_to_screen` routine.
6. Update `op_view` entry/exit and persistence.
7. Update `view_render_text`.
8. Make header labels charset-aware.
9. Update `view_loop` dispatch.
10. Replace the footer with the charset-aware render routine.
11. Add `README.TXT` to `example/build-work-d64.sh` and rebuild the fixture.
12. Run the verification loop.

## Testing Strategy

**Build verification**

`./build.sh` finishes with `Complete. (0)` and zero warnings. `build/commander.prg` loads at `$0401`; `SYS 1038` lands on `jmp start`. Build size rises slightly (new routines and state) and must stay in the expected range.

**Behaviour checks**

Against `example/work.d64` in a graphical `xpet` session:

- Open a SEQ file with `V`: text shows raw screen codes (SCREEN default).
- Open `README.TXT` with `V`, press `A`: ASCII prose renders; in UPPER, lowercase letters show as inverse-video uppercase (e.g. `a` renders as reversed `A`).
- Press `L`: lowercase letters now render normally; the `VIEW` header label and all footer shortcuts stay uppercase; the filename in the header shifts to lowercase (e.g. `readme.txt`).
- Press `U`: letters revert to uppercase rendering; the filename shifts back to uppercase; PCR back to uppercase.
- Press `S`: raw screen codes return.
- Press `H` then `T`: hex/text still switch; offset preserved; labels stay uppercase in both charsets.
- Press `E`: viewer closes; panels reappear in the uppercase set; BASIC `READY.` and `PRINT FRE(0)` still work after `Q` (confirms PCR and ZP restored).
- Reopen with `V` on another file: modes restore to last value, offset resets to zero.
- Footer row 24 matches the specified 40 base bytes exactly in UPPER (verify via VICE monitor dump of `$83C0`-`$83E7`); in LOWER each letter position has bit 6 set ($40 added) and non-letter positions are unchanged.

## Verification

Run the verification loop in `TESTING.md`. The implementation is complete only when all steps pass.

- Assemble with `./build.sh` (expect `Complete. (0)`).
- Confirm the PRG load address is `$0401`.
- Headless smoke run under `xpet -warp`.
- Graphical behaviour check for the changed feature.
