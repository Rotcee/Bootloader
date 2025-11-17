[bits 16]

BUFFER_SIZE equ 64

start_stage2:
    ; Configurar segmento de datos
    mov ax, cs
    mov ds, ax

shell_loop:
    mov si, prompt
    call print_string
    mov byte [buffer_len], 0
    mov di, cmd_buffer
    call read_line

    call run_command
    jmp shell_loop

run_command:
    ; Añadir un terminador null al final del comando introducido
    mov bl, [buffer_len]
    mov bh, 0
    mov byte [cmd_buffer + bx], 0

    ; Comparar con comandos conocidos
    mov si, cmd_clear_str
    mov di, cmd_buffer
    call strcmp
    je .do_clear

    mov si, cmd_reboot_str
    mov di, cmd_buffer
    call strcmp
    je .do_reboot

    mov si, cmd_ls_str
    mov di, cmd_buffer
    call strcmp
    je .do_ls

    ; Comando desconocido
    mov si, msg_unknown
    call print_string
    call print_newline
    ret

.do_clear:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    ret

.do_reboot:
    int 0x19 ; Reiniciar el sistema (Warm boot)
    ret

.do_ls:

    ; --- Lógica de lectura de disco "en línea" ---

    ; Resetear el disco

    mov ah, 0x00

    mov dl, 0x80

    int 0x13

    jc .ls_error



    ; Leer el sector 3 en 0x9000:0000

    mov ax, 0x9000

    mov es, ax

    xor bx, bx

    mov ah, 0x02

    mov al, 1

    mov ch, 0

    mov cl, 3

    mov dh, 0

    mov dl, 0x80

    int 0x13

    jc .ls_error

    ; --- Fin de la lectura en línea ---



    ; Parsear y listar la tabla

    mov si, 0

.ls_loop:

    mov al, [es:si]

    cmp al, 0

    je .ls_done



    push si

    push ds

    mov ax, es

    mov ds, ax

    call print_string

    pop ds

    pop si



    call print_newline

    add si, 12

    jmp .ls_loop



.ls_done:

    ret

.ls_error:

    mov si, msg_ls_err

    call print_string

    call print_newline

    ret



; --- Subrutinas ---

read_line:

.loop:

    mov ah, 0x00
    int 0x16


    cmp al, 0x0d ; Enter
    je .done

    cmp al, 0x08 ; Backspace
    je .backspace

    mov bl, [buffer_len]
    cmp bl, BUFFER_SIZE - 1
    jge .loop

    mov [di], al
    inc di
    inc byte [buffer_len]

    mov ah, 0x0e
    int 0x10
    jmp .loop

.backspace:
    mov bl, [buffer_len]
    cmp bl, 0
    je .loop

    dec di
    dec byte [buffer_len]

    mov ah, 0x0e
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .loop

.done:
    call print_newline
    ret

strcmp:
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no_match
    cmp al, 0
    je .match
    inc si
    inc di
    jmp .loop
.no_match:
    ret
.match:
    ; Para que el 'je' funcione fuera, necesitamos setear el flag Z
    ; lo hacemos comparando algo consigo mismo.
    cmp ax, ax
    ret

print_string:
    mov ah, 0x0e
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    ret

print_newline:
    mov ah, 0x0e
    mov al, 0x0d
    int 0x10
    mov al, 0x0a
    int 0x10
    ret

; --- Datos ---
prompt db '> ', 0
msg_unknown db 'Comando desconocido.', 0
cmd_clear_str db 'clear', 0
cmd_reboot_str db 'reboot', 0
cmd_ls_str db 'ls', 0
msg_ls_ok db 'Tabla de ficheros leida.', 0
msg_ls_err db 'Error al leer el disco.', 0

buffer_len db 0
cmd_buffer times BUFFER_SIZE db 0

times 512 - ($ - $) db 0