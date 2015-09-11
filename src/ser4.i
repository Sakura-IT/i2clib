;==========================================================================
; Hardware specifics of the KDT SatCom I²C bus interface,
; to be included in "i2c.library.s"
;==========================================================================

    NOLIST
    INCLUDE "resources/misc.i"
    INCLUDE "hardware/cia.i"
    LIST

; These are not in "cia.i" (too bad):
CIABPRA     = $BFD000
CIABDDRA    = $BFD200

; What I/O lines do we use?
; SDA out: DTR inverted
; SDA in:  DCD \_
; SCL out: RTS / non-inverted

INITPORT MACRO
    lea CIABDDRA,a0             ; init the DDR bits
    bset #CIAB_COMRTS,(a0)
    bset #CIAB_COMDTR,(a0)
    bclr #CIAB_COMCD,(a0)
    lea CIABPRA,a0              ; make SDA and SCL HI
    bset #CIAB_COMRTS,(a0)
    bclr #CIAB_COMDTR,(a0)
    ENDM
ALLOCPERCALL MACRO
    ENDM
RELEASEPERCALL MACRO
    ENDM

PREP4MACROS MACRO
    lea CIABPRA,a0
    ENDM
SCLH MACRO
    bset #CIAB_COMRTS,(a0)
    ENDM
SCLL MACRO
    bclr #CIAB_COMRTS,(a0)
    ENDM
SDAH MACRO
    bclr #CIAB_COMDTR,(a0)
    ENDM
SDAL MACRO
    bset #CIAB_COMDTR,(a0)
    ENDM
SDAtest MACRO
    btst #CIAB_COMCD,(a0)
    ENDM
IDLEREAD MACRO
    tst.b (a0)
    ENDM

; Allocate parallel or serial port?
MYBITS = MR_SERIALBITS
MYPORT = MR_SERIALPORT
HW_TYPE = 1

; this will become the 2nd half of the Version String:
IDPART2 MACRO
    dc.b " for serial interface (KDK SatCom)",13,10,0
    ENDM
    
