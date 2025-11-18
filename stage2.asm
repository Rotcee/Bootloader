[bits 16]

BUFFER_SIZE equ 64

start_stage2:
    ; Configurar segmentos de datos y extra
    mov ax, cs
    mov ds, ax
    mov es, ax

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

    mov si, cmd_time_str
    mov di, cmd_buffer
    call strcmp
    je .do_time

    mov si, cmd_echo_str
    mov di, cmd_buffer
    call strcmp
    je .do_echo

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
    int 0x19
    ret

.do_time:
    call read_cmos

    ; Imprimir Horas
    mov al, [time_h]
    call bcd_to_dec
    call print_2_digits
    call print_colon

    ; Imprimir Minutos
    mov al, [time_m]
    call bcd_to_dec
    call print_2_digits
    call print_colon

    ; Imprimir Segundos
    mov al, [time_s]
    call bcd_to_dec
    call print_2_digits

    call print_newline
    ret

.do_echo:
    ; Mover SI al inicio del mensaje (después de 'echo' y el espacio)
    mov si, cmd_buffer
    add si, 5 ; Saltar "echo "
    call print_string
    call print_newline
    ret

; --- Subrutinas ---

print_colon:
    mov ah, 0x0e
    mov al, ':'
    int 0x10
    ret

; Convierte un byte BCD en AL a un byte decimal en AL (usando AAD)
bcd_to_dec:
    mov ah, al
    shr ah, 4       ; ah = dígito de las decenas
    and al, 0x0F    ; al = dígito de las unidades
    aad             ; al = ah * 10 + al. El resultado binario queda en AL.
    mov ah, 0       ; Limpiar AH por si acaso
    ret

; Imprime un número de 0-99 en AL como dos dígitos (sin usar DIV)
print_2_digits:
    mov cl, '0' ; Contador para las decenas
.tens_loop:
    cmp al, 10
    jb .print_digits
    sub al, 10
    inc cl
    jmp .tens_loop
.print_digits:
    ; Imprimir dígito de las decenas
    push ax     ; Guardar el resto (unidades)
    mov al, cl
    mov ah, 0x0e
    int 0x10
    pop ax      ; Recuperar el resto

    ; Imprimir dígito de las unidades
    add al, '0'
    mov ah, 0x0e
    int 0x10
    ret

; Lee la hora del CMOS y la guarda en las variables time_h, time_m, time_s
read_cmos:
    ; Esperar a que no haya una actualización en progreso
.wait:
    mov al, 0x0A    ; Status Register A
    out 0x70, al
    in al, 0x71
    test al, 0x80   ; Bit 7 es el 'Update in progress' flag
    jnz .wait

    ; Leer segundos
    mov al, 0x00
    out 0x70, al
    in al, 0x71
    mov [time_s], al

    ; Leer minutos
    mov al, 0x02
    out 0x70, al
    in al, 0x71
    mov [time_m], al

    ; Leer horas
    mov al, 0x04
    out 0x70, al
    in al, 0x71
    mov [time_h], al
    ret

read_line:
.loop:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0d ; Enter
    je read_line_done
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
read_line_done:
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
cmd_time_str db 'time', 0
cmd_echo_str db 'echo', 0

time_h db 0
time_m db 0
time_s db 0

buffer_len db 0
cmd_buffer times BUFFER_SIZE db 0
