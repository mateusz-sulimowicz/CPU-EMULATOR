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
FLAG_OP		equ 0xC000

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

	mov	r13b, [r9 + PC_CT]
	mov	r10w, [rcx + 2 * r13]
	mov	r12w, r10w
	cmp	r10w, BREAK_OP
	je	.done
	
	and	r10w, OP_MASK
	; switch(OPERATION_TYPE)
	cmp	r10w, UNARY_OP
	je	.unary_op
	cmp	r10w, FLAG_OP
	je	.flag_op
	cmp	r10w, JMP_OP
	je	.jmp_op
.binary_op:
	


	jmp	.after
.unary_op:


	jmp	.after
.flag_op:
	shr	r12w, 8
	mov	[r9 + C_FL], r12b
	jmp	.after
.jmp_op:	
	mov	r13b, r12b
	shr	r12w, 8
	

	jmp	.after
.after:
	inc	byte [r9 + PC_CT]
	dec	rdx
	jmp	.next	
.done:
	leave
	ret
