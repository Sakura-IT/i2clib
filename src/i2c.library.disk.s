;==========================================================================
; i2c.library.disk.s -- run-time library for accessing I²C-bus hardware on
; the floppy port.
; Based on "i2c.library.s", but significantly different in the way it
; does its resource allocation
;==========================================================================

    INCLUDE "disk.i"
VERSION = 40
REVISION = 1
IDPART1 MACRO    ; IDPART2 is defined in the hw. specific includes
    dc.b 'i2c.library 40.1 (03 Jun 99)'
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
    LIST

; library offsets in Exec:
Alert               = -108
Forbid              = -132
Permit              = -138
FreeMem             = -210
Remove              = -252
FindTask            = -294
AllocSignal         = -330
FreeSignal          = -336
GetMsg              = -372
WaitPort            = -384
CloseLibrary        = -414
OpenResource        = -498
OpenLibrary         = -552
InitSemaphore       = -558
ObtainSemaphore     = -564
ReleaseSemaphore    = -570
; offsets in Dos:
StrToLong           = -816
GetVar              = -906

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
      APTR DiskBase
      APTR mySegList
      APTR PortOpponent             ; always NULL with this library version
      UBYTE BusOK                   ; Boolean: Allocation successful?
      UBYTE AllocError              ; Why not?
      ULONG UnitNo                  ; "floppy" unit 0 through 3 that we use
      STRUCT myDRU,DRU_SIZE         ; DiscResourceUnit, needed for GetUnit()
      STRUCT ReplyPort,MP_SIZE      ; MessagePort, DRU needs one
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
    INITBYTE HwType,2               ; 2=floppy port
    INITBYTE myDRU+LN_TYPE,NT_MESSAGE
    INITLONG myDRU+LN_NAME,LibName
    INITWORD myDRU+MN_LENGTH,MN_SIZE
    INITBYTE myDRU+DRU_DISCBLOCK+LN_TYPE,NT_INTERRUPT
    INITBYTE myDRU+DRU_DISCSYNC+LN_TYPE,NT_INTERRUPT
    INITBYTE myDRU+DRU_INDEX+LN_TYPE,NT_INTERRUPT
    INITBYTE ReplyPort+LN_TYPE,NT_MSGPORT
    INITBYTE ReplyPort+MP_FLAGS,PA_SIGNAL
    dc.w 0

    ; Plaintext error table for the I2CErrText function
errtab:
    dc.b err00-err00                                        ; OK
    dc.b err01-err00,err02-err00,err03-err00,err04-err00    ; 8 I/O errors
    dc.b err05-err00,err_x-err00,err_x-err00,err08-err00
    dc.b err_1-err00,err_2-err00,err_3-err00                ; 6 alloc errors
    dc.b err_4-err00,err_5-err00,err_x-err00
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
err_1:  dc.b 'all disk units taken',0
err_2:  dc.b 'no interface detected',0
err_3:  dc.b 'no '
DiskName: dc.b 'disk.resource',0
err_4:  dc.b 'AllocSignal() failed',0
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
    ; open the disk.resource, but don't try to allocate yet
    moveq #0,d0
    lea DiskName(pc),a1
    jsr OpenResource(a6)
    move.l d0,DiskBase(a5)          ; stash resource base
    bne.s 1$
    ; What the heck? Can't open disk.resource! -> ALERT
    movem.l d7/a5/a6,-(a7)
    move.l #AG_OpenRes!AO_DiskRsrc,d7
    jsr Alert(a6)
    movem.l (a7)+,d7/a5/a6
1$: ; link my reply port into the DRU-structure (can't do that by static
    ; initializers, sorry), it will be initialized later, per task (i. e.
    ; per call)
    lea ReplyPort(a5),a0
    move.l a0,myDRU+MN_REPLYPORT(a5)
    ; prepare my semaphore:
    lea Referee(a5),a0
    jsr InitSemaphore(a6)
    move.l   a5,d0
    move.l   (a7)+,a5
    rts

;==========================================================================
;          *** Here come the library specific functions ***
;==========================================================================

;==========================================================================
AllocI2C: ; (DelayType: D0.B, Name: A1)
;--------------------------------------------------------------------------
; New in V39: allocates the hardware to the library, not to the calling
; program, so the A1 parameter will be ignored.
; DelayType (D0) is ignored, too, and will always be DELAY_LOOP.
; Is now executed automatically during Open(), but you may call it as
; often as you like, e.g. after temporarily releasing the hardware (see
; FreeI2C) or if automatic allocation failed and you want to try again.
; But then remember to call InitI2C(), too.
; Returncodes (D0):
;   0 = OK
;   1 = all floppy units stolen by someone else
;   2 = no interface detected
;   3 = resource wasn't open (hm!)
;   4 = AllocSignal() failed (might also be reported later)
;   5 = allocation forbidden by the LockOut flag
;--------------------------------------------------------------------------
; internal use of registers:
; D4: delay counter
; D5: delay value
; D6: return code
; D7: trashed by the port macros
;--------------------------------------------------------------------------
    movem.l d4-d7/a5,-(a7)
    move.l a6,a5                    ; I2CBase is now in A5
    move.l SysBase(a5),a6
    ; Seize the semaphore, so no one can start a ShutDownI2C() simultaneously:
    lea Referee(a5),a0
    jsr ObtainSemaphore(a6)
    moveq #I2C_OK,d6
    tst.b BusOK(a5)                 ; Do we already own the port?
    bne AllocEnd                    ; yes, fine
    moveq #I2C_ACTIVE,d6
    tst.b LockOut(a5)               ; No, are we allowed to?
    bne AllocEnd
    moveq #I2C_NO_MISC_RESOURCE,d6
    move.l DiskBase(a5),a6
    move.l a6,d0                    ; was disk.resource found?
    beq AllocEnd
    ; Loop over all four disk units, starting from 0
    moveq #0,d0
    moveq #I2C_PORT_BUSY,d6         ; Error code should all attempts fail
AllocLoop:
    move.l d0,UnitNo(a5)
    jsr DR_ALLOCUNIT(a6)            ; try to allocate a disk drive
    tst.l d0
    beq NoAlloc                     ; allocated OK?
    moveq #I2C_BITS_BUSY,d6         ; yes: reduces the worst possible error
    ; Now check for an interface attached to the allocated disk unit
    move.l SysBase(a5),a6
    bsr GrabTheDisk
    move.l DiskBase(a5),a6          ; doesn't affect the Z flag!
    beq 1$
    move.l d1,d6                    ; double darn! AllocSignal() failed!
    bra NoGrab
1$  move.l #100,d5                  ; "huge" delay value in D5
    exg a5,a6
    bsr ForceInit
    exg a5,a6
    PREP4MACROS                     ; trashes D7
    SDAL
    bsr BigDelay                    ; trashes D4
    SDAtest
    bne NoReaction
    SDAH
    bsr BigDelay
    SDAtest
    beq NoReaction
    ; Coolness! We found our interface! Write it down:
    st BusOK(a5)                    ; BusOK=TRUE
    moveq #I2C_OK,d6
    jsr DR_GIVEUNIT(a6)             ; return the floppy port
    bra AllocEnd                    ; but not this unit, it's ours now
NoReaction:
    jsr DR_GIVEUNIT(a6)             ; return the floppy port
NoGrab:
    move.l UnitNo(a5),d0
    jsr DR_FREEUNIT(a6)             ; return this unit, it's no good
NoAlloc:
    move.l UnitNo(a5),d0
    addq.l #1,d0
    cmpi.b #4,d0
    bne AllocLoop
AllocEnd:
    move.b d6,AllocError(a5)
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ReleaseSemaphore(a6)
    move.l a5,a6                    ; I2CBase back in A6
    move.l d6,d0
    movem.l (a7)+,d4-d7/a5
    rts

GrabTheDisk:    ; allocate disk port
    ; Trashes the scratch registers, expects I2CBase in a5, ExecBase in a6.
    ; DO NOT CALL if disk.resource was not open!
    ; Places an I/O return code in d0 (you may test for Z-flag whether
    ; allocation was successful) and an allocation return code in d1.

    ; Need to do kind of a CreatePort first (really: initialze MP_SIGBIT,
    ; MP_SIGTASK and the MP_MSGLIST structure but not allocate a whole new
    ; structure, as CreatePort would do)
    moveq #-1,d0                    ; allocate a signal bit
    jsr AllocSignal(a6)
    cmpi.b #-1,d0
    bne 1$
    moveq #I2C_ERROR_PORT,d1
    move.b d1,AllocError(a5)
    moveq #I2C_HARDW_BUSY,d0
    rts                             ; Z-flag cleared to indicate failure
1$  move.b d0,ReplyPort+MP_SIGBIT(a5)
    clr.l d0
    move.l d0,a1
    jsr FindTask(a6)                ; write down the calling task
    move.l d0,ReplyPort+MP_SIGTASK(a5)
    lea ReplyPort+MP_MSGLIST(a5),a0
    NEWLIST a0                      ; clear the message list
RetryLoop:
    lea myDRU(a5),a1
    move.l DiskBase(a5),a6
    jsr DR_GETUNIT(a6)
    move.l SysBase(a5),a6
    tst.l d0
    bne 1$                          ; allocation successful -> done
    move.l myDRU+MN_REPLYPORT(a5),a0
    jsr WaitPort(a6)                ; else wait for retry notification
    move.l myDRU+MN_REPLYPORT(a5),a0
    jsr GetMsg(a6)                  ; collect the message
    bra.s RetryLoop                 ; and try again
1$: move.b ReplyPort+MP_SIGBIT(a5),d0
    jsr FreeSignal(a6)              ; free the task's sigbit
    moveq #0,d0                     ; Z-flag indicates success
    rts

;==========================================================================
FreeI2C: ; ()
;--------------------------------------------------------------------------
; Returns the allocated hardware, is executed automatically during Close().
; Calling it explicitly to allow, say, the printer.device temporary access
; to its hardware is perfectly legal, but won't work if more than one
; client has the library open.
;--------------------------------------------------------------------------
    cmpi.w #1,LIB_OPENCNT(a6)       ; Are we the last client of the library?
    bne FreeEnd                     ; No.
    ; Here comes a (poor) countermeasure against clients who call
    ; ShutDownI2C() and then quit without calling BringBackI2C(). It only
    ; works after *all* clients have closed the library, but that's the best
    ; we can do:
    sf LockOut(a6)
FreeImmediate:
    tst.b BusOK(a6)                 ; Do we own the hardware anyway?
    beq FreeEnd                     ; No.
    move.l a5,-(a7)                 ; Else return it:
    move.l a6,a5                    ; I2CBase is now in A5
    move.l DiskBase(a5),a6
    move.l a6,d0                    ; since move to <An> doesn't set flags!
    beq 1$
    ; That was a test for something really weird: How could we possibly own
    ; the hardware if there was no resource to do the allocation? (But then
    ; again, would you bet a guru on that?)
    move.l UnitNo(a5),d0            ; return the disk unit
    jsr DR_FREEUNIT(a6)
1$  sf BusOK(a5)                    ; BusOK=FALSE
    move.l a5,a6                    ; I2CBase back in A6
    move.l (a7)+,a5
FreeEnd:
    moveq #0,d0
    rts

    INCLUDE "i2c.generic.s"

    END

