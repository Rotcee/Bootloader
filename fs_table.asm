[bits 16]

; Formato de entrada (12 bytes):
; - 10 bytes: Nombre del fichero (relleno con 0)
; - 1 byte:  Sector de inicio
; - 1 byte:  Tamaño en sectores

; Primera entrada: hello.txt
db 'hello.txt', 0, 0, 0 ; Nombre
db 4                    ; Sector de inicio (0=MBR, 1=Stage2, 2=FS_Table, 3=hello.txt)
db 1                    ; Tamaño en sectores

; Segunda entrada: fin de la tabla (nombre empieza con null)
db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
db 0
db 0

; Rellenar el resto del sector (512 bytes) con ceros
times 512 - ($ - $$) db 0
