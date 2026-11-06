[bits 16]
[org 0x7C00]

; DI = cmdbuf idx

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
    mov al, 0x01          ; number of sectors
    mov ch, 0x00          ; cylinder 0
    mov dh, 0x00          ; head     0
    mov cl, 0x02          ; sector   2
	mov dl, [boot_drive]  ; load boot drive (DL)
    int 0x13              ; BIOS disk

	jnc pre_prompt        ; if (!carry): pre_prompt();
	cmp di, 8             ; if (DI != 8):
	inc di  ; (always happens)
	jne init_sectors      ; init_sectors();

pre_prompt:
	jmp CMD_help

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

	; CMD_clear
	cmp al, 'c'
	je CMD_clear

	; CMD_ascii
	cmp al, '@'
	je CMD_ascii

	; CMD_list
	cmp al, 'l'
	je CMD_list

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
	xor di, di  ; idx = 0;
	.step:
		mov byte al, [help + di]  ; AL -> help[DI]
		cmp al, 0                 ; if (AL == 0):
		je .done                  ; .done();

		call putc                 ; putc();
		inc di                    ; increment idx
		jmp .step
	.done:
	jmp prompt.completed

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

	; newline
	mov al, 0x0D  ; \r
	call putc
	mov al, 0x0A  ; \n
	call putc

	jmp prompt.completed

CMD_list:
	jmp prompt.completed

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

boot_drive: db 0
help: db " '?' shows this menu", 0x0D, 0x0A, " '-' shuts off this device", 0x0D, 0x0A, " 'c' clears this console", 0x0D, 0x0A, " '@' shows the ASCII charset", 0x0D, 0x0A, " 'l' lists files", 0x0D, 0x0A, " '#' before any text echoes it back", 0x0D, 0x0A, 0
cmdbuf: times 33 db 0  ; 32-char cmdbuf

filec: db 0                 ; initial filecount of 0
filen: times (8 *7) db 0  ; capacity for 7 filenames, each 8 chars
filed: times (32*7) db 0  ; capacity for 7 files, each 32 bytes

times 1024 - ($ - $$) db 0