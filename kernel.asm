[bits 32]
%include "config.inc"

[org KERNEL_LOAD_PHYS]

elf_header:
    db 0x7F, 'ELF'
    db 1, 1, 1, 0
    times 8 db 0
    dw 2
    dw 3
    dd 1
    dd KERNEL_LOAD_PHYS
    dd phdr - $$
    dd 0
    dd 0
    dw 52
    dw 32
    dw 1
    dw 0
    dw 0
    dw 0

phdr:
    dd 1
    dd payload - $$
    dd KERNEL_LOAD_PHYS
    dd KERNEL_LOAD_PHYS
    dd payload_end - payload
    dd payload_end - payload
    dd 5
    dd 0x1000

SCREEN_COLS   equ 80
VIDEO_BASE    equ 0xB8000
RIGHT_LIMIT   equ 50            ; (SCREEN_COLS - len(mensaje))
COLOR_DELAY   equ 40

payload:
    mov byte [pos], 0
    mov byte [dir], 1
    mov byte [color], 0x1F
    mov byte [color_steps], 0

.main_loop:
    call clear_line
    call draw_text
    call delay

    movzx eax, byte [pos]
    movsx ecx, byte [dir]
    add eax, ecx
    cmp eax, 0
    jl .hit_left
    cmp eax, RIGHT_LIMIT
    jg .hit_right
    mov [pos], al
    jmp .update_color

.hit_left:
    mov byte [pos], 0
    neg ecx
    mov [dir], cl
    jmp .update_color

.hit_right:
    mov byte [pos], RIGHT_LIMIT
    neg ecx
    mov [dir], cl

.update_color:
    mov al, [color_steps]
    inc al
    cmp al, COLOR_DELAY
    jb .store_steps
    mov al, 0
    mov bl, [color]
    add bl, 0x10
    cmp bl, 0xF0
    jb .store_color
    mov bl, 0x1F
.store_color:
    mov [color], bl
.store_steps:
    mov [color_steps], al
    jmp .main_loop

clear_line:
    mov edi, VIDEO_BASE
    mov ecx, SCREEN_COLS
    mov ax, 0x0720
.cl_loop:
    mov [edi], ax
    add edi, 2
    loop .cl_loop
    ret

draw_text:
    mov edi, VIDEO_BASE
    movzx eax, byte [pos]
    shl eax, 1
    add edi, eax
    mov esi, kernel_msg
    mov ecx, kernel_len
    mov ah, [color]
.draw_loop:
    mov al, [esi]
    mov [edi], ax
    inc esi
    add edi, 2
    loop .draw_loop
    ret

delay:
    mov ecx, 100000000
.delay_loop:
    loop .delay_loop
    ret

pos   db 0
dir   db 1
color db 0x1F
color_steps db 0

kernel_msg db 'Kernel ELF en modo protegido! ', 0
kernel_len equ $ - kernel_msg - 1
payload_end:

times KERNEL_TOTAL_BYTES - ($ - $$) db 0
