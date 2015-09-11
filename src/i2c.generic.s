;==========================================================================
; i2c.generic.s -- parts of the i2c.library that are identical for all
; three implementation styles and are included at the end of all source
; files ("i2c.library.s", "i2c.library.card.s" and "i2c.library.disk.s").
;==========================================================================

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
;             *** Some more library specific functions ***
;==========================================================================

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
    INITPORT
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
AutoSetDelay:
;--------------------------------------------------------------------------
; Is called from the library init routine, with I2CBase in A5, ExecBase in
; A6. If dos 2.0 is available, it reads the environment variable I2CDELAY.
;--------------------------------------------------------------------------
    lea DosName(pc),a1
    moveq #36,d0
    jsr OpenLibrary(a6)
    tst.l d0
    bne 1$
    rts                             ; tough luck, couldn't open dos V36+
1$  move.l d0,a6                    ; else prepare to call DOS
    movem.l d2-d4,-(a7)
    lea VarName(pc),a1              ; Why the hell does DOS want the buffer
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
    movem.l (a7)+,d2-d4
    move.l a6,a1
    move.l SysBase(a5),a6
    jsr CloseLibrary(a6)            ; close dos.library again
    rts
VarSpace:
    dc.l 0,0,0                      ; reserve 12 bytes
VarName:
    dc.b 'I2CDELAY',0
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
    move.l PortOpponent(a6),d0
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
; D0: data byte to be sent
; D1: number of bytes remainig in buffer
; D2: echo byte
; D3: bit counter / error code
; D4: delay counter
; D5: delay size
; D6: initial number of bytes
; D7: mirror for the CIA register
; A0/A1: CIA port address(es)
; A2(!): I/O buffer
; A5: I2CBase, since we need Exec, too
;--------------------------------------------------------------------------
    movem.l d2-d7/a2/a5,-(a7)       ; Save the used registers ...
    move.l a6,a5                    ; I2CBase is now in A5,
    move.l a1,a2                    ; the buffer pointer in A2
    movem.l d0-d1,-(a7)             ; Save parameters from the scratch regs.
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ObtainSemaphore(a6)         ; make sure we're alone in this code
    addq.l #1,SendCalls(a5)         ; count the call
    moveq #I2C_HARDW_BUSY,d3        ; May we access the hardware anyway?
    tst.b BusOK(a5)
    beq AbortIO                     ; no
    ALLOCPERCALL                    ; will do nothing in most library versions
    movem.l (a7)+,d0-d1
    move.l SlowI2C(a5),d5           ; pre-load some frequently used stuff
    PREP4MACROS
    move.w d1,d6                    ; backup, because D1 will be destroyed
    bclr #0,d0                      ; make the address "write" style
    bset #15,d0                     ; always enable reading the ACK bit
    ; I²C-bus start condition,
    ; DATA=H->L, wait>=4.0µs, CLK=H->L  ("protocol violation to LO"):
    SDAL
    bsr BigDelay
    SCLL
    bsr BigDelay                    ; NineBitIO starts without DELAY
SendLoop:   ; Send the byte in D0
    bsr NineBitIO
    moveq #I2C_OK,d3
    sub.b d2,d0
    bne HardErr                     ; That's not what we sent!
    tst.w d2
    bmi AckErr                      ; ACK bit "1", that means "NAK"
    subq.w #1,d1
    bmi EndIO                       ; all done
    move.b (a2)+,d0                 ; else get a byte from the buffer
    addq.l #1,SendBytes(a5)         ; count it for the log
    bra SendLoop
AckErr:
    cmp.w d1,d6                     ; if this was the 1st (=address) byte,
    beq NoReply                     ; this is the classical "bad address" error
    moveq #I2C_OK,d3                ; "NAK" might still be "OK",
    tst.w d1                        ; if this were the last byte anyway
    beq EndIO                       ; yes
    moveq #I2C_REJECT,d3            ; else: error "data rejected"
    addq.l #1,Overflows(a5)         ; count the overflow
    bra EndIO

;==========================================================================
ReceiveI2C: ; (addr: D0.B, number: D1.W, buffer: A1)
;--------------------------------------------------------------------------
; LSB in addr will always be set to make a valid I²C-bus read address.
; Read from I²C-bus cannot be stopped without reading at least one byte.
; So if number=0 bytes are requested, still 1 byte will be received,
; however not copied to the buffer.
; Return code: $00AABBCC, with
;   CC: zero, if an error occured (for V38 compatibility)
;   BB: error number
;   AA: return code of AllocI2C (as you shouldn't call AllocI2C explicitly)
;--------------------------------------------------------------------------
; internal use of registers:
; D0: data byte to be sent
; D1: number of requested bytes to go
; D2: echo byte (=received byte)
; D3: bit counter / error code
; D4: delay counter
; D5: delay size
; D7: mirror for the CIA register
; A0/A1: CIA port address(es)
; A2(!): I/O buffer
; A5: I2CBase, since we need Exec, too
;--------------------------------------------------------------------------
    movem.l d2-d7/a2/a5,-(a7)       ; Save the used registers ...
    move.l a6,a5                    ; I2CBase is now in A5,
    move.l a1,a2                    ; the buffer pointer in A2
    movem.l d0-d1,-(a7)             ; Save parameters from the scratch regs.
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ObtainSemaphore(a6)         ; make sure we're alone in this code
    addq.l #1,RecvCalls(a5)         ; count the call
    moveq #I2C_HARDW_BUSY,d3        ; May we access the hardware anyway?
    tst.b BusOK(a5)
    beq AbortIO                     ; no
    ALLOCPERCALL                    ; will do nothing in most library versions
    movem.l (a7)+,d0-d1
    move.l SlowI2C(a5),d5           ; pre-load some frequently used stuff
    PREP4MACROS
    bset #0,d0                      ; make the address "read" style
    bset #15,d0                     ; and enable reading the ACK bit
    ; I²C-bus start condition:
    SDAL
    bsr BigDelay
    SCLL
    bsr BigDelay
    ; Send the address byte first (is found in D0)
    bsr NineBitIO
    cmp.b d2,d0
    bne HardErr                     ; That's not what we sent!
    tst.w d2
    bmi NoReply                     ; Adress got no reply!
    ; Now we can receive data, but remember:
    ; We must receive 1 byte at least, even if 0 were requested.
RecvLoop:
    moveq #-1,d0                    ; enable reading 8 bits,
    subq.w #1,d1                    ; count the byte
    ble 1$
    lsr.w #1,d0                     ; always ACK=0, except last byte
1$  bsr NineBitIO
    tst.w d1                        ; Was this the 1st of 0 bytes?
    bmi 2$                          ; Yes, don't store it, just quit.
    move.b d2,(a2)+                 ; Else store the byte to the buffer.
    addq.l #1,RecvBytes(a5)         ; count it for the log
    tst.w d1
    bne RecvLoop                    ; Any more to receive?
2$  moveq #I2C_OK,d3
    bra EndIO                       ; all done

;==========================================================================
; Subroutines for both SendI2C and ReceiveI2C:
;--------------------------------------------------------------------------

    ; these are jumped to (!) at the end of both Send and Receive:
AbortIO:                            ; wasn't allowed to touch the hardware
    movem.l (a7)+,d0-d1             ; only need to clear the stack
    addq.l #1,Lost(a5)              ; count the lost call
    bra ReportAndFinish
NoReply:
    moveq #I2C_NO_REPLY,d3          ; error: "no reply"
    addq.l #1,Unheard(a5)           ; count the "bad" address
    bra EndIO
HardErr:                            ; encountered a real bad hardware error
    addq.l #1,Errors(a5)            ; count the error
    moveq #SDA_HI,d3                ; Suppose "SDA always HI",
    cmp.b #$FF,d2                   ; is that so?
    beq EndIO                       ; yes
    moveq #SDA_LO,d3                ; Well then, "SDA always LO"?
    tst.b d2
    beq EndIO                       ; yes
    moveq #SDA_TRASHED,d3           ; "SDA trashed" in no specific way
EndIO:
    ; stop the bus,
    ; stop condition is CLK=L->H, wait>=4.7µs, DATA=L->H, wait>=4.7µs
    ; ("protocol violation to HI")
    SDAL                            ; make sure DATA is LO
    bsr BigDelay
    SCLH
    bsr BigDelay
    SDAH
    bsr BigDelay                    ; ensure a minimum "bus free" time
    RELEASEPERCALL                  ; may trash a6!
ReportAndFinish:
    ; compose the return value $00AABBCC, taking BB from D3.B:
    moveq #0,d2
    move.b AllocError(a5),d2
    swap d2                         ; AA
    asl.w #8,d3                     ; this will be BB
    seq d2                          ; CC=TRUE, if no error
    or.w d3,d2                      ; that's it
    move.l SysBase(a5),a6
    lea Referee(a5),a0
    jsr ReleaseSemaphore(a6)        ; release the semaphore
    move.l d2,d0                    ; set return code
    move.l a5,a6                    ; I2CBase back in A6
    movem.l (a7)+,d2-d7/a2/a5       ; retrieve the registers
    rts

DELAY MACRO                         ; extra delay as specified by D5
    ; loops D5 times when called without parameters,
    ; DELAY A loops D5/2 times, DELAY B loops (D5+1)/2 times
    ; DELAY X loops 2*(D5+1) times
    move.l d5,d4
    ;
    IFC '\1','A'
    lsr.l #1,d4
    ENDC
    IFC '\1','B'
    addq.l #1,d4
    lsr.l #1,d4
    ENDC
    IFC '\1','X'
    addq.l #1,d4
    asl.l #1,d4
    ENDC
    ;
    beq quit\@
loop\@:
    IDLEREAD                        ; read a CIA register => 1.4µs
    subq.l #1,d4
    bne loop\@
quit\@:
    ENDM

BigDelay:   ; is used during bus start/stop
    ; Delays twice, plus two, to make sure that NineBitIO is the critical
    ; operation regarding delay value, not the start/stop conditions.
    DELAY X
    rts

NineBitIO:  ; Universal subroutine for sending/receiving a byte, including
    ; ACK bit (#15): send 9 bits from D0 and monitor SDA line to return
    ; a 9 bit "echo" in D2.
    ; The required minimum timing can be guaranteed from the number of
    ; CIA R/W accesses (i. e. EClock-cycles). CLK=HI: 3 cycles -> 4.2µs,
    ; CLK=LO: 4 cycles -> 5.6µs.
    rol.w #1,d0                     ; put ACK bit in a more convenient place
    clr.w d2                        ; echo-"byte"
    moveq #8,d3                     ; 9 bit
BitLoop:
    DELAY A
    btst d3,d0
    beq 1$
    SDAH                            ; send "1"
    bra 2$
1$  SDAL                            ; send "0"
2$  DELAY B
    SCLH                            ; CLK-pulse (>=4.0µs) to indicate
    DELAY                           ;  "valid DATA"
    SDAtest
    beq 3$                          ; SDA LO?
    bset d3,d2                      ; else set the according "echo-bit"
3$  SCLL                            ; CLK=LO (>=4.7µs) to prepare for
    dbf d3,BitLoop                  ;  the next bit
    ror.w #1,d0                     ; undo the shifting
    ror.w #1,d2                     ; same for the echo byte
    rts

