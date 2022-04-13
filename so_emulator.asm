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

X_REF		equ 4
Y_REF		equ 5
XD_REF		equ 6
YD_REF		equ 7

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
; Dla kazdego rdzenia 
; wskazniki na mozliwe argumenty operacji.
argptr times 8 * CORES dq 0

section .text

op_type: 
dq before_binary_op - op_type 
dq before_unary_op - op_type
dq cflag_op - op_type
dq jmp_op - op_type

binary_op:
dq mov_op - binary_op
dq ignore - binary_op
dq or_op - binary_op
dq ignore - binary_op
dq add_op - binary_op
dq sub_op - binary_op
dq adc_op - binary_op
dq sbb_op - binary_op

unary_op:
dq mov_op - unary_op
dq ignore - unary_op
dq ignore - unary_op
dq xor_op - unary_op
dq add_op - unary_op
dq cmpi_op - unary_op
dq rcr_op - unary_op
 	
; rdi	- wskaznik na pamiec programu,
; rsi	- wskaznik na pamiec danych,
; rdx	- ilosc krokow do wykonania,
; rcx	- identyfikator rdzenia z [1, CORES).
so_emul:
	enter 	0, 0
	push	r10
	push	r11
	push	r12
	push	r13
	push	r14
	push	r15

next:	
	lea	r9, [rel cpu_state] 	; *rdi = state[core];
	lea	r9, [r9 + rcx * SIZEOF_STATE]
	mov	r8, [r9]		; r8 = aktualny stan rdzenia.	

	test	rdx, rdx
	jz	done

	; ---------------------------------------
	; --- Tworzymy tablice wskaznikow -------
	; --- na mozliwe argumenty operacji. ----
	; ---------------------------------------

	xor	r13, r13
	xor	r14, r14
	xor	r15, r15

	; r11 = &argptr[core];
	mov 	rax, rcx
	shl	rax, 6
	lea	r11, [rel argptr]
	lea	r11, [r11 + rax]

	; argptr[core][A_REG] = &(state[core].A);
	lea	r12, [r9 + A_REG]
	mov	[r11 + 8 * A_REG], r12

	; argptr[core][D_REG] = &(state[core].D);
	lea	r12, [r9 + D_REG]
	mov 	[r11 + 8 * D_REG], r12
	; r13b = state[core].D;
	mov	r13b, [r12]

	; argptr[core][X_REG] = &(state[core].X);
	lea	r12, [r9 + X_REG]
	mov	[r11 + 8 * X_REG], r12
	; r14b = state[core].X
	mov 	r14b, [r12]

	; argptr[core][Y_REG] = &(state[core].Y);
	lea	r12, [r9 + Y_REG]
	mov	[r11 + 8 * Y_REG], r12
	; r15b = state[core].Y;
	mov	r15b, [r12]

	; argptr[core][X_REF] = data + state[core].X;
	lea	r12, [rsi + r14]
	mov	[r11 + 8 * X_REF], r12

	; argptr[core][Y_REF] = data + state[core].Y;
	lea	r12, [rsi + r15]
	mov	[r11 + 8 * Y_REF], r12
	
	; argptr[core][XD_REF] = data + state[core].X + state[core].D;
	mov	al, r14b
	add	al, r13b
	lea	r12, [rsi + rax]
	mov	[r11 + 8 * XD_REF], r12

	; argptr[core][YD_REF] = data + state[core].Y + state[core].D;
	mov	al, r15b
	add	al, r13b
	lea	r12, [rsi + rax]
	mov	[r11 + 8 * YD_REF], r12
	; ---------------------------------------

	xor	r10, r10
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
	cmp	r12, 3
	ja	ignore	
	lea  	rax, [rel op_type]
	add	rax, [rax + 8 * r12]
	jmp	rax
before_binary_op:
	mov	r14, [r11 + 8 * r14]	; r14 = argptr[core][arg1_code];
	mov	r15, [r11 + 8 * r15]	; r15 = argptr[core][arg2_code];

	cmp	r13b, 8
	je	xchg_op

	mov	r15b, [r15] 		; r15b = *argptr[core][arg2_code];
	; ------------------------------
	; ----- SWITCH(BINARY_OP) ------
	; ------------------------------
	cmp	r13b, 7
	ja	ignore
	lea	rax, [rel binary_op]
	add	rax, [rax + 8 * r13]
	jmp	rax
before_unary_op:
	mov	r14, [r11 + 8 * r14] 	; r14 = argptr[core][arg1_code];

	; swap(r13b, r15b)
	mov	r10b, r13b
	mov	r13b, r15b
	mov	r15b, r10b
	; ------------------------------
	; ----- SWITCH(UNARY_OP) -------
	; ------------------------------
	cmp	r13b, 7
	ja	ignore
	lea	rax, [rel unary_op]
	add	rax, [rax + 8 * r13]
	jmp	rax
after:
ignore:
	inc	byte [r9 + PC_CT]
	dec	rdx
	jmp	next	
done:
	pop	r15
	pop	r14
	pop	r13
	pop	r12
	pop	r11
	pop	r10

	mov	rax, r8
	leave
	ret

; --------------------------------------
; -------- POMOCNICZE ------------------
; --------------------------------------
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
	jmp	set_carry_flag
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

	shr	al, 1	
	jnc	after
	add 	[r9 + PC_CT], al
	jmp	after

set_flags:
	jnc	clear_carry
	mov	byte [r9 + C_FL], 1
	jmp 	set_zero_flag
clear_carry:
	mov	byte [r9 + C_FL], 0
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
	jmp	after
clear_carry_flag:
	mov	byte [r9 + C_FL], 0
	jmp	after
