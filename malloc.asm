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


	.text
	.thumb

	;; EXPORTS
	.global gtmalloc
	.global free
	.global minit
	.global memcpy
	.global memset

	.align 2

vMB					.equ	0x20000204
vME					.equ	0x20007FFF
u15_mask			.equ	0x7FFF

SIZE_MALLOC_META	.equ	0x2						; malloc block header metadata size
SIZE_MALLOC_HEAD	.equ	SIZE_MALLOC_META * 2	; malloc block header size
MALLOC_BASE			.field	vMB						; malloc base address
MALLOC_END			.field	vME						; malloc end address
MALLOC_MAX			.field	vME - vMB				; malloc max allocation size

;; Parameters: r0 (size)
;; Return: r1 (ptr)
;; Clobbers: r0-r6
;; INFO: Allocates a sequence of bytes at the returned address that has a
;;		 length that is at least equal to that which was supplied in r0.
gtmalloc:
	ldr		r1,MALLOC_BASE
	mov		r3,#u15_mask

malloc_find:	;; Find a malloc block that fits the required size
	ldrh	r2,[r1,#SIZE_MALLOC_META]				; Load 'current' field from header
	tst		r2,#0x8000
	bne		malloc_find_next
	cmp		r2,r0
	bcc		malloc_find_next
	b 		malloc_found
malloc_find_next:
	; Mask out 'allocated' bit
	and		r2,r2,r3

	; Point to next header
	add		r1,r1,r2
	add		r1,#SIZE_MALLOC_HEAD

	; Check if next header is valid
	ldr		r2,MALLOC_END
	cmp		r1,r2
	beq 	malloc_error
	b 		malloc_find
malloc_found:
	; Mask out 'allocated' bit
	;and		r2,r2,r3

	; Point to next header (in r2)
	add		r2,r1,r2
	add		r2,#SIZE_MALLOC_HEAD

	; r1 = 'adr'
	; r2 = 'next'

	ldrh	r4,[r1,#SIZE_MALLOC_META]				; Load 'current' field from 'adr' header
	and		r4,r3
	; r4 = adr->current.size

	; Check if we have to overcommit
	add		r0,#4
	cmp		r4,r0
	sub		r0,#4
	bcc		malloc_found_overcommit

	; r0 = 'total_allocated'

	; Check if 'adr' is the last valid header in the heap
	ldr		r3,MALLOC_END
	cmp		r2,r3
	beq		malloc_found_lasthead
	b		malloc_found_regular

malloc_found_overcommit:
	mov		r0,r4
	; r0 = 'total_allocated'
	b 		malloc_end

malloc_found_lasthead:
	; next = adr + sizeof(malloc_head) + size;
	add		r2,r1,r0
	add		r2,r2,#SIZE_MALLOC_HEAD

	ldr		r3,MALLOC_END
	sub		r3,r3,r2
	sub		r3,r3,#SIZE_MALLOC_HEAD
	strh	r3,[r2,#SIZE_MALLOC_META]
	b		malloc_end

malloc_found_regular:
	add		r3,r1,r0
	add		r3,r3,#SIZE_MALLOC_HEAD
	; r3 = 'new_next'

	mov		r4,r2
	sub		r4,r4,r3
	sub		r4,r4,#SIZE_MALLOC_HEAD
	; r4 = next - (new_next + sizeof(malloc_head));

	mov		r6,#u15_mask
	ldrh 	r5,[r2,#SIZE_MALLOC_META]
	tst		r5,#0x8000
	and		r5,r5,r6
	bne		malloc_found_regular_nextalloc

	add		r4,r4,r5
	add		r4,r4,#SIZE_MALLOC_HEAD
	strh	r4,[r3,#SIZE_MALLOC_META]

	b malloc_found_end

malloc_found_regular_nextalloc:
	strh	r4,[r3,#SIZE_MALLOC_META]
	strh	r4,[r2]

malloc_found_end:
	mov		r2,r3

malloc_end:		;; Finalizes double-linked list headers and returns
	orr		r0,#0x8000
	str		r0,[r1,#SIZE_MALLOC_META]
	strh	r0,[r2]

	add		r1,#SIZE_MALLOC_HEAD

	bx 		lr


malloc_error:	;; Return NULL
	mov		r1,#0
	bx 		lr




;; Parameters: r0 (ptr)
;; Return: void
;; Clobbers: r0-r5
;; INFO: Frees a resource at a given pointer
free:
	sub		r0,#SIZE_MALLOC_HEAD
	ldrh	r1,[r0,#SIZE_MALLOC_META]
	mov		r2,#u15_mask
	and		r1,r1,r2
	mov		r4,r1
	add		r1,r1,r0
	add		r1,#SIZE_MALLOC_HEAD

	mov		r5,#0			; Mark that next block shouldn't be changed

	; Check if next head is, in fact, the end of the heap
	ldr		r2,MALLOC_END
	cmp		r1,r2
	beq		free_mergeprev_last

	; Check if we can merge the next block with the block being freed
	ldrh	r3,[r1,#SIZE_MALLOC_META]
	tst		r3,#0x8000
	bne		free_mergeprev_notlast

	; Add next block's size + header size to current block
	mov		r2,#u15_mask
	and		r3,r3,r2
	add		r4,r4,r3
	add		r4,r4,#SIZE_MALLOC_HEAD
	b 		free_mergeprev_last

free_mergeprev_notlast:
	ldrh	r3,[r1]				; Get 'next' blocks 'previous' field
	mov		r5,#u15_mask
	and		r3,r3,r5
	mov		r5,r1				; Mark that next block should be updated

free_mergeprev_last:	;; Check if we can merge the block being freed with the previous block
	; Check if there is a previous block
	ldr		r2,MALLOC_BASE
	cmp		r0,r2
	beq		free_end

	; Check if previous block is allocated or not
	ldrh	r1,[r0]
	tst		r1,#0x8000
	bne		free_end

	; Add previous block's size to the size: we're going to make the previous block the "master" now
	add		r4,r4,r1
	add		r4,r4,#SIZE_MALLOC_HEAD

	; Shift free pointer back to previous block head
	sub		r0,r0,r1
	sub		r0,r0,#SIZE_MALLOC_HEAD

free_end:
	; Store size and unset 'allocated' bit
	strh	r4,[r0,#SIZE_MALLOC_META]

	; Check if 'next' head has to be updated
	cmp		r5,#0
	it		eq
	bxeq	lr

	strh	r4,[r5]

	bx lr

;; Parameters: void
;; Return: void
;; Clobbers: r0-r1
;; INFO: Clears first metadata address for use by malloc.
minit:
	ldr		r0,MALLOC_BASE
	ldr 	r1,MALLOC_MAX
	sub		r1,#SIZE_MALLOC_HEAD
	lsl		r1,#16
	str		r1,[r0]
	bx lr



;; Parameters: r0 (const ptr), r1 (ptr), r2 (len)
;; Return: void
;; Clobbers: r0-r3
;; INFO: Copies (r2) bytes from r0 to r1.
memcpy:						;; Initialization
	add		r3,r0,r2

memcpy_loop:				;; Word-wise data copy
	sub		r2,r3,r0
	cmp		r2,#4
	bcc		memcpy_small
	ldr		r2,[r0]
	str		r2,[r1]
	add		r0,#4
	add		r1,#4
	b		memcpy_loop

memcpy_small:				;; Sub-word data copy
	cmp		r2,#0
	it		eq
	bxeq	lr

	cmp		r2,#1
	ittt	eq
	ldrbeq	r3,[r0]
	strbeq	r3,[r1]
	bxeq	lr

	ldrh	r3,[r0]
	strh	r3,[r1]

	cmp		r2,#3
	ittt	eq
	ldrbeq	r3,[r0,#2]
	strbeq	r3,[r1,#2]
	bxeq	lr

	ldrh	r3,[r0,#2]
	strh	r3,[r1,#2]

	bx lr


;; Parameters: r0 (ptr), r1 (byte), r2 (len)
;; Return: void
;; Clobbers: r0-r3
;; INFO: Overwrites 'r2' bytes at the address specified by r0 with the lowest
;;		 byte in r1.
memset:
	; Copy lowest byte in r1 to all 4 bytes in r1
	and		r1,#0xFF
	mov		r3,#0x101
	movt	r3,#0x101
	mul		r1,r1,r3

	; Compute end of write range
	add		r3,r0,r2
memset_loop:
	sub		r2,r3,r0
	cmp		r2,#4
	bcc		memset_small
	str		r1,[r0]
	add		r0,#4
	b		memset_loop

memset_small:
	cmp		r2,#1
	it		cc
	bxcc	lr

	itt		eq
	strbeq	r1,[r0]
	bxeq	lr

	strh	r1,[r0]

	cmp		r2,#3
	itt		eq
	strbeq	r1,[r0,#2]
	bxeq	lr

	strh	r1,[r0,#2]

	bx lr
