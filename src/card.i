;==========================================================================
; Some macro definitions to be included in "i2c.library.card.s", 
; NOT in "i2c.library.s"!
;==========================================================================

; a CIA address, needed for the delay loops:
CIABPRA = $BFD000

; What I/O lines do we use?
; SCL out: bit1 \_ in the word (!) at the
; SDA out: bit0 /  base address of our board
; SDA in:  bit0  of the same address

INITPORT MACRO
    move.l myConfigDev(a6),a1
    move.l cd_BoardAddr(a1),a1
    move.w #3,(a1)
    ENDM
ALLOCPERCALL MACRO
    ENDM
RELEASEPERCALL MACRO
    ENDM

PREP4MACROS MACRO
    lea CIABPRA,a0
    move.l myConfigDev(a5),a1
    move.l cd_BoardAddr(a1),a1
    moveq #3,d7
    ENDM
SCLH MACRO
    bset #1,d7
    move.w d7,(a1)
    ENDM
SCLL MACRO
    bclr #1,d7
    move.w d7,(a1)
    ENDM
SDAH MACRO
    bset #0,d7
    move.w d7,(a1)
    ENDM
SDAL MACRO
    bclr #0,d7
    move.w d7,(a1)
    ENDM
SDAtest MACRO
    btst #0,1(a1)
    ENDM
IDLEREAD MACRO
    tst.b (a0)
    ENDM

; identify the board we use:
VENDOR  = $5757
PRODUCT =   $89
    
; this will become the 2nd half of the Version String:
IDPART2 MACRO
    dc.b ' for Zorro boards (M&T TeleTxt)',13,10,0
    ENDM

