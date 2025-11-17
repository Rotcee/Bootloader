[bits 16]

db 'Hola desde un fichero en disco!', 0x0d, 0x0a, 0

times 512 - ($ - $$) db 0
