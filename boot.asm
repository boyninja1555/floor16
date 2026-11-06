[bits 16]
[org 0x7C00]

; DI = cmdbuf idx

init:
	cli             ; disable (clear) interrupts
    xor ax, ax
    mov ds, ax      ; data segment  -> 0
    mov es, ax      ; extra segment -> 0
    mov ss, ax      ; stack segment -> 0
    mov sp, 0x7C00  ; stack ptr     -> 0x7C00
    sti             ; enable (start) interrupts

init_sectors:
    mov ax, 0x1000
    mov es, ax
    xor bx, bx

    mov ah, 0x02  ; read sector
    mov al, 0x01  ; number of sectors
    mov ch, 0x00  ; cylinder 0
    mov dh, 0x00  ; head     0
    mov cl, 0x02  ; sector   2
    int 0x13      ; BIOS disk

prompt:
	xor di, di  ; start of cmdbuf

	; fancy prompt text
	mov al, '@'
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

		cmp di, 16                 ; if (DI >= 16):
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

	; newline
	mov al, 0x0D  ; \r
	call putc
	mov al, 0x0A  ; \n
	call putc

	; command branches
	mov byte al, [cmdbuf]  ; AL -> cmdbuf[0]

	; CMD_help
	cmp al, '?'
	je CMD_help

	; CMD_comment
	cmp al, '#'
	je CMD_comment

	; CMD_stop
	cmp al, '-'
	je CMD_stop

	; Invalid command
	mov al, '?'
	call putc
	mov al, 0x0D  ; \r
	call putc
	mov al, 0x0A  ; \n
	call putc
	jmp prompt

CMD_help:
	xor di, di  ; idx = 0;
	.step:
		mov byte al, [help + di]  ; AL -> help[DI]
		cmp al, 0                 ; if (AL == 0):
		je .done                  ; .done();

		call putc                 ; putc();
		inc di                    ; increment idx
		jmp .step
	.done:
	jmp prompt

CMD_comment:
	mov di, 1  ; start cmdbuf idx past '#'
	.step:
		mov byte al, [cmdbuf + di]  ; AL -> cmdbuf[DI]
		cmp al, 0                   ; if (AL == 0):
		je .done                    ; .done();

		call putc                   ; putc();
		inc di                      ; increment cmdbuf idx
		jmp .step
	.done:

	; newline
	mov al, 0x0D  ; \r
	call putc
	mov al, 0x0A  ; \n
	call putc

	jmp prompt

CMD_stop:
	; connect to APM interface
    mov ax, 0x5301  ; APM connect interface
    xor bx, bx      ; device ID (0: system BIOS)
    int 0x15        ; BIOS power management

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

	jmp $

; al = char
putc:
	mov ah, 0x0E  ; teletype
	int 0x10      ; BIOS interrupt
	ret

times 510 - ($ - $$) db 0
dw 0xAA55

;;;;;;;;;;;;;;;;;;
;;;            ;;;
;;;  SECTOR 2  ;;;
;;;            ;;;
;;;;;;;;;;;;;;;;;;

help: db " '?' shows this menu", 0x0D, 0x0A, " '-' shuts off this device", 0x0D, 0x0A, " '#' before any text echoes it back", 0x0D, 0x0A, 0
cmdbuf: times 17 db 0  ; 16-char cmdbuf

times 1024 - ($ - $$) db 0