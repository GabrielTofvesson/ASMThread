; Non-volatile memory routines
FLASH_base		.field	0x400FD000	; Flash control base address
SYSCONF			.field	0x400FE000	; System memory control base address
WRKEY0			.field	0x71D5		; Write key when BOOTCFG address KEY bit is 0
WRKEY1			.field	0xA442		; Write key when BOOTCFG address KEY bit is 1
FLASH_END		.field	0x3FFFF		; End of flash memory region

; Flash control offsets
FMA				.equ	0x0			; Target address (0x0 - 0x3FFFF)
FMD				.equ	0x4			; Data
FMC				.equ	0x8			; Direct (single) write control  -  Writes 1 word
FMC2			.equ	0x20    	; Buffered (wide) write control  -  Writes up to 32 words
FWB_base		.equ	0x100		; Buffered data base offset (max: 0x17C)
BOOTCFG			.equ	0x1D0		; Boot configuration address offset

	.text
	.thumb
	.global flashtest
	.align 2

;; Writes a value near then end of the flash region
;; Doesn't seem to survive resets, though
;; TODO: Investigate reset-triggered FLASH clearing
flashtest:
	;; Read word
	ldr		r1,FLASH_END
	sub		r1,r1,#8
	ldr		r4,[r1]					; Read last word

	;; Write word
	; Write target address
	ldr		r0,FLASH_base
	str		r1,[r0,#FMA]

	; Write data to add to FLASH
	mvn		r1,r4
	str		r1,[r0,#FMD]

	; Trigger write
	ldr		r1,WRKEY0 				; TODO: Select appropriate WRKEY based on BOOTCFG
	lsl		r1,#0x10
	orr		r1,#1
	str		r1,[r0,#FMC]

flashtest_await_write:
	ldrb	r1,[r0,#FMC]
	tst		r1,#1
	beq		flashtest_complete

flashtest_aight:
	b flashtest_await_write

flashtest_complete:
	bx lr
