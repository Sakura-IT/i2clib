;==========================================================================
; Hardware specifics of the "Microtext" tuner/teletext I²C bus interface,
; to be included in "i2c.library.s"
;==========================================================================

    NOLIST
    INCLUDE "resources/misc.i"
    INCLUDE "hardware/cia.i"
    LIST

; These are not in "cia.i" (too bad):
CIAAPRB     = $BFE101
CIAADDRB    = $BFE301

; What I/O lines do we use?
; SCL out: Centronics bit #0
; SDA out: Centronics bit #1 \_ will have to keep switching
; SDA in:  Centronics bit #1 /  the data direction bit

INITPORT MACRO
    move.b #$FF,CIAADDRB        ; all lines in output mode
    move.b #$BF,CIAAPRB         ; seems to be required for Microtext
    ENDM
ALLOCPERCALL MACRO
    ENDM
RELEASEPERCALL MACRO
    ENDM

PREP4MACROS MACRO
    lea CIAAPRB,a0              ; for SCL and SDAin
    lea CIAADDRB,a1             ; for toggling SDA
    ENDM
SCLH MACRO
    bset #0,(a0)
    ENDM
SCLL MACRO
    bclr #0,(a0)
    ENDM
SDAH MACRO
    bclr #1,(a1)                ; bit 1 as an input -> HI
    ENDM
SDAL MACRO
    bclr #1,(a0)
    bset #1,(a1)                ; bit 1 as an output -> LO
    ENDM
SDAtest MACRO
    btst #1,(a0)
    ENDM
IDLEREAD MACRO
    tst.b (a0)
    ENDM

; Allocate parallel or serial port?
MYBITS = MR_PARALLELBITS
MYPORT = MR_PARALLELPORT
HW_TYPE = 0

; this will become the 2nd half of the Version String:
IDPART2 MACRO
    dc.b ' for parallel interface (Microtext)',13,10,0
    ENDM

