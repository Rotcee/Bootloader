[org 0x7c00]
[bits 16]

start:
    ; Limpiar la pantalla
    mov ah, 0x00
    mov al, 0x03  ; Modo texto 80x25
    int 0x10

    ; Configurar segmentos y pila
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00

    ; Imprimir mensaje de bienvenida
    mov si, msg_welcome
    call print_string
    call print_newline

    ; Cargar la segunda fase
    mov si, msg_loading
    call print_string
    call print_newline
    call load_stage2

    jmp 0x800:0x0000 ; Saltar a la segunda fase

print_string:
    mov ah, 0x0e ; Función de teletipo
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
    mov al, 0x0d ; Carriage Return
    int 0x10
    mov al, 0x0a ; Line Feed
    int 0x10
    ret

load_stage2:
    ; Resetear el disco duro
    mov ah, 0x00
    mov dl, 0x80 ; Drive 0 (C:)
    int 0x13
    jc .error

    ; Preparar dirección de carga
    mov ax, 0x800       ; Segmento donde cargar
    mov es, ax          ; ES = 0x800
    xor bx, bx          ; BX = 0. Dirección final = 0x8000

    ; Leer desde el disco
    mov ah, 0x02        ; Función de lectura de disco
    mov al, 1           ; Número de sectores a leer
    mov ch, 0           ; Pista/Cilindro
    mov cl, 2           ; Sector de inicio
    mov dh, 0           ; Cabeza
    mov dl, 0x80        ; Drive 0 (C:)
    int 0x13
    jc .error
    ret
.error:
    mov si, msg_error
    call print_string
    call print_newline
    jmp $

msg_welcome db 'Bootloader Fase 1 Iniciado...', 0
msg_loading db 'Cargando Fase 2...', 0
msg_error   db 'Error al cargar la Fase 2.', 0

times 510-($-$$) db 0
dw 0xaa55