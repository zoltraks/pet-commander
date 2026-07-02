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
VERSION_MINOR = 3

; ---- KERNAL routines ----------------------------------
; PET 3032 KERNAL jump table entries.  Note: the PET does NOT
; have SETNAM ($FFBD) or SETLFS ($FFBA) -- those are C64-only.
; The PET's OPEN and CLOSE entries include BASIC parameter
; parsing, so we call the low-level logic directly instead.
; See pet_setnam, pet_setlfs, pet_open, pet_close below.

OPEN   = $FFC0
CLOSE  = $FFC3
CHKIN  = $FFC6
CHKOUT = $FFC9
CLRCHN = $FFCC
CHRIN  = $FFCF
CHROUT = $FFD2
GETIN  = $FFE4
CLALL  = $FFE7

; ---- PET KERNAL internal addresses --------------------
; These are the actual ROM entry points (past the BASIC
; parameter-parsing stubs) and the zero-page locations that
; the PET OPEN/CLOSE routines use internally.

PET_OPEN_LOGIC  = $F524 ; OPEN after param parse
PET_CLOSE_LOGIC = $F2AC ; CLOSE after param parse
PET_FNLEN       = $D1   ; filename length
PET_LA          = $D2   ; logical file number
PET_SA          = $D3   ; secondary address
PET_DEV         = $D4   ; device number
PET_FNADR_LO    = $DA   ; filename address low
PET_FNADR_HI    = $DB   ; filename address high

; ---- KERNAL zero-page mirrors -------------------------

STATUS = $0096
BLNSW  = $00A7

; ---- Hardware -----------------------------------------

SCREEN      = $8000
BUFFER      = $7C00     ; 1000-byte back buffer, page-aligned; target of all drawing
VIA_PORTB   = $E840     ; VIA port B (PB5 = VBLANK signal)
RETRACE_BIT = $20       ; PB5 mask: LOW during VBLANK, HIGH during active display
PCR         = $E84C     ; VIA Peripheral Control Register; bits 3:1 select charset
PCR_U       = $0C       ; PCR bits 3:1 = 110 -> uppercase/graphics set (default)
PCR_L       = $0E       ; PCR bits 3:1 = 111 -> lowercase/text set

; ---- Layout constants ---------------------------------

PANEL_ROWS  = 18        ; visible directory rows in each panel (rows 4..21)
PANEL_WIDTH = 20        ; columns per panel including frame borders
PANEL_INNER = 18        ; inner content columns (excluding frame borders)
MAX_ENTRY   = 64        ; entries per panel
ENT_SIZE    = 20        ; bytes per entry record
                        ; layout: blo, bhi, type, name[16], pad

; ---- Viewer layout constants ---------------------------

VIEW_ROWS      = 21     ; visible content rows (rows 2..22 inside frame)
VIEW_TEXT_COLS = 38     ; columns per text-mode row (cols 1..38 inside frame)
VIEW_HEX_COLS  = 8      ; bytes per hex-mode row
VIEW_CHUNK     = 2048   ; chunk buffer size for partial load
VIEW_LFN       = 3      ; logical file number for the viewer

; ---- ZP pointers (borrowed) ---------------------------

sp_lo = $FB             ; primary indirect pointer (source / entry)
sp_hi = $FC
dp_lo = $FD             ; secondary indirect pointer (screen dest)
dp_hi = $FE

; ---- PETSCII / screen codes ---------------------------

SC_SPACE = $20
SC_DOT   = $2E          ; screen code for '.' (non-printable placeholder)

; Center-line box-drawing style (see docs/skill/commodore-pet-skill/system/graphics.md)
; All codes are identical in both character sets -- no charset switching needed.

BOX_TL     = $70        ; corner TL (h-right + v-down)
BOX_TR     = $6E        ; corner TR (h-left + v-down)
BOX_BR     = $7D        ; corner BR (h-left + v-up)
BOX_BL     = $6D        ; corner BL (h-right + v-up)
BOX_H      = $40        ; horizontal center line
BOX_V      = $5D        ; vertical center line
BOX_TJD    = $72        ; T-junction down (h-both + v-down)
BOX_TJU    = $71        ; T-junction up (h-both + v-up)
BOX_TRIGHT = $6B        ; T-junction right (v-both + h-right)
BOX_TLEFT  = $73        ; T-junction left (v-both + h-left)
DOT_H      = $60        ; dotted horizontal line
HB_LEFT    = $61        ; left half block (left 4px filled)
HB_RLEFT   = $E1        ; reversed left half block (right 4px filled)

; ---- PETSCII keys -------------------------------------

K_UP     = $91
K_DOWN   = $11
K_LEFT   = $9D
K_RIGHT  = $1D
K_HOME   = $13
K_RETURN = $0D
K_DEL    = $14
K_STOP   = $03
K_SPACE  = $20
K_TAB    = $09

; ---- PETSCII characters used in DOS commands ----------

CH_S     = $53
CH_R     = $52
CH_C     = $43
CH_N     = $4E
CH_L     = $4C
CH_D     = $44
CH_Q     = $51
CH_Y     = $59
CH_V     = $56
CH_H     = $48
CH_T     = $54
CH_A     = $41
CH_U     = $55
CH_E     = $45
CH_M     = $4D          ; Menu key
CH_F     = $46          ; File menu shortcut
CH_I     = $49          ; Info menu item
CH_0     = $30
CH_COLON = $3A
CH_EQ    = $3D

; ---- Menu layout constants ----------------------------

MENU_COUNT = 3          ; number of menus (File, Disk, Help)
MENU_FILE  = 0
MENU_DISK  = 1
MENU_HELP  = 2
DROP_WIDTH = 12         ; dropdown interior width (items area)
DROP_COLS  = 14         ; dropdown total width including borders

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

filler_40d:     byte 0  ; $040D -- padding so SYS 1038 lands on JMP at $040E

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

active_panel:   byte 0  ; 0 = left, 1 = right
quit_flag:      byte 0
status_msg:     byte 0  ; nonzero -> status_buf overrides help row
key_val:        byte 0

; ---- Per-panel state ----------------------------------

p_drive:        byte 8, 8
p_count:        byte 0, 0
p_sel:          byte 0, 0
p_top:          byte 0, 0

; 16 PETSCII chars per panel for disk title (panel*16 offset)

p_title:        ds 32, 0

; ---- Menu state ---------------------------------------

menu_active:    byte 0  ; 0 = panel mode, 1 = menu mode
menu_idx:       byte 0  ; current menu (0=File, 1=Disk, 2=Help)
menu_sel:       byte 0  ; selected item within current dropdown
menu_debounce:  byte 0  ; counter: ignore opening key while nonzero
menu_open_key:  byte 0  ; PETSCII of key that opened menu (for debounce)

; ---- Find/filter state --------------------------------

p_filter:       byte 0, 0       ; nonzero = filter active per panel
p_filter_str:   ds 32, 0        ; 16-char filter string per panel
p_filter_len:   byte 0, 0       ; filter string length per panel

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

        lda menu_active
        bne ml_dispatch
        ldx menu_debounce       ; decrement debounce counter
        beq ml_no_db2
        dex
        stx menu_debounce

ml_no_db2:

        jsr GETIN
        beq main_loop
        sta key_val
        lda menu_debounce       ; during debounce, ignore the close key
        beq ml_check_key
        lda key_val
        cmp menu_open_key       ; menu_open_key holds the close key during close debounce
        beq main_loop

ml_check_key:

        jsr dispatch_key
        lda quit_flag
        bne do_exit
        jmp main_loop

ml_dispatch:

        jsr menu_loop
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

        lda $AE                 ; file count before
        pha
        jsr PET_OPEN_LOGIC
        pla
        cmp $AE                 ; old vs new: C=0 if old < new (increased)
        bcc po_ok               ; $AE increased -> success
        sec                     ; carry set = error
        rts

po_ok:

        clc                     ; carry clear = success
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

        lda #0
        sta quit_flag           ; clear stale quit flag from previous RUN
        sta menu_active         ; menu not active on startup
        sta p_filter            ; no filter on panel 0
        sta p_filter+1          ; no filter on panel 1
        sta p_filter_len
        sta p_filter_len+1

        lda #$93                ; PETSCII CLR/HOME
        jsr CHROUT

        jsr clear_screen        ; clear back buffer (uninitialized at fixed addr)
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
        cmp #CH_V
        beq do_view
        cmp #CH_M
        beq do_menu_open
        cmp #$12                ; RVS ON (Tab) -> toggle menu
        beq do_menu_open
        cmp #$92                ; RVS OFF (Shift+Tab) -> toggle menu
        beq do_menu_open
        cmp #K_RETURN
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
        jsr redraw_panels
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

do_menu_open:

        lda #1
        sta menu_active
        lda key_val
        sta menu_open_key       ; remember key for debounce
        lda #MENU_FILE
        sta menu_idx
        lda #0
        sta menu_sel
        lda #30                 ; debounce ~0.5s (30 frames at 60Hz)
        sta menu_debounce
        jsr full_redraw
        rts

do_view:        jmp op_view

; =========================================================
; Menu system: menu_loop, draw_dropdown, menu item tables
; =========================================================

; menu_loop: handle keys while menu is active
; Redraws the menu bar with active highlight and the dropdown,
; then waits for a key and routes it.

menu_loop:

        jsr full_redraw         ; draw panels + menu bar + status line
        jsr draw_dropdown       ; overlay the dropdown
        jsr present_screen
        jmp ml_wait

ml_close_jmp:

        jmp do_menu_close

ml_wait:

        ldx menu_debounce       ; decrement debounce counter each iteration
        beq ml_no_db
        dex
        stx menu_debounce

ml_no_db:

        jsr GETIN
        beq ml_wait
        sta key_val
        lda menu_debounce       ; during debounce, ignore the opening key
        bne ml_skip_open_key
        jmp ml_check_keys

ml_skip_open_key:

        lda key_val
        cmp menu_open_key
        beq ml_wait

ml_check_keys:

        lda key_val
        cmp #CH_M
        beq ml_close_jmp
        cmp #$12                ; RVS ON (Tab) -> close menu
        beq ml_close_jmp
        cmp #$92                ; RVS OFF (Shift+Tab) -> close menu
        beq ml_close_jmp
        cmp #K_STOP
        beq ml_close_jmp
        cmp #K_RETURN
        bne ml_skip_activate
        jmp do_menu_activate

ml_skip_activate:

        cmp #K_LEFT
        beq do_menu_prev
        cmp #K_RIGHT
        beq do_menu_next
        cmp #K_UP
        beq do_menu_up
        cmp #K_DOWN
        beq do_menu_down
        cmp #CH_F
        bne ml_not_f
        jmp do_menu_file

ml_not_f:

        cmp #CH_D
        bne ml_not_d
        jmp do_menu_disk

ml_not_d:

        cmp #CH_H
        bne ml_not_h
        jmp do_menu_help

ml_not_h:

        jmp ml_wait

do_menu_close:

        lda key_val
        sta menu_open_key       ; save close key for debounce
        lda #0
        sta menu_active
        lda #30                 ; debounce close key too
        sta menu_debounce
        jsr full_redraw
        jsr flush_keys
        rts

do_menu_prev:

        lda menu_idx
        beq dmp_wrap
        dec menu_idx
        jmp dmp_done

dmp_wrap:

        lda #(MENU_COUNT-1)
        sta menu_idx

dmp_done:

        lda #0
        sta menu_sel
        rts

do_menu_next:

        lda menu_idx
        cmp #(MENU_COUNT-1)
        bne dmn_inc
        lda #0
        sta menu_idx
        jmp dmn_done

dmn_inc:

        inc menu_idx

dmn_done:

        lda #0
        sta menu_sel
        rts

do_menu_up:

        lda menu_sel
        beq dmu_wrap
        dec menu_sel
        rts

dmu_wrap:

        ; wrap to last item in current menu

        ldx menu_idx
        lda menu_item_count,x
        sta menu_sel
        rts

do_menu_down:

        ldx menu_idx
        lda menu_item_count,x
        sta dmd_max
        lda menu_sel
        cmp dmd_max
        bcc dmd_inc
        lda #0
        sta menu_sel
        rts

dmd_inc:

        inc menu_sel
        rts
dmd_max:        byte 0

do_menu_file:

        lda #MENU_FILE
        sta menu_idx
        lda #0
        sta menu_sel
        rts

do_menu_disk:

        lda #MENU_DISK
        sta menu_idx
        lda #0
        sta menu_sel
        rts

do_menu_help:

        lda #MENU_HELP
        sta menu_idx
        lda #0
        sta menu_sel
        rts

; do_menu_activate: execute the selected menu item

do_menu_activate:

        lda menu_idx
        cmp #MENU_FILE
        beq dma_file
        cmp #MENU_DISK
        beq dma_disk
        jmp dma_help

dma_file:

        ldx menu_sel
        cpx #0
        beq dma_view
        cpx #1
        beq dma_copy
        cpx #2
        beq dma_rename
        cpx #3
        beq dma_delete
        cpx #4
        beq dma_info
        cpx #5
        beq dma_find
        cpx #6
        beq dma_quit
        rts

dma_view:

        jsr do_menu_close
        jmp op_view

dma_copy:

        jsr do_menu_close
        jmp op_copy

dma_rename:

        jsr do_menu_close
        jmp op_rename

dma_delete:

        jsr do_menu_close
        jmp op_delete

dma_info:

        jsr do_menu_close
        jmp op_info

dma_find:

        jsr do_menu_close
        jmp op_find

dma_quit:

        jsr do_menu_close
        lda #1
        sta quit_flag
        rts

dma_disk:

        ldx menu_sel
        cpx #0
        beq dma_change
        cpx #1
        beq dma_reload
        rts

dma_change:

        jsr do_menu_close
        jmp op_change

dma_reload:

        jsr do_menu_close
        jmp do_reload

dma_help:

        ldx menu_sel
        cpx #0
        beq dma_about
        rts

dma_about:

        jsr do_menu_close
        jmp op_about

; =========================================================
; draw_dropdown: draw the current menu's dropdown box
; The dropdown drops from the menu bar (row 0) into the panel area.
; Width is 12 columns; left edge is title_col-2, clamped so the
; right edge never exceeds column 38.
; Height = item_count + 3 rows:
;   row 1          : top T-junction connectors
;   rows 2..count+1: menu items
;   row count+2    : empty interior row
;   row count+3    : bottom border
; Selected item is highlighted with reversed video and a half-block
; left edge ($E1) and right edge ($61).
; =========================================================

draw_dropdown:

        ; Get the dropdown's title column and item count

        ldx menu_idx
        lda menu_col,x
        sta dd_col
        lda menu_item_count,x
        sta dd_count

        ; Compute left edge = title_col - 2, right edge = left + 11 (12-column box).
        ; If the box would exceed the right edge, clamp right to 38 and use a
        ; narrower 11-column box (left = 28) so the right edge stays aligned with
        ; the right edge of the active menu title area.

        lda dd_col
        sec
        sbc #2
        sta dd_left
        clc
        adc #11
        cmp #39
        bcc dd_store_right
        lda #38
        sta dd_right
        lda #28
        sta dd_left
        jmp dd_right_done

dd_store_right:

        sta dd_right

dd_right_done:

        ; Draw top edge connectors at row 1 and clear the interior

        ldx #1
        jsr row_addr_sp
        ldy dd_left
        lda #BOX_TLEFT
        sta (sp_lo),y
        ldy dd_right
        lda #BOX_TRIGHT
        sta (sp_lo),y
        jsr draw_dropdown_clear_interior

        ; Total rows = count + 4; row index starts at 2 (first item).
        ; The extra row is the bottom border (row count + 3).

        lda dd_count
        clc
        adc #4
        sta dd_rows
        ldx #2

dd_row_loop:

        stx dd_row
        txa
        sec
        sbc #2
        sta dd_item_idx

        ; Classify the row: item, empty interior, or bottom border

        ldx dd_item_idx
        cpx dd_count
        bcc dd_item_row         ; 0 <= item_idx < count  -> item
        beq dd_empty_row        ; item_idx == count      -> empty row
        jmp dd_bottom_row       ; item_idx > count       -> bottom border

dd_item_row:

        jsr draw_dropdown_row
        jmp dd_next_row

dd_empty_row:

        jsr draw_dropdown_sides
        jmp dd_next_row

dd_bottom_row:

        jsr draw_dropdown_bottom
        jmp dd_next_row

dd_next_row:

        ldx dd_row
        inx
        cpx dd_rows
        bcc dd_row_loop
        rts

; draw_dropdown_sides: clear interior and draw vertical borders for the current row.

draw_dropdown_sides:

        ldx dd_row
        jsr row_addr_sp
        jsr draw_dropdown_clear_interior
        ldy dd_left
        lda #BOX_V
        sta (sp_lo),y
        ldy dd_right
        lda #BOX_V
        sta (sp_lo),y
        rts

; draw_dropdown_bottom: draw bottom border for the current row.

draw_dropdown_bottom:

        ldx dd_row
        jsr row_addr_sp
        ldy dd_left
        lda #BOX_BL
        sta (sp_lo),y
        ldy dd_right
        lda #BOX_BR
        sta (sp_lo),y
        ldy dd_left
        iny

        ; Horizontal line between the corners

        lda #BOX_H

dd_bot_fill:

        sta (sp_lo),y
        iny
        cpy dd_right
        bne dd_bot_fill
        rts

; draw_dropdown_clear_interior: fill cols dd_left+1 .. dd_right-1 with spaces.

draw_dropdown_clear_interior:

        ldy dd_left
        iny
        lda #SC_SPACE

ddci_loop:

        sta (sp_lo),y
        iny
        cpy dd_right
        bne ddci_loop
        rts

; draw_dropdown_row: draw one item row (dd_item_idx) with side borders,
; left-aligned label, right-aligned shortcut, and selected highlight.
; The interior width is dd_right - dd_left - 1 (normally 10, 9 when the
; box is clamped to the right edge). Layout inside the box:
;   offset 0              : left edge (space, or $E1 when selected)
;   offsets 1..width-4    : label (padded with spaces)
;   offset width-3        : padding space
;   offset width-2        : shortcut
;   offset width-1        : right edge (space, or $61 when selected)
; The right border at dd_right is drawn separately and is never overwritten.

draw_dropdown_row:

        ; Load label and shortcut for this item before touching the screen pointer

        jsr dd_get_item_label
        jsr dd_get_item_shortcut

        ; Set selected flag

        lda #0
        sta dd_sel_flag
        ldx dd_item_idx
        cpx menu_sel
        bne ddr_set_row
        lda #$ff
        sta dd_sel_flag

        ; Compute interior width and special offsets from the actual border cols

ddr_set_row:

        lda dd_right
        sec
        sbc dd_left
        sbc #1
        sta dd_width            ; interior width (e.g., 10 or 9)
        tax
        dex                     ; width-1 = right edge offset
        stx dd_right_edge
        dex                     ; width-2 = shortcut offset
        stx dd_shortcut_off
        dex                     ; width-3 = padding space offset
        stx dd_space_off

        ; Set screen pointer for this row

        ldx dd_row
        jsr row_addr_sp

        ; Clear interior and draw side borders.
        ; For the selected item, use T-junctions (BOX_TLEFT/BOX_TRIGHT) when the
        ; dropdown is wide (>= 12 total columns), otherwise keep vertical borders
        ; (BOX_V) so the highlight bar sits inside the narrower frame.

        jsr draw_dropdown_clear_interior

        ; Wide dropdowns (>=12 total cols) use T-junctions for the selected
        ; item; narrow dropdowns keep vertical borders so the highlight bar
        ; sits inside the frame.

        ldy dd_left
        lda dd_width
        cmp #10
        bcc ddr_left_v        ; narrow: plain vertical border
        lda #BOX_V
        ldx dd_sel_flag
        beq ddr_left_border
        lda #BOX_TLEFT
        bne ddr_left_border
ddr_left_v:
        lda #BOX_V
ddr_left_border:
        sta (sp_lo),y

        ldy dd_right
        lda dd_width
        cmp #10
        bcc ddr_right_v       ; narrow: plain vertical border
        lda #BOX_V
        ldx dd_sel_flag
        beq ddr_right_border
        lda #BOX_TRIGHT
        bne ddr_right_border
ddr_right_v:
        lda #BOX_V
ddr_right_border:
        sta (sp_lo),y

        ; Draw interior offsets 0..dd_width-1

        ldy #0
        sty ddr_off

ddr_loop:

        ; Compute screen column

        lda dd_left
        clc
        adc ddr_off
        adc #1
        tay

        ; Determine what to draw at this interior offset

        ldx ddr_off
        beq ddr_offset0
        cpx dd_right_edge
        beq ddr_right_edge_draw
        cpx dd_shortcut_off
        beq ddr_shortcut
        cpx dd_space_off
        beq ddr_space

        ; offsets 1..space_off-1: label chars (padded with spaces)
        txa
        sec
        sbc #1
        tax
        lda dd_label_buf,x
        beq ddr_label_sp
        jsr petscii_to_screen
        jmp ddr_char

ddr_label_sp:

        lda #SC_SPACE
        jmp ddr_char

ddr_space:

        lda #SC_SPACE
        jmp ddr_char

ddr_shortcut:

        lda dd_shortcut
        jsr petscii_to_screen
        jmp ddr_char

ddr_offset0:

        lda dd_sel_flag
        beq ddr_sp0
        lda #HB_RLEFT           ; $E1 reversed left half-block
        jmp ddr_char

ddr_sp0:

        lda #SC_SPACE
        jmp ddr_char

ddr_right_edge_draw:

        lda dd_sel_flag
        beq ddr_sp_re
        lda #HB_LEFT            ; $61 left half-block
        jmp ddr_char

ddr_sp_re:

        lda #SC_SPACE

        ; Reverse content offsets (1..right_edge-1) when selected

ddr_char:

        ldx dd_sel_flag
        beq ddr_store
        ldx ddr_off
        beq ddr_store
        cpx dd_right_edge
        beq ddr_store
        ora #$80

ddr_store:

        sta (sp_lo),y

        inc ddr_off
        lda ddr_off
        cmp dd_width
        bne ddr_loop
        rts

; dd_get_item_label: get the label for menu_idx/dd_item_idx into dd_label_buf

dd_get_item_label:

        ; Each menu has a table of item labels
        ; Labels are fixed-length (8 chars + shortcut char = 9 bytes per item)
        ; For simplicity, use lookup by menu and item index

        lda menu_idx
        cmp #MENU_FILE
        beq dd_gil_file
        cmp #MENU_DISK
        beq dd_gil_disk
        jmp dd_gil_help

dd_gil_file:

        lda dd_item_idx
        asl                     ; *2 (each pointer is 2 bytes)
        tax
        lda menu_file_labels,x
        sta sp_lo
        lda menu_file_labels+1,x
        sta sp_hi
        jmp dd_gil_copy

dd_gil_disk:

        lda dd_item_idx
        asl
        tax
        lda menu_disk_labels,x
        sta sp_lo
        lda menu_disk_labels+1,x
        sta sp_hi
        jmp dd_gil_copy

dd_gil_help:

        lda dd_item_idx
        asl
        tax
        lda menu_help_labels,x
        sta sp_lo
        lda menu_help_labels+1,x
        sta sp_hi
        jmp dd_gil_copy

dd_gil_copy:

        ; Copy up to DROP_WIDTH chars from (sp_lo) to dd_label_buf

        ldy #0

dd_gil_loop:

        cpy #DROP_WIDTH
        bcs dd_gil_done
        lda (sp_lo),y
        sta dd_label_buf,y
        beq dd_gil_fill
        iny
        jmp dd_gil_loop

dd_gil_fill:

        ; Fill rest with zeros

        lda #0
        sta dd_label_buf,y
        iny
        cpy #DROP_WIDTH
        bcc dd_gil_fill

dd_gil_done:

        rts

; dd_get_item_shortcut: load the PETSCII shortcut for
; menu_idx/dd_item_idx into dd_shortcut.

dd_get_item_shortcut:

        lda menu_idx
        cmp #MENU_FILE
        bne dd_gis_disk
        ldx dd_item_idx
        lda menu_file_shortcuts,x
        sta dd_shortcut
        rts

dd_gis_disk:

        cmp #MENU_DISK
        bne dd_gis_help
        ldx dd_item_idx
        lda menu_disk_shortcuts,x
        sta dd_shortcut
        rts

dd_gis_help:

        ldx dd_item_idx
        lda menu_help_shortcuts,x
        sta dd_shortcut
        rts

; Menu data tables

menu_col:       byte 3, 9, 33   ; column positions for File, Disk, Help titles

menu_item_count: byte 7, 2, 1   ; number of items per menu

; Menu item labels (null-terminated PETSCII strings)

menu_file_labels:

        word mfl_view, mfl_copy, mfl_rename, mfl_delete, mfl_info, mfl_find, mfl_quit

menu_disk_labels:

        word mdl_change, mdl_reload

menu_help_labels:

        word mhl_about

mfl_view:       byte "VIEW", 0
mfl_copy:       byte "COPY", 0
mfl_rename:     byte "RENAME", 0
mfl_delete:     byte "DELETE", 0
mfl_info:       byte "INFO", 0
mfl_find:       byte "FIND", 0
mfl_quit:       byte "QUIT", 0

mdl_change:     byte "CHANGE", 0
mdl_reload:     byte "RELOAD", 0

mhl_about:      byte "ABOUT", 0

; Menu shortcuts (PETSCII, converted to screen code when drawn)

menu_file_shortcuts:    byte $56, $43, $4E, $44, $49, $46, $51
menu_disk_shortcuts:    byte $43, $52
menu_help_shortcuts:    byte $41

; Dropdown temporaries

dd_col:         byte 0          ; title column for current menu
dd_left:        byte 0          ; dropdown left border column
dd_right:       byte 0          ; dropdown right border column
dd_count:       byte 0          ; number of items in current menu
dd_rows:        byte 0          ; total dropdown rows (count + 4)
dd_row:         byte 0          ; current row being drawn
dd_item_idx:    byte 0          ; current item index
dd_shortcut:    byte 0          ; shortcut PETSCII for current item
dd_sel_flag:    byte 0          ; $ff if current item is selected, else 0
ddr_off:        byte 0          ; interior column offset for drawing
dd_width:       byte 0          ; interior width (dd_right - dd_left - 1)
dd_right_edge:  byte 0          ; interior offset of right highlight edge
dd_shortcut_off: byte 0         ; interior offset of shortcut char
dd_space_off:   byte 0          ; interior offset of padding space before shortcut
dd_label_buf:   ds DROP_WIDTH, 0

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
        jsr draw_menu_bar
        jsr draw_frames
        jsr draw_status_line

        ; fall through

redraw_panels:

        lda #0
        jsr draw_panel
        lda #1
        jsr draw_panel
        jsr draw_status_line
        jsr present_screen
        rts

redraw_active:

        lda active_panel
        jsr draw_panel
        jsr draw_status_line
        jsr present_screen
        rts

; =========================================================
; clear_screen: fill all 1000 bytes with $20
; =========================================================

clear_screen:

        lda #SC_SPACE
        ldx #0

cs_loop:

        sta BUFFER,x
        sta BUFFER+$100,x
        sta BUFFER+$200,x
        inx
        bne cs_loop             ; 768 bytes done (3 pages)

        ldx #$E8                ; remaining 232 bytes: $7F00-$7FE7

cs_tail:

        dex
        sta BUFFER+$300,x       ; x = 231..0, writes $7FE7..$7F00
        bne cs_tail             ; 232 bytes done, total = 1000
        rts

; =========================================================
; draw_menu_bar (screen row 0): reverse-video bar with menu titles
; Shows FILE, DISK, and HELP with half-block borders.
; The active menu title area (when menu_active) is normal video;
; inactive titles are reversed against the reversed bar.
; =========================================================

draw_menu_bar:

        ldx #0
        jsr row_addr_sp

        ; Left border

        ldy #0
        lda #HB_RLEFT           ; $E1 reversed left half-block
        sta (sp_lo),y

        ; Right border

        ldy #39
        lda #HB_LEFT            ; $61 left half-block
        sta (sp_lo),y

        ; Fill cols 1-38 with reversed space

        ldy #1
        lda #$A0                ; reversed space

dmb_fill:

        sta (sp_lo),y
        iny
        cpy #39
        bne dmb_fill

        ; If a menu is active, draw its 6-column title area as normal spaces
        ; so the active title stands out in normal video.

        lda menu_active
        beq dmb_titles
        ldx menu_idx
        lda menu_col,x
        sec
        sbc #1
        tay
        lda #SC_SPACE
        ldx #6

        ; Write 6 normal spaces for the active title area

dmb_active_fill:

        sta (sp_lo),y
        iny
        dex
        bne dmb_active_fill

dmb_titles:

        ; Write menu titles: FILE at cols 3-6, DISK at cols 9-12, HELP at cols 33-36
        ; Each title letter is reversed unless it is in the active menu area
        ; FILE = screen codes $06,$09,$0C,$05

        ldy #3
        lda #$06                ; 'F'
        jsr dmb_write_title_char
        ldy #4
        lda #$09                ; 'I'
        jsr dmb_write_title_char
        ldy #5
        lda #$0C                ; 'L'
        jsr dmb_write_title_char
        ldy #6
        lda #$05                ; 'E'
        jsr dmb_write_title_char

        ; DISK = screen codes $04,$09,$13,$0B

        ldy #9
        lda #$04                ; 'D'
        jsr dmb_write_title_char
        ldy #10
        lda #$09                ; 'I'
        jsr dmb_write_title_char
        ldy #11
        lda #$13                ; 'S'
        jsr dmb_write_title_char
        ldy #12
        lda #$0B                ; 'K'
        jsr dmb_write_title_char

        ; HELP = screen codes $08,$05,$0C,$10

        ldy #33
        lda #$08                ; 'H'
        jsr dmb_write_title_char
        ldy #34
        lda #$05                ; 'E'
        jsr dmb_write_title_char
        ldy #35
        lda #$0C                ; 'L'
        jsr dmb_write_title_char
        ldy #36
        lda #$10                ; 'P'
        jsr dmb_write_title_char
        rts

; dmb_write_title_char: A = screen code, Y = column.
; If menu_active and this position is in the active menu title area,
; write normal video (no bit 7). Otherwise write reversed (bit 7 set).
; The active menu title areas are: File=cols 2-7, Disk=cols 8-13, Help=cols 32-37.

dmb_write_title_char:

        pha                     ; save screen code
        lda menu_active
        beq dmb_rev             ; menu not active -> reverse all

        ; Check if Y is in the active menu's column range

        lda menu_idx
        cmp #MENU_FILE
        bne dmb_chk_disk
        cpy #2
        bcc dmb_rev
        cpy #8
        bcc dmb_normal          ; cols 2-7 = File active area
        jmp dmb_rev

dmb_chk_disk:

        cmp #MENU_DISK
        bne dmb_chk_help
        cpy #8
        bcc dmb_rev
        cpy #14
        bcc dmb_normal          ; cols 8-13 = Disk active area
        jmp dmb_rev

dmb_chk_help:

        cpy #32
        bcc dmb_rev
        cpy #38
        bcc dmb_normal          ; cols 32-37 = Help active area
        jmp dmb_rev

dmb_rev:

        pla
        ora #$80                ; reverse video
        sta (sp_lo),y
        rts

dmb_normal:

        pla
        sta (sp_lo),y           ; normal video
        rts

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
        lda #BOX_H
        ldy #1

df_top1:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH-1)
        bne df_top1
        lda #BOX_TR             ; left panel top-right corner (col 19)
        sta (sp_lo),y
        iny
        lda #BOX_TL             ; right panel top-left corner (col 20)
        sta (sp_lo),y
        iny
        lda #BOX_H

df_top2:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH*2-1)
        bne df_top2
        lda #BOX_TR
        sta (sp_lo),y

        ; Rows 2..22 sides

        ldx #2

df_sides:

        stx df_row
        jsr row_addr_sp
        ldy #0
        lda #BOX_V
        sta (sp_lo),y
        ldy #(PANEL_WIDTH-1)
        lda #BOX_V
        sta (sp_lo),y
        ldy #PANEL_WIDTH
        lda #BOX_V
        sta (sp_lo),y
        ldy #(PANEL_WIDTH*2-1)
        lda #BOX_V
        sta (sp_lo),y
        ldx df_row
        inx
        cpx #23
        bne df_sides

        ; Row 3: separator line (T-right, H*18, T-left for each panel)

        ldx #3
        jsr row_addr_sp
        ldy #0
        lda #BOX_TRIGHT
        sta (sp_lo),y
        lda #BOX_H
        ldy #1

df_sep1:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH-1)
        bne df_sep1
        lda #BOX_TLEFT
        sta (sp_lo),y
        iny
        lda #BOX_TRIGHT
        sta (sp_lo),y
        iny
        lda #BOX_H

df_sep2:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH*2-1)
        bne df_sep2
        lda #BOX_TLEFT
        sta (sp_lo),y

        ; Row 22: dotted separator line (V, dotted*18, V for each panel)

        ldx #22
        jsr row_addr_sp
        ldy #0
        lda #BOX_V
        sta (sp_lo),y
        lda #DOT_H
        ldy #1

df_dot1:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH-1)
        bne df_dot1
        lda #BOX_V
        sta (sp_lo),y
        iny
        lda #BOX_V
        sta (sp_lo),y
        iny
        lda #DOT_H

df_dot2:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH*2-1)
        bne df_dot2
        lda #BOX_V
        sta (sp_lo),y

        ; Row 23 bottom

        ldx #23
        jsr row_addr_sp
        ldy #0
        lda #BOX_BL
        sta (sp_lo),y
        lda #BOX_H
        ldy #1

df_bot1:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH-1)
        bne df_bot1
        lda #BOX_BR             ; left panel bottom-right corner (col 19)
        sta (sp_lo),y
        iny
        lda #BOX_BL             ; right panel bottom-left corner (col 20)
        sta (sp_lo),y
        iny
        lda #BOX_H

df_bot2:

        sta (sp_lo),y
        iny
        cpy #(PANEL_WIDTH*2-1)
        bne df_bot2
        lda #BOX_BR
        sta (sp_lo),y
        rts

df_row:         byte 0

; =========================================================
; draw_status_line (row 24): reverse-video bar showing selected file info
; or DOS status message. Half-block borders like the menu bar.
; =========================================================

draw_status_line:

        ldx #24
        jsr row_addr_sp

        ; Left border

        ldy #0
        lda #HB_RLEFT
        sta (sp_lo),y

        ; Right border

        ldy #39
        lda #HB_LEFT
        sta (sp_lo),y

        ; Fill cols 1-38 with reversed space

        ldy #1
        lda #$A0

dsl_fill:

        sta (sp_lo),y
        iny
        cpy #39
        bne dsl_fill

        ; If status_msg is set, overlay the status buffer

        lda status_msg
        bne dsl_status

        ; Otherwise show selected file info

        jsr draw_status_fileinfo
        rts

; Overlay status_buf (PETSCII screen codes) into the reversed bar

dsl_status:

        ldy #1
        ldx #0

dsl_stat_loop:

        lda status_buf,x
        beq dsl_stat_done
        ora #$80                ; reverse video
        sta (sp_lo),y
        inx
        iny
        cpy #39
        bne dsl_stat_loop

dsl_stat_done:

        rts

; draw_status_fileinfo: show selected file's name, size, type
; Format: [border] filename(16) spaces... size_bytes(right-aligned,~36) sp type [border]
; Uses sp_lo/sp_hi for the entry record, dp_lo/dp_hi for screen row 24.
; Record layout: y=0 blo, y=1 bhi, y=2 type(screen code), y=3..18 name(PETSCII)

draw_status_fileinfo:

        jsr selected_entry_sp
        bcc dsf_have_entry
        rts                     ; empty panel, leave reversed spaces

dsf_have_entry:

        ; Set dp to row 24 start in BUFFER

        lda #<(BUFFER+24*40)
        sta dp_lo
        lda #>(BUFFER+24*40)
        sta dp_hi

        ; ---- Filename: cols 1-16 (16 chars, left-aligned, reversed) ----

        ldx #0

dsf_name_loop:

        cpx #16
        bcs dsf_name_done
        txa
        clc
        adc #3                  ; record offset = 3 + name_index
        tay
        lda (sp_lo),y           ; read name char from record
        beq dsf_name_sp
        cmp #$22                ; skip quote chars
        beq dsf_name_sp
        cmp #$A0                ; skip shifted-space
        beq dsf_name_sp
        jsr petscii_to_screen
        jmp dsf_name_store

dsf_name_sp:

        lda #SC_SPACE

dsf_name_store:

        ora #$80                ; reverse video
        sta dsf_ch              ; save char
        txa
        clc
        adc #1                  ; screen col = 1 + X
        tay
        lda dsf_ch
        sta (dp_lo),y
        inx
        jmp dsf_name_loop

dsf_name_done:

        ; ---- Type char at col 38 (reversed) ----

        ldy #2                  ; type at record offset 2 (already screen code)
        lda (sp_lo),y
        ora #$80                ; reverse video
        ldy #38
        sta (dp_lo),y

        ; ---- Read block count from record offsets 0/1 ----

        ldy #0
        lda (sp_lo),y
        sta dsf_blo
        iny
        lda (sp_lo),y
        sta dsf_bhi

        ; ---- Convert 16-bit block count to 5-digit decimal ----

        jsr dsf_format_blocks

        ; ---- Write block count right-aligned at cols 32-36 ----

        ldx #0
        stx dsf_lead            ; 0 = still suppressing leading zeroes

dsf_blk_write:

        lda dsf_blkstr,x
        ldy dsf_lead
        bne dsf_blk_emit

        ; Still suppressing leading zeroes

        cmp #$30                ; '0'
        bne dsf_blk_nz

        ; It's a leading zero: emit space instead

        lda #SC_SPACE
        jmp dsf_blk_emit

dsf_blk_nz:

        ; First non-zero digit: stop suppressing

        sta dsf_ch              ; save digit value
        lda #1
        sta dsf_lead
        lda dsf_ch              ; restore digit value

dsf_blk_emit:

        ora #$80                ; reverse video
        sta dsf_ch              ; save char
        txa
        clc
        adc #32                 ; cols 32-36
        tay
        lda dsf_ch
        sta (dp_lo),y
        inx
        cpx #5
        bne dsf_blk_write

dsf_done:

        rts

dsf_blo:        byte 0
dsf_bhi:        byte 0
dsf_ch:         byte 0
dsf_lead:       byte 0
dsf_blkstr:     ds 5, 0 ; 5-digit decimal as PET screen codes

; dsf_format_blocks: convert 16-bit dsf_blo/dsf_bhi to 5 PET screen-code digits
; Screen codes $30-$39 = digits '0'-'9', so ora #$30 converts value 0-9 to screen code.

dsf_format_blocks:

        ; 10000 = $2710

        ldy #0

dsf_10k:

        lda dsf_blo
        sec
        sbc #$10
        sta dsf_tmp
        lda dsf_bhi
        sbc #$27
        bcc dsf_10k_done
        sta dsf_bhi
        lda dsf_tmp
        sta dsf_blo
        iny
        jmp dsf_10k

dsf_10k_done:

        tya
        ora #$30
        sta dsf_blkstr

        ; 1000 = $03E8

        ldy #0

dsf_1k:

        lda dsf_blo
        sec
        sbc #$E8
        sta dsf_tmp
        lda dsf_bhi
        sbc #$03
        bcc dsf_1k_done
        sta dsf_bhi
        lda dsf_tmp
        sta dsf_blo
        iny
        jmp dsf_1k

dsf_1k_done:

        tya
        ora #$30
        sta dsf_blkstr+1

        ; 100 = $0064

        ldy #0

dsf_100:

        lda dsf_blo
        sec
        sbc #100
        sta dsf_tmp
        lda dsf_bhi
        sbc #0
        bcc dsf_100_done
        sta dsf_bhi
        lda dsf_tmp
        sta dsf_blo
        iny
        jmp dsf_100

dsf_100_done:

        tya
        ora #$30
        sta dsf_blkstr+2

        ; 10 = $0A

        ldy #0

dsf_10:

        lda dsf_blo
        sec
        sbc #10
        sta dsf_tmp
        lda dsf_bhi
        sbc #0
        bcc dsf_10_done
        sta dsf_bhi
        lda dsf_tmp
        sta dsf_blo
        iny
        jmp dsf_10

dsf_10_done:

        tya
        ora #$30
        sta dsf_blkstr+3

        ; 1

        lda dsf_blo
        ora #$30
        sta dsf_blkstr+4
        rts

dsf_tmp:        byte 0

; =========================================================
; clear_status: clear status message and redraw status line
; =========================================================

clear_status:

        lda #0
        sta status_msg
        jsr draw_status_line
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
        jsr draw_status_line
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
        jsr draw_panel_header
        jsr draw_panel_rows
        rts

; =========================================================
; draw_panel_header: render drive number + disk title on row 2
; =========================================================

draw_panel_header:

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

        ; Clear the inner cols

        ldy #0
        lda #SC_SPACE

dp_hclr:

        sta (dp_lo),y
        iny
        cpy #PANEL_INNER
        bne dp_hclr

        ; "8:" (drive number + colon, no space after)

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

        ; Disk title: copy 16 chars starting at col 2

        ldx #0

dp_titcp:

        cpx #16
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
        adc #2
        tay
        lda dp_tit_a
        sta (dp_lo),y
        inx
        jmp dp_titcp

dp_titcp_done:

        rts

; =========================================================
; draw_panel_rows: render PANEL_ROWS file rows (rows 3..22)
; =========================================================

draw_panel_rows:

        ; ---- File rows: screen rows 4 .. 4+PANEL_ROWS-1 ----

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
        adc #4
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

        ; clear inner cols

        ldy #0
        lda #SC_SPACE

dp_clr:

        sta (dp_lo),y
        iny
        cpy #PANEL_INNER
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
        cpy #PANEL_INNER
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
;   0..14 : filename (up to 15 chars, left-aligned)
;   15..17: block count (right-aligned decimal)
;
; The entry record address is computed into sp_lo; (sp_lo),y reads bytes:
;   y=0 blocks_lo, y=1 blocks_hi, y=2 type, y=3..18 name (16 max)
; (dp_lo),y writes to screen.
; =========================================================

draw_entry:

        ; sp = entries_pN + cur_absidx * 20

        jsr panel_entry_sp

        ; ---- Filename: cols 0..14 (15 chars, left-aligned) ----

        ldx #0
        ldy #3                  ; record offset

de_name:

        cpx #15
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
        tay
        lda de_ch
        sta (dp_lo),y
        ldy de_yrec
        iny
        inx
        jmp de_name

de_name_done:

        ; ---- Block count right-aligned at cols 15..17 ----

        ldy #0
        lda (sp_lo),y
        sta num_lo
        iny
        lda (sp_lo),y
        sta num_hi
        jsr print_num3_right    ; writes right-aligned into cols 15..17

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
; print_num3_right: same as print_num3 but writes at cols 15..17
; =========================================================

print_num3_right:

        ; hundreds digit

        lda #0
        sta pn_dig

pnr_h:

        lda num_lo
        sec
        sbc #100
        sta pn_tmp_lo
        lda num_hi
        sbc #0
        bcc pnr_h_done
        sta num_hi
        lda pn_tmp_lo
        sta num_lo
        inc pn_dig
        jmp pnr_h

pnr_h_done:

        lda pn_dig
        bne pnr_h_show
        lda #SC_SPACE
        jmp pnr_h_put

pnr_h_show:

        clc
        adc #CH_0
        jsr petscii_to_screen

pnr_h_put:

        ldy #15
        sta (dp_lo),y

        ; tens digit

        lda #0
        sta pn_dig

pnr_t:

        lda num_lo
        sec
        sbc #10
        bcc pnr_t_done
        sta num_lo
        inc pn_dig
        jmp pnr_t

pnr_t_done:

        lda pn_dig
        bne pnr_t_show
        ldy #15
        lda (dp_lo),y
        cmp #SC_SPACE
        bne pnr_t_zero
        lda #SC_SPACE
        jmp pnr_t_put

pnr_t_zero:

        lda #0
        clc
        adc #CH_0
        jsr petscii_to_screen
        jmp pnr_t_put

pnr_t_show:

        clc
        adc #CH_0
        jsr petscii_to_screen

pnr_t_put:

        ldy #16
        sta (dp_lo),y

        ; ones digit

        lda num_lo
        clc
        adc #CH_0
        jsr petscii_to_screen
        ldy #17
        sta (dp_lo),y
        rts

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
; ascii_to_screen: A in ASCII -> A in screen code
; Depends on view_charset (0=UPPER, 1=LOWER).
; Used only in viewer text mode when view_charset_mode=1.
; =========================================================

ascii_to_screen:

        cmp #$20
        bcc a2s_dot             ; $00-$1F non-printable
        cmp #$7F
        beq a2s_dot             ; $7F DEL
        cmp #$80
        bcs a2s_dot             ; $80-$FF non-printable

        ; $20-$7E printable ASCII

        cmp #$41
        bcc a2s_petscii         ; $20-$40 -> petscii_to_screen
        cmp #$5B
        bcc a2s_upper_az        ; $41-$5A A-Z
        cmp #$61
        bcc a2s_petscii         ; $5B-$60 -> petscii_to_screen
        cmp #$7B
        bcc a2s_lower_az        ; $61-$7A a-z

        ; $7B-$7E -> petscii_to_screen

a2s_petscii:

        jmp petscii_to_screen

a2s_upper_az:

        ; A-Z: UPPER -> -$40 ($01-$1A); LOWER -> identity ($41-$5A)

        pha                     ; save byte
        lda view_charset
        bne a2s_ua_lower
        pla                     ; restore byte
        sec
        sbc #$40
        rts

a2s_ua_lower:

        pla                     ; restore byte (identity)
        rts

a2s_lower_az:

        ; a-z: LOWER -> -$60 ($01-$1A); UPPER -> -$60 then ORA #$80

        pha                     ; save byte
        lda view_charset
        bne a2s_la_lower
        pla                     ; restore byte
        sec
        sbc #$60
        ora #$80                ; inverse-video uppercase
        rts

a2s_la_lower:

        pla                     ; restore byte
        sec
        sbc #$60
        rts

a2s_dot:

        lda #SC_DOT
        rts

; =========================================================
; row_addr_sp: X = screen row (0..24); sets sp_lo/sp_hi to col-0 addr
; Base is BUFFER (the back buffer), not SCREEN. All sp-based drawing
; composes off-screen; present_screen blits BUFFER to SCREEN.
; =========================================================

row_addr_sp:

        lda #<BUFFER
        sta sp_lo
        lda #>BUFFER
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
; panel_entry_sp: sp_lo/sp_hi = entries_pN + cur_absidx * 20
; Uses cur_panel to select table, cur_absidx as index.
; =========================================================

panel_entry_sp:

        lda cur_panel
        bne pes_p1
        lda #<entries_p0
        sta sp_lo
        lda #>entries_p0
        sta sp_hi
        jmp pes_add

pes_p1:

        lda #<entries_p1
        sta sp_lo
        lda #>entries_p1
        sta sp_hi

pes_add:

        lda cur_absidx
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
; entry_record_sp: sp_lo/sp_hi = entries_pN + p_count[N]*20
; =========================================================

entry_record_sp:

        ldx cur_panel
        lda p_count,x
        sta cur_absidx
        jmp panel_entry_sp

; =========================================================
; selected_entry_sp: sp_lo/sp_hi -> active panel's selected entry
; Returns C=1 if panel is empty.
; =========================================================

selected_entry_sp:

        lda active_panel
        sta cur_panel
        ldx cur_panel
        lda p_count,x
        beq ses_empty
        lda p_sel,x
        sta cur_absidx
        jsr panel_entry_sp
        clc
        rts

ses_empty:

        sec
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
        jsr redraw_panels
        rts

op_del_cancel:

        jmp op_cancel

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
        jsr redraw_panels
        rts

op_ren_cancel:

        jmp op_cancel

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
        jsr redraw_panels
        rts

op_cp_cancel:

        jmp op_cancel

msg_copy_to:            byte "COPY TO",0

; =========================================================
; op_cancel: shared cancel cleanup for file operations
; =========================================================

op_cancel:

        jsr clear_status
        jsr redraw_panels
        rts

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
        jsr draw_status_line
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
        jsr present_screen
        lda #0
        sta prompt_len

pt_loop:

        jsr show_prompt_buf
        jsr present_screen
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

        sta BUFFER+24*40,x
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
        sta BUFFER+24*40,x
        iny
        inx
        cpx #16
        bne dpl_loop

dpl_done:

        ; Append ": "

        lda #CH_COLON
        jsr petscii_to_screen
        sta BUFFER+24*40,x
        inx
        lda #SC_SPACE
        sta BUFFER+24*40,x
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
        sta BUFFER+24*40,y
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
        sta BUFFER+24*40,y
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
        jsr present_screen

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
; Present / blit: double-buffered screen update
; All drawing composes into BUFFER; present_screen waits for
; VBLANK and copies BUFFER to SCREEN in one atomic pass.
; copy_buffer is the only writer of SCREEN.
; =========================================================

; ---- wait_vblank: bounded two-phase VBLANK sync via VIA PB5 ----
; PB5 is LOW during VBLANK, HIGH during active display.
; Phase 1 skips any remaining VBLANK (wait for HIGH); phase 2 waits
; for the next VBLANK start (wait for LOW). Both phases are bounded
; so the routine never hangs if the retrace bit is not toggling
; (e.g. under emulators that do not mirror VBLANK onto VIA PB5).
; On real hardware it returns at the start of VBLANK. Clobbers A, X.

wait_vblank:

        ldx #$00

wv_p1:

        lda VIA_PORTB
        and #RETRACE_BIT
        bne wv_p2               ; bit HIGH: VBLANK ended -> phase 2
        dex
        bne wv_p1
        rts                     ; phase 1 bound exhausted: give up (no sync)

wv_p2:

        ldx #$00

wv_p2_loop:

        lda VIA_PORTB
        and #RETRACE_BIT
        beq wv_done             ; bit LOW: VBLANK started
        dex
        bne wv_p2_loop
        rts                     ; phase 2 bound exhausted: give up (no sync)

wv_done:

        rts                     ; at start of VBLANK

; ---- copy_buffer: copy 1000 bytes BUFFER -> SCREEN ----
; Page-strided: 3 full pages (768 bytes) + 232-byte tail.
; Clobbers A and X.

copy_buffer:

        ldx #0

cb_loop:

        lda BUFFER,x            ; $7C00-$7CFF -> $8000-$80FF
        sta SCREEN,x
        lda BUFFER+$100,x       ; $7D00-$7DFF -> $8100-$81FF
        sta SCREEN+$100,x
        lda BUFFER+$200,x       ; $7E00-$7EFF -> $8200-$82FF
        sta SCREEN+$200,x
        inx
        bne cb_loop             ; 768 bytes done (3 pages)

        ldx #$E8                ; remaining 232 bytes: $7F00-$7FE7 -> $8300-$83E7

cb_tail:

        dex
        lda BUFFER+$300,x       ; x = 231..0, reads $7FE7..$7F00
        sta SCREEN+$300,x       ; writes $83E7..$8300
        txa                     ; test X, not the loaded byte
        bne cb_tail             ; 232 bytes done, total = 1000
        rts

; ---- present_screen: wait for VBLANK, then blit BUFFER -> SCREEN ----
; Called at the end of every redraw entry point and after each
; interactive row-24 update. Clobbers A and X.

present_screen:

        jsr wait_vblank
        jsr view_flush_pcr      ; apply staged PCR charset during VBLANK
        jsr copy_buffer
        rts

; flush_keys: drain all pending keys from the keyboard buffer.
; Called after menu close to remove auto-repeat keys before the
; main loop resumes.

flush_keys:

        jsr GETIN
        bne flush_keys
        rts

; =========================================================
; Viewer: modal file viewer with text and hex display
; Opens the selected file, loads chunks into view_chunk,
; renders text or hex, scrolls, and restores panels on close.
; =========================================================

; nibble_to_sc: A = nibble (0-15) -> A = screen code for hex digit

nibble_to_sc:

        cmp #10
        bcc nts_digit
        sbc #9                  ; carry set: A = nibble - 9 (10->1='A', 15->6='F')
        rts

nts_digit:

        clc
        adc #$30                ; 0-9 -> $30-$39
        rts

; ---- write_hex_byte: write 2 hex screen codes at (sp_lo),Y ----
; Input:  A = byte, sp_lo/sp_hi = screen row, Y = column
; Output: Y advanced by 2

write_hex_byte:

        sta whb_tmp
        lsr
        lsr
        lsr
        lsr
        jsr nibble_to_sc
        sta (sp_lo),y
        iny
        lda whb_tmp
        and #$0F
        jsr nibble_to_sc
        sta (sp_lo),y
        iny
        rts

; ---- view_calc_valid: bytes available in current row ----
; Returns A = min(view_chunk_len - vr_bufcur, view_row_size), 0 if past EOF

view_calc_valid:

        lda vr_bufcur+1
        cmp view_chunk_len+1
        bcc vcv_calc
        bne vcv_zero
        lda vr_bufcur
        cmp view_chunk_len
        bcc vcv_calc

vcv_zero:

        lda #0
        rts

vcv_calc:

        sec
        lda view_chunk_len
        sbc vr_bufcur
        sta vcv_tmp
        lda view_chunk_len+1
        sbc vr_bufcur+1
        bne vcv_clamp           ; high byte nonzero -> > 255 -> clamp
        lda vcv_tmp
        cmp view_row_size
        bcc vcv_done

vcv_clamp:

        lda view_row_size

vcv_done:

        rts

; =========================================================
; op_info: show file information window
; =========================================================

op_info:

        jsr selected_entry_sp
        bcs oi_done             ; empty panel

        ; Save the entry pointer; draw_info_window clobbers sp_lo/sp_hi

        lda sp_lo
        sta diw_entry_lo
        lda sp_hi
        sta diw_entry_hi

        ; Draw a simple info window over the screen

        jsr draw_info_window

        ; Wait for any key

        jsr wait_any_key

        ; Restore panels

        jsr full_redraw

oi_done:

        rts

; draw_info_window: draw a bordered window with file details

draw_info_window:

        ; Draw a window from row 8 to row 16, cols 5 to 34 (30 cols, 9 rows)
        ; Top border

        ldx #8
        jsr row_addr_sp
        ldy #5
        lda #BOX_TL
        sta (sp_lo),y
        lda #BOX_H
        ldy #6

diw_top:

        sta (sp_lo),y
        iny
        cpy #34
        bne diw_top
        ldy #34
        lda #BOX_TR
        sta (sp_lo),y

        ; Sides and content for rows 9-15

        ldx #9

diw_mid:

        stx diw_row
        jsr row_addr_sp
        ldy #5
        lda #BOX_V
        sta (sp_lo),y
        ldy #34
        lda #BOX_V
        sta (sp_lo),y

        ; Clear interior

        ldy #6
        lda #SC_SPACE

diw_clr:

        sta (sp_lo),y
        iny
        cpy #34
        bne diw_clr
        ldx diw_row
        inx
        cpx #16
        bne diw_mid

        ; Bottom border

        ldx #16
        jsr row_addr_sp
        ldy #5
        lda #BOX_BL
        sta (sp_lo),y
        lda #BOX_H
        ldy #6

diw_bot:

        sta (sp_lo),y
        iny
        cpy #34
        bne diw_bot
        ldy #34
        lda #BOX_BR
        sta (sp_lo),y

        ; Write title "FILE INFORMATION" at row 9, col 7

        ldx #9
        jsr row_addr_sp
        ldy #7
        lda #$06                ; 'F'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$0C                ; 'L'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$06                ; 'F'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$0D                ; 'M'
        sta (sp_lo),y
        iny
        lda #$01                ; 'A'
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y

        ; Row 11: filename (16 chars max, PETSCII -> screen code)

        ldx #11
        jsr diw_set_row
        ldx #0

diw_name_loop:

        cpx #16
        bcs diw_name_done
        txa
        clc
        adc #3                  ; record offset = 3 + name_index
        tay
        lda (sp_lo),y
        beq diw_name_pad
        cmp #$22                ; skip quote
        beq diw_name_pad
        cmp #$A0                ; skip shifted-space
        beq diw_name_pad
        jsr petscii_to_screen
        jmp diw_name_store

diw_name_pad:

        lda #SC_SPACE

diw_name_store:

        pha                     ; save screen char
        lda diw_scr_lo
        sta sp_lo
        lda diw_scr_hi
        sta sp_hi
        txa
        clc
        adc #7
        tay
        pla
        sta (sp_lo),y
        lda diw_entry_lo
        sta sp_lo
        lda diw_entry_hi
        sta sp_hi
        inx
        jmp diw_name_loop

diw_name_done:

        ; Row 12: type

        ldx #12
        jsr diw_set_row
        ldy #7
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$19                ; 'Y'
        sta (sp_lo),y
        iny
        lda #$10                ; 'P'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$3A                ; ':'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda diw_entry_lo
        sta sp_lo
        lda diw_entry_hi
        sta sp_hi
        ldy #2
        lda (sp_lo),y
        pha
        lda diw_scr_lo
        sta sp_lo
        lda diw_scr_hi
        sta sp_hi
        pla
        ldy #13
        sta (sp_lo),y

        ; Row 13: blocks

        ldx #13
        jsr diw_set_row
        ldy #7
        lda #$02                ; 'B'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$03                ; 'C'
        sta (sp_lo),y
        iny
        lda #$0B                ; 'K'
        sta (sp_lo),y
        iny
        lda #$13                ; 'S'
        sta (sp_lo),y
        iny
        lda #$3A                ; ':'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda diw_entry_lo
        sta sp_lo
        lda diw_entry_hi
        sta sp_hi
        ldy #0
        lda (sp_lo),y
        sta dsf_blo
        iny
        lda (sp_lo),y
        sta dsf_bhi
        jsr dsf_format_blocks
        lda diw_scr_lo
        sta sp_lo
        lda diw_scr_hi
        sta sp_hi
        ldy #14
        ldx #0
        lda #0
        sta diw_lead

diw_blk_loop:

        cpx #5
        bcs diw_blk_done
        lda dsf_blkstr,x
        cmp #$30                ; '0'
        bne diw_blk_nz
        lda diw_lead
        bne diw_blk_nz
        lda #SC_SPACE
        jmp diw_blk_store

diw_blk_nz:

        lda #1
        sta diw_lead
        lda dsf_blkstr,x

diw_blk_store:

        sta (sp_lo),y
        iny
        inx
        jmp diw_blk_loop

diw_blk_done:

        ; Row 14: drive

        ldx #14
        jsr diw_set_row
        ldy #7
        lda #$04                ; 'D'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$16                ; 'V'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$3A                ; ':'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda active_panel
        tax
        lda p_drive,x
        clc
        adc #CH_0
        jsr petscii_to_screen
        ldy #14
        sta (sp_lo),y

        ; Row 15: bytes = blocks * 254

        ldx #15
        jsr diw_set_row
        ldy #7
        lda #$02                ; 'B'
        sta (sp_lo),y
        iny
        lda #$19                ; 'Y'
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$13                ; 'S'
        sta (sp_lo),y
        iny
        lda #$3A                ; ':'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny

        ; Compute bytes = blocks * 254 (low 16 bits are enough for 2031)
        lda diw_entry_lo
        sta sp_lo
        lda diw_entry_hi
        sta sp_hi
        ldy #0
        lda (sp_lo),y
        sta dsf_blo
        iny
        lda (sp_lo),y
        sta dsf_bhi
        jsr diw_mul254
        lda diw_bytes_lo
        sta dsf_blo
        lda diw_bytes_mid
        sta dsf_bhi
        jsr dsf_format_blocks
        lda diw_scr_lo
        sta sp_lo
        lda diw_scr_hi
        sta sp_hi
        ldy #14
        ldx #0
        lda #0
        sta diw_lead

diw_bytes_loop:

        cpx #5
        bcs diw_bytes_done
        lda dsf_blkstr,x
        cmp #$30                ; '0'
        bne diw_bytes_nz
        lda diw_lead
        bne diw_bytes_nz
        lda #SC_SPACE
        jmp diw_bytes_store

diw_bytes_nz:

        lda #1
        sta diw_lead
        lda dsf_blkstr,x

diw_bytes_store:

        sta (sp_lo),y
        iny
        inx
        jmp diw_bytes_loop

diw_bytes_done:

        jsr present_screen
        rts

; diw_set_row: set sp to screen row X (cols 5-34) and save in diw_scr

diw_set_row:

        jsr row_addr_sp
        lda sp_lo
        sta diw_scr_lo
        lda sp_hi
        sta diw_scr_hi
        rts

diw_row:        byte 0
diw_entry_lo:   byte 0
diw_entry_hi:   byte 0
diw_scr_lo:     byte 0
diw_scr_hi:     byte 0
diw_lead:       byte 0
diw_bytes_lo:   byte 0
diw_bytes_mid:  byte 0
diw_bytes_hi:   byte 0

; diw_mul254: multiply dsf_blo/dsf_bhi by 254, result in diw_bytes_lo/mid/hi

diw_mul254:

        ; blocks * 2
        lda dsf_blo
        asl
        sta diw_bytes_lo        ; low byte of blocks*2
        lda dsf_bhi
        rol
        sta diw_bytes_mid       ; mid byte of blocks*2
        lda #0
        rol
        sta diw_bytes_hi        ; high byte of blocks*2

        ; result = blocks*256 - blocks*2
        sec
        lda #0
        sbc diw_bytes_lo
        sta diw_bytes_lo
        lda dsf_blo
        sbc diw_bytes_mid
        sta diw_bytes_mid
        lda dsf_bhi
        sbc diw_bytes_hi
        sta diw_bytes_hi
        rts

; =========================================================
; op_about: show about window
; =========================================================

op_about:

        ; Clear menu selection so the menu bar is redrawn with no active title
        ; while the ABOUT modal is displayed.
        lda #0
        sta menu_active
        jsr draw_menu_bar
        jsr draw_about_window
        jsr wait_any_key
        jsr full_redraw
        rts

; draw_about_window: bordered window with program info
; Window: rows 5-20, cols 5-34, with inner vertical bars at cols 8 and 31.

ABOUT_TOP       = 5
ABOUT_BOT       = 20
ABOUT_LEFT      = 5
ABOUT_RIGHT     = 34
ABOUT_INNER_L   = 8
ABOUT_INNER_R   = 31

draw_about_window:

        ; Draw top border

        ldx #ABOUT_TOP
        jsr row_addr_sp
        ldy #ABOUT_LEFT
        lda #BOX_TL
        sta (sp_lo),y
        lda #BOX_H
        ldy #ABOUT_LEFT+1

daw_top:

        sta (sp_lo),y
        iny
        cpy #ABOUT_RIGHT
        bne daw_top
        ldy #ABOUT_RIGHT
        lda #BOX_TR
        sta (sp_lo),y

        ; Draw side borders and clear interior for rows 6..19

        ldx #ABOUT_TOP+1

daw_mid:

        stx daw_row
        jsr row_addr_sp
        ldy #ABOUT_LEFT
        lda #BOX_V
        sta (sp_lo),y
        ldy #ABOUT_RIGHT
        lda #BOX_V
        sta (sp_lo),y

        ; Clear interior

        ldy #ABOUT_LEFT+1
        lda #SC_SPACE

daw_clr:

        sta (sp_lo),y
        iny
        cpy #ABOUT_RIGHT
        bne daw_clr

        ldx daw_row
        inx
        cpx #ABOUT_BOT
        bne daw_mid

        ; Draw bottom border

        ldx #ABOUT_BOT
        jsr row_addr_sp
        ldy #ABOUT_LEFT
        lda #BOX_BL
        sta (sp_lo),y
        lda #BOX_H
        ldy #ABOUT_LEFT+1

daw_bot:

        sta (sp_lo),y
        iny
        cpy #ABOUT_RIGHT
        bne daw_bot
        ldy #ABOUT_RIGHT
        lda #BOX_BR
        sta (sp_lo),y

        ; Draw inner vertical bars at cols 8 and 31 on rows 6..19.
        ; Use $60 (decorative half-block).  Skip bars on rows that the
        ; layout example leaves clear (row 12 both, row 11/14 left only).

        ldx #ABOUT_TOP+1

daw_bars:

        stx daw_row
        cpx #12
        beq daw_next_row        ; row 12: no inner bars
        jsr row_addr_sp
        ldy #ABOUT_INNER_R
        lda #$60
        sta (sp_lo),y
        ldx daw_row
        cpx #11
        beq daw_next_row        ; row 11: keep only right bar
        cpx #14
        beq daw_next_row        ; row 14: keep only right bar
        ldy #ABOUT_INNER_L
        sta (sp_lo),y

daw_next_row:

        ldx daw_row
        inx
        cpx #ABOUT_BOT
        bne daw_bars

        ; Row 7 (absolute): "PET COMMANDER" at cols 13-25

        ldx #7
        jsr row_addr_sp
        ldy #13
        lda #$10                ; 'P'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda #$03                ; 'C'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$0D                ; 'M'
        sta (sp_lo),y
        iny
        lda #$0D                ; 'M'
        sta (sp_lo),y
        iny
        lda #$01                ; 'A'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$04                ; 'D'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y

        ; Row 8 (absolute): 6-character decorative underline at cols 12-17

        ldx #8
        jsr row_addr_sp
        ldy #12
        lda #$60
        sta (sp_lo),y
        iny
        sta (sp_lo),y
        iny
        sta (sp_lo),y
        iny
        sta (sp_lo),y
        iny
        sta (sp_lo),y
        iny
        sta (sp_lo),y

        ; Row 10 (absolute): "VERSION: 0.3" at cols 14-25

        ldx #10
        jsr row_addr_sp
        ldy #14
        lda #$16                ; 'V'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$13                ; 'S'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$3A                ; ':'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda #$30                ; '0'
        sta (sp_lo),y
        iny
        lda #$2E                ; '.'
        sta (sp_lo),y
        iny
        lda #$33                ; '3'
        sta (sp_lo),y

        ; Row 13 (absolute): "BROUGHT TO YOU BY ZOLTAR X" at cols 7-32
        ; This spans the full width, so it overwrites the inner bars.

        ldx #13
        jsr row_addr_sp
        ldy #7
        lda #$02                ; 'B'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$15                ; 'U'
        sta (sp_lo),y
        iny
        lda #$07                ; 'G'
        sta (sp_lo),y
        iny
        lda #$08                ; 'H'
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$20                ; ' '
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$20                ; ' '
        sta (sp_lo),y
        iny
        lda #$19                ; 'Y'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$15                ; 'U'
        sta (sp_lo),y
        iny
        lda #$20                ; ' '
        sta (sp_lo),y
        iny
        lda #$02                ; 'B'
        sta (sp_lo),y
        iny
        lda #$19                ; 'Y'
        sta (sp_lo),y
        iny
        lda #$20                ; ' '
        sta (sp_lo),y
        iny
        lda #$1A                ; 'Z'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$0C                ; 'L'
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$01                ; 'A'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$20                ; ' '
        sta (sp_lo),y
        iny
        lda #$18                ; 'X'
        sta (sp_lo),y

        ; Row 14 (absolute): short separator at cols 19-20

        ldx #14
        jsr row_addr_sp
        ldy #19
        lda #$60
        sta (sp_lo),y
        iny
        sta (sp_lo),y

        ; Row 15 (absolute): "NEW GENERATION" at cols 13-26

        ldx #15
        jsr row_addr_sp
        ldy #13
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$17                ; 'W'
        sta (sp_lo),y
        iny
        lda #$20                ; ' '
        sta (sp_lo),y
        iny
        lda #$07                ; 'G'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$01                ; 'A'
        sta (sp_lo),y
        iny
        lda #$14                ; 'T'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$0F                ; 'O'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y

        ; Row 18 (absolute): "OK" button at cols 17-21
        ; Layout: $60 decorative half-block, $E1 reversed left half-block,
        ; 'O' reversed, 'K' reversed, $61 left half-block.

        ldx #18
        jsr row_addr_sp
        ldy #17
        lda #$60
        sta (sp_lo),y
        iny
        lda #HB_RLEFT           ; $E1 reversed left half-block
        sta (sp_lo),y
        iny
        lda #$8F                ; 'O' reversed
        sta (sp_lo),y
        iny
        lda #$8B                ; 'K' reversed
        sta (sp_lo),y
        iny
        lda #HB_LEFT            ; $61 left half-block
        sta (sp_lo),y

        jsr present_screen
        rts

daw_row:        byte 0

; =========================================================
; op_change: change drive window
; =========================================================

op_change:

        jsr draw_change_window

        ; Read a 1-2 digit drive number

        ldx #0                  ; digit count

oc_input:

        jsr GETIN
        beq oc_input
        cmp #K_RETURN
        beq oc_commit
        cmp #K_STOP
        beq oc_cancel
        cmp #CH_0
        bcc oc_input
        cmp #$3A                ; past '9'
        bcs oc_input

        ; Store digit

        sta oc_digits,x
        inx
        cpx #2
        bcs oc_input            ; max 2 digits

        ; Echo digit on screen (simple)

        jmp oc_input

oc_commit:

        ; Convert digits to drive number

        cpx #0
        beq oc_cancel           ; no digits entered

        ; Single digit

        lda oc_digits
        sec
        sbc #CH_0
        sta oc_drive
        cpx #2
        bne oc_set_drive

        ; Two digits: first * 10 + second

        lda oc_digits
        sec
        sbc #CH_0
        sta oc_tmp
        asl
        asl
        clc
        adc oc_tmp              ; *5
        asl                     ; *10
        sta oc_tmp
        lda oc_digits+1
        sec
        sbc #CH_0
        clc
        adc oc_tmp
        sta oc_drive

oc_set_drive:

        ; Validate: drive 8-11

        cmp #8
        bcc oc_cancel
        cmp #12
        bcs oc_cancel

        ; Set the active panel's drive

        ldx active_panel
        sta p_drive,x

        ; Reload the panel

        lda active_panel
        jsr load_panel
        jsr full_redraw
        rts

oc_cancel:

        jsr full_redraw
        rts

; draw_change_window: bordered window with drive prompt

draw_change_window:

        ldx #10
        jsr row_addr_sp
        ldy #8
        lda #BOX_TL
        sta (sp_lo),y
        lda #BOX_H
        ldy #9

dcw_top:

        sta (sp_lo),y
        iny
        cpy #31
        bne dcw_top
        ldy #31
        lda #BOX_TR
        sta (sp_lo),y
        ldx #11

dcw_mid:

        stx dcw_row
        jsr row_addr_sp
        ldy #8
        lda #BOX_V
        sta (sp_lo),y
        ldy #31
        lda #BOX_V
        sta (sp_lo),y
        ldy #9
        lda #SC_SPACE

dcw_clr:

        sta (sp_lo),y
        iny
        cpy #31
        bne dcw_clr
        ldx dcw_row
        inx
        cpx #14
        bne dcw_mid
        ldx #14
        jsr row_addr_sp
        ldy #8
        lda #BOX_BL
        sta (sp_lo),y
        lda #BOX_H
        ldy #9

dcw_bot:

        sta (sp_lo),y
        iny
        cpy #31
        bne dcw_bot
        ldy #31
        lda #BOX_BR
        sta (sp_lo),y

        ; Write "CHANGE DRIVE" at row 11, col 10

        ldx #11
        jsr row_addr_sp
        ldy #10
        lda #$03                ; 'C'
        sta (sp_lo),y
        iny
        lda #$08                ; 'H'
        sta (sp_lo),y
        iny
        lda #$01                ; 'A'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$06                ; 'G'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        iny
        lda #$04                ; 'D'
        sta (sp_lo),y
        iny
        lda #$12                ; 'R'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$16                ; 'V'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y

        ; Write "NEW: " at row 12, col 12

        ldx #12
        jsr row_addr_sp
        ldy #12
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$05                ; 'E'
        sta (sp_lo),y
        iny
        lda #$17                ; 'W'
        sta (sp_lo),y
        iny
        lda #CH_COLON
        jsr petscii_to_screen
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        jsr present_screen
        rts

dcw_row:        byte 0
oc_digits:      byte 0, 0
oc_drive:       byte 0
oc_tmp:         byte 0

; =========================================================
; op_find: find/search filter
; =========================================================

op_find:

        ; Draw a FIND: prompt on the status line

        ldx #24
        jsr row_addr_sp
        ldy #1
        lda #$06                ; 'F'
        sta (sp_lo),y
        iny
        lda #$09                ; 'I'
        sta (sp_lo),y
        iny
        lda #$0E                ; 'N'
        sta (sp_lo),y
        iny
        lda #$04                ; 'D'
        sta (sp_lo),y
        iny
        lda #CH_COLON
        jsr petscii_to_screen
        sta (sp_lo),y
        iny
        lda #SC_SPACE
        sta (sp_lo),y
        jsr present_screen

        ; Read search string (up to 16 chars)

        ldx #0

of_input:

        jsr GETIN
        beq of_input
        cmp #K_RETURN
        beq of_commit
        cmp #K_STOP
        beq of_cancel
        cmp #K_DEL
        bne of_char

        ; Backspace

        cpx #0
        beq of_input
        dex
        jmp of_input

of_char:

        cpx #16
        bcs of_input
        sta of_buf,x
        inx
        jmp of_input

of_commit:

        ; If empty string, clear filter

        cpx #0
        bne of_set_filter

        ; Clear filter

        ldx active_panel
        lda #0
        sta p_filter,x
        sta p_filter_len,x
        jsr full_redraw
        rts

of_set_filter:

        ; Copy search string to p_filter_str for active panel

        stx of_len
        ldy #0

of_copy:

        cpy of_len
        bcs of_copy_done
        lda of_buf,y
        ldx active_panel
        beq of_cp_p0

        ; Panel 1: offset 16

        sta p_filter_str+16,y
        jmp of_cp_next

of_cp_p0:

        sta p_filter_str,y

of_cp_next:

        iny
        jmp of_copy

of_copy_done:

        ldx active_panel
        lda of_len
        sta p_filter_len,x
        lda #1
        sta p_filter,x
        jsr full_redraw
        rts

of_cancel:

        jsr full_redraw
        rts

of_buf:         ds 16, 0
of_len:         byte 0

; =========================================================
; wait_any_key: block until any key is pressed
; =========================================================

wait_any_key:

        jsr GETIN
        beq wait_any_key
        rts

; =========================================================
; op_view: open the viewer on the selected file
; =========================================================

op_view:

        jsr selected_entry_sp
        bcs ov_exit             ; empty panel
        jsr copy_name_to_savename
        jsr view_copy_fname

        ; Init per-open viewer state (modes persist across opens)

        lda #0
        sta view_top
        sta view_top+1
        sta view_chunk_base
        sta view_chunk_base+1
        sta view_at_eof
        sta view_pcr_pending            ; no staged PCR write at open
        jsr view_set_mode_params        ; reads persisted view_mode
        jsr view_load_chunk
        bcs ov_exit                     ; open failed, status already set
        jsr view_apply_charset          ; save PCR charset, switch to view_charset
        jsr view_loop
        jsr view_restore_charset        ; restore PCR charset -> uppercase
        jsr full_redraw                 ; restore panels

ov_exit:

        rts

; ---- view_copy_fname: copy savename -> view_fname ----

view_copy_fname:

        ldx #0

vcf_loop:

        cpx savename_len
        bcs vcf_done
        lda savename,x
        sta view_fname,x
        inx
        jmp vcf_loop

vcf_done:

        stx view_fname_len
        rts

; ---- view_set_mode_params: set view_row_size and view_screen_size ----

view_set_mode_params:

        lda view_mode
        beq vsm_text

        ; Hex mode: row=8, screen=21*8=168, page=21*8=168 (no overlap)

        lda #VIEW_HEX_COLS
        sta view_row_size
        lda #<(VIEW_ROWS*VIEW_HEX_COLS)
        sta view_screen_size
        lda #>(VIEW_ROWS*VIEW_HEX_COLS)
        sta view_screen_size+1
        lda #<(VIEW_ROWS*VIEW_HEX_COLS)
        sta view_page_size
        lda #>(VIEW_ROWS*VIEW_HEX_COLS)
        sta view_page_size+1
        rts

vsm_text:

        ; Text mode: row=38, screen=21*38=798, page=20*38=760 (1-line overlap)

        lda #VIEW_TEXT_COLS
        sta view_row_size
        lda #<(VIEW_ROWS*VIEW_TEXT_COLS)
        sta view_screen_size
        lda #>(VIEW_ROWS*VIEW_TEXT_COLS)
        sta view_screen_size+1
        lda #<((VIEW_ROWS-1)*VIEW_TEXT_COLS)
        sta view_page_size
        lda #>((VIEW_ROWS-1)*VIEW_TEXT_COLS)
        sta view_page_size+1
        rts

; ---- view_set_pcr_charset: stage view_charset into PCR bits 3:1 ----
; Sets view_char_offset ($00 UPPER, $40 LOWER) immediately so label
; rendering into BUFFER composes with the correct screen codes.
; Stages the PCR write (view_pending_pcr_cs + view_pcr_pending) instead
; of writing PCR directly; view_flush_pcr applies it during VBLANK so
; the charset change and the content blit share one VBLANK window.

view_set_pcr_charset:

        ldx view_charset
        beq vspc_upper
        lda #PCR_L              ; LOWER bits to stage
        ldx #$40
        bne vspc_store

vspc_upper:

        lda #PCR_U              ; UPPER bits to stage
        ldx #$00

vspc_store:

        sta view_pending_pcr_cs ; stage the PCR write (do not touch PCR yet)
        stx view_char_offset    ; set offset now for label rendering
        lda #$ff
        sta view_pcr_pending    ; mark a write as pending
        rts

; ---- view_flush_pcr: apply staged PCR charset write during VBLANK ----
; No-op when view_pcr_pending is clear (all main-program present calls).
; Read-modify-write preserves CB2 (IEEE-488 NDAC). Called by present_screen
; between wait_vblank and copy_buffer.

view_flush_pcr:

        lda view_pcr_pending
        beq vfp_done
        lda PCR
        and #$F1                ; clear bits 3:1
        ora view_pending_pcr_cs ; apply staged bits
        sta PCR
        lda #0
        sta view_pcr_pending

vfp_done:

        rts

; ---- view_apply_charset: save PCR bits 3:1, then switch ----
; Called after view_load_chunk succeeds in op_view.

view_apply_charset:

        lda PCR
        and #$0E                ; isolate bits 3:1
        sta saved_pcr_cs
        jsr view_set_pcr_charset
        rts

; ---- view_restore_charset: stage restore of saved PCR bits 3:1 ----
; Called after view_loop returns in op_view, before full_redraw.
; Stages the restore; full_redraw's present_screen flushes it during
; VBLANK so the viewer frame and the panel restore appear together.

view_restore_charset:

        lda saved_pcr_cs
        sta view_pending_pcr_cs ; stage the restore
        lda #$ff
        sta view_pcr_pending
        rts

; =========================================================
; view_load_chunk: open file, skip to view_chunk_base, read chunk, close
; Returns C=1 on open failure (status set), C=0 on success.
; =========================================================

view_load_chunk:

        jsr restore_zp
        jsr CLALL
        lda view_fname_len
        ldx #<view_fname
        ldy #>view_fname
        jsr pet_setnam
        ldx active_panel
        lda p_drive,x
        sta cur_drive
        lda #VIEW_LFN
        ldx cur_drive
        ldy #0                  ; SA=0 (read)
        jsr pet_setlfs
        jsr restore_zp
        jsr pet_open
        bcc vlc_opened
        jmp vlc_err

vlc_opened:

        jsr restore_zp
        ldx #VIEW_LFN
        jsr CHKIN

        ; Skip view_chunk_base bytes

        lda view_chunk_base
        sta vlc_skl
        lda view_chunk_base+1
        sta vlc_skh

vlc_skip:

        lda vlc_skl
        ora vlc_skh
        beq vlc_read_init
        jsr CHRIN
        lda STATUS
        bne vlc_read_init       ; EOF during skip
        lda vlc_skl
        bne vlc_skip_dec
        dec vlc_skh

vlc_skip_dec:

        dec vlc_skl
        jmp vlc_skip

vlc_read_init:

        lda #0
        sta view_chunk_len
        sta view_chunk_len+1
        sta view_at_eof
        lda #<view_chunk
        sta sp_lo
        lda #>view_chunk
        sta sp_hi
        ldy #0

vlc_read:

        lda view_chunk_len+1
        cmp #>VIEW_CHUNK
        bcc vlc_read_byte
        bne vlc_done
        lda view_chunk_len
        cmp #<VIEW_CHUNK
        bcs vlc_done

vlc_read_byte:

        jsr CHRIN
        sta (sp_lo),y
        inc view_chunk_len
        bne vlc_chk
        inc view_chunk_len+1

vlc_chk:

        lda STATUS
        bne vlc_eof
        iny
        bne vlc_read
        inc sp_hi
        jmp vlc_read

vlc_eof:

        lda #1
        sta view_at_eof

vlc_done:

        jsr restore_zp
        jsr CLRCHN
        lda #VIEW_LFN
        jsr pet_close
        clc
        rts

vlc_err:

        lda #<msg_view_err
        ldy #>msg_view_err
        jsr set_status
        jsr present_screen      ; show VIEW OPEN FAILED (no redraw follows)
        sec
        rts

; =========================================================
; view_render: clear screen, draw header, frame, content, footer
; =========================================================

view_render:

        jsr clear_screen

        ; --- Header bar (row 0) ---

        jsr view_draw_header

        ; --- Content frame (rows 1, 2-22, 23) ---

        jsr view_draw_frame

        ; --- Content rows (rows 2-22) ---

        lda view_mode
        bne vr_hex_mode
        jsr view_render_text
        jmp vr_footer

vr_hex_mode:

        jsr view_render_hex

vr_footer:

        ; --- Footer bar (row 24) ---

        jsr view_draw_footer

vr_done:

        jsr present_screen
        rts

; =========================================================
; view_draw_footer: draw footer bar (row 24) from view_footer_base
; Letter positions (base & $7F in $01-$1A) get view_char_offset
; so labels stay uppercase in either character set.
; =========================================================

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

; =========================================================
; view_draw_header: draw reverse-video header on row 0
; Layout: $E1 | reversed content (38 cols) | $61
; Content: "  VIEW  filename<pad>  MODE  "
; =========================================================

view_draw_header:

        ldx #0
        jsr row_addr_sp

        ; Left border

        ldy #0
        lda #HB_RLEFT
        sta (sp_lo),y

        ; Right border

        ldy #39
        lda #HB_LEFT
        sta (sp_lo),y

        ; Fill cols 1-38 with reversed space ($A0)

        ldy #1
        lda #$A0

vdh_fill:

        sta (sp_lo),y
        iny
        cpy #39
        bne vdh_fill

        ; Write "VIEW" at cols 3-6 (reversed screen codes)
        ; Label letters get view_char_offset so they stay uppercase in LOWER

        ldy #3
        lda #$96                ; 'V' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$89                ; 'I' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$85                ; 'E' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$97                ; 'W' reversed
        ora view_char_offset
        sta (sp_lo),y

        ; Write filename at cols 9.. (reversed)

        ldy #9
        ldx #0

vdh_fn:

        cpx view_fname_len
        bcs vdh_mode
        lda view_fname,x
        jsr petscii_to_screen
        ora #$80                ; reverse
        sta (sp_lo),y
        iny
        inx
        jmp vdh_fn

vdh_mode:

        ; Write mode right-aligned ending at col 35
        ; TEXT = 4 chars -> cols 32-35; HEX = 3 chars -> cols 33-35

        lda view_mode
        bne vdh_hex

        ; Text mode: "TEXT" reversed at cols 32-35

        ldy #32
        lda #$94                ; 'T' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$85                ; 'E' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$98                ; 'X' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$94                ; 'T' reversed
        ora view_char_offset
        sta (sp_lo),y
        rts

vdh_hex:

        ; Hex mode: "HEX" reversed at cols 33-35

        ldy #33
        lda #$88                ; 'H' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$85                ; 'E' reversed
        ora view_char_offset
        sta (sp_lo),y
        iny
        lda #$98                ; 'X' reversed
        ora view_char_offset
        sta (sp_lo),y
        rts

; =========================================================
; view_draw_frame: draw content frame borders
; Hex mode: T-junctions at cols 5, 17, 29, 34
; Text mode: plain borders (no internal dividers)
; =========================================================

view_draw_frame:

        ; --- Top border (row 1) ---

        ldx #1
        jsr row_addr_sp
        ldy #0
        lda #BOX_TL
        sta (sp_lo),y
        ldy #39
        lda #BOX_TR
        sta (sp_lo),y

        ; Fill horizontal line cols 1-38

        ldy #1
        lda #BOX_H

vdf_top_fill:

        sta (sp_lo),y
        iny
        cpy #39
        bne vdf_top_fill

        ; Hex mode: place T-junctions on top border

        lda view_mode
        beq vdf_top_done
        ldy #5
        lda #BOX_TJD
        sta (sp_lo),y
        ldy #17
        sta (sp_lo),y
        ldy #29
        sta (sp_lo),y
        ldy #34
        lda #BOX_TJU
        sta (sp_lo),y

vdf_top_done:

        ; --- Bottom border (row 23) ---

        ldx #23
        jsr row_addr_sp
        ldy #0
        lda #BOX_BL
        sta (sp_lo),y
        ldy #39
        lda #BOX_BR
        sta (sp_lo),y
        ldy #1
        lda #BOX_H

vdf_bot_fill:

        sta (sp_lo),y
        iny
        cpy #39
        bne vdf_bot_fill
        lda view_mode
        beq vdf_bot_done
        ldy #5
        lda #BOX_TJU
        sta (sp_lo),y
        ldy #17
        sta (sp_lo),y
        ldy #29
        sta (sp_lo),y
        ldy #34
        sta (sp_lo),y

vdf_bot_done:

        ; --- Side borders and dividers (rows 2-22) ---

        ldx #2

vdf_sides:

        stx vdf_row
        jsr row_addr_sp
        ldy #0
        lda #BOX_V
        sta (sp_lo),y
        ldy #39
        sta (sp_lo),y

        ; Hex mode: internal dividers at cols 5, 17, 29, 34

        lda view_mode
        beq vdf_sides_next
        ldy #5
        lda #BOX_V
        sta (sp_lo),y
        ldy #17
        sta (sp_lo),y
        ldy #29
        sta (sp_lo),y
        ldy #34
        sta (sp_lo),y

vdf_sides_next:

        ldx vdf_row
        inx
        cpx #23
        bne vdf_sides
        rts

vdf_row:         byte 0

; =========================================================
; view_render_text: render VIEW_ROWS rows of text (rows 2..22)
; Content fills cols 1-38 (inside frame borders at 0 and 39)
; =========================================================

view_render_text:

        ; dp = view_chunk + (view_top - view_chunk_base)

        sec
        lda view_top
        sbc view_chunk_base
        sta vr_off
        lda view_top+1
        sbc view_chunk_base+1
        sta vr_off+1
        lda #<view_chunk
        clc
        adc vr_off
        sta dp_lo
        lda #>view_chunk
        adc vr_off+1
        sta dp_hi
        lda vr_off
        sta vr_bufcur
        lda vr_off+1
        sta vr_bufcur+1
        ldx #2

vrt_row:

        stx vr_rownum
        jsr row_addr_sp
        jsr view_calc_valid
        sta vr_valid

        ; Write data at cols 1..38
        ; Y indexes data in chunk buffer, vr_col tracks screen column

        lda #1
        sta vr_col
        ldy #0

vrt_data_loop:

        cpy vr_valid
        bcs vrt_pad
        sty vr_ytmp             ; save data index
        lda view_charset_mode
        bne vrt_ascii           ; ASCII render: translate

        ; SCREEN render: store raw byte as screen code (no conversion)

        lda (dp_lo),y
        jmp vrt_data_store

vrt_ascii:

        lda (dp_lo),y
        jsr ascii_to_screen

vrt_data_store:

        ldy vr_col
        sta (sp_lo),y
        inc vr_col
        ldy vr_ytmp             ; restore data index
        iny
        cpy #VIEW_TEXT_COLS
        bcc vrt_data_loop

vrt_pad:

        lda #SC_SPACE
        ldy vr_col

vrt_pad_loop:

        cpy #39
        bcs vrt_row_done
        sta (sp_lo),y
        iny
        jmp vrt_pad_loop

vrt_row_done:

        lda dp_lo
        clc
        adc #VIEW_TEXT_COLS
        sta dp_lo
        lda dp_hi
        adc #0
        sta dp_hi
        lda vr_bufcur
        clc
        adc #VIEW_TEXT_COLS
        sta vr_bufcur
        lda vr_bufcur+1
        adc #0
        sta vr_bufcur+1
        ldx vr_rownum
        inx
        cpx #(2+VIEW_ROWS)
        bne vrt_row
        rts

; =========================================================
; view_render_hex: render VIEW_ROWS rows of hex (rows 2..22)
; Row format: |ADDR|HH HH HH HH|HH HH HH HH|AAAA|AAAA|
;   col 0: border, cols 1-4: address, col 5: divider,
;   cols 6-16: hex group 1, col 17: divider,
;   cols 18-28: hex group 2, col 29: divider,
;   cols 30-33: ASCII group 1 (raw screen codes), col 34: divider,
;   cols 35-38: ASCII group 2 (raw screen codes), col 39: border
; =========================================================

view_render_hex:

        sec
        lda view_top
        sbc view_chunk_base
        sta vr_off
        lda view_top+1
        sbc view_chunk_base+1
        sta vr_off+1
        lda #<view_chunk
        clc
        adc vr_off
        sta dp_lo
        lda #>view_chunk
        adc vr_off+1
        sta dp_hi
        lda vr_off
        sta vr_bufcur
        lda vr_off+1
        sta vr_bufcur+1
        lda view_top
        sta vr_fileoff
        lda view_top+1
        sta vr_fileoff+1
        ldx #2

vrh_row:

        stx vr_rownum
        jsr row_addr_sp

        ; --- Address (4 hex digits at cols 1-4) ---

        ldy #1
        lda vr_fileoff+1
        jsr write_hex_byte
        lda vr_fileoff
        jsr write_hex_byte

        ; --- Valid bytes in this row ---

        jsr view_calc_valid
        sta vr_valid

        ; --- Hex group 1 (cols 6-16): 4 bytes as HH HH HH HH ---

        ldy #6
        ldx #0

vrh_hex1_loop:

        cpx #0
        beq vrh_hex1_first
        lda #SC_SPACE
        sta (sp_lo),y
        iny

vrh_hex1_first:

        cpx vr_valid
        bcs vrh_hex1_pad
        sty vr_ytmp
        txa
        tay
        lda (dp_lo),y
        ldy vr_ytmp
        jsr write_hex_byte
        jmp vrh_hex1_next

vrh_hex1_pad:

        lda #SC_SPACE
        sta (sp_lo),y
        iny
        sta (sp_lo),y
        iny

vrh_hex1_next:

        inx
        cpx #4
        bne vrh_hex1_loop

        ; --- Hex group 2 (cols 18-28): 4 bytes as HH HH HH HH ---

        ldy #18
        ldx #0

vrh_hex2_loop:

        cpx #0
        beq vrh_hex2_first
        lda #SC_SPACE
        sta (sp_lo),y
        iny

vrh_hex2_first:

        cpx vr_valid
        bcs vrh_hex2_pad
        sty vr_ytmp
        txa
        tay
        lda (dp_lo),y
        ldy vr_ytmp
        jsr write_hex_byte
        jmp vrh_hex2_next

vrh_hex2_pad:

        lda #SC_SPACE
        sta (sp_lo),y
        iny
        sta (sp_lo),y
        iny

vrh_hex2_next:

        inx
        cpx #4
        bne vrh_hex2_loop

        ; --- ASCII group 1 (cols 30-33): 4 raw bytes as screen codes ---

        ldy #30
        ldx #0

vrh_ascii1_loop:

        cpx vr_valid
        bcs vrh_ascii1_pad
        sty vr_ytmp
        txa
        tay
        lda (dp_lo),y
        ldy vr_ytmp
        sta (sp_lo),y           ; raw screen code, no conversion
        jmp vrh_ascii1_next

vrh_ascii1_pad:

        lda #SC_SPACE
        sta (sp_lo),y

vrh_ascii1_next:

        iny
        inx
        cpx #4
        bne vrh_ascii1_loop

        ; --- ASCII group 2 (cols 35-38): 4 raw bytes as screen codes ---

        ldy #35
        ldx #0

vrh_ascii2_loop:

        cpx vr_valid
        bcs vrh_ascii2_pad
        sty vr_ytmp
        txa
        tay
        lda (dp_lo),y
        ldy vr_ytmp
        sta (sp_lo),y           ; raw screen code, no conversion
        jmp vrh_ascii2_next

vrh_ascii2_pad:

        lda #SC_SPACE
        sta (sp_lo),y

vrh_ascii2_next:

        iny
        inx
        cpx #4
        bne vrh_ascii2_loop

        ; --- Advance for next row ---

        lda dp_lo
        clc
        adc #VIEW_HEX_COLS
        sta dp_lo
        lda dp_hi
        adc #0
        sta dp_hi
        lda vr_bufcur
        clc
        adc #VIEW_HEX_COLS
        sta vr_bufcur
        lda vr_bufcur+1
        adc #0
        sta vr_bufcur+1
        lda vr_fileoff
        clc
        adc #VIEW_HEX_COLS
        sta vr_fileoff
        lda vr_fileoff+1
        adc #0
        sta vr_fileoff+1
        ldx vr_rownum
        inx
        cpx #(2+VIEW_ROWS)
        beq vrh_done
        jmp vrh_row

vrh_done:

        rts

; =========================================================
; view_loop: render, read keys, dispatch
; =========================================================

view_loop:

        jsr view_render

vl_wait:

        jsr GETIN
        beq vl_wait
        cmp #CH_H
        beq vl_hex
        cmp #CH_T
        beq vl_text
        cmp #CH_A
        beq vl_ascii
        cmp #CH_S
        beq vl_screen
        cmp #CH_L
        beq vl_lower
        cmp #CH_U
        beq vl_upper
        cmp #K_UP
        beq vl_up
        cmp #K_DOWN
        beq vl_down
        cmp #K_LEFT
        beq vl_pgup
        cmp #K_RIGHT
        beq vl_pgdn
        cmp #K_HOME
        beq vl_home
        cmp #CH_E
        beq vl_quit
        cmp #K_STOP
        beq vl_quit
        jmp vl_wait

vl_hex:

        lda #1
        sta view_mode
        jsr view_set_mode_params
        jmp view_loop

vl_text:

        lda #0
        sta view_mode
        jsr view_set_mode_params
        jmp view_loop

vl_ascii:

        lda #1
        sta view_charset_mode
        jmp view_loop

vl_screen:

        lda #0
        sta view_charset_mode
        jmp view_loop

vl_lower:

        lda #1
        sta view_charset
        jsr view_set_pcr_charset
        jmp view_loop

vl_upper:

        lda #0
        sta view_charset
        jsr view_set_pcr_charset
        jmp view_loop

vl_up:

        jsr view_scroll_up
        jmp view_loop

vl_down:

        jsr view_scroll_down
        jmp view_loop

vl_pgup:

        jsr view_page_up
        jmp view_loop

vl_pgdn:

        jsr view_page_down
        jmp view_loop

vl_home:

        jsr view_home
        jmp view_loop

vl_quit:

        rts

; =========================================================
; view_scroll_down: advance view_top by one row, reload if needed
; =========================================================

view_scroll_down:

        clc
        lda view_top
        adc view_row_size
        sta view_top
        lda view_top+1
        adc #0
        sta view_top+1

        ; Check if view_top + screen_size > chunk_base + chunk_len

        clc
        lda view_top
        adc view_screen_size
        sta vsd_end_lo
        lda view_top+1
        adc view_screen_size+1
        sta vsd_end_hi
        clc
        lda view_chunk_base
        adc view_chunk_len
        sta vsd_chunkend_lo
        lda view_chunk_base+1
        adc view_chunk_len+1
        sta vsd_chunkend_hi
        lda vsd_end_hi
        cmp vsd_chunkend_hi
        bcc vsd_done
        bne vsd_need_reload
        lda vsd_end_lo
        cmp vsd_chunkend_lo
        bcc vsd_done
        lda view_at_eof
        bne vsd_clamp

vsd_need_reload:

        jsr view_reload_at_top
        rts

vsd_clamp:

        sec
        lda view_top
        sbc view_row_size
        sta view_top
        lda view_top+1
        sbc #0
        sta view_top+1

vsd_done:

        rts

; =========================================================
; view_scroll_up: retreat view_top by one row, reload if needed
; =========================================================

view_scroll_up:

        lda view_top
        ora view_top+1
        beq vsu_done
        sec
        lda view_top
        sbc view_row_size
        sta view_top
        lda view_top+1
        sbc #0
        sta view_top+1
        lda view_top+1
        cmp view_chunk_base+1
        bcc vsu_reload
        bne vsu_done
        lda view_top
        cmp view_chunk_base
        bcc vsu_reload
        rts

vsu_reload:

        jsr view_reload_at_top

vsu_done:

        rts

; =========================================================
; view_home: jump to start of file
; =========================================================

view_home:

        lda #0
        sta view_top
        sta view_top+1
        sta view_chunk_base
        sta view_chunk_base+1
        jsr view_load_chunk
        rts

; =========================================================
; view_reload_at_top: view_chunk_base = view_top; reload chunk
; Shared reload tail for the scroll handlers that move view_top
; past the current chunk. Clobbers A and X (via view_load_chunk).
; =========================================================

view_reload_at_top:

        lda view_top
        sta view_chunk_base
        lda view_top+1
        sta view_chunk_base+1
        jsr view_load_chunk
        rts

; =========================================================
; view_page_down: advance view_top by view_page_size, reload if needed
; =========================================================

view_page_down:

        clc
        lda view_top
        adc view_page_size
        sta view_top
        lda view_top+1
        adc view_page_size+1
        sta view_top+1

        ; Check if view_top + screen_size > chunk_base + chunk_len

        clc
        lda view_top
        adc view_screen_size
        sta vpd_end_lo
        lda view_top+1
        adc view_screen_size+1
        sta vpd_end_hi
        clc
        lda view_chunk_base
        adc view_chunk_len
        sta vpd_chunkend_lo
        lda view_chunk_base+1
        adc view_chunk_len+1
        sta vpd_chunkend_hi
        lda vpd_end_hi
        cmp vpd_chunkend_hi
        bcc vpd_done
        bne vpd_need_reload
        lda vpd_end_lo
        cmp vpd_chunkend_lo
        bcc vpd_done
        lda view_at_eof
        bne vpd_clamp

vpd_need_reload:

        jsr view_reload_at_top
        rts

vpd_clamp:

        sec
        lda view_top
        sbc view_page_size
        sta view_top
        lda view_top+1
        sbc #0
        sta view_top+1

vpd_done:

        rts

; =========================================================
; view_page_up: retreat view_top by view_page_size, reload if needed
; =========================================================

view_page_up:

        lda view_top
        ora view_top+1
        beq vpu_done
        sec
        lda view_top
        sbc view_page_size
        sta view_top
        lda view_top+1
        sbc view_page_size+1
        sta view_top+1
        bcs vpu_check

        ; Underflow: clamp to 0

        lda #0
        sta view_top
        sta view_top+1

vpu_check:

        lda view_top+1
        cmp view_chunk_base+1
        bcc vpu_reload
        bne vpu_done
        lda view_top
        cmp view_chunk_base
        bcc vpu_reload
        rts

vpu_reload:

        jsr view_reload_at_top

vpu_done:

        rts

; =========================================================
; Viewer state and buffers
; =========================================================

view_mode:       byte 0                 ; 0=text, 1=hex (persisted across opens)
view_charset_mode: byte 0               ; 0=SCREEN (raw), 1=ASCII (translate) (persisted)
view_charset:    byte 0                 ; 0=UPPER, 1=LOWER (persisted)
view_char_offset: byte 0                ; $00 UPPER, $40 LOWER; ORed into label letters
saved_pcr_cs:    byte 0                 ; PCR bits 3:1 saved on viewer entry
view_pcr_pending: byte 0                ; nonzero = a PCR charset write is staged
view_pending_pcr_cs: byte 0             ; staged PCR bits 3:1 to OR into PCR on flush
view_top:        word 0                 ; byte offset of visible top
view_chunk_base: word 0                 ; byte offset of chunk start
view_chunk_len:  word 0                 ; bytes loaded in chunk
view_at_eof:     byte 0                 ; nonzero if last read hit EOF
view_row_size:   byte 0                 ; bytes per row (38 or 8)
view_screen_size: word 0                ; bytes per screen (798 or 168)
view_page_size:  word 0                 ; bytes per page (760 text, 168 hex)
view_fname:      ds 16, 0               ; filename being viewed
view_fname_len:  byte 0
view_chunk:      ds VIEW_CHUNK, 0       ; chunk buffer

; Viewer temporaries

vr_off:          word 0
vr_bufcur:       word 0
vr_valid:        byte 0
vr_rownum:       byte 0
vr_fileoff:      word 0
vr_ytmp:         byte 0
vr_col:          byte 0
vlc_skl:         byte 0
vlc_skh:         byte 0
vsd_end_lo:      byte 0
vsd_end_hi:      byte 0
vsd_chunkend_lo: byte 0
vsd_chunkend_hi: byte 0
vpd_end_lo:      byte 0
vpd_end_hi:      byte 0
vpd_chunkend_lo: byte 0
vpd_chunkend_hi: byte 0
vcv_tmp:         byte 0
whb_tmp:         byte 0

; Viewer strings
; Footer bar (row 24): 40 base screen codes (uppercase-set form).
; view_draw_footer applies view_char_offset to letter positions
; (base & $7F in $01-$1A) so labels stay uppercase in LOWER.
; $E1=HB_RLEFT border, $61=HB_LEFT border.
; Layout: T(ext) H(ex) A(scii) S(creen) L(ower) U(pper) E(xit)

view_footer_base:

        byte $E1                        ; col 0: left border
        byte $14                        ; col 1: 'T' normal
        byte $85,$98,$94                ; cols 2-4: 'EXT' reversed
        byte $A0                        ; col 5: reversed space
        byte $08                        ; col 6: 'H' normal
        byte $85,$98                    ; cols 7-8: 'EX' reversed
        byte $A0                        ; col 9: reversed space
        byte $01                        ; col 10: 'A' normal
        byte $93,$83,$89,$89            ; cols 11-14: 'SCII' reversed
        byte $A0                        ; col 15: reversed space
        byte $13                        ; col 16: 'S' normal
        byte $83,$92,$85,$85,$8E        ; cols 17-21: 'CREEN' reversed
        byte $A0                        ; col 22: reversed space
        byte $0C                        ; col 23: 'L' normal
        byte $8F,$97,$85,$92            ; cols 24-27: 'OWER' reversed
        byte $A0                        ; col 28: reversed space
        byte $15                        ; col 29: 'U' normal
        byte $90,$90,$85,$92            ; cols 30-33: 'PPER' reversed
        byte $A0                        ; col 34: reversed space
        byte $05                        ; col 35: 'E' normal
        byte $98,$89,$94                ; cols 36-38: 'XIT' reversed
        byte $61                        ; col 39: right border
msg_view_err:      byte "VIEW OPEN FAILED",0

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

