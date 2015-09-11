;==========================================================================
; Some macro definitions to be included in "i2c.library.disk.s",
; NOT in "i2c.library.s"!
;==========================================================================

    NOLIST
    INCLUDE "resources/disk.i"
    INCLUDE "hardware/cia.i"
    LIST

; These are not in "cia.i" (too bad):
CIAAPRA     = $BFE001
CIAADDRA    = $BFE201
CIABPRB     = $BFD100
CIABDDRB    = $BFD300

; What I/O lines do we use?
; SCL out: STEP \
; SDA out: DIR   } all inverted
; SDA in:  TRK0 /

; The following macro is the main part of the public InitI2C function.
; It will also be called once for every new client and during
; BringBackI2C.
; Hmm... This seems like a bad place to do any initialization: We're
; not protected by the semaphore here and might corrupt someone else's
; I/O operation. :-(
; Register usage: Can expect I2C_Base in A6 and may use D0/D1/A0/A1 as
; scratch registers.
INITPORT MACRO
    lea CIABPRB,a0
    move.b #$FF,(a0)
    bclr #CIAB_DSKDIREC,(a0)
    bclr #CIAB_DSKSTEP,(a0)
    move.l UnitNo(a6),d0
    addq.l #CIAB_DSKSEL0,d0
    bclr d0,(a0)
    ENDM
ALLOCPERCALL MACRO
    bsr GrabTheDisk                 ; allocate the floppy port
    move.l d0,d3
    bne AbortIO
    exg a5,a6
    bsr ForceInit                   ; calls INITPORT
    exg a5,a6
    ENDM
RELEASEPERCALL MACRO
    move.l UnitNo(a5),d0            ; release the select line
    addq.l #CIAB_DSKSEL0,d0
    bset d0,(a0)
    move.l DiskBase(a5),a6          ; return the floppy port
    jsr DR_GIVEUNIT(a6)
    ENDM

PREP4MACROS MACRO
    lea CIABPRB,a0
    lea CIAAPRA,a1
    move.b (a0),d7
    ENDM
SCLH MACRO
    bclr #CIAB_DSKSTEP,d7
    move.b d7,(a0)
    ENDM
SCLL MACRO
    bset #CIAB_DSKSTEP,d7
    move.b d7,(a0)
    ENDM
SDAH MACRO
    bclr #CIAB_DSKDIREC,d7
    move.b d7,(a0)
    ENDM
SDAL MACRO
    bset #CIAB_DSKDIREC,d7
    move.b d7,(a0)
    ENDM
SDAtest MACRO
    btst #CIAB_DSKTRACK0,(a1)
    seq d4          ; invert the Z flag
    tst.b d4
    ENDM
IDLEREAD MACRO
    tst.b (a0)
    ENDM

; this will become the 2nd half of the Version String:
IDPART2 MACRO
    dc.b ' fake disk device',13,10,0
    ENDM

