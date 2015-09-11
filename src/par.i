;==========================================================================
; Hardware specifics of J.L.'s I²C bus interface,
; to be included in "i2c.library.s"
;==========================================================================

    NOLIST
    INCLUDE "resources/misc.i"
    INCLUDE "hardware/cia.i"
    LIST

; These are not in "cia.i" (too bad):
CIAAPRB     = $BFE101
CIAADDRB    = $BFE301
CIABPRA     = $BFD000
CIABDDRA    = $BFD200

; What I/O lines do we use?
; SDA out: Data2 inverted
; SDA in:  POUT  \_
; SCL out: SEL   / non-inverted

INITPORT MACRO
    lea CIABDDRA,a0             ; init the DDR bits
    bset #CIAB_PRTRSEL,(a0)
    bclr #CIAB_PRTRPOUT,(a0)
    bset #2,CIAADDRB
    bclr #2,CIAAPRB             ; make SDA and SCL HI
    bset #CIAB_PRTRSEL,CIABPRA
    ENDM
ALLOCPERCALL MACRO
    ENDM
RELEASEPERCALL MACRO
    ENDM

PREP4MACROS MACRO
    lea CIABPRA,a0
    lea CIAAPRB,a1
    ENDM
SCLH MACRO
    bset #CIAB_PRTRSEL,(a0)
    ENDM
SCLL MACRO
    bclr #CIAB_PRTRSEL,(a0)
    ENDM
SDAH MACRO
    bclr #2,(a1)
    ENDM
SDAL MACRO
    bset #2,(a1)
    ENDM
SDAtest MACRO
    btst #CIAB_PRTRPOUT,(a0)
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
    dc.b ' for parallel interface (J.L.)',13,10,0
    ENDM

