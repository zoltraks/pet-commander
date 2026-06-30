        processor 6502

; =========================================================
; PET Commander -- Norton-style two-panel file manager
; for Commodore PET 3032
;
; Build:  dasm src/commander.asm -f1 -o build/commander.prg
; Run:    xpet -model 3032 -drive8type 2031 -autostart work.d64
;
; The program borrows zero-page bytes $FB-$FE for indirect
; addressing (KERNAL tape pointers; safe while tape is idle).
; Their original values are saved at start and restored at
; exit, so BASIC remains usable after Q / RUN-STOP.
; =========================================================

; ---- Version --------------------------------------------
; Two-number scheme MAJOR.MINOR. MINOR runs 0-9; the next
; increment past 9 rolls MAJOR over and resets MINOR to 0
; (0.9 -> 1.0, 9.9 -> 10.0). See docs/VERSIONING.md.
VERSION_MAJOR = 0
VERSION_MINOR = 1

; ---- KERNAL routines ----------------------------------
; PET 3032 KERNAL jump table entries.  Note: the PET does NOT
; have SETNAM ($FFBD) or SETLFS ($FFBA) -- those are C64-only.
; The PET's OPEN and CLOSE entries include BASIC parameter
; parsing, so we call the low-level logic directly instead.
; See pet_setnam, pet_setlfs, pet_open, pet_close below.
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CHKOUT  = $FFC9
CLRCHN  = $FFCC
CHRIN   = $FFCF
CHROUT  = $FFD2
GETIN   = $FFE4
CLALL   = $FFE7

; ---- PET KERNAL internal addresses --------------------
; These are the actual ROM entry points (past the BASIC
; parameter-parsing stubs) and the zero-page locations that
; the PET OPEN/CLOSE routines use internally.
PET_OPEN_LOGIC  = $F524      ; OPEN after param parse
PET_CLOSE_LOGIC = $F2AC      ; CLOSE after param parse
PET_FNLEN       = $D1        ; filename length
PET_LA          = $D2        ; logical file number
PET_SA          = $D3        ; secondary address
PET_DEV         = $D4        ; device number
PET_FNADR_LO    = $DA        ; filename address low
PET_FNADR_HI    = $DB        ; filename address high

; ---- KERNAL zero-page mirrors -------------------------
STATUS  = $0096
BLNSW   = $00A7

; ---- Hardware -----------------------------------------
SCREEN  = $8000

; ---- Layout constants ---------------------------------
PANEL_ROWS = 20                 ; visible directory rows in each panel
MAX_ENTRY  = 64                 ; entries per panel
ENT_SIZE   = 20                 ; bytes per entry record
                                ; layout: blo, bhi, type, name[16], pad

; ---- ZP pointers (borrowed) ---------------------------
sp_lo   = $FB                   ; primary indirect pointer (source / entry)
sp_hi   = $FC
dp_lo   = $FD                   ; secondary indirect pointer (screen dest)
dp_hi   = $FE

; ---- PETSCII / screen codes ---------------------------
SC_SPACE  = $20
BOX_TL    = $66
BOX_TR    = $67
BOX_BR    = $68
BOX_BL    = $69
BOX_HTOP  = $62
BOX_HBOT  = $64
BOX_VLEFT = $65
BOX_VRIGHT= $63

; ---- PETSCII keys -------------------------------------
K_UP    = $91
K_DOWN  = $11
K_LEFT  = $9D
K_RIGHT = $1D
K_HOME  = $13
K_RETURN= $0D
K_DEL   = $14
K_STOP  = $03
K_SPACE = $20
K_TAB   = $09

; ---- PETSCII characters used in DOS commands ----------
CH_S    = $53
CH_R    = $52
CH_C    = $43
CH_N    = $4E
CH_L    = $4C
CH_D    = $44
CH_Q    = $51
CH_Y    = $59
CH_0    = $30
CH_COLON = $3A
CH_EQ   = $3D

        org $0401

; =========================================================
; BASIC stub: 10 SYS1038
; =========================================================

        word nextline
        word 10
        byte $9E
        byte "1","0","3","8",0

nextline:

        word 0                  ; end-of-BASIC-program marker ($040B-$040C)

filler_40d:     byte 0          ; $040D -- padding so SYS 1038 lands on JMP at $040E

; SYS 1038 = $040E lands on this JMP; it transfers control to the real start.

        jmp start               ; $040E-$0410

; =========================================================
; State (initialised in init)
; =========================================================

saved_blnsw:    byte 0
saved_fb:       byte 0
saved_fc:       byte 0
saved_fd:       byte 0
saved_fe:       byte 0

active_panel:   byte 0          ; 0 = left, 1 = right
quit_flag:      byte 0
status_msg:     byte 0          ; nonzero -> status_buf overrides help row
key_val:        byte 0

; ---- Per-panel state ----------------------------------
p_drive:        byte 8, 8
p_count:        byte 0, 0
p_sel:          byte 0, 0
p_top:          byte 0, 0

; 16 PETSCII chars per panel for disk title (panel*16 offset)
p_title:        ds 32, 0

; =========================================================
; Main entry
; =========================================================

start:

        jsr init

        ; Load both panels with drive 8 directory
        lda #0
        jsr load_panel
        lda #1
        jsr load_panel

        jsr full_redraw

main_loop:

        jsr GETIN
        beq main_loop
        sta key_val
        jsr dispatch_key
        lda quit_flag
        bne do_exit
        jmp main_loop

do_exit:

        jsr exit_program
        rts                     ; return to BASIC

; =========================================================
; PET-specific KERNAL I/O wrappers
; The PET 3032 lacks SETNAM/SETLFS in its KERNAL jump table
; and its OPEN/CLOSE entries include BASIC text parsing.
; These wrappers set the PET's zero-page locations directly
; and call the low-level ROM logic.
; =========================================================

; pet_setnam: A=length, X=addr_lo, Y=addr_hi
pet_setnam:
        sta PET_FNLEN
        stx PET_FNADR_LO
        sty PET_FNADR_HI
        rts

; pet_setlfs: A=LFN, X=DEV, Y=SA
pet_setlfs:
        sta PET_LA
        stx PET_DEV
        sty PET_SA
        rts

; pet_open: call PET OPEN logic (params already set up)
; Returns with carry clear on success, set on error.
; The PET OPEN routine doesn't use carry for errors -- it
; jumps to the BASIC error handler on failure.  We detect
; success by checking whether $AE (file count) increased.
pet_open:
        lda $AE         ; file count before
        pha
        jsr PET_OPEN_LOGIC
        pla
        cmp $AE         ; old vs new: C=0 if old < new (increased)
        bcc po_ok       ; $AE increased -> success
        sec             ; carry set = error
        rts
po_ok:
        clc             ; carry clear = success
        rts

; pet_close: A = logical file number to close
pet_close:
        sta PET_LA
        jsr PET_CLOSE_LOGIC
        rts

; =========================================================
; init: save ZP, switch charset, disable cursor, clear screen
; =========================================================

init:

        ; Save the ZP bytes we will borrow
        lda sp_lo
        sta saved_fb
        lda sp_hi
        sta saved_fc
        lda dp_lo
        sta saved_fd
        lda dp_hi
        sta saved_fe

        lda BLNSW
        sta saved_blnsw
        lda #$01
        sta BLNSW               ; disable cursor blink

        lda #$93                ; PETSCII CLR/HOME
        jsr CHROUT
        rts

; =========================================================
; restore_zp: restore borrowed ZP bytes ($FB-$FE) from saved
; values.  KERNAL I/O routines (OPEN, CLOSE, CLRCHN, CHKIN,
; CHRIN) clobber these tape pointers, so we must restore them
; before each KERNAL call and before using them ourselves.
; =========================================================

restore_zp:

        lda saved_fb
        sta sp_lo
        lda saved_fc
        sta sp_hi
        lda saved_fd
        sta dp_lo
        lda saved_fe
        sta dp_hi
        rts

; =========================================================
; exit_program: undo everything init did
; =========================================================

exit_program:

        jsr CLALL

        lda saved_blnsw
        sta BLNSW

        ; Restore ZP
        lda saved_fb
        sta sp_lo
        lda saved_fc
        sta sp_hi
        lda saved_fd
        sta dp_lo
        lda saved_fe
        sta dp_hi

        lda #$93
        jsr CHROUT
        rts

; =========================================================
; dispatch_key: act on key_val
; =========================================================

dispatch_key:

        lda key_val
        cmp #CH_Q
        beq do_quit
        cmp #K_STOP
        beq do_quit
        cmp #CH_L
        beq do_reload
        cmp #CH_D
        beq do_delete
        cmp #CH_N
        beq do_rename
        cmp #CH_C
        beq do_copy
        cmp #K_TAB
        beq do_switch
        cmp #K_SPACE
        beq do_switch
        cmp #K_LEFT
        beq do_switch
        cmp #K_RIGHT
        beq do_switch
        cmp #K_UP
        beq do_up
        cmp #K_DOWN
        beq do_down
        cmp #K_HOME
        beq do_home
        rts

do_quit:

        lda #1
        sta quit_flag
        rts

do_reload:

        lda active_panel
        jsr load_panel
        jsr full_redraw
        rts

do_switch:

        lda active_panel
        eor #1
        sta active_panel
        jsr redraw_panels
        rts

do_up:

        jsr cursor_up
        jsr redraw_active
        rts

do_down:

        jsr cursor_down
        jsr redraw_active
        rts

do_home:

        ldx active_panel
        lda #0
        sta p_sel,x
        sta p_top,x
        jsr redraw_active
        rts

do_delete:      jmp op_delete
do_rename:      jmp op_rename
do_copy:        jmp op_copy

; =========================================================
; cursor_up / cursor_down: move p_sel and adjust p_top
; =========================================================

cursor_up:

        ldx active_panel
        lda p_sel,x
        beq cu_done
        sec
        sbc #1
        sta p_sel,x
        cmp p_top,x
        bcs cu_done
        sta p_top,x

cu_done:

        rts

cursor_down:

        ldx active_panel
        lda p_count,x
        beq cd_done
        sec
        sbc #1
        sta cd_max
        lda p_sel,x
        cmp cd_max
        bcs cd_done
        clc
        adc #1
        sta p_sel,x
        ; if past visible window, scroll
        sec
        sbc #(PANEL_ROWS-1)
        bcc cd_done
        cmp p_top,x
        bcc cd_done
        sta p_top,x

cd_done:

        rts

cd_max:         byte 0

; =========================================================
; full_redraw / redraw_panels / redraw_active
; =========================================================

full_redraw:

        jsr clear_screen
        jsr draw_title_bar
        jsr draw_frames
        jsr draw_help_bar
        ; fall through

redraw_panels:

        lda #0
        jsr draw_panel
        lda #1
        jsr draw_panel
        jsr draw_status
        rts

redraw_active:

        lda active_panel
        jsr draw_panel
        rts

; =========================================================
; clear_screen: fill all 1000 bytes with $20
; =========================================================

clear_screen:

        lda #SC_SPACE
        ldx #0

cs_loop:

        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        inx
        bne cs_loop             ; 768 bytes done (3 pages)

        ldx #$E8                ; remaining 232 bytes: $8300-$83E7

cs_tail:

        dex
        sta SCREEN+$300,x       ; x = 231..0, writes $83E7..$8300
        bne cs_tail             ; 232 bytes done, total = 1000
        rts

; =========================================================
; draw_title_bar (screen row 0), reversed for emphasis
; =========================================================

draw_title_bar:

        ldx #0

dt_loop:

        lda title_str,x
        sta SCREEN,x
        inx
        cpx #40
        bne dt_loop

        ldx #39

dt_rvs:

        lda SCREEN,x
        ora #$80
        sta SCREEN,x
        dex
        bpl dt_rvs
        rts

; "        PET COMMANDER  --  DRIVE 8      "  (40 chars, screen codes)
title_str:

        byte $20,$20,$20,$20,$20,$20,$20,$20
        byte $10,$05,$14,$20,$03,$0F,$0D,$0D
        byte $01,$0E,$04,$05,$12,$20,$20,$2D
        byte $2D,$20,$20,$04,$12,$09,$16,$05
        byte $20,$38,$20,$20,$20,$20,$20,$20

; =========================================================
; draw_frames: top, sides, bottom borders for both panels
; Layout:
;   row 1: top borders
;   rows 2..22: sides
;   row 23: bottom borders
; Left panel cols 0..19, right panel cols 20..39
; =========================================================

draw_frames:

        ; Row 1 top
        ldx #1
        jsr row_addr_sp
        ldy #0
        lda #BOX_TL
        sta (sp_lo),y
        lda #BOX_HTOP
        ldy #1

df_top1:

        sta (sp_lo),y
        iny
        cpy #19
        bne df_top1
        lda #BOX_TR
        sta (sp_lo),y
        iny
        lda #BOX_TL
        sta (sp_lo),y
        iny
        lda #BOX_HTOP

df_top2:

        sta (sp_lo),y
        iny
        cpy #39
        bne df_top2
        lda #BOX_TR
        sta (sp_lo),y

        ; Rows 2..22 sides
        ldx #2

df_sides:

        stx df_row
        jsr row_addr_sp
        ldy #0
        lda #BOX_VLEFT
        sta (sp_lo),y
        ldy #19
        lda #BOX_VRIGHT
        sta (sp_lo),y
        ldy #20
        lda #BOX_VLEFT
        sta (sp_lo),y
        ldy #39
        lda #BOX_VRIGHT
        sta (sp_lo),y
        ldx df_row
        inx
        cpx #23
        bne df_sides

        ; Row 23 bottom
        ldx #23
        jsr row_addr_sp
        ldy #0
        lda #BOX_BL
        sta (sp_lo),y
        lda #BOX_HBOT
        ldy #1

df_bot1:

        sta (sp_lo),y
        iny
        cpy #19
        bne df_bot1
        lda #BOX_BR
        sta (sp_lo),y
        iny
        lda #BOX_BL
        sta (sp_lo),y
        iny
        lda #BOX_HBOT

df_bot2:

        sta (sp_lo),y
        iny
        cpy #39
        bne df_bot2
        lda #BOX_BR
        sta (sp_lo),y
        rts

df_row:         byte 0

; =========================================================
; draw_help_bar (row 24): command keys
; =========================================================

draw_help_bar:

        ldx #0

dh_loop:

        lda help_str,x
        sta SCREEN+24*40,x
        inx
        cpx #40
        bne dh_loop
        rts

; "TAB-SW N-REN C-CPY D-DEL L-LOD Q-QUIT   "  (40 chars, screen codes)
help_str:

        byte $14,$01,$02,$2D,$13,$17,$20
        byte $0E,$2D,$12,$05,$0E,$20
        byte $03,$2D,$03,$10,$19,$20
        byte $04,$2D,$04,$05,$0C,$20
        byte $0C,$2D,$0C,$0F,$04,$20
        byte $11,$2D,$11,$15,$09,$14
        byte $20,$20,$20,$20

; =========================================================
; draw_status: overlay status_buf on row 24 if status_msg set
; =========================================================

draw_status:

        lda status_msg
        beq ds_done
        ldx #0

ds_loop:

        lda status_buf,x
        beq ds_done
        sta SCREEN+24*40,x
        inx
        cpx #40
        bne ds_loop

ds_done:

        rts

clear_status:

        lda #0
        sta status_msg
        jsr draw_help_bar
        rts

; =========================================================
; set_status: A=lo, Y=hi of null-terminated PETSCII string
; converts to screen codes and stores in status_buf
; =========================================================

set_status:

        sta sp_lo
        sty sp_hi
        ldy #0

ss_loop:

        lda (sp_lo),y
        beq ss_done
        jsr petscii_to_screen
        sta status_buf,y
        iny
        cpy #40
        bne ss_loop

ss_done:

        lda #0
        sta status_buf,y
        lda #1
        sta status_msg
        jsr draw_help_bar
        jsr draw_status
        rts

status_buf:     ds 41, 0

; =========================================================
; draw_panel: A = panel index (0 or 1)
; Renders the panel header (row 2) and PANEL_ROWS file rows (rows 3..22)
; =========================================================

draw_panel:

        sta cur_panel
        tax
        lda col_offset,x
        sta cur_col

        ; ---- Header row (screen row 2) ----
        ldx #2
        jsr row_addr_sp
        lda sp_lo
        clc
        adc cur_col
        sta dp_lo
        lda sp_hi
        adc #0
        sta dp_hi

        ; Clear the 18 inner cols
        ldy #0
        lda #SC_SPACE

dp_hclr:

        sta (dp_lo),y
        iny
        cpy #18
        bne dp_hclr

        ; "8: " (drive number)
        ldx cur_panel
        lda p_drive,x
        clc
        adc #CH_0
        jsr petscii_to_screen
        ldy #0
        sta (dp_lo),y
        lda #CH_COLON
        jsr petscii_to_screen
        ldy #1
        sta (dp_lo),y
        ; Y already 1, advance to 2 (a space already there)

        ; Disk title: copy 16 chars starting at offset 3
        ldx #0

dp_titcp:

        cpx #15
        bcs dp_titcp_done
        lda cur_panel
        beq dp_tit_p0
        lda p_title+16,x
        jmp dp_tit_got

dp_tit_p0:

        lda p_title,x

dp_tit_got:

        beq dp_tit_space
        jsr petscii_to_screen
        jmp dp_tit_store

dp_tit_space:

        lda #SC_SPACE

dp_tit_store:

        sta dp_tit_a
        txa
        clc
        adc #3
        tay
        lda dp_tit_a
        sta (dp_lo),y
        inx
        jmp dp_titcp

dp_titcp_done:

        ; Header row done; reverse the inner 18 cols for emphasis
        ldy #0

dp_hrvs:

        lda (dp_lo),y
        ora #$80
        sta (dp_lo),y
        iny
        cpy #18
        bne dp_hrvs

        ; ---- File rows: screen rows 3 .. 3+PANEL_ROWS-1 ----
        ldx #0

dp_rows:

        stx cur_visrow
        ; absolute entry index
        ldy cur_panel
        lda p_top,y
        clc
        adc cur_visrow
        sta cur_absidx

        ; compute row screen address
        lda cur_visrow
        clc
        adc #3
        tax
        jsr row_addr_sp
        ; inner-col pointer into dp_lo
        lda sp_lo
        clc
        adc cur_col
        sta dp_lo
        lda sp_hi
        adc #0
        sta dp_hi

        ; clear 18 inner cols
        ldy #0
        lda #SC_SPACE

dp_clr:

        sta (dp_lo),y
        iny
        cpy #18
        bne dp_clr

        ; abs_idx < count?
        ldy cur_panel
        lda p_count,y
        beq dp_row_done
        cmp cur_absidx
        beq dp_row_done
        bcc dp_row_done

        jsr draw_entry

        ; Highlight if this is the active panel's selection
        lda cur_panel
        cmp active_panel
        bne dp_row_done
        ldy cur_panel
        lda p_sel,y
        cmp cur_absidx
        bne dp_row_done
        ldy #0

dp_rvs:

        lda (dp_lo),y
        ora #$80
        sta (dp_lo),y
        iny
        cpy #18
        bne dp_rvs

dp_row_done:

        ldx cur_visrow
        inx
        cpx #PANEL_ROWS
        beq dp_panel_done
        jmp dp_rows

dp_panel_done:

        rts

cur_panel:      byte 0
cur_col:        byte 0
cur_visrow:     byte 0
cur_absidx:     byte 0
col_offset:     byte 1, 21
dp_tit_a:       byte 0

; =========================================================
; draw_entry: render entry cur_absidx of cur_panel into (dp_lo)
; Inner column layout (18 cols):
;   0..2  : block count (right-aligned decimal)
;   3     : space
;   4..15 : filename (up to 12 chars)
;   16    : space
;   17    : type screen code
;
; The entry record address is computed into sp_lo; (sp_lo),y reads bytes:
;   y=0 blocks_lo, y=1 blocks_hi, y=2 type, y=3..18 name (16 max)
; (dp_lo),y writes to screen.
; =========================================================

draw_entry:

        ; Pick base of entries array
        lda cur_panel
        bne de_p1
        lda #<entries_p0
        sta sp_lo
        lda #>entries_p0
        sta sp_hi
        jmp de_add

de_p1:

        lda #<entries_p1
        sta sp_lo
        lda #>entries_p1
        sta sp_hi

de_add:

        ; sp += cur_absidx * 20
        lda cur_absidx
        jsr mul20               ; result in m20_lo/m20_hi
        lda sp_lo
        clc
        adc m20_lo
        sta sp_lo
        lda sp_hi
        adc m20_hi
        sta sp_hi

        ; ---- Block count -> num_lo/num_hi ----
        ldy #0
        lda (sp_lo),y
        sta num_lo
        iny
        lda (sp_lo),y
        sta num_hi
        jsr print_num3          ; writes into cols 0..2 of (dp_lo)

        ; ---- Filename: cols 4..15 (12 chars) ----
        ldx #0
        ldy #3                  ; record offset

de_name:

        cpx #12
        bcs de_name_done
        sty de_yrec
        lda (sp_lo),y
        beq de_name_pad
        cmp #$22
        beq de_name_pad
        cmp #$A0
        beq de_name_pad
        jsr petscii_to_screen
        jmp de_name_store

de_name_pad:

        lda #SC_SPACE

de_name_store:

        sta de_ch
        txa
        clc
        adc #4
        tay
        lda de_ch
        sta (dp_lo),y
        ldy de_yrec
        iny
        inx
        jmp de_name

de_name_done:

        ; ---- Type (already a screen code) at col 17 ----
        ldy #2
        lda (sp_lo),y
        ldy #17
        sta (dp_lo),y
        rts

de_yrec:        byte 0
de_ch:          byte 0
num_lo:         byte 0
num_hi:         byte 0

; =========================================================
; print_num3: print num_lo/num_hi as right-aligned 3-digit
; decimal into (dp_lo),0..2. Leading zeros suppressed.
; =========================================================

print_num3:

        ; hundreds digit
        lda #0
        sta pn_dig

pn_h:

        lda num_lo
        sec
        sbc #100
        sta pn_tmp_lo
        lda num_hi
        sbc #0
        bcc pn_h_done
        sta num_hi
        lda pn_tmp_lo
        sta num_lo
        inc pn_dig
        jmp pn_h

pn_h_done:

        lda pn_dig
        bne pn_h_show
        lda #SC_SPACE
        jmp pn_h_put

pn_h_show:

        clc
        adc #CH_0
        jsr petscii_to_screen

pn_h_put:

        ldy #0
        sta (dp_lo),y

        ; tens digit
        lda #0
        sta pn_dig

pn_t:

        lda num_lo
        sec
        sbc #10
        bcc pn_t_done
        sta num_lo
        inc pn_dig
        jmp pn_t

pn_t_done:

        lda pn_dig
        bne pn_t_show
        ; suppress only if hundreds was also blank
        ldy #0
        lda (dp_lo),y
        cmp #SC_SPACE
        bne pn_t_zero
        lda #SC_SPACE
        jmp pn_t_put

pn_t_zero:

        lda #0
        clc
        adc #CH_0
        jsr petscii_to_screen
        jmp pn_t_put

pn_t_show:

        clc
        adc #CH_0
        jsr petscii_to_screen

pn_t_put:

        ldy #1
        sta (dp_lo),y

        ; ones digit
        lda num_lo
        clc
        adc #CH_0
        jsr petscii_to_screen
        ldy #2
        sta (dp_lo),y
        rts

pn_dig:         byte 0
pn_tmp_lo:      byte 0

; =========================================================
; mul20: A -> m20_lo/m20_hi = A * 20
; (A<<4) + (A<<2)
; =========================================================

mul20:

        sta m20_x4_lo
        lda #0
        sta m20_x4_hi
        ; x4: shift left twice
        asl m20_x4_lo
        rol m20_x4_hi
        asl m20_x4_lo
        rol m20_x4_hi

        lda m20_x4_lo
        sta m20_x16_lo
        lda m20_x4_hi
        sta m20_x16_hi
        ; x16: shift left twice more
        asl m20_x16_lo
        rol m20_x16_hi
        asl m20_x16_lo
        rol m20_x16_hi

        lda m20_x4_lo
        clc
        adc m20_x16_lo
        sta m20_lo
        lda m20_x4_hi
        adc m20_x16_hi
        sta m20_hi
        rts

m20_x4_lo:      byte 0
m20_x4_hi:      byte 0
m20_x16_lo:     byte 0
m20_x16_hi:     byte 0
m20_lo:         byte 0
m20_hi:         byte 0

; =========================================================
; petscii_to_screen: A in PETSCII -> A in screen code
; =========================================================

petscii_to_screen:

        cmp #$20
        bcc p2s_done            ; control codes pass through
        cmp #$40
        bcc p2s_done            ; $20-$3F unchanged
        cmp #$60
        bcc p2s_sub40           ; $40-$5F
        cmp #$80
        bcc p2s_done            ; $60-$7F unchanged (rare)
        cmp #$C0
        bcc p2s_sub40           ; $80-$BF
        ; $C0-$FF
        sec
        sbc #$80
        rts

p2s_sub40:

        sec
        sbc #$40
        rts

p2s_done:

        rts

; =========================================================
; row_addr_sp: X = screen row (0..24); sets sp_lo/sp_hi to col-0 addr
; =========================================================

row_addr_sp:

        lda #<SCREEN
        sta sp_lo
        lda #>SCREEN
        sta sp_hi
        cpx #0
        beq ras_done

ras_loop:

        lda sp_lo
        clc
        adc #40
        sta sp_lo
        bcc ras_skip
        inc sp_hi

ras_skip:

        dex
        bne ras_loop

ras_done:

        rts

; =========================================================
; load_panel: A = panel index. Reads "$" from p_drive[A].
; =========================================================

load_panel:

        sta cur_panel

        ldx cur_panel
        lda #0
        sta p_count,x
        sta p_sel,x
        sta p_top,x

        ; Zero this panel's title
        lda cur_panel
        beq lp_zt_p0
        ldx #16

lp_zt_loop1:

        lda #0
        sta p_title+16-1,x
        dex
        bne lp_zt_loop1
        jmp lp_open

lp_zt_p0:

        ldx #16

lp_zt_loop0:

        lda #0
        sta p_title-1,x
        dex
        bne lp_zt_loop0

lp_open:

        jsr restore_zp
        jsr CLALL

        ; SETNAM("$")
        lda #1
        ldx #<dollar
        ldy #>dollar
        jsr pet_setnam

        ; SETLFS (LFN=2, dev=p_drive, SA=0)
        ldx cur_panel
        lda p_drive,x
        sta cur_drive
        lda #2
        ldx cur_drive
        ldy #0
        jsr pet_setlfs

        jsr restore_zp
        jsr pet_open
        bcc lp_chkin
        jmp lp_err

lp_chkin:

        jsr restore_zp
        ldx #2
        jsr CHKIN
        ; PET CHKIN jumps to error handler on failure;
        ; if it returns, it succeeded.  No carry check.

lp_skip_hdr:

        ; Skip 2-byte load address
        jsr CHRIN
        jsr CHRIN

        ; ---- First "line" = disk title ----
        ; Skip next-line ptr (2) and line# (2)
        jsr CHRIN
        jsr CHRIN
        jsr CHRIN
        jsr CHRIN

        ; sp = base of p_title[panel*16]
        lda cur_panel
        bne lp_tp1
        lda #<p_title
        sta sp_lo
        lda #>p_title
        sta sp_hi
        jmp lp_t_loop_init

lp_tp1:

        lda #<(p_title+16)
        sta sp_lo
        lda #>(p_title+16)
        sta sp_hi

lp_t_loop_init:

        ; State 0=before quote, 1=in title, 2=after
        lda #0
        sta lp_state
        sta lp_tch

lp_t_loop:

        jsr CHRIN
        sta lp_byte
        lda STATUS
        beq lp_t_proc
        jmp lp_t_eol

lp_t_proc:

        lda lp_byte
        bne lp_t_nz
        jmp lp_t_eol

lp_t_nz:

        ldx lp_state
        beq lp_t_s0
        cpx #1
        beq lp_t_s1
        ; state 2: discard
        jmp lp_t_loop

lp_t_s0:

        cmp #$22
        beq lp_t_open
        jmp lp_t_loop

lp_t_open:

        lda #1
        sta lp_state
        jmp lp_t_loop

lp_t_s1:

        cmp #$22
        beq lp_t_close
        cmp #$A0
        beq lp_t_loop           ; skip pad
        ldx lp_tch
        cpx #16
        bcs lp_t_loop
        ldy lp_tch
        sta (sp_lo),y
        inc lp_tch
        jmp lp_t_loop

lp_t_close:

        lda #2
        sta lp_state
        jmp lp_t_loop

lp_t_eol:

        ; ---- Entry loop ----

lp_e_loop:

        ; Read next-line ptr (2 bytes); both zero means end already
        jsr CHRIN
        sta lp_blo
        lda STATUS
        beq lp_e_n2
        jmp lp_done

lp_e_n2:

        jsr CHRIN
        lda STATUS
        beq lp_e_blo
        jmp lp_done

lp_e_blo:

        ; Read block count
        jsr CHRIN
        sta lp_blo
        jsr CHRIN
        sta lp_bhi

        lda lp_blo
        ora lp_bhi
        bne lp_have
        jmp lp_done

lp_have:

        ; Check capacity
        ldx cur_panel
        lda p_count,x
        cmp #MAX_ENTRY
        bcc lp_room
        jmp lp_skip

lp_room:

        ; Compute entry record address into sp
        jsr entry_record_sp

        ; Store block count
        ldy #0
        lda lp_blo
        sta (sp_lo),y
        iny
        lda lp_bhi
        sta (sp_lo),y
        ; Default type = space
        ldy #2
        lda #SC_SPACE
        sta (sp_lo),y
        ; Zero name region
        ldy #3
        ldx #0

lp_zname:

        lda #0
        sta (sp_lo),y
        iny
        inx
        cpx #16
        bne lp_zname

        ; Parse: skip to first quote, read until close quote, find type
        lda #0
        sta lp_state
        sta lp_nch
        sta lp_tych

lp_b_loop:

        jsr CHRIN
        sta lp_byte
        lda STATUS
        beq lp_b_ok
        jmp lp_b_eof

lp_b_ok:

        lda lp_byte
        bne lp_b_nz
        jmp lp_b_done

lp_b_nz:

        ldx lp_state
        beq lp_b_s0
        cpx #1
        beq lp_b_s1
        cpx #2
        beq lp_b_s2
        jmp lp_b_s3

lp_b_s0:

        ; before quote
        cmp #$22
        bne lp_b_loop
        lda #1
        sta lp_state
        jmp lp_b_loop

lp_b_s1:

        ; in name
        cmp #$22
        beq lp_b_s1_cl
        cmp #$A0
        beq lp_b_loop           ; skip pad
        ldx lp_nch
        cpx #16
        bcs lp_b_loop
        ldy lp_nch
        iny
        iny
        iny                     ; record offset 3+nch
        sta (sp_lo),y
        inc lp_nch
        jmp lp_b_loop

lp_b_s1_cl:

        lda #2
        sta lp_state
        jmp lp_b_loop

lp_b_s2:

        ; after closing quote, skip spaces and the lock '<'
        cmp #$20
        beq lp_b_loop
        cmp #$3C
        beq lp_b_loop
        ; this byte is first type char
        ldy #2
        sta (sp_lo),y
        jsr petscii_to_screen
        ldy #2
        sta (sp_lo),y
        lda #1
        sta lp_tych
        lda #3
        sta lp_state
        jmp lp_b_loop

lp_b_s3:

        ; in type tail: ignore remaining
        jmp lp_b_loop

lp_b_eof:

        ; STATUS hit during entry parse: if any name char, count it
        lda lp_nch
        beq lp_done
        ; fall through

lp_b_done:

        ; Only count entries that actually had a name in quotes
        ; (skips the trailing "BLOCKS FREE." line which has no quoted name)
        lda lp_nch
        beq lp_b_skip
        ldx cur_panel
        inc p_count,x

lp_b_skip:

        jmp lp_e_loop

lp_skip:

        ; Skip rest of this entry's line bytes until $00
        jsr CHRIN
        sta lp_byte
        lda STATUS
        beq lp_sk_ok
        jmp lp_done

lp_sk_ok:

        lda lp_byte
        beq lp_skip_done
        jmp lp_skip

lp_skip_done:

        jmp lp_e_loop

lp_err:

        lda #<msg_no_disk
        ldy #>msg_no_disk
        jsr set_status

lp_done:

        jsr restore_zp
        jsr CLRCHN
        lda #2
        jsr pet_close
        rts

lp_state:       byte 0
lp_tch:         byte 0
lp_byte:        byte 0
lp_blo:         byte 0
lp_bhi:         byte 0
lp_nch:         byte 0
lp_tych:        byte 0
cur_drive:      byte 0

dollar:         byte "$"
msg_no_disk:    byte "DRIVE NOT READY",0

; =========================================================
; entry_record_sp: sp_lo/sp_hi = entries_pN + p_count[N]*20
; =========================================================

entry_record_sp:

        lda cur_panel
        bne ers_p1
        lda #<entries_p0
        sta sp_lo
        lda #>entries_p0
        sta sp_hi
        jmp ers_add

ers_p1:

        lda #<entries_p1
        sta sp_lo
        lda #>entries_p1
        sta sp_hi

ers_add:

        ldx cur_panel
        lda p_count,x
        jsr mul20
        lda sp_lo
        clc
        adc m20_lo
        sta sp_lo
        lda sp_hi
        adc m20_hi
        sta sp_hi
        rts

; =========================================================
; selected_entry_sp: sp_lo/sp_hi -> active panel's selected entry
; Returns C=1 if panel is empty.
; =========================================================

selected_entry_sp:

        lda active_panel
        sta cur_panel
        ldx cur_panel
        lda p_count,x
        bne ses_have
        sec
        rts

ses_have:

        lda p_sel,x
        sta cur_absidx
        lda cur_panel
        bne ses_p1
        lda #<entries_p0
        sta sp_lo
        lda #>entries_p0
        sta sp_hi
        jmp ses_add

ses_p1:

        lda #<entries_p1
        sta sp_lo
        lda #>entries_p1
        sta sp_hi

ses_add:

        lda cur_absidx
        jsr mul20
        lda sp_lo
        clc
        adc m20_lo
        sta sp_lo
        lda sp_hi
        adc m20_hi
        sta sp_hi
        clc
        rts

; =========================================================
; copy_name_to_cmd: copy entry name (PETSCII) into cmd_buf+3
; Reads from (sp_lo)+3 .. (sp_lo)+18, stops at $00 or 16 chars
; Returns A = number of name bytes copied
; =========================================================

copy_name_to_cmd:

        ldy #3
        ldx #0

cnc_loop:

        cpx #16
        bcs cnc_done
        lda (sp_lo),y
        beq cnc_done
        sta cmd_buf+3,x
        iny
        inx
        bne cnc_loop

cnc_done:

        txa
        rts

; =========================================================
; copy_name_to_savename: copy raw PETSCII name to savename
; =========================================================

copy_name_to_savename:

        ldy #3
        ldx #0

cns_loop:

        cpx #16
        bcs cns_done
        lda (sp_lo),y
        beq cns_done
        sta savename,x
        iny
        inx
        bne cns_loop

cns_done:

        stx savename_len
        rts

savename:       ds 16, 0
savename_len:   byte 0

; =========================================================
; op_delete: scratch the selected file (with Y/N confirmation)
; =========================================================

op_delete:

        jsr selected_entry_sp
        bcc op_del_have
        rts

op_del_have:

        ; Build "S0:NAME"
        lda #CH_S
        sta cmd_buf+0
        lda #CH_0
        sta cmd_buf+1
        lda #CH_COLON
        sta cmd_buf+2
        jsr copy_name_to_cmd
        clc
        adc #3
        sta cmd_len

        lda #<msg_confirm_del
        ldy #>msg_confirm_del
        jsr prompt_yn
        bcs op_del_cancel

        jsr send_dos_cmd
        jsr read_dos_status

        lda active_panel
        jsr load_panel
        jsr full_redraw
        rts

op_del_cancel:

        jsr clear_status
        jsr full_redraw
        rts

msg_confirm_del:        byte "DELETE? Y/N",0

; =========================================================
; op_rename: prompt for new name, send R0:NEW=0:OLD
; =========================================================

op_rename:

        jsr selected_entry_sp
        bcc op_ren_have
        rts

op_ren_have:

        jsr copy_name_to_savename

        lda #<msg_new_name
        ldy #>msg_new_name
        jsr prompt_text
        bcs op_ren_cancel
        lda prompt_len
        bne op_ren_build
        jmp op_ren_cancel

op_ren_build:

        ldy #0
        lda #CH_R
        sta cmd_buf,y
        iny
        lda #CH_0
        sta cmd_buf,y
        iny
        lda #CH_COLON
        sta cmd_buf,y
        iny

        ldx #0

op_ren_new:

        cpx prompt_len
        beq op_ren_eq
        lda prompt_buf,x
        sta cmd_buf,y
        iny
        inx
        bne op_ren_new

op_ren_eq:

        lda #CH_EQ
        sta cmd_buf,y
        iny
        lda #CH_0
        sta cmd_buf,y
        iny
        lda #CH_COLON
        sta cmd_buf,y
        iny

        ldx #0

op_ren_old:

        cpx savename_len
        beq op_ren_send
        lda savename,x
        sta cmd_buf,y
        iny
        inx
        bne op_ren_old

op_ren_send:

        sty cmd_len
        jsr send_dos_cmd
        jsr read_dos_status

        lda active_panel
        jsr load_panel
        jsr full_redraw
        rts

op_ren_cancel:

        jsr clear_status
        jsr full_redraw
        rts

msg_new_name:           byte "NEW NAME",0

; =========================================================
; op_copy: prompt for destination, send C0:DEST=0:SRC
; =========================================================

op_copy:

        jsr selected_entry_sp
        bcc op_cp_have
        rts

op_cp_have:

        jsr copy_name_to_savename

        lda #<msg_copy_to
        ldy #>msg_copy_to
        jsr prompt_text
        bcs op_cp_cancel
        lda prompt_len
        bne op_cp_build
        jmp op_cp_cancel

op_cp_build:

        ldy #0
        lda #CH_C
        sta cmd_buf,y
        iny
        lda #CH_0
        sta cmd_buf,y
        iny
        lda #CH_COLON
        sta cmd_buf,y
        iny

        ldx #0

op_cp_dst:

        cpx prompt_len
        beq op_cp_eq
        lda prompt_buf,x
        sta cmd_buf,y
        iny
        inx
        bne op_cp_dst

op_cp_eq:

        lda #CH_EQ
        sta cmd_buf,y
        iny
        lda #CH_0
        sta cmd_buf,y
        iny
        lda #CH_COLON
        sta cmd_buf,y
        iny

        ldx #0

op_cp_src:

        cpx savename_len
        beq op_cp_send
        lda savename,x
        sta cmd_buf,y
        iny
        inx
        bne op_cp_src

op_cp_send:

        sty cmd_len
        jsr send_dos_cmd
        jsr read_dos_status

        lda active_panel
        jsr load_panel
        jsr full_redraw
        rts

op_cp_cancel:

        jsr clear_status
        jsr full_redraw
        rts

msg_copy_to:            byte "COPY TO",0

; =========================================================
; send_dos_cmd: open command channel with cmd_buf[0..cmd_len-1]
; =========================================================

send_dos_cmd:

        jsr restore_zp
        jsr CLALL
        lda cmd_len
        ldx #<cmd_buf
        ldy #>cmd_buf
        jsr pet_setnam

        ldx active_panel
        lda p_drive,x
        sta cur_drive
        lda #15
        ldx cur_drive
        ldy #15
        jsr pet_setlfs

        jsr restore_zp
        jsr pet_open
        bcs sdc_err
        lda #15
        jsr pet_close
        clc
        rts

sdc_err:

        sec
        rts

; =========================================================
; read_dos_status: open command channel (no filename), read status
; into status_buf as screen codes, set status_msg
; =========================================================

read_dos_status:

        jsr restore_zp
        jsr CLALL
        lda #0
        jsr pet_setnam
        ldx active_panel
        lda p_drive,x
        sta cur_drive
        lda #15
        ldx cur_drive
        ldy #15
        jsr pet_setlfs
        jsr restore_zp
        jsr pet_open
        bcs rds_err

        jsr restore_zp
        ldx #15
        jsr CHKIN
        ldx #0

rds_loop:

        jsr CHRIN
        sta rds_byte
        cmp #$0D
        beq rds_done
        lda STATUS
        beq rds_store
        jmp rds_done

rds_store:

        lda rds_byte
        jsr petscii_to_screen
        sta status_buf,x
        inx
        cpx #40
        bne rds_loop

rds_done:

        lda #0
        sta status_buf,x
        jsr restore_zp
        jsr CLRCHN
        lda #15
        jsr pet_close
        lda #1
        sta status_msg
        jsr draw_help_bar
        jsr draw_status
        rts

rds_err:

        lda #<msg_status_err
        ldy #>msg_status_err
        jsr set_status
        rts

rds_byte:               byte 0
msg_status_err:         byte "STATUS READ FAILED",0

; =========================================================
; prompt_text: A=lo Y=hi PETSCII prompt. Reads up to 16 PETSCII
; chars into prompt_buf. RETURN commits, STOP cancels (C=1).
; =========================================================

prompt_text:

        sta prompt_src_lo
        sty prompt_src_hi
        jsr draw_prompt_label
        lda #0
        sta prompt_len

pt_loop:

        jsr show_prompt_buf
        jsr GETIN
        beq pt_loop
        cmp #K_STOP
        beq pt_cancel
        cmp #K_RETURN
        beq pt_done
        cmp #K_DEL
        beq pt_back
        cmp #$20
        bcc pt_loop
        cmp #$60
        bcs pt_loop
        ldx prompt_len
        cpx #16
        bcs pt_loop
        sta prompt_buf,x
        inc prompt_len
        jmp pt_loop

pt_back:

        ldx prompt_len
        beq pt_loop
        dex
        stx prompt_len
        lda #0
        sta prompt_buf,x
        jmp pt_loop

pt_done:

        jsr clear_status
        clc
        rts

pt_cancel:

        jsr clear_status
        sec
        rts

prompt_src_lo:  byte 0
prompt_src_hi:  byte 0
prompt_buf:     ds 17, 0
prompt_len:     byte 0

; ---- draw_prompt_label: wipe row 24, write PETSCII label + ": " ----
draw_prompt_label:

        ldx #0
        lda #SC_SPACE

dpl_clr:

        sta SCREEN+24*40,x
        inx
        cpx #40
        bne dpl_clr

        lda prompt_src_lo
        sta sp_lo
        lda prompt_src_hi
        sta sp_hi

        ldy #0
        ldx #0

dpl_loop:

        lda (sp_lo),y
        beq dpl_done
        jsr petscii_to_screen
        sta SCREEN+24*40,x
        iny
        inx
        cpx #16
        bne dpl_loop

dpl_done:

        ; Append ": "
        lda #CH_COLON
        jsr petscii_to_screen
        sta SCREEN+24*40,x
        inx
        lda #SC_SPACE
        sta SCREEN+24*40,x
        inx
        stx prompt_label_len
        rts

prompt_label_len:       byte 0

; ---- show_prompt_buf: render current input onto row 24 ----
show_prompt_buf:

        ldx #0

spb_loop:

        cpx prompt_len
        bcs spb_pad
        lda prompt_buf,x
        jsr petscii_to_screen
        sta spb_a
        txa
        clc
        adc prompt_label_len
        tay
        lda spb_a
        sta SCREEN+24*40,y
        inx
        jmp spb_loop

spb_pad:

        ; Fill the rest of the row with spaces

spb_pad_loop:

        txa
        clc
        adc prompt_label_len
        cmp #40
        bcs spb_done
        tay
        lda #SC_SPACE
        sta SCREEN+24*40,y
        inx
        jmp spb_pad_loop

spb_done:

        rts

spb_a:          byte 0

; =========================================================
; prompt_yn: A=lo Y=hi PETSCII prompt; wait Y/RETURN (C=0) or N/STOP (C=1)
; =========================================================

prompt_yn:

        sta prompt_src_lo
        sty prompt_src_hi
        jsr draw_prompt_label

py_loop:

        jsr GETIN
        beq py_loop
        cmp #CH_Y
        beq py_yes
        cmp #K_RETURN
        beq py_yes
        cmp #CH_N
        beq py_no
        cmp #K_STOP
        beq py_no
        jmp py_loop

py_yes:

        jsr clear_status
        clc
        rts

py_no:

        jsr clear_status
        sec
        rts

; =========================================================
; Working buffers
; =========================================================

cmd_buf:        ds 48, 0
cmd_len:        byte 0

; =========================================================
; Per-panel entry tables -- MAX_ENTRY * 20 bytes each
; =========================================================

entries_p0:     ds MAX_ENTRY*ENT_SIZE, 0
entries_p1:     ds MAX_ENTRY*ENT_SIZE, 0
