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

payload:
    mov edi, 0xB8000
    mov esi, kernel_msg
    mov ah, 0x1F
.print_loop:
    lodsb
    test al, al
    je .halt
    mov [edi], ax
    add edi, 2
    jmp .print_loop
.halt:
    hlt
    jmp .halt

kernel_msg db 'Kernel ELF en modo protegido!', 0
payload_end:

times KERNEL_TOTAL_BYTES - ($ - $$) db 0
