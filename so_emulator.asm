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

OP_MASK		equ 0xC000
BINARY_OP	equ 0x0000
UNARY_OP	equ 0x4000
JMP_OP		equ 0x8000
CFLAG_OP	equ 0xC000

MOV_OP		equ 0
OR_OP		equ 2
XOR_OP		equ 3
ADD_OP		equ 4
SUB_OP		equ 5
ADC_OP		equ 6
SBB_OP		equ 7
XCHG_OP		equ 8

CMPI_OP		equ 5
RCRI_OP		equ 6

; To jest stan procesora SO.
; struct __attribute__((packed)) so_state_t {
; uint8_t A, D, X, Y, PC;
; uint8_t unused;
; uint8_t C, Z;
; }

SIZEOF_STATE 	equ 8

section .data

; Dla kazdego rdzenia jego stan.
state times CORES * SIZEOF_STATE db 0
; Dla kazdego rdzenia 
; wskazniki na mozliwe argumenty operacji.
argptr times 8 * CORES dq 0

section .text

; rdi 	- wskaznik na output,
; rsi	- wskaznik na pamiec programu,
; rcx	- wskaznik na pamiec danych,
; rdx	- ilosc krokow do wykonania,
; r8	- identyfikator rdzenia z [0, CORES).
so_emul:
	enter	0, 0

.next:	
	; *rdi = state[core];
	lea	r9, [state + r8 * SIZEOF_STATE]
	mov	r10, [r9]
	mov 	[rdi], r10	

	test	rdx, rdx
	jz	.done

	; --- Tworzymy tablice wskaznikow -------
	; --- na potencjalne argumenty operacji.

	xor	r13, r13
	xor	r14, r14
	xor	r15, r15

	; r11 = &argptr[core];
	mov 	rax, r8
	shl	rax, 6
	lea	r11, [argptr + rax]

	; argptr[core][A_REG] = &(state[core].A);
	lea	r12, [r9 + A_REG]
	mov	[r11 + A_REG], r12

	; argptr[core][D_REG] = &(state[core].D);
	lea	r12, [r9 + D_REG]
	mov 	[r11 + D_REG], r12
	; r13b = state[core].D;
	mov	r13b, [r12]

	; argptr[core][X_REG] = &(state[core].X);
	lea	r12, [r9 + X_REG]
	mov	[r11 + X_REG], r12
	; r14b = state[core].X
	mov 	r14b, [r12]

	; argptr[core][Y_REG] = &(state[core].Y);
	lea	r12, [r9 + Y_REG]
	mov	[r11 + Y_REG], r12
	; r15b = state[core].Y;
	mov	r15b, [r12]

	; argptr[core][X_REF] = data + state[core].X;
	lea	r12, [rcx + r14]
	mov	[r11 + X_REF], r12

	; argptr[core][Y_REF] = data + state[core].Y;
	lea	r12, [rcx + r15]
	mov	[r11 + Y_REF], r12
	
	; argptr[core][XD_REF] = data + state[core].X + state[core].D;
	mov	al, r14b
	add	al, r13b
	lea	r12, [rcx + rax]
	mov	[r11 + XD_REF], r12

	; argptr[core][YD_REF] = data + state[core].Y + state[core].D;
	mov	al, r15b
	add	al, r13b
	lea	r12, [rcx + rax]
	mov	[r11 + YD_REF], r12

	; ---------------------------------------

	xor	r10, r10
	xor	r12, r12

	; Kazda instrukcja jest postaci:
	; [ TYP - 2 bity ][ A - 3 bity ][ B - 3 bity ][ C - 8 bitow ]

	mov	r13b, [r9 + PC_CT] ; r13b = state[core].PC;
	mov	r10w, [rcx + 2 * r13] ; r10w = code[r13b];
	mov	r12w, r10w ; r12w = tresc instrukcji.

	cmp	r10w, BREAK_OP ; Instrukcja BRK konczy wykonanie programu.
	je	.done

	mov	r13b, r12b ; r13b = pole C.
	shr	r12w, 8

	mov	r14b, r12b
	and	r14b, 0x7 ; r14b = pole B.
	shr	r12w, 3

	mov 	r15b, r12b ; r15b = pole A.

	and	r10w, OP_MASK ; r10w = pole TYP i 14 zer.

	; ---- switch(operation_type)
	cmp	r10w, CFLAG_OP
	je	.cflag_op
	cmp	r10w, JMP_OP
	je	.jmp_op

	mov	r14, [r11 + r14] ; r14b = argptr[core][arg1_code];
	cmp	r10w, UNARY_OP
	je	.unary_op
.binary_op:
	mov	r15, [r11 + r15]
	mov	r15b, [r15] ; r15b = *argptr[core][arg2_code];

	cmp	r13b, SUB_OP
	je	.sub
	cmp	r13b, ADC_OP
	je	.adc
	cmp	r13b, SBB_OP
	je	.sbb
	cmp	r13b, XCHG_OP
	je	.xchg
	jmp	.common ; default common
.sub:
	sub	[r14], r15b
	jmp	.modify_zero_flag
.adc: ;TODO
	jmp	.after
.sbb: ;TODO
	jmp	.after
.xchg:; TODO
	jmp	.after
.unary_op:
	; ---- swap(r13b, r15b) ----
	mov	r10b, r13b
	mov	r13b, r15b
	mov	r15b, r10b
	; --------------------------

	cmp	r13b, CMPI_OP
	je	.cmpi
	cmp	r13b, RCRI_OP
	je	.rcri
.common:
	; ---- switch(op_num) ------
	cmp	r13b, OR_OP
	je	.or
	cmp	r13b, XOR_OP
	je	.xor
	cmp	r13b, ADD_OP
	je	.add
	; default .mov
	; --------------------------
.mov:
	mov	[r14], r15b
	jmp	.after
.or:
	or	[r14], r15b
	jmp	.modify_zero_flag
.xor:
	xor	[r14], r15b
	jmp	.modify_zero_flag
.add:
	add	[r14], r15b
	jmp	.modify_zero_flag
.cmpi:
	xor	r13b, r13b
	cmp	[r14], r15b
	adc	r13b, 0
	mov 	[r9 + C_FL], r13b
	cmp	[r14], r15b
	jmp	.modify_zero_flag
.rcri:
	mov	r13b, [r9 + C_FL]
	shr	r13b, 1
	rcr	byte [r14], 1
	adc	r13b, 0
	mov 	[r9 + C_FL], r13b
	jmp	.after
.cflag_op:
	mov	[r9 + C_FL], r14b
	jmp	.after
.jmp_op:	
	mov	al, 1
	; TODO petla?
	add	al, r14b
	shr	r14b, 1

	mov	r15b, [r9 + C_FL]
	and	r15b, r14b
	add 	al, r15b
	shr 	r14b, 1

	mov	r15b, [r9 + Z_FL]
	and	r15b, r14b
	add 	al, r14b

	and	al, 1	
	mul	r13b ; TODO bez mnozenia
	add 	[r9 + PC_CT], al
	jmp	.after
.modify_zero_flag:
	jnz	.clear_zero
.set_zero:
	mov	byte [r9 + Z_FL], 1
	jmp	.after
.clear_zero:
	mov	byte [r9 + Z_FL], 0
.after:
	inc	byte [r9 + PC_CT]
	dec	rdx
	jmp	.next	
.done:
	leave
	ret
