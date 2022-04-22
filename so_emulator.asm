; Emulator procesora SO.
; autor: Mateusz Sulimowicz
; MIMUW, 2021.

global so_emul

A_REG		equ 0
D_REG		equ 1
X_REG		equ 2
Y_REG		equ 3
PC_CT		equ 4
C_FL		equ 6
Z_FL		equ 7

BREAK_OP	equ 0xffff

; To jest stan procesora SO.
; struct __attribute__((packed)) so_state_t {
; uint8_t A, D, X, Y, PC;
; uint8_t unused;
; uint8_t C, Z;
; }

SIZEOF_STATE 	equ 8

section .data

; Dla kazdego rdzenia jego stan.
cpu_state times CORES * SIZEOF_STATE db 0

section .text

load_ptr:
	cmp	r11, 3
	ja	.load_dataptr
	lea	rax, [r9 + r11]
	ret
.load_dataptr:
	xor	rax, rax
	cmp	r11, 6
	jb	.load_xy
	mov	al, [r9 + D_REG]
	sub	r11, 2
.load_xy:
	add	al, [r9 + r11 - 2]
	add	rax, rsi
	ret
	
; rdi	- wskaznik na pamiec programu,
; rsi	- wskaznik na pamiec danych,
; rdx	- ilosc krokow do wykonania,
; rcx	- identyfikator rdzenia z [1, CORES).
so_emul:
	push	r12
	push	r13
	push	r14
	push	r15

next:	
	lea	r9, [rel cpu_state] 	; *rdi = state[core];
	lea	r9, [r9 + rcx * SIZEOF_STATE]	

	test	rdx, rdx
	jz	done

	xor	r12, r12
	xor	r13, r13
	xor	r14, r14
	xor	r15, r15

	; ------------------------------
	; Kazda instrukcja jest postaci:
	; [ TYP - 2 bity ]
	; [ A - 3 bity 	 ]
	; [ B - 3 bity   ]
	; [ C - 8 bitow  ]
	; ------------------------------
	mov	r13b, [r9 + PC_CT]	; r13b = state[core].PC;
	mov	r12w, [rdi + 2 * r13]	; r12w = code[r13b];

	inc	byte [r9 + PC_CT]
	dec	rdx

	cmp	r12w, BREAK_OP 		; Instrukcja BRK konczy wykonanie programu.
	je	done

	mov	r13b, r12b 	      	; r13b = pole C.
	shr	r12w, 8

	mov	r14b, r12b
	and	r14b, 0x7 	      	; r14b = pole B.
	shr	r12w, 3

	mov 	r15b, r12b
	and	r15b, 0x7
	shr	r12w, 3			; r15b = pole A.
	; ------------------------------
	; ----- SWITCH(OP_TYPE) --------
	; ------------------------------
	lea  	rax, [rel op_type]
	movsx	r11, word [rax + 2 * r12]
	add	rax, r11
	jmp	rax
before_binary_op:
	mov	r11, r14
	call	load_ptr
	mov	r14, rax

	mov	r11, r15
	call 	load_ptr
	mov	r15, rax

	cmp	r13b, 8
	je	xchg_op

	mov	r15b, [r15] 		; r15b = *argptr[core][arg2_code];
	; ------------------------------
	; ----- SWITCH(BINARY_OP) ------
	; ------------------------------
	lea	rax, [rel binary_op]
	movsx	r11, word [rax + 2 * r13]
	add	rax, r11
	jmp	rax
before_unary_op:
	mov	r11, r14
	call	load_ptr
	mov	r14, rax

	xchg	r13b, r15b
	; ------------------------------
	; ----- SWITCH(UNARY_OP) -------
	; ------------------------------
	lea	rax, [rel unary_op]
	movsx	r11, word [rax + 2 * r13]
	add	rax, r11
	jmp	rax
after:
ignore:
	jmp	next
done:
	pop	r15
	pop	r14
	pop	r13
	pop	r12
	mov	rax, [r9]
	ret

; --------------------------------------
; -------- POMOCNICZE ------------------
; --------------------------------------

op_type: 
dw before_binary_op - op_type 
dw before_unary_op - op_type
dw cflag_op - op_type
dw jmp_op - op_type

binary_op:
dw mov_op - binary_op
dw ignore - binary_op
dw or_op - binary_op
dw ignore - binary_op
dw add_op - binary_op
dw sub_op - binary_op
dw adc_op - binary_op
dw sbb_op - binary_op

unary_op:
dw mov_op - unary_op
dw ignore - unary_op
dw ignore - unary_op
dw xor_op - unary_op
dw add_op - unary_op
dw cmpi_op - unary_op
dw rcr_op - unary_op

mov_op:
	mov	[r14], r15b
	jmp	after
or_op:
	or	[r14], r15b
	jmp	set_zero_flag
xor_op:
	xor	[r14], r15b
	jmp	set_zero_flag
add_op:
	add	[r14], r15b
	jmp	set_zero_flag
sub_op:
	sub	[r14], r15b
	jmp	set_zero_flag
adc_op:
	mov	al, [r9 + C_FL]
	shr	al, 1
	adc	[r14], r15b
	jmp	set_flags
sbb_op:
	mov	al, [r9 + C_FL]
	shr	al, 1
	sbb	[r14], r15b
	jmp	set_flags
xchg_op:
	mov	al, [r15]
   lock xchg	[r14], al
	mov	[r15], al
	jmp	after
cmpi_op:
	cmp	[r14], r15b
	jmp	set_flags
rcr_op:
	mov	al, [r9 + C_FL]
	shr	al, 1
	rcr	byte [r14], 1
	call	set_carry_flag
	jmp	after
cflag_op:
	mov	[r9 + C_FL], r14b
	jmp	after
jmp_op:	
	mov	al, 1
	add	al, r14b
	shr	r14b, 1

	mov	r15b, [r9 + C_FL]
	and	r15b, r14b
	add 	al, r15b
	shr 	r14b, 1

	mov	r15b, [r9 + Z_FL]
	and	r15b, r14b
	add 	al, r15b

	and	al, 1	
	jz	after
	add 	[r9 + PC_CT], r13b
	jmp	after

set_flags:
	call	set_carry_flag
set_zero_flag:
	jnz	clear_zero_flag
	mov	byte [r9 + Z_FL], 1
	jmp	after
clear_zero_flag:
	mov	byte [r9 + Z_FL], 0
	jmp	after

set_carry_flag:
	jnc	clear_carry_flag
	mov	byte [r9 + C_FL], 1
	ret
clear_carry_flag:
	mov	byte [r9 + C_FL], 0
	ret
