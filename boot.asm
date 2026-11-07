[bits 16]
[org 0x7C00]

; DI = cmdbuf idx

;;;;;;;;;;;;;;;;;;
;;;            ;;;
;;;  SECTOR 1  ;;;
;;;            ;;;
;;;;;;;;;;;;;;;;;;

init:
	mov [boot_drive], dl  ; save boot drive (DL)

	cli                   ; disable (clear) interrupts
    xor ax, ax
    mov ds, ax            ; data segment  -> 0
    mov es, ax            ; extra segment -> 0
    mov ss, ax            ; stack segment -> 0
    mov sp, 0x7C00        ; stack ptr     -> 0x7C00
    sti                   ; enable (start) interrupts

; DI = retry counter
xor di, di
init_sectors:
    xor ax, ax
    mov es, ax
    mov bx, 0x7E00

    mov ah, 0x02          ; read sector
    mov al, 0x02          ; number of sectors
    mov ch, 0x00          ; cylinder 0
    mov dh, 0x00          ; head     0
    mov cl, 0x02          ; sector   2
	mov dl, [boot_drive]  ; load boot drive (DL)
    int 0x13              ; BIOS disk

	jnc pre_prompt        ; if (!carry): pre_prompt();
	inc di  ; (always happens)
	cmp di, 8             ; if (DI != 8):
	jne init_sectors      ; init_sectors();

pre_prompt:
	jmp CMD_help

prompt:
	xor di, di  ; start of cmdbuf

	; fancy prompt text
	mov al, [promptchar]
	call putc
	mov al, ' '
	call putc

	.input:
		mov ah, 0x00               ; keypress
		int 0x16                   ; BIOS keyboard

		cmp ah, 0x1C               ; if (AH == SCAN_ENTER):
		je .enter                  ; .enter();

		cmp ah, 0x0E               ; if (AH == SCAN_BACKSPACE):
		je .backspace              ; .backspace();

		cmp di, 32                 ; if (DI >= 32):
		jge .input                 ; .input();

		mov [cmdbuf + di], al      ; save ASCII symbol to cmdbuf
		inc di                     ; increment cmdbuf idx

		call putc                  ; visual echo (guess what? AL already contains the ASCII symbol!)
		jmp .input
	.backspace:
		cmp di, 0                  ; if (DI == 0):
		je .input                  ; .input();

		dec di                     ; decrement cmdbuf idx
		mov byte [cmdbuf + di], 0  ; replace with nothing

		; visuals
		mov al, 0x08               ; move back
		call putc
		mov al, ' '                ; replace with space
		call putc
		mov al, 0x08               ; move back
		call putc

		jmp .input
	.enter:
	call putnl

	; command branches
	mov byte al, [cmdbuf]  ; AL -> cmdbuf[0]

	; CMD_null
	cmp al, 0
	je prompt

	; CMD_help
	cmp al, '?'
	je CMD_help

	; CMD_comment
	cmp al, '#'
	je CMD_comment

	; CMD_clear
	cmp al, 'c'
	je CMD_clear

	; CMD_ascii
	cmp al, '@'
	je CMD_ascii

	; CMD_promptchar
	cmp al, '&'
	je CMD_promptchar

	; CMD_slot
	cmp al, '$'
	je CMD_slot

	; CMD_shutoff
	cmp al, '-'
	je CMD_shutoff

	; Invalid command
	mov al, '?'
	call putc
	call putnl

	.completed:
		xor di, di  ; cmdbuf idx = 0;
		.step:
			mov byte al, [cmdbuf + di]  ; AL -> cmdbuf[DI]
			cmp al, 0                   ; if (AL == 0):
			je .done                    ; .done();

			mov byte [cmdbuf + di], 0   ; reset char
			inc di                      ; increment cmdbuf idx
			jmp .step
		.done:
	jmp prompt

CMD_help:
	mov bx, help
	call puts

	jmp prompt.completed

CMD_comment:
	mov bx, cmdbuf+1
	call puts
	call putnl

	jmp prompt.completed

CMD_clear:
	mov ah, 0x06  ; scroll up
	mov al, 0x00  ; entire window
	mov bh, 0x07  ; white-on-black
	mov ch, 0     ; ul-row
	mov cl, 0     ; ul-col
	mov dh, 24    ; lr-row
	mov dl, 79    ; lr-col
	int 0x10      ; BIOS interrupt

	mov ah, 0x02  ; set cursor position
	mov bh, 0x00  ; page
	mov dh, 0     ; row
	mov dl, 0     ; col
	int 10h       ; BIOS interrupt

	jmp prompt.completed

CMD_ascii:
	mov al, 0x20  ; char = ' ';
	.step:
		cmp al, 0x7F  ; if (AL == 0x7F):
		je .done      ; .done();

		call putc
		inc al
		jmp .step
	.done:
	call putnl

	jmp prompt.completed

CMD_promptchar:
	mov bx, cmdbuf
	call strlen
	cmp di, 2     ; if (strlen(cmdbuf+1) == 2):
	je .nosyntax  ; .nosyntax();

	.syntax:
		mov al, '&'
		call putc
		mov al, '?'
		call putc
		call putnl

		jmp prompt.completed
	.nosyntax:

	xor bx, bx            ; BX -> 0
	mov bl, [cmdbuf + 1]  ; BL -> cmdbuf[1]
	mov [promptchar], bl  ; promptchar -> BL

	jmp prompt.completed

CMD_slot:
	mov byte al, [cmdbuf + 1]  ; AL -> cmdbuf[1]

	cmp al, 'a'
	jne .noalloc
	.alloc:
		mov al, 1
		call slot_alloc

		jmp prompt.completed
	.noalloc:

	cmp al, 'f'
	jne .nofree
	.free:
		mov al, 1
		call slot_free

		jmp prompt.completed
	.nofree:

	cmp al, 's'
	jne .nostatus
	.status:
		mov al, 1
		call slot_status

		cmp ah, 0
		je .notallocd
		mov bx, allocd_t
		jmp .allocdlog
		.notallocd: mov bx, allocd_f
		.allocdlog: call puts

		jmp prompt.completed
	.nostatus:

	mov al, '$'
	call putc
	mov al, '?'
	call putc
	call putnl

	jmp prompt.completed

CMD_shutoff:
	; connect to APM interface
    mov ax, 0x5301  ; APM connect interface
    xor bx, bx      ; device ID (0: system BIOS)
    int 0x15        ; BIOS power management
	jc .legacy      ; if (carry): .legacy();

    ; enable power management
    mov ax, 0x5308  ; enable/disable power management
    mov bx, 0x0001  ; all devices (1)
    mov cx, 0x0001  ; enable      (1)
    int 0x15        ; BIOS power management

    ; shutoff
    mov ax, 0x5307  ; set power state
    mov bx, 0x0001  ; all devices (1)
    mov cx, 0x0003  ; off state   (3)
    int 0x15        ; BIOS power management

	.legacy:
		mov dx, 0xB004
		mov ax, 0x2000
		out dx, ax

	mov bx, shutoff_failed
	call puts

	jmp prompt.completed

; bx = char*
strlen:
	xor di, di
	.step:
		cmp byte [bx + di], 0  ; if (BX[DI] == 0):
		je .done               ; .done();

		inc di
		jmp .step
	.done:
	ret

putnl:
	mov al, 0x0D  ; \r
	call putc
	mov al, 0x0A  ; \n
	call putc
	ret

; bx = char*
puts:
	xor di, di
	.step:
		mov al, [bx + di]  ; AL -> BX[DI]
		cmp al, 0          ; if (AL == 0):
		je .done           ; .done();

		call putc
		inc di
		jmp .step
	.done:
	ret

; al = char
putc:
	push ax
	mov ah, 0x0E  ; teletype
	int 0x10      ; BIOS interrupt
	pop ax
	ret

boot_drive: db 0

times 510 - ($ - $$) db 0
dw 0xAA55

;;;;;;;;;;;;;;;;;;
;;;            ;;;
;;;  SECTOR 2  ;;;
;;;            ;;;
;;;;;;;;;;;;;;;;;;

; immutable data
help:           db " '?' shows this menu", 0x0D, 0x0A, " '-' shuts off this device", 0x0D, 0x0A, " 'c' clears this console", 0x0D, 0x0A, " '@' shows the ASCII charset", 0x0D, 0x0A, " '&' followed by anything will set your prompt character", 0x0D, 0x0A, " '$a' allocates a slot", 0x0D, 0x0A, " '$f' frees a slot", 0x0D, 0x0A, " '$s' retrieves the status of a slot", 0x0D, 0x0A, " '#' before any text echoes it back", 0x0D, 0x0A, 0
shutoff_failed: db "Shutoff failed, your system likely does not support APM nor the legacy method.", 0
allocd_t:       db "[allocated] true", 0x0D, 0x0A, 0
allocd_f:       db "[allocated] false", 0x0D, 0x0A, 0

; mutable data
promptchar:      db '@'
cmdbuf: times 33 db 0  ; 32-char cmdbuf

; extra code
SLOT_COUNT equ 8
SLOT_SIZE  equ 63

; al = ID (1-indexed)
slot_alloc:
    push ax
    push di
    push es

    xor ah, ah  ; allows AX to represent AL alone
    mov di, ax
    dec di      ; IDs are 1-indexed
    shl di, 6   ; *64

    xor ax, ax
    mov es, ax
    mov byte [es:slots + di], 1

    pop es
    pop di
    pop ax
    ret

; al = ID (1-indexed)
slot_free:
    push ax
    push di
    push es

    xor ah, ah  ; allows AX to represent AL alone
    mov di, ax
    dec di      ; IDs are 1-indexed
    shl di, 6   ; *64

    xor ax, ax
    mov es, ax
    mov byte [es:slots + di], 0

    pop es
    pop di
    pop ax
    ret

; al = ID
slot_status:
    push di
    push es

    xor ah, ah  ; allows AX to represent AL alone
    mov di, ax
    dec di      ; IDs are 1-indexed
    shl di, 6   ; *64

    xor ax, ax
    mov es, ax
    mov ah, [es:slots + di]

    pop es
    pop di
    ret

times 1024 - ($ - $$) db 0

;;;;;;;;;;;;;;;;;;
;;;            ;;;
;;;  SECTOR 3  ;;;
;;;   Slots    ;;;
;;;            ;;;
;;;;;;;;;;;;;;;;;;

slots: times SLOT_COUNT*(SLOT_SIZE+1) db 0

times 1536 - ($ - $$) db 0