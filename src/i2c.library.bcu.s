;==========================================================================
; i2c.library.bcu.s -- run-time library for accessing I²C-bus hardware
; using the PCF8584 bus controller unit.
;==========================================================================

    INCLUDE "bcu.i"
VERSION = 40
REVISION = 2
IDPART1 MACRO   ; IDPART2 is defined in the hw. specific includes
    dc.b 'i2c.library 40.3 (30 Dec 99)'
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
TIMEOUT_TICKS  = 25     ; half a second

    NOLIST
    INCLUDE "exec/types.i"
    INCLUDE "exec/initializers.i"
    INCLUDE "exec/libraries.i"
    INCLUDE "exec/lists.i"
    INCLUDE "exec/alerts.i"
    INCLUDE "exec/semaphores.i"
    INCLUDE "exec/resident.i"
    INCLUDE "exec/interrupts.i"
    INCLUDE "exec/tasks.i"
    INCLUDE "libraries/configvars.i"
    INCLUDE "hardware/intbits.i"
    LIST

; library offsets in Exec:
Alert               = -108
Forbid              = -132
Permit              = -138
AddIntServer        = -168
RemIntServer        = -174
FreeMem             = -210
Remove              = -252
FindTask            = -294
Wait                = -318
Signal              = -324
AllocSignal         = -330
FreeSignal          = -336
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
      APTR myConfigDev
      APTR myBoardAddr              ; info about our teletext board
      APTR mySegList
      ULONG ClockTable              ; 4 byte values actually
      UBYTE BusOK                   ; Boolean: can we access the hardware?
      UBYTE AllocError              ; Why not?
      UBYTE LockOut                 ; SysOp says: Don't touch the hardware!
      ; Info for the Interrupts:
      UBYTE IoError                 ; I/O result code
      UWORD PollSize                ; threshold for interrupt mode
      UBYTE IntEnabled              ; interrupts enabled?
      UBYTE RecvMode                ; send or receive?
      APTR  BufferSpace             ; caller-supplied I/O buffer
      UWORD BytesToGo               ; number of bytes in it
      UWORD BytesDone               ; bytes already sent/received
      UWORD TickDown                ; timeout management with VERTB
      APTR  SigTask                 ; task waiting for the background I/O
      ULONG SigMask                 ; SigBit to apply
      UBYTE SigBit
      UBYTE DataByte
      STRUCT BlankInt,IS_SIZE       ; Interrupt control structures
      STRUCT IoInt,IS_SIZE
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
    INITWORD PollSize,8
    INITBYTE HwType,4               ; 4=smart controller
    INITBYTE BlankInt+LN_TYPE,NT_INTERRUPT
    INITLONG BlankInt+LN_NAME,LibName
    INITLONG BlankInt+IS_CODE,BlankIntServer
    INITBYTE IoInt+LN_TYPE,NT_INTERRUPT
    INITBYTE IoInt+LN_PRI,100       ; or rather 125?
    INITLONG IoInt+LN_NAME,LibName
    INITLONG IoInt+IS_CODE,IoIntServer
    dc.w 0

    ; Plaintext error table for the I2CErrText function
errtab:
    dc.b err00-err00                                        ; OK
    dc.b err01-err00,err02-err00,err03-err00,err_x-err00    ; 8 I/O errors
    dc.b err_x-err00,err06-err00,err_x-err00,err08-err00
    dc.b err_1-err00,err_2-err00,err_3-err00                ; 6 alloc errors
    dc.b err_4-err00,err_5-err00,err_x-err00
    dc.b error-err00,err_x-err00                            ; extras
errstrs:
err00:  dc.b 'OK',0
    ; I/O errors:
err01:  dc.b 'data rejected',0
err02:  dc.b 'no reply',0
err03:  dc.b 'protocol error',0
err06:  dc.b 'timeout occured',0
err08:  dc.b 'hardware is busy',0
    ; allocation errors:
err_1:  dc.b 'board is busy',0
err_2:  dc.b 'board not found',0
err_3:  dc.b 'no '
ExpansionName: dc.b 'expansion.library',0
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
    bsr ReadEnvVars
    ; open expansion.library, find our board, and close the library again
    lea ExpansionName(pc),a1
    moveq #0,d0
    jsr OpenLibrary(a6)
    tst.l d0
    bne.s InitGotExLib
    ; What the heck? Can't open expansion.library! -> ALERT
    movem.l d7/a5/a6,-(a7)
    move.l #AG_OpenLib!AO_ExpansionLib,d7
    jsr Alert(a6)
    movem.l (a7)+,d7/a5/a6
    move.b #I2C_NO_MISC_RESOURCE,AllocError(a5)
    bra.s InitExLibDone
InitGotExLib:
    move.l d0,a6                    ; ExpansionBase in A6
    moveq #0,d0
    move.l d0,a0                    ; examine the list from the start
    move.l #VENDOR,d0
    move.l #PRODUCT,d1
    jsr FindConfigDev(a6)           ; find our board
    move.l d0,myConfigDev(a5)
    beq 1$                          ; not found
    move.l d0,a0
    move.l cd_BoardAddr(a0),d0
1$  move.l d0,myBoardAddr(a5)       ; store the board address (or NULL)
    move.l a6,a1
    move.l SysBase(a5),a6           ; ExecBase back in A6
    jsr CloseLibrary(a6)            ; close expansion.lib
InitExLibDone:
    lea Referee(a5),a0              ; prepare my semaphore
    jsr InitSemaphore(a6)
    ; Complete the interrupt data structures. The IS_DATA field, which
    ; points to our libbase, cannot be filled in by the initializer table.
    move.l a5,BlankInt+IS_DATA(a5)
    move.l a5,IoInt+IS_DATA(a5)
    ; Add the vertical blank interrupt server...
    moveq #INTB_VERTB,d0
    lea BlankInt(a5),a1
    jsr AddIntServer(a6)
    ; ...and one for hw. interrupt 2 (aka PORTS), to process I/O events.
    moveq #INTB_PORTS,d0
    lea IoInt(a5),a1
    jsr AddIntServer(a6)
    move.l a5,d0
    move.l (a7)+,a5
    rts

;==========================================================================
;   *** Here come the system interface commands: Open/Close/Expunge ***
;--------------------------------------------------------------------------
; Exec has turned off task switching while in these routines, so we should
; not take too long in them.
;==========================================================================

;==========================================================================
Null: ; This might have a meaning in future OS versions ...
;--------------------------------------------------------------------------
    moveq #0,d0
    rts

;==========================================================================
Open: ; (libptr: A6, version: D0)
;--------------------------------------------------------------------------
; Open returns the library pointer in D0 if the open was successful, else
; NULL. But we won't fail, there are gentler ways of reporting trouble :-)
;--------------------------------------------------------------------------
    addq.w #1,LIB_OPENCNT(a6)       ; count the new client
    bclr #LIBB_DELEXP,myFlags(a6)   ; prevent delayed expunges
    bsr AllocI2C
    bsr InitI2C
    move.l a6,d0
    rts

;==========================================================================
Close: ; (libptr: A6)
;--------------------------------------------------------------------------
; If the library is no longer open and there is a delayed expunge pending
; then Close should call Expunge and return the segment list (as given to
; Init). This will remove us from memory.
; Otherwise Close should return NULL.
;--------------------------------------------------------------------------
    bsr FreeI2C                     ; will do nothing unless LIB_OPENCNT is 1
    moveq #0,d0                     ; default return value
    subq.w #1,LIB_OPENCNT(a6)       ; One client down,
    bne.s 1$                        ; any left?
    btst #LIBB_DELEXP,myFlags(a6)   ; Is there a delayed expunge pending?
    beq.s 1$
    bsr Expunge                     ; do the expunge
1$  rts

;==========================================================================
Expunge: ; (libptr: A6)
;--------------------------------------------------------------------------
; If the library is no longer open, then Expunge should return the segment
; list (as given to Init). Otherwise Expunge should set the delayed expunge
; flag and return NULL.
; Important note: Expunge is called from the memory allocator, so DON'T
; try funny things here that might take long.
;--------------------------------------------------------------------------
    movem.l d2/a5/a6,-(a7)
    move.l a6,a5
    move.l SysBase(a5),a6
    tst.w LIB_OPENCNT(a5)           ; see if anyone has us open
    beq 1$
    ; Sorry, we can only set the delayed expunge flag
    bset #LIBB_DELEXP,myFlags(a5)
    moveq #0,d0
    bra.s Expunge_End
1$: ; Go ahead and get rid of us.
    moveq #INTB_VERTB,d0            ; remove interrupt servers
    lea BlankInt(a5),a1
    jsr RemIntServer(a6)
    moveq #INTB_PORTS,d0
    lea IoInt(a5),a1
    jsr RemIntServer(a6)
    move.l mySegList(a5),d2         ; Store our seglist in d2,
    move.l a5,a1
    jsr Remove(a6)                  ; unlink from library list,
    moveq #0,d0
    move.l a5,a1
    move.w LIB_NEGSIZE(a5),d0
    sub.l d0,a1
    add.w LIB_POSSIZE(a5),d0
    jsr FreeMem(a6)                 ; free our memory,
    move.l d2,d0                    ; set up the return value.
Expunge_End:
    movem.l (a7)+,d2/a5/a6
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
    move.l myBoardAddr(a5),d0       ; is that true?
    beq AllocEnd                    ; yes
    moveq #I2C_PORT_BUSY,d6         ; error: someone else uses our hardware
    move.l myConfigDev(a5),a0
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



;==========================================================================
InitI2C: ; ()
;--------------------------------------------------------------------------
; Sets up data direction registers and makes sure both bus lines are HI.
; Is part of Open() in V39, but not part of AllocI2C(), so you might still
; need to call it directly.
;--------------------------------------------------------------------------
    tst.b BusOK(a6)                 ; May we access the port anyway?
    beq InitDone                    ; no
ForceInit:                          ; side entry that doesn't check
    ; hmm...
InitDone:
    moveq #0,d0
    rts

;==========================================================================
SetI2CDelay: ; (ticks: D0.L)
;--------------------------------------------------------------------------
; Adjust the timing of I²C-bus I/O, which must not exceed 100kHz. Unit is
; EClock-Ticks (about 1.4 µs), the delay will be added to every SCL pulse.
; Small delay values should be OK, e.g. 0 with OCS/ECS, 4 with AGA.
; Returns the old delay value in D0. Especially useful when called with
; I2CDELAY_READONLY=-1 as parameter, which will leave the old delay value
; still valid.
;--------------------------------------------------------------------------
    move.l SlowI2C(a6),d1
    tst.l d0
    bmi 1$                          ; that's I2CDELAY_READONLY
    move.l d0,SlowI2C(a6)
1$  move.l d1,d0
    rts

;==========================================================================
ReadEnvVars:
;--------------------------------------------------------------------------
; Is called from the library init routine, with I2CBase in A5, ExecBase in
; A6. If dos 2.0 is available, it reads the environment variable I2CDELAY.
; Also tries to read a variable called I2CXTAL, depending on which we will
; set up the translation table of delay values to S2 register bitmaps,
; and a I2CPOLLSIZE variable, to adjust the minimum transfer size for which
; to use interrupts.
;--------------------------------------------------------------------------
    lea DosName(pc),a1
    moveq #36,d0
    jsr OpenLibrary(a6)
    tst.l d0
    bne 1$
    rts                             ; tough luck, couldn't open dos V36+
1$  move.l d0,a6                    ; else prepare to call DOS
    movem.l d2-d4,-(a7)

    ; Try to read "I2CDELAY"
    lea VarName(pc),a1              ; Why on earth does DOS want the buffer
    move.l a1,d1                    ;  addresses in data registers ???
    lea VarSpace(pc),a1
    move.l a1,d2
    moveq #12,d3                    ; buffer size at VarSpace
    moveq #0,d4                     ; flags
    jsr GetVar(a6)                  ; read the variable
    tst.l d0
    bmi VarNotFound                 ; value size "-1" indicates "not found"
    lea VarSpace(pc),a1             ; have DOS parse the number string
    move.l a1,d1
    lea SlowI2C(a5),a1              ; place the result directly in our libbase
    move.l a1,d2
    jsr StrToLong(a6)
VarNotFound:

    ; Try to read "I2CPOLLSIZE", much the same as above, but it's .w!
    lea Var2Name(pc),a1
    move.l a1,d1
    lea VarSpace(pc),a1
    move.l a1,d2
    ; but note that d3 and d4 haven't changed (big deal!)
    jsr GetVar(a6)                  ; read the variable
    tst.l d0
    bmi Var2NotFound                ; value size "-1" indicates "not found"
    lea VarSpace(pc),a1             ; have DOS parse the number string
    move.l a1,d1
    lea LongSpace(pc),a1            ; space for the intermediate result
    move.l a1,d2
    jsr StrToLong(a6)
    move.l LongSpace(pc),d0         ; read the result
    swap d0
    tst.w d0                        ; examine the upper 16 bit
    beq 1$
    moveq #-1,d0                    ; if non-zero, clamp to 0xffff
1$  swap d0                         ; undo the previous swap
    move.w d0,PollSize(a5)          ; and store it as a word
Var2NotFound:

    ; Try to read "I2CXTAL"
    lea Var3Name(pc),a1
    move.l a1,d1
    lea VarSpace(pc),a1
    move.l a1,d2
    jsr GetVar(a6)
    tst.l d0
    bmi Var3NotFound
    lea VarSpace(pc),a1
    move.l a1,d1
    lea LongSpace(pc),a1            ; space for the intermediate result
    move.l a1,d2
    jsr StrToLong(a6)
    move.l LongSpace(pc),d0         ; read the result, then translate it
    move.l #$00010203,d1            ; table bitmap for 3 MHz
    cmpi.b #3,d0                    ; use it?
    beq WriteTable                  ; yes
    move.l #$10111213,d1            ; table for 4.43 MHz
    cmpi.b #4,d0
    beq WriteTable
    move.l #$14151617,d1            ; table for 6 MHz
    cmpi.b #6,d0
    beq WriteTable
    move.l #$18191a1b,d1            ; table for 8 MHz
    cmpi.b #8,d0
    beq WriteTable
Var3NotFound:
    move.l #$1c1d1e1f,d1            ; default: table for 12 MHz
WriteTable:
    move.l d1,ClockTable(a5)

    movem.l (a7)+,d2-d4
    move.l a6,a1
    move.l SysBase(a5),a6
    jsr CloseLibrary(a6)            ; close dos.library again
    rts
VarSpace:
    dc.l 0,0,0                      ; reserve 12 bytes
LongSpace:
    dc.l 0                          ; + 4 more
VarName:
    dc.b 'I2CDELAY',0
Var2Name:
    dc.b 'I2CPOLLSIZE',0
Var3Name:
    dc.b 'I2CXTAL',0
DosName:
    dc.b 'dos.library',0
    even

;==========================================================================
ShutDownI2C: ; ()
;--------------------------------------------------------------------------
; Returns the allocated hardware immediately, and all subsequent I/O calls
; will fail. Most important: not even AllocI2C() will work, only calling
; BringBackI2C() will return things to normal.
; DON'T call this function unless the user has agreed to it, and has
; entitled you explicitly. Otherwise you will create great confusion, with
; all other clients of the library suddenly helpless.
; B.t.w., because there are so many different library versions, you don't
; even know what hardware you are about to return, and if it is needed at
; all, but the user knows.
; I'd say a sensible application could be a small CLI tool "locki2c" or a
; big red toggle gadget in your program window.
;--------------------------------------------------------------------------
    move.l a5,-(a7)
    move.l a6,a5                    ; I2CBase is now in A5
    move.l SysBase(a5),a6
    lea Referee(a5),a0              ; Semaphore will make sure that all
    jsr ObtainSemaphore(a6)         ; I/O is finished.
    exg a5,a6
    st LockOut(a6)                  ; Set up the lock and
    bsr FreeImmediate               ; return the hardware, unconditionally.
    exg a5,a6
    lea Referee(a5),a0
    jsr ReleaseSemaphore(a6)
    move.l a5,a6                    ; I2CBase back in A6
    move.l (a7)+,a5
    move.b #I2C_ACTIVE,AllocError(a6)   ; just to inform the user
    moveq #0,d0
    rts

;==========================================================================
BringBackI2C: ; ()
;--------------------------------------------------------------------------
; The opposite of ShutDownI2C, see comments there.
; Return values are the same as with AllocI2C, but unlike AllocI2C, a call
; to InitI2C is already included.
;--------------------------------------------------------------------------
    sf LockOut(a6)                  ; Release the lock
    bsr AllocI2C                    ; and (try to) get our hardware back.
    move.l d0,-(a7)                 ; save the result
    bsr InitI2C
    move.l (a7)+,d0
    rts

;==========================================================================
GetI2COpponent: ; ()
;--------------------------------------------------------------------------
; Returns the name of who's to blame that we could not allocate our
; hardware. If we actually own the hardware, or if the hardware that we
; use doesn't supply this kind of information, the result will be a NULL
; pointer!
;--------------------------------------------------------------------------
    moveq #0,d0
    rts

;==========================================================================
I2CErrText: ; (errnum: D0.L)
;--------------------------------------------------------------------------
; Returns a STRPTR to a brief description of the supplied error number,
; which you got from SendI2C or ReceiveI2C.
; Legal error numbers:                              internal translation
; $00AA0800, AA=1..6: allocation errors                            9..14
; $0000BB00, BB=1..8: I/O errors                                    1..8
; $000000CC, CC<>0    OK                                               0
; $00000000:          error, somehow                                  15
; Illegal values do no harm and will only return "???".               16
;--------------------------------------------------------------------------
MAXALLOCERR = 6
MAXIOERR    = 8
GENERICERR  = MAXIOERR+MAXALLOCERR+1
UNKNOWNERR  = GENERICERR+1
    ; look at AA first:
    swap d0                         ; -> $BBCC00AA
    cmpi.b #MAXALLOCERR,d0
    bhi unknown                     ; unknown allocation error
    tst.b d0
    beq 1$                          ; no allocation error at all
    addq.b #MAXIOERR,d0             ; else translate to internal number
    bra.s decode                    ; and decode it
1$  ; look at BB:
    rol.l #8,d0                     ; -> $CC00AABB (really: $CC0000BB)
    cmpi.b #MAXIOERR,d0
    bhi unknown                     ; unknown I/O error
    tst.b d0
    beq 2$                          ; no allocation error at all
    bra.s decode                    ; else decode it
2$  ; look at CC:
    rol.l #8,d0                     ; -> $00AABBCC
    tst.b d0
    beq 3$                          ; unspecific error, strange ...
    moveq #0,d0                     ; OK
    bra.s decode
3$  moveq #GENERICERR,d0
    bra.s decode
unknown:
    moveq #UNKNOWNERR,d0
decode:
    ; look up an internal error number 0..16 from the error table
    ext.w d0
    lea errtab(pc),a0
    move.b 0(a0,d0.w),d0
    ; Note that "ext.w d0" is not needed at this point (because the middle
    ; low byte in d0 is still 00) *and* would be wrong, because some offsets
    ; in errtab are >127.
    lea errstrs(pc),a0
    lea 0(a0,d0.w),a0
    move.l a0,d0
    rts



;==========================================================================
SendI2C: ; (addr: D0.B, number: D1.W, buffer: A1)
;--------------------------------------------------------------------------
; LSB in addr will always be cleared to make a valid I²C-bus write address.
; Sending number=0 bytes is allowed, too.
; Return code: $00AABBCC, with
;   CC: zero, if an error occured (for V38 compatibility)
;   BB: error number
;   AA: return code of AllocI2C (as you shouldn't call AllocI2C explicitly)
;--------------------------------------------------------------------------
; internal use of registers:
; D1: byte counter
; A0: base address of the expansion board
; A5: I2C_Base
; A6: SysBase
;--------------------------------------------------------------------------
    move.l a5,-(a7)                 ; Save the used registers ...
    move.l a6,a5                    ; I2C_Base is now in A5,
    movem.l d0-d1/a1,-(a7)          ; Save parameters from the scratch regs.
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ObtainSemaphore(a6)         ; make sure we're alone in this code
    movem.l (a7)+,d0-d1/a1
    addq.l #1,SendCalls(a5)         ; count the call
    sf RecvMode(a5)                 ; indicate send mode
    bsr InitPerCall
    beq ReportAndFinish             ; either AllocSignal() failed or hardware busy
    bclr #0,d0                      ; make the address "write" style
    move.b d0,REG_S0(a0)            ; prepare to send it
    tst.b IntEnabled(a5)            ; interrupt mode?
    bne BkgndIO                     ; yes
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_STA+CTRLF_ACK,REG_S1(a0)  ; send address
SendLoop:
    move.b SigBit(a5),d1            ; Have we been signaled?
    move.l SigTask(a5),a1           ;  That would be true in case of both
    move.l TC_SIGRECVD(a1),d0       ;  timeout and normal completion.
    btst d1,d0
    bne EndIO                       ; All done.
    move.b REG_S1(a0),d0
    btst #STATB_PIN,d0              ; wait for the last byte to complete
    bne SendLoop                    ; PIN bit must be cleared
    move.w BytesDone(a5),d1         ; prepare register parameters and call...
    bsr SendServer                  ; side entry (!) of our interrupt routine
    move.l myBoardAddr(a5),a0       ; restore the board address
    bra SendLoop



;==========================================================================
ReceiveI2C: ; (addr: D0.B, number: D1.W, buffer: A1)
;--------------------------------------------------------------------------
; LSB in addr will always be set to make a valid I²C-bus read address.
; Read from I²C-bus cannot be stopped without reading at least one byte.
; So if number=0 bytes are requested, still 1 byte will be received,
; however copied to an internal dummy buffer only.
; Return code: $00AABBCC, with
;   CC: zero, if an error occured (for V38 compatibility)
;   BB: error number
;   AA: return code of AllocI2C (as you shouldn't call AllocI2C explicitly)
;--------------------------------------------------------------------------
; internal use of registers:
; D1: byte counter
; A0: base address of the expansion board
; A5: I2C_Base
; A6: SysBase
;--------------------------------------------------------------------------
    move.l a5,-(a7)                 ; Save the used registers ...
    move.l a6,a5                    ; I2C_Base is now in A5,
    tst.w d1                        ; check for zero-byte buffer
    bne 1$
    moveq #1,d1                     ; fix "illegal" parameters
    lea DataByte(a5),a1
1$  movem.l d0-d1/a1,-(a7)          ; Save parameters from the scratch regs.
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ObtainSemaphore(a6)         ; make sure we're alone in this code
    movem.l (a7)+,d0-d1/a1
    addq.l #1,RecvCalls(a5)         ; count the call
    st RecvMode(a5)                 ; indicate receive mode
    bsr InitPerCall
    beq ReportAndFinish             ; either AllocSignal() failed or hardware busy
    bset #0,d0                      ; make the address "read" style
    move.b d0,REG_S0(a0)            ; prepare to send it
    tst.b IntEnabled(a5)            ; interrupt mode?
    bne BkgndIO                     ; yes
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_STA+CTRLF_ACK,REG_S1(a0)  ; send address
RecvLoop:
    move.b SigBit(a5),d1            ; Have we been signaled?
    move.l SigTask(a5),a1           ;  That would be true in case of both
    move.l TC_SIGRECVD(a1),d0       ;  timeout and normal completion.
    btst d1,d0
    bne EndIO                       ; All done.
    move.b REG_S1(a0),d0
    btst #STATB_PIN,d0              ; wait for the last byte to complete
    bne RecvLoop                    ; PIN bit must be cleared
    move.w BytesDone(a5),d1         ; prepare register parameters and call...
    bsr RecvServer                  ; side entry (!) of our interrupt routine
    move.l myBoardAddr(a5),a0       ; restore the board address
    bra RecvLoop



;==========================================================================
; Subroutines for both SendI2C and ReceiveI2C:
;--------------------------------------------------------------------------

InitPerCall:
; This is called at the start of SendI2C/ReceiveI2C, while we already
; hold the semaphore.
; Receives the same register parameters as Send/ReceiveI2C.
; Register usage: Can expect I2C_Base in A5, ExecBase in A6, and may
; use D0/D1/A0/A1 as scratch registers.
; Returns with Z-flag set to indicate failure (no signal allocated).
; For the caller's convenience, D0 will contain the I2C address and A0
; will be the board address, after we successfully return.

    tst.b BusOK(a5)                 ; may we access the hardware anyway?
    bne 1$
    addq.l #1,Lost(a5)              ; no, count the lost call
    move.b #I2C_HARDW_BUSY,IoError(a5)
    moveq #0,d0                     ; Z=1 to indicate failure
    rts

    ; Put the function parameters into globals
1$  move.b d0,DataByte(a5)          ; chip address
    move.l a1,BufferSpace(a5)       ; buffer description
    clr.w BytesDone(a5)             ; byte counter
    move.w d1,BytesToGo(a5)
    cmp.w PollSize(a5),d1           ; should we enter interrupt mode?
    shi IntEnabled(a5)              ;  (true for "large" transfers)
    move.b #I2C_OK,IoError(a5)      ; set up a default I/O result code.

    ; Set up the chip registers.
    move.l myBoardAddr(a5),a0
    move.b #CTRLF_PIN,REG_S1(a0)    ; select S0' register
    move.b #$55,REG_S0(a0)          ; set own address
    move.l SlowI2C(a5),d0           ; convert delay value to clock bit pattern
    moveq #3,d1
    cmp.l d1,d0                     ; make sure we don't run off the table
    bls 2$
    move.l d1,d0
2$  lea ClockTable(a5),a1
    move.b 0(a1,d0.w),d0
    move.b #CTRLF_PIN+CTRLF_ES1,REG_S1(a0)  ; select S2 (clock) register
    move.b d0,REG_S0(a0)
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_ACK,REG_S1(a0)    ; select S0 (data)

    ; Set up the signaling related variables for use by the interrupts.
    moveq #-1,d0                    ; allocate a signal bit
    jsr AllocSignal(a6)
    cmpi.b #-1,d0
    bne 3$
    addq.l #1,Lost(a5)              ; failed, count the call as lost
    move.b #I2C_ERROR_PORT,AllocError(a5)
    move.b #I2C_HARDW_BUSY,IoError(a5)
    moveq #0,d0                     ; Z-flag set to indicate failure
    rts
3$  move.b d0,SigBit(a5)
    moveq #0,d1
    move.l d1,a1                    ; clear A1, for FindTask( NULL )
    bset d0,d1                      ; D1 = 1 << D0
    move.l d1,SigMask(a5)
    jsr FindTask(a6)
    move.l d0,d1                    ; write down the calling task
    move.l myBoardAddr(a5),a0       ; set up "return values" as we promised
    move.b DataByte(a5),d0
    move.w #TIMEOUT_TICKS,TickDown(a5)  ; start the timer
    move.l d1,SigTask(a5)           ; this will also clear the Z-flag
    rts

    ; These are jumped to (!) at the end of both Send and Receive:
BkgndIO:
    ; Only need to trigger the interrupt chain:
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_STA+CTRLF_ACK+CTRLF_ENI,REG_S1(a0)
    move.l SigMask(a5),d0           ; Interrupt will do the rest
    jsr Wait(a6)                    ; Wait for it
    move.l myBoardAddr(a5),a0       ; restore the hardware base address
EndIO:
    ; The stop condition has already been generated by the subroutine that
    ; also set our signal bit, and the interrupt enable bit has also been
    ; cleared.
    ; We now just wait for the bus to go to idle state.
    clr.l SigTask(a5)               ; keep the interrupts from signaling us
    move.w #TIMEOUT_TICKS,TickDown(a5)  ; then prepare a timeout counter
1$  tst.w TickDown(a5)
    beq 2$                          ; ouch, timeout
    btst #STATB_NBB,REG_S1(a0)
    beq 1$                          ; still busy
2$  ; Release anything allocated in InitPerCall:
    move.b SigBit(a5),d0
    jsr FreeSignal(a6)              ; free the task's sigbit
ReportAndFinish:                    ; compose the return value $00AABBCC
    moveq #0,d0
    move.b AllocError(a5),d0
    swap d0                         ; AA
    move.b IoError(a5),d1
    asl.w #8,d1                     ; this will be BB
    seq d0                          ; CC=TRUE, if no error
    or.w d1,d0                      ; that's it
    move.l d0,-(a7)                 ; push the result for one more system call
    lea Referee(a5),a0
    jsr ReleaseSemaphore(a6)        ; release the semaphore
    move.l (a7)+,d0                 ; that's our return code
    move.l a5,a6                    ; I2C_Base back in A6
    movem.l (a7)+,a5                ; retrieve the registers
    rts


;==========================================================================
BlankIntServer: ; (data: A1)
;--------------------------------------------------------------------------
; Is called 50 times a second and will decrement TickDown with every call,
; until it's zero.
; When that happens, the waiting task (if we have one) will be signaled.
; Also, if we have a SigTask, a bus stop condition will be generated and
; a global I/O error code is written. This simplifies error handling for
; the owner task.
; A1 actually points at I2C_Base
; Caution: Must not trash A0, see autodoc note on AddIntServer().
;--------------------------------------------------------------------------
    tst.w TickDown(a1)
    beq 2$                          ; counter is already zero, do nothing
    subq.w #1,TickDown(a1)          ; count down
    bne 1$                          ; but still above zero?
    ; Wake up a waiting task, if we have one.
    move.l SigTask(a1),d1
    beq 2$                          ; no task to be signaled
    ; for debug output: bchg #1,$bfe001
    move.l a0,a5                    ; make a backup of A0
    move.l myBoardAddr(a1),a0       ; get the hardware base address
    ; Send the bus stop condition. Note that we also clear the
    ; ENI bit in this write access.
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_STO+CTRLF_ACK,REG_S1(a0)
    move.b #SCL_TIMEOUT,IoError(a1) ; write an error code
    addq.l #1,Errors(a1)            ; count it (as a protocol error)
    move.l SysBase(a1),a6
    move.l SigMask(a1),d0
    move.l d1,a1                    ; this trashes our only pointer to I2C_Base!
    jsr Signal(a6)                  ; call Exec
    move.l a5,a0                    ; restore A0
1$  moveq #0,d0                     ; Must return with Z=1 to allow further
2$  rts                             ;   processing of the VERTB chain!


;==========================================================================
IoIntServer: ; (data: A1)
;--------------------------------------------------------------------------
; Is called whenever an INT2 occurs in the system. Must check whether it
; came from the I2C hardware, and if so, at least clear the cause of the
; interrupt.
; A1 actually points at I2C_Base
; Being an interrupt server, we have D0/D1/A0/A1/A5/A6 as scratch
; registers (see autodocs on AddIntServer).
;--------------------------------------------------------------------------
; internal use of registers:
; D0: cache for status register / recently received byte
; D1: number of bytes already processed
; A0: base address of the expansion board
; A1: moves through the caller-supplied buffer
; A5: I2C_Base
; A6: ExecBase
;--------------------------------------------------------------------------
    tst.b IntEnabled(a1)            ; are we in interrupt mode anyway?
    bne 1$                          ; yes
    rts                             ; return with Z -> resume chain
1$  move.l myBoardAddr(a1),a0       ; get the hardware base address
    move.b REG_S1(a0),d0
    btst #STATB_PIN,d0              ; does our hardware need servicing?
    beq 2$                          ; yes
    moveq #0,d0                     ; set Z-bit to allow further
    rts                             ;   processing of the server chain
2$: ; This interrupt was apparently caused by our own hardware,
    ; so process it.
    move.l a1,a5                    ; I2C_Base in A5
    move.w BytesDone(a5),d1         ; we'll need this anyway
    tst.b RecvMode(a5)
    bne RecvServer

SendServer:
    ; Send one byte (or be done).
    ; May be called directly in polled mode, after waiting for PIN. Expects
    ; the S1 value in D0, the ascending byte counter in D1, the board
    ; address in A0, I2C_Base in A5. May trash the scratch registers and
    ; may load ExecBase into A6. Make sure to have a SigTask around and
    ; check for its tc_SigRecvd flags upon return.
    ; Check for errors first. If we find one, report it in IoError(a5)
    ; (should be initially set to I2C_OK by the caller!).
    andi.b #STATF_BER+STATF_LRB,d0
    beq SendNextByte                ; no errors for this byte
    btst #STATB_BER,d0
    beq 1$
    move.b #SDA_TRASHED,IoError(a5) ; ouch, protocol error
    addq.l #1,Errors(a5)            ; count it
    bra StopAfterPacket
1$  tst.w d1                        ; got NAK, was this the 1st (=address) byte?
    bne 2$
    move.b #I2C_NO_REPLY,IoError(a5); yes, the classical "bad address" error
    addq.l #1,Unheard(a5)           ; count it
    bra StopAfterPacket
2$  cmp.w BytesToGo(a5),d1          ; "NAK" might still be "OK",
    beq StopAfterPacket             ; if this were the last byte anyway
    move.b #I2C_REJECT,IoError(a5)  ; else: error "data rejected"
    addq.l #1,Overflows(a5)         ; count the overflow
    bra StopAfterPacket
SendNextByte:
    cmp.w BytesToGo(a5),d1          ; done yet?
    beq StopAfterPacket             ; yes
    move.l BufferSpace(a5),a1       ; else get a byte from the buffer
    move.b 0(a1,d1.w),d0
    addq.w #1,d1                    ; count it for the current send operation
    move.w d1,BytesDone(a5)
    addq.l #1,SendBytes(a5)         ; count it for the global log
    move.b d0,REG_S0(a0)            ; send it (this resets the PIN bit)
    bra ServerDone

RecvServer:
    ; Much like the SendServer, but a little trickier.
    ; We have to start by a dummy read, which means doing one more loop
    ; than the number of bytes would suggest. Also, since a read of 0 bytes
    ; is impossible, the owner task (!) must make sure that we always can
    ; receive at least 1 byte and also have valid buffer space for it!
    tst.w d1                        ; is this the first cycle?
    bne RecvNextByte                ; no
    andi.b #STATF_BER+STATF_LRB,d0  ; do error checking on the address byte
    beq RecvDummy                   ; no errors
    btst #STATB_BER,d0
    beq 1$
    move.b #SDA_TRASHED,IoError(a5) ; ouch, protocol error
    addq.l #1,Errors(a5)            ; count it
    bra StopAfterPacket
1$  move.b #I2C_NO_REPLY,IoError(a5); got NAK, the classical "bad address" error
    addq.l #1,Unheard(a5)           ; count it
    bra StopAfterPacket
RecvDummy:
    addq.w #1,d1                    ; increment byte counter
    move.w d1,BytesDone(a5)
    cmp.w BytesToGo(a5),d1          ; only one byte to read?
    bne 2$                          ; no
    tst.b IntEnabled(a5)
    bne 1$
    move.b #CTRLF_ESO,REG_S1(a0)    ; create a NAK here already,
    bra 2$
1$  move.b #CTRLF_ESO+CTRLF_ENI,REG_S1(a0)  ; preserving the ENI bit!
2$  tst.b REG_S0(a0)                ; the dummy read
    bra ServerDone
RecvNextByte:
    move.l BufferSpace(a5),a1       ; get buffer location for the next byte
    lea -1(a1,d1.w),a1              ; first time we get here, D1 is already 1!
    addq.l #1,RecvBytes(a5)         ; count it for the global log
    cmp.w BytesToGo(a5),d1          ; last byte?
    bne 1$                          ; no
    ; Send the bus stop condition, *before* reading the last byte.
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_STO+CTRLF_ACK,REG_S1(a0)
    move.b REG_S0(a0),(a1)          ; read the last byte
    bra PacketDone
1$  addq.w #1,d1                    ; increment byte counter
    move.w d1,BytesDone(a5)
    cmp.w BytesToGo(a5),d1          ; last byte but one?
    bne 3$                          ; no
    tst.b IntEnabled(a5)
    bne 2$
    move.b #CTRLF_ESO,REG_S1(a0)    ; yes, create a NAK,
    bra 3$
2$  move.b #CTRLF_ESO+CTRLF_ENI,REG_S1(a0)  ; preserving the ENI bit!
3$  move.b REG_S0(a0),(a1)          ; read a byte
    bra ServerDone

StopAfterPacket:
    ; Send the bus stop condition. Note that we also clear the
    ; ENI bit in this write access, since we are done for now.
    move.b #CTRLF_PIN+CTRLF_ESO+CTRLF_STO+CTRLF_ACK,REG_S1(a0)
PacketDone:
    ; Wake up a waiting task, if we have one.
    move.l SigTask(a5),d1
    beq ServerDone                  ; no task to be signaled
    move.l SysBase(a5),a6
    move.l SigMask(a5),d0
    move.l d1,a1
    jsr Signal(a6)                  ; call Exec
ServerDone:
    move.w #TIMEOUT_TICKS,TickDown(a5)  ; restart timeout counter
    ; Note that this, being a non-zero move, also clears the Z-bit,
    ; which we need to do to end the interrupt server chain.
    rts


    END
