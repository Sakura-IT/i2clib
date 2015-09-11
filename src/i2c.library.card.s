;==========================================================================
; i2c.library.card.s -- run-time library for accessing I²C-bus hardware on
; the M&T TeleTxt Zorro Board.
; Based on "i2c.library.s", but is a little simpler indeed, as it need
; not do any hardware allocation, just has to find its board address.
;==========================================================================

    INCLUDE "card.i"
VERSION = 40
REVISION = 0
IDPART1 MACRO   ; IDPART2 is defined in the hw. specific includes
    dc.b 'i2c.library 40.0 (24 Aug 98)'
    ENDM

;==========================================================================
; Some definitions that will appear in the #?.h-file, too.
;--------------------------------------------------------------------------
; Allocation Errors:
I2C_OK         = 0
I2C_PORT_BUSY  = 1
I2C_BITS_BUSY  = 2
I2C_NO_MISC_RESOURCE = 3
I2C_ERROR_PORT = 4
I2C_ACTIVE     = 5
I2C_NO_TIMER   = 6
;--------------------------------------------------------------------------
; I/O Errors:
;I2C_OK        = 0
I2C_REJECT     = 1
I2C_NO_REPLY   = 2
SDA_TRASHED    = 3
SDA_LO         = 4
SDA_HI         = 5
SCL_TIMEOUT    = 6
SCL_HI         = 7
I2C_HARDW_BUSY = 8
;--------------------------------------------------------------------------
FALSE          = 0
;==========================================================================

    NOLIST
    INCLUDE "exec/types.i"
    INCLUDE "exec/initializers.i"
    INCLUDE "exec/libraries.i"
    INCLUDE "exec/lists.i"
    INCLUDE "exec/alerts.i"
    INCLUDE "exec/semaphores.i"
    INCLUDE "exec/resident.i"
    INCLUDE "libraries/configvars.i"
    LIST

; library offsets in Exec:
Alert               = -108
Forbid              = -132
Permit              = -138
FreeMem             = -210
Remove              = -252
OpenLibrary         = -552
CloseLibrary        = -414
InitSemaphore       = -558
ObtainSemaphore     = -564
ReleaseSemaphore    = -570
; ... in DOS:
StrToLong           = -816
GetVar              = -906
; ... and in expansion.lib:
FindConfigDev       =  -72


;==========================================================================
;                 *** Object generation starts here ***
;==========================================================================

    SECTION code

;==========================================================================
Start:
;--------------------------------------------------------------------------
; Do nothing if run as a program (we ARE a load module, but a library!):
;--------------------------------------------------------------------------
    moveq #10,d0                    ; remember, moveq is always ".l"
    rts

; A romtag structure, both "exec" and "ramlib" look for this.
RomTag:
    dc.w RTC_MATCHWORD  ; UWORD RT_MATCHWORD
    dc.l RomTag         ; APTR  RT_MATCHTAG
    dc.l EndCode        ; APTR  RT_ENDSKIP
    dc.b RTF_AUTOINIT   ; UBYTE RT_FLAGS
    dc.b VERSION        ; UBYTE RT_VERSION
    dc.b NT_LIBRARY     ; UBYTE RT_TYPE
    dc.b 0              ; BYTE  RT_PRI
    dc.l LibName        ; APTR  RT_NAME
    dc.l IDString       ; APTR  RT_IDSTRING
    dc.l InitTable      ; APTR  RT_INIT  table for InitResident()

    ; The romtag specified that we were "RTF_AUTOINIT". This means that the
    ; RT_INIT structure member points to one of these tables below.
    ; If the AUTOINIT bit was not set then RT_INIT would point to a routine
    ; to run.

    ; Marker EndCode must not be before RomTag in memory, nor span sections.
    ; Right after the rom tag is OK and always safe:
EndCode:

LibName:  dc.b 'i2c.library',0
IDString:
    IDPART1
    IDPART2
    even                ; force word alignment

InitTable:
    dc.l I2CLib_SIZE    ; size of library base data space
    dc.l funcTable      ; pointer to function initializers
    dc.l dataTable      ; pointer to data initializers
    dc.l initRoutine    ; routine to run

funcTable:
    ;------ standard system routines
    dc.l Open
    dc.l Close
    dc.l Expunge
    dc.l Null
    ;------ my libraries definitions
    dc.l AllocI2C
    dc.l FreeI2C
    dc.l SetI2CDelay
    dc.l InitI2C
    dc.l SendI2C
    dc.l ReceiveI2C
    dc.l GetI2COpponent
    dc.l I2CErrText
    dc.l ShutDownI2C
    dc.l BringBackI2C
    ;------ function table end marker
    dc.l -1

    ; base structure of my library:
    STRUCTURE I2CLib,LIB_SIZE
      ULONG SendCalls               ; some statistics
      ULONG SendBytes
      ULONG RecvCalls
      ULONG RecvBytes
      ULONG Lost
      ULONG Unheard
      ULONG Overflows
      ULONG Errors
      UBYTE HwType
      UBYTE myFlags
      ULONG SlowI2C
      STRUCT Referee,SS_SIZE        ; a SignalSemaphore
      APTR SysBase
      APTR myConfigDev              ; info about our teletext board
      APTR mySegList
      APTR PortOpponent             ; always NULL with this library version
      UBYTE BusOK                   ; Boolean: can we access the hardware?
      UBYTE AllocError              ; Why not?
      UBYTE LockOut                 ; SysOp says: Don't touch the hardware!
    LABEL I2CLib_SIZE

    ; The data table initializes static data structures. Cryptic format,
    ; but generated conveniently by the macros from "exec/initializers.i".
    ; Macro arguments: offset from the library base, initvalue.
    ; Note that InitStruct(), which processes this table, starts by zeroing
    ; our whole library base structure, so explicit initializations to zero
    ; are never needed.
dataTable:
    INITBYTE LN_TYPE,NT_LIBRARY
    INITLONG LN_NAME,LibName
    INITLONG LIB_IDSTRING,IDString
    INITWORD LIB_VERSION,VERSION
    INITWORD LIB_REVISION,REVISION
    INITBYTE LIB_FLAGS,LIBF_SUMUSED!LIBF_CHANGED
    INITBYTE HwType,3               ; 3=Zorro board
    dc.w 0

    ; Plaintext error table for the I2CErrText function
errtab:
    dc.b err00-err00                                        ; OK
    dc.b err01-err00,err02-err00,err03-err00,err04-err00    ; 8 I/O errors
    dc.b err05-err00,err_x-err00,err_x-err00,err08-err00
    dc.b err_1-err00,err_2-err00,err_3-err00                ; 6 alloc errors
    dc.b err_x-err00,err_5-err00,err_x-err00
    dc.b error-err00,err_x-err00                            ; extras
errstrs:
err00:  dc.b 'OK',0
    ; I/O errors:
err01:  dc.b 'data rejected',0
err02:  dc.b 'no reply',0
err03:  dc.b 'SDA trashed',0
err04:  dc.b 'SDA always LO',0
err05:  dc.b 'SDA always HI',0
err08:  dc.b 'hardware is busy',0
    ; allocation errors:
err_1:  dc.b 'board is busy',0
err_2:  dc.b 'board not found',0
err_3:  dc.b 'no '
ExpansionName: dc.b 'expansion.library',0
err_5:  dc.b 'temporary shutdown',0     ; slightly changed meaning
    ; extras:
error:  dc.b 'error',0
err_x:  dc.b '???',0
    even

;==========================================================================
initRoutine: ; (libptr: D0, SegList: A0, ExecBase: A6)
;--------------------------------------------------------------------------
; This routine gets called after the library has been allocated. If it
; returns non-zero then the library will be linked into the library list.
;--------------------------------------------------------------------------
    move.l a5,-(a7)
    move.l d0,a5                    ; A5 points to ourselves now
    move.l a6,SysBase(a5)           ; pointer to exec.library
    move.l a0,mySegList(a5)         ; pointer to our loaded code
    ; try to read our environment variable for bus timing, "I2CDELAY":
    bsr AutoSetDelay
    ; open expansion.library, find our board, and close the library again
    lea ExpansionName(pc),a1
    moveq #0,d0
    jsr OpenLibrary(a6)
    tst.l d0
    bne.s 1$
    ; What the heck? Can't open expansion.library! -> ALERT
    movem.l d7/a5/a6,-(a7)
    move.l #AG_OpenLib!AO_ExpansionLib,d7
    jsr Alert(a6)
    movem.l (a7)+,d7/a5/a6
    move.b #I2C_NO_MISC_RESOURCE,AllocError(a5)
    bra.s 2$
1$: move.l d0,a6                    ; ExpansionBase in A6
    moveq #0,d0
    move.l d0,a0                    ; examine the list from the start
    move.l #VENDOR,d0
    move.l #PRODUCT,d1
    jsr FindConfigDev(a6)           ; find our board
    move.l d0,myConfigDev(a5)
    move.l a6,a1
    move.l SysBase(a5),a6           ; ExecBase back in A6
    jsr CloseLibrary(a6)            ; close expansion.lib
2$: ; prepare my semaphore;
    lea Referee(a5),a0
    jsr InitSemaphore(a6)
    move.l a5,d0
    move.l (a7)+,a5
    rts

;==========================================================================
;          *** Here come the library specific functions ***
;==========================================================================

;==========================================================================
AllocI2C: ; (DelayType: D0.B, Name: A1)
;--------------------------------------------------------------------------
; Forget about the parameters, they're obsolete in V39 anyway. Also, for
; the hardware on a Zorro board, there is really no way of "allocating".
; All we do is check if the board is there at all, and if some driver
; is already bound to it (shouldn't normally occur in our case).
; Returncodes (D0):
;   0 = OK
;   1 = board allocated to another driver
;   2 = board not found
;   3 = library wasn't open (hm!)
;   5 = allocation forbidden by the LockOut flag
;--------------------------------------------------------------------------
; internal use of registers:
; D6: return code
;--------------------------------------------------------------------------
    movem.l d6/a5,-(a7)
    move.l a6,a5                    ; I2CBase is now in A5
    move.l SysBase(a5),a6
    ; Seize the semaphore, so no one can start a ShutDownI2C() simultaneously:
    lea Referee(a5),a0
    jsr ObtainSemaphore(a6)
    moveq #I2C_OK,d6                ; default return code
    tst.b BusOK(a5)                 ; Do we already own the port?
    bne AllocEnd                    ; yes, fine
    move.b AllocError(a5),d6        ; No. Due to a truly fatal error?
    cmp.b #I2C_NO_MISC_RESOURCE,d6  ; ... like this one?
    beq AllocEnd                    ; We can only report it once more.
    moveq #I2C_ACTIVE,d6            ; error: not allowed to allocate
    tst.b LockOut(a5)               ; is that true?
    bne AllocEnd                    ; yes
    moveq #I2C_BITS_BUSY,d6         ; error: board not present
    move.l myConfigDev(a5),d0       ; is that true?
    beq AllocEnd                    ; yes
    moveq #I2C_PORT_BUSY,d6         ; error: someone else uses our hardware
    move.l d0,a0
    tst.l cd_Driver(a0)             ; is that true?
    bne AllocEnd                    ; yes
    ; All tests were OK, so write that down:
    st BusOK(a5)                    ; BusOK=TRUE
    moveq #I2C_OK,d6
AllocEnd:
    move.b d6,AllocError(a5)
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ReleaseSemaphore(a6)
    move.l a5,a6                    ; I2CBase back in A6
    move.l d6,d0
    movem.l (a7)+,d6/a5
    rts

;==========================================================================
FreeI2C: ; ()
;--------------------------------------------------------------------------
; Returns the allocated hardware, which is really an awful lot of work in
; this version of the library. :->
; Is called on every Close(), but will do nothing if more than one client
; has the library open.
;--------------------------------------------------------------------------
    cmpi.w #1,LIB_OPENCNT(a6)       ; Are we the last client of the library?
    bne FreeEnd                     ; No.
    ; Here comes a (poor) countermeasure against clients who call
    ; ShutDownI2C() and then quit without calling BringBackI2C(). It only
    ; works after *all* clients have closed the library, but that's the best
    ; we can do:
    sf LockOut(a6)
FreeImmediate:
    sf BusOK(a6)                    ; BusOK=FALSE
FreeEnd:
    moveq #0,d0
    rts

    INCLUDE "i2c.generic.s"

    END

