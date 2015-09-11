;==========================================================================
; Some macro definitions to be included in "i2c.library.bcu.s",
; NOT in "i2c.library.s"!
;==========================================================================

; Where are the chip registers, relative to board base address?
REG_S0 = 0  ; note that these offsets are valid for *byte* access!
REG_S1 = 2

; Bit mask definitions for the S1 register.
CTRLB_ACK = 0   ; send ACK bit?
CTRLB_STO = 1   ; generate stop condition
CTRLB_STA = 2   ; generate start condition
CTRLB_ENI = 3   ; interrupt enable
CTRLB_ES2 = 4   ; ES1/ES2: which register at offset 0?
CTRLB_ES1 = 5   ;  0/0=S0 (or S0'), 1/0=S2, 0/1=S3
CTRLB_ESO = 6   ; enable serial output
CTRLB_PIN = 7   ; write as 1 to clear all status bits
CTRLF_ACK = $01
CTRLF_STO = $02
CTRLF_STA = $04
CTRLF_ENI = $08
CTRLF_ES2 = $10
CTRLF_ES1 = $20
CTRLF_ESO = $40
CTRLF_PIN = $80
STATB_NBB = 0   ; not bus busy, if cleared, a transmission is going on
STATB_LAB = 1   ; lost arbitration
STATB_AAS = 2   ; addressed as slave, i.e. matching address received
STATB_LRB = 3   ; last received bit, i.e. slave ACK bit
STATB_AD0 = 3   ; when in slave mode: addressed by broadcast (0x00)?
STATB_BER = 4   ; bus error (misplaced start/stop)
STATB_STS = 5   ; external stop condition detected
STATB_PIN = 7   ; is set while a byte transmission is running
STATF_NBB = $01
STATF_LAB = $02
STATF_AAS = $04
STATF_LRB = $08
STATF_AD0 = $08
STATF_BER = $10
STATF_STS = $20
STATF_PIN = $80

; identify the board we use:
VENDOR  = 5001
PRODUCT =   15

; this will become the 2nd half of the Version String:
IDPART2 MACRO
    dc.b ' for ICY controller board',13,10,0
    ENDM
