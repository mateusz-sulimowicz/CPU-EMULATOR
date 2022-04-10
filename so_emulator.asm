global so_emul

A_REG		equ 0
D_REG		equ 1
X_REG		equ 2
Y_REG		equ 3
PC_CT		equ 4
C_FL		equ 6
Z_FL		equ 7

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
; Wskazniki na mozliwe argumenty operacji.
argptr times 8 * CORES dq 0

section .text

; rdi 	- wskaznik na output,
; rsi	- wskaznik na pamiec programu,
; rcx	- wskaznik na pamiec danych,
; rdx	- ilosc krokow do wykonania,
; r8	- identyfikator rdzenia z [0, CORES).
so_emul:
	enter	0, 0
	
	; *rdi = state[core];
	mov	r10, [state + r8 * SIZEOF_STATE]
	mov 	[rdi], r10	

.next_op:
	test	rdx, rdx
	jz	.done

	; --- Tworzymy tablice wskaznikow -------
	; --- na potencjalne argumenty operacji.

	xor	r13, r13;
	xor	r14, r14;
	xor	r15, r15;

	; r11 = argptr[core];
	mov 	rax, r8
	shl	rax, 6
	lea	r11, [argptr + rax]

	lea	r12, [state + r8 * SIZEOF_STATE + A_REG]
	mov	[r11 + A_REG], r12

	





.binary_op:
.unary_op:
.flag_op:
.jmp_op:	


.done:
	leave
	ret
