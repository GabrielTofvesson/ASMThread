; Code-style key:
;	[instruction/definition]					; Single-line description
;	;; Section label
;	; Code-block label
;
;
;
;	-- "Function" definition
;	;; Parameters: rX (type)
;	;; Return:	rX (type), [flags] (reason)
;	;; Clobbers: rX-rY
;	;; INFO: General description of what the function does
;
;	-- Note that functions should declare return values as clobbered.
;
;
;	-- Function naming scheme:
;
;	function:							;; Function's entry point
;		[insn]
;	function_localjumplabel:			;; Local jump label
;		[insn]
;	function_localjumplabel_sublabel:	;; Jump label that is a part of (or a child-label of) function_localjumplabel. (Think nested block-statements)
;		[insn]
;	function_end:						;; End of function (if explicit declaration is necessary)
;		[insn]


mvb		.macro dst,imm
		mov		dst,#(:imm(2, $$symlen(imm)): & 0xffff)
		movt	dst,#(:imm(2, $$symlen(imm)): >> 16)
		.endm

daa		.macro adr,imm,c1,c2
		.asg :imm(1):,TMP1
		.asg :imm(2, $$symlen(imm)-1):, LIT1
		.asg :adr(1):,TMP2
		.asg :adr(2, $$symlen(imm)-1):, LIT2
		.if $$symlen(c1) = 0
		.asg r0,c1
		.endif
		.if $$symlen(c2) = 0
		.asg r1,c2
		.endif
		.if $$symcmp(TMP1,"#") = 0 & $$symcmp(TMP2,"#") = 0
		mvb c1,adr
		mov c2,imm
		str c2,[c1]
		.else
		.emsg	"Bad Macro Parameter"
		.endif
		.endm

print	.macro msg
		adr r0,msg
		bl strlen
		adr r0,msg
		bl printstring
		.endm


; UART stuff
RCGCUART		.equ	0x400FE618
RCGCGPIO		.equ	0x400fe608
UART0_UARTIBRD	.equ	0x4000c024
UART0_UARTFBRD	.equ	0x4000c028
UART0_UARTLCRH	.equ	0x4000c02c
UART0_UARTCTL	.equ	0x4000c030
UART0_UARTFR	.equ	0x4000c018
UART0_UARTDR	.equ	0x4000c000
GPIOA_GPIOAFSEL	.equ	0x40004420
GPIOA_GPIODEN	.equ	0x4000451c

STRST		.equ	0x989680
CPERIPH		.equ	0xe000e000
STCTL		.equ	0x010
STRLD		.equ	0x014
STCUR		.equ	0x18
VBASE		.equ	0x20000000		; RAM virtual memory base address
STACK_BASE	.equ	0x20000200
HEAP_END	.equ	0x20007FFF
TMPTR		.field	0x20000200		; Thread MUX config pointer address
TMS			.equ	0x0				; Thread MUX thread count
TMC			.equ	0x4				; Thread MUX current thread
TMF			.equ	0x8				; Thread MUX flag offset
TMV			.equ	0xC				; Thread MUX address vector base address
TCOUNT_MAX	.equ	0x20			; Max thread vector count allowed
TFRAME_SIZE	.equ	0x4				; Thread MUX frame size
;TSTACK_PTR	.equ	0x4				; Thread stack pointer
;TEXEC_PTR	.equ	0x0				; Thread execution address


TEST_MESSAGE:	.string		"Hello, thread",13,10,0

	.text
	.thumb

	;; EXPORTS
	.global main
	.global IntSysTick
	.global startthread
	.global threadexit
	.global threadlock
	.global threadunlock

	;; IMPORTS
	;.global flashtest
	.global gtmalloc
	.global minit
	.global free
	.global memcpy
	.global memset

	.align 2

main:
	; Initialize peripherals
	bl		inituart

	; Initialize gtmalloc range
	bl		minit

	; Allocate TMUX data
	mov		r0,#(0xC + (TCOUNT_MAX * TFRAME_SIZE))
	bl		gtmalloc
	mov		r0,r1

	; Clear data pointed to by r0
	push	{r0}
	mov		r2,#(0xC + (TCOUNT_MAX * TFRAME_SIZE))
	mov		r1,#0
	bl		memset
	pop		{r0}


	; Initialize Thread MUX Size value to 1 (main thread)
	ldr		r1,TMPTR
	str		r0,[r1]
	mov		r1,#1
	str		r1,[r0,#TMS]

	; Initialize Thread MUX Current (int) to 0
	mov		r1,#0
	str		r1,[r0,#TMC]

	; Thread execution address and stack are inferred from the blank frame
	;str		r1,[r0,#TMV]
	;str		r1,[r0,#(TMV + 4)]


	; Enable SysTick (and thereby the thread management subsystem)
	cpsid	i								; disable interrupts

	mvb		r1,#CPERIPH
	mvb 	r0,#STRST						; Set up SysTick to start counting down from STRST (max 24 bits)
	str 	r0,[r1,#STRLD]
	str		r0,[r1,#STCUR]

	ldr 	r0,[r1,#STCTL]
	orr 	r0,#0x7							; Enable system interrupt, set source to system clock (80 MHz), enable timer
	str 	r0,[r1,#STCTL]

	cpsie	i								; enable interrupts

	; Run thread test
	adr		r0,test_thread
	bl 		startthread

loop:	; Wait forever
	b loop

	.align 4

test_thread:
	print TEST_MESSAGE
	b threadexit							; No need to bl since this is the end of the thread anyway

	.align 2

;; Parameters: r0 (thread routine address)
;; Return: r0 (non-zero if succeeded)
;; Clobbers: r0-r6
;; INFO: This adds a new entry to the thread multiplexing vector. In the case
;;		 where (for some reason) there is an attempt >=2**32 threads, r0 will
;;		 be returned as 0 to indicate that an overflow was caught. This also
;;		 implies that the thread wasn't created, but that the program will
;;		 continue to execute as normal.
startthread:
	push 	{r0,lr}
	bl 		threadlock			; Ensure changes to TMUX data don't change while we are updating them

	ldr		r0,[r1,#TMS]		; Get current thread count
	mov		r2,r0				; Duplicate it for future use
	add		r0,r0,#1
	cmp		r0,#TCOUNT_MAX
	beq		startthread_end	; If C-flag is set, then r0 == 0 and no more threads can be created: return

	str		r0,[r1,#TMS]
	mov		r0,#TFRAME_SIZE
	mul		r2,r2,r0			; Multiply r2 by TFRAME_SIZE to get address offset for next thread address entry

	pop		{r0}
	push	{r1, r2}

	bl		initthreadstack		; Allocate a blank (but valid) thread stack

	pop 	{r1, r2}			; Restore addresses
	add		r1,r1,r2
	add		r1,r1,#TMV

	str		r4,[r1]				; Store stack data pointer to threa frame

startthread_end:
	bl 		threadunlock
	pop 	{pc}



;; Parameters: void
;; Return: void
;; Clobbers: r0-r1
threadlock:
	ldr		r1,TMPTR
	ldr		r1,[r1]
	ldr		r0,[r1,#TMF]
	orr		r0,#1
	str		r0,[r1,#TMF]
	bx lr



;; Parameters: void
;; Return: void
;; Clobbers: r0-r2
threadunlock:
	ldr		r1,TMPTR
	ldr		r1,[r1]
	mvn		r2,#1
	ldr		r0,[r1,#TMF]
	and		r0,r0,r2
	str		r0,[r1,#TMF]
	bx lr


;; Parameters: void
;; Return: doesn't
;; Clobbers: N/A
threadexit:
	; Mark this thread for termination by the thread handler
	ldr		r1,TMPTR
	ldr		r1,[r1]

	; Thread0 cannot be killed; just sit in an infinite loop instead
	ldr		r0,[r1,#TMC]
	cmp		r0,#0
	beq		threadexit_wait

	ldr		r0,[r1,#TMF]
	orr		r0,#2
	str		r0,[r1,#TMF]

	; Set SysTick counter to 0 (trigger SysTick interrupt)
	mvb		r1,#CPERIPH
	mov		r0,#0
	str		r0,[r1]
threadexit_wait:
	; Wait for imminent SysTick interrupt to take over
	b threadexit_wait



	.align 2
IntSysTick:
	; CPU pushes some registers here (before ISR state is set and PC is changed):
	; push	{r0-r3, ip, lr, pc, CPSR}
	; Check if we are interrupting an interrupt
	mvn		r0,#6
	cmp		r0,lr
	it		ne
	bxne	lr

	; Check if there are any threads to multiplex. If not, just return
	ldr		r0,TMPTR
	ldr		r0,[r0]
	ldr		r1,[r0,#TMS]							; Load current thread count
	cmp		r1,#1
	it		eq
	bxeq	lr

	; Check if thread-lock flag is set. If so, return to active thread
	ldr		r2,[r0,#TMF]
	tst		r2,#1
	it		ne
	bxne	lr

	; Check if thread-kill flag is set; if so, remove thread from address vector
	tst		r2,#2
	beq		IntSysTick_save
	ldr		r2,[r0,#TMC]
	sub		r1,#1
	cmp		r1,r2									; Check if we are going to loop back to Thread1 after ISR
	bne		IntSysTick_fulldelete

	sub		r2,#1
	str		r2,[r0,#TMC]
	str		r1,[r0,#TMS]
	b		IntSysTick_loadnext

IntSysTick_fulldelete:
	; Move future threads down to this one's position
	push	{r0-r3, lr}

	; Compute current frame offset and how many frames to copy
	mov		r3,r1
	mov		r1,r2
	mov		r2,r3
	mov		r3,#TFRAME_SIZE
	sub		r2,r2,r1
	mul		r1,r3
	mul		r2,r3

	; Get thread vector address
	add		r0,#TMV

	; Offset base vector address by the current frame address
	add		r1,r1,r0

	; Get address of next frame
	add		r0,r1,#TFRAME_SIZE

	; Copy future frames to current frame address
	bl		memcpy

	pop		{r0-r3, lr}

	b 		IntSysTick_loadnext

IntSysTick_save:
	;; Store the current stack
	; Compute frame offset and save link register value as current frame execution address pointer
	mov		r3,#TFRAME_SIZE
	mul		r2,r2,r3
	add		r2,r2,r0
	add		r2,r2,#TMV

	mov		r3,r0

	push 	{r4-r11}								; Push all the otherwise un-pushed registers (except SP because it's special)
	mvb		r0,#STACK_BASE
	sub		r0,r0,sp								; Compute stack size that needs to be saved
	add		r0,r0,#4								; Include SP in stack metadata

	push	{r0, r2, r3}
	bl		gtmalloc
	pop		{r0, r2, r3}

	; r0 = gtmalloc size
	; r1 = gtmalloc ptr
	; r2 = pointer to current thread frame
	; r3 = thread control base address

	push	{r0-r3}

	sub		r0,#4
	mov		r2,r0
	mov		r0,sp
	add		r0,r0,#16
	add		r1,r1,#4

	; Copy all stack values except sp
	bl 		memcpy

	pop		{r0-r3}

	; Save sp to thread stack copy
	str		sp,[r1]

	; Save thread stack copy pointer to frame
	str		r1,[r2]

IntSysTick_loadnext:
	;; Load the next stack
	; Load a fresh thread control pointer
	ldr		r0,TMPTR
	ldr		r0,[r0]
	ldr		r2,[r0,#TMC]
	ldr		r1,[r0,#TMS]
	sub		r1,r1,#1
	cmp		r1,r2									; Check if we are going to loop back to Thread0 after ISR
	ite		eq
	eoreq	r2,r2
	addne	r2,#1

	str		r2,[r0,#TMC]

	; Check frame integrity
	mov		r3,#TFRAME_SIZE
	mul		r2,r3
	add		r2,r2,r0
	add		r2,r2,#TMV
	ldr		r0,[r2]									; Load stack data pointer for thread to be run


	ldr		r1,[r0]									; Copy thread's stack pointer into r1
	mov		sp,r1									; Activate thread's stack

	; Copy thread's stack into active stack region
	push	{r0-r2}
	mvb		r2,#STACK_BASE
	sub		r2,r2,r1
	add		r0,#4

	bl		memcpy
	pop		{r0-r2}




	push	{r2}
	bl		free									; Free thread stack-copy pointer
	pop		{r2}

	mvn		lr,#6									; lr = 0xFFFFFFF9 	// address informs processor that it should read return address from stack

	pop		{r4-r11}								; Pop values that aren't auto-popped

	;; Resume thread at the given address
	bx lr




;; Parameters: r0 (str), r1 (uint32_t)
;; Return: void
;; Clobbers: r0-r5
;; INFO: Prints a string of a given length to UART0 serial bus
printstring:							; void printstring(char * r0, uint32_t r1){
	mvb r2,#UART0_UARTFR				; 	r2 = UART0_UARTFR; 						// UART0 Flags
	mvb r3,#UART0_UARTDR				;	r3 = UART0_UARTDR; 						// UART0 Data address
	add r1,r0							;	r1 += r0;								// r1 now holds the address of the first byte after the string
printstring_loop:						; 	while (true) {
	cmp r0,r1							;		if(r0 == r1)						// Check if more bytes can be read
	beq printstring_end					;			break;
	ldrb r4,[r0],#1						; 		r4 = (char) *(r0++);				// Put next char in r4
printstring_printchar_loop:				; 		while(true){
	ldr r5,[r2]							; 			r5 = *r2;						// Read UART0 status flags
	ands r5,r5,#0x20					; 			r5 &= 0x20;						// Only get 6th flag bit
	bne printstring_printchar_loop		; 			if(r5 != 0x20) continue;		// If bit isn't set, UART0 isn't done flushing
										;			break;
										;		}
	str r4,[r3]							; 		*r3 = r4;							// Write character to UART0 data address
	b printstring_loop					; 		continue;
printstring_end:						; 	}
	bx lr								; 	return;
										; }

;; Parameters: r0 (str)
;; Return: r1 (uint32_t)
;; Clobbers: r1, r2
;; INFO: Computes the length of a given C-style string.
strlen:									; uint32_t strlen(char * r0) {
	mov r1,r0							; 	r1 = r0;
strlen_loop:							; 	while(true){
	ldrb r2,[r0], #1					; 		r2 = (char) *(r0++);
	cmp r2,#0							; 		if(r2 != 0)
	bne strlen_loop						; 			continue;
strlen_endloop:							; 	}
	sub r1,r0,r1						; 	r1 = r0 - r1;
	bx lr								; 	return r1;
										; }

;; Parameters: void
;; Return: void
;; Clobbers: r0, r1
;; INFO: Initialize UART0 communication bus at 115200 baud.
inituart:
	daa #RCGCUART,#0x01						; Koppla in serieport

	mvb r1,#RCGCGPIO						; Koppla in GPIO port A
	ldr r0,[r1]
	orr r0,r0,#0x01
	str r0,[r1]

	nop										; vänta lite
	nop
	nop

	daa #GPIOA_GPIOAFSEL,#0x03				; pinnar PA0 och PA1 som serieport
	daa #GPIOA_GPIODEN,#0x03				; Digital I/O på PA0 och PA1
	daa #UART0_UARTIBRD,#0x08				; Sätt hastighet till 115200 baud
	daa #UART0_UARTFBRD,#44					; Andra värdet för att få 115200 baud
	daa #UART0_UARTLCRH,#0x60				; 8 bit, 1 stop bit, ingen paritet, ingen FIFO
	daa #UART0_UARTCTL,#0x0301				; Börja använda serieport

	bx  lr

;; Parameters: r0 (thread pc)
;; Return: r4 (ptr)
;; Clobbers: r0-r6
;; INFO: Generate a blank stack frame
initthreadstack:
	push	{r0, lr}						; Save argument and return address

	; Allocate thread stack
	mov		r0,#0x44
	bl		gtmalloc
	mov		r4,r1

	; Clear thread stack data
	mov		r2,#0x38
	mov		r0,r1
	add		r0,#4
	mov		r1,#0
	bl		memset

	pop		{r0}							; Restore argument

	; Save thread's PC (argument) to blank stack
	str		r0,[r4,#0x3C]

	; Save a valid CPSR to the blank stack
	mvb		r0,#0x81000000
	str		r0,[r4,#0x40]

	; Save a valid stack pointer
	mvb		r0,#(STACK_BASE - 0x40)
	str		r0,[r4]

	pop		{pc}							; Fast return
