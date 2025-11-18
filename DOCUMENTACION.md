# Guía integral del Bootloader

Esta guía describe cada componente del proyecto, a qué problema responde y cómo funciona línea a línea. Úsala como referencia para mantener o extender la cadena de arranque.

---

## 1. Objetivos del proyecto
1. Mostrar un bootloader mínimo que imprime texto usando interrupciones BIOS.
2. Añadir una segunda etapa capaz de leer del teclado y escribir en pantalla.
3. Cargar un kernel ELF en memoria y cederle el control.
4. Inicializar la GDT y pasar a modo protegido antes de saltar al kernel.

---

## 2. Estructura del repositorio

| Archivo            | Propósito                                                                 |
|--------------------|---------------------------------------------------------------------------|
| `boot.asm`         | Etapa 1 (MBR) – carga Stage 2 y delega ejecución.                         |
| `stage2.asm`       | Etapa 2 – shell BIOS + cargador del kernel + transición a modo protegido. |
| `kernel.asm`       | Kernel ELF de demostración (modo protegido).                              |
| `config.inc`       | Constantes compartidas (segmentos, offsets, tamaños).                     |
| `build.bat`        | Ensambla cada binario y concatena `boot.img`.                             |
| `run.bat`          | Inicia QEMU con la imagen resultante.                                     |
| `DOCUMENTACION.md` | Este documento.                                                           |

Herramientas requeridas: NASM (`nasm -f bin`) y QEMU (`qemu-system-x86_64`).  
Los scripts asumen que ambas herramientas están accesibles desde el PATH.

---

## 3. Flujo del arranque

1. **BIOS → Stage 1:** BIOS copia `boot.bin` en `0x7C00` y cede el control.
2. **Stage 1 → Stage 2:** `boot.asm` limpia la pantalla, muestra mensajes y usa INT 13h para leer 6 sectores (Stage 2) a `0x8000`, luego hace `jmp 0x800:0000`.
3. **Shell (Stage 2):** acepta comandos `clear`, `reboot`, `time`, `echo`, `boot`. El prompt se mantiene hasta que el usuario teclea `boot`.
4. **Carga del kernel:** el comando `boot` lee 4 sectores de `boot.img` a partir del sector 8 y los guarda físicamente en `0x10000`.
5. **Transición a modo protegido:** Stage 2 habilita la línea A20, carga la GDT y activa el bit PE de CR0. Con un salto largo entra en modo protegido.
6. **Kernel ELF:** `kernel.asm` imprime un mensaje en 0xB8000 y permanece en un bucle `hlt`, demostrando que el control ya no vuelve al shell.

---

## 4. Configuración compartida (`config.inc`)

| Línea | Constante             | Descripción                                                                                      |
|-------|----------------------|--------------------------------------------------------------------------------------------------|
| 3     | `STAGE2_SEGMENT`     | Segmento físico (0x800) donde Stage 1 carga Stage 2.                                             |
| 4     | `STAGE2_SECTORS`     | Sectores reservados para Stage 2 (6 × 512 B = 3 KiB).                                            |
| 5–6   | `STAGE2_BASE/TOTAL`  | Conversión a dirección física y tamaño en bytes.                                                 |
| 11–13 | `KERNEL_*`           | Sector inicial del kernel (posterior a Stage 2) y tamaño total (4 sectores = 2 KiB).             |
| 15–18 | `KERNEL_LOAD_*`      | Dirección física donde se colocará el kernel y sus equivalentes segmento:offset para INT 13h.    |
| 16    | `KERNEL_STACK_TOP`   | Ubicación de la pila de modo protegido (0x00090000).                                             |

---

## 5. Stage 1 (`boot.asm`)

Directivas clave: `%include "config.inc"`, `[org 0x7c00]`, `[bits 16]`.

1. **Inicialización de pantalla**
   - Líneas 6‑10: llamada a INT 10h (AH=0x00, AL=0x03) para limpiar la pantalla e iniciar el modo texto 80×25.

2. **Segmentos y pila**
   - Líneas 12‑17: DS/ES/SS se ponen en 0; SP se posiciona en 0x7C00 para aprovechar la memoria del boot sector como pila.

3. **Mensajes de estado**
   - Líneas 19‑27: se muestran “Bootloader Fase 1...” y “Cargando Fase 2...” mediante la rutina `print_string` (INT 10h modo teletipo).

4. **Carga de Stage 2**
   - Líneas 49‑72 (`load_stage2`):
     1. Resetea la unidad (`INT 13h AH=0`).
     2. Apunta ES:BX a 0x8000.
     3. Usa `INT 13h AH=0x02` para leer `STAGE2_SECTORS` sectores comenzando en CHS 0/0/2.

5. **Transferencia de control**
   - Línea 30: `jmp STAGE2_SEGMENT:0` lleva la ejecución a la segunda etapa.

6. **Relleno y firma**
   - Líneas 79‑84: relleno con ceros hasta el byte 510 y firma `0xAA55`.

Subrutinas incluidas:
- `print_string`: bucle que lee caracteres desde SI y los envía mediante INT 10h AH=0x0E.
- `print_newline`: emite CR/LF.

---

## 6. Stage 2 (`stage2.asm`)

### 6.1 Inicialización
- Carga `CS` en `DS`/`ES`.
- Mueve la pila a 0x7000:0000 (`cli`, `mov ss,0x7000`, `mov sp,0`, `sti`).

### 6.2 Shell interactivo
1. Mostrar prompt `> `.
2. Limpiar `cmd_buffer` y leer línea con `read_line` (usa INT 16h, eco por INT 10h).
3. Parsear comando (`run_command`), separando `cmd_name` y argumentos (`args_ptr`).
4. Comparar contra los comandos conocidos mediante `strcmp`.

### 6.3 Comandos disponibles
1. **`clear`**: reconfigura modo texto (INT 10h AH=0).
2. **`reboot`**: invoca INT 19h para reiniciar.
3. **`time`**: lee CMOS (0x70/0x71), convierte BCD a decimal y muestra HH:MM:SS.
4. **`echo`**: imprime el resto de la línea o sólo un salto de línea si no hay texto.
5. **`boot`**: muestra mensajes de estado, llama a `load_kernel` y, si tiene éxito, ejecuta `enter_protected_mode`.

### 6.4 Carga del kernel (`load_kernel`)
1. Guardar AX/BX/CX/DX.
2. Programar ES:BX = `KERNEL_LOAD_SEG:KERNEL_LOAD_OFF`.
3. Leer `KERNEL_TOTAL_SECTORS` desde `KERNEL_FIRST_SECTOR` mediante INT 13h AH=0x02.
4. Ajustar Carry: `clc` si la lectura fue correcta; `stc` en caso de error.

### 6.5 Transición a modo protegido
1. **Habilitar A20** (`enable_a20`):
   - Lee el puerto 0x92.
   - Enciende el bit 1 y apaga el bit 0 para habilitar la línea A20 sin reiniciar el sistema.
2. **Cargar la GDT**:
   - `gdt_start` define tres descriptores (nulo, código plano, datos plano).
   - `gdt_descriptor` contiene límite/base absolutos (`STAGE2_BASE + gdt_start`).
   - `lgdt [gdt_descriptor]` publica la GDT a la CPU.
3. **Activar modo protegido**:
   - `mov eax, cr0` + `or eax, 1` + `mov cr0, eax`.
   - `jmp dword CODE_SEG:PROTECTED_MODE_ENTRY_LINEAR` realiza un salto largo con el nuevo selector de código.
4. **`protected_mode_entry` (código 32‑bits)**:
   - Carga DS/ES/FS/GS/SS con `DATA_SEG`.
   - Fija `ESP = KERNEL_STACK_TOP`.
   - `mov eax, KERNEL_LOAD_PHYS` seguido de `jmp eax` para saltar al kernel.

### 6.6 Subrutinas auxiliares destacadas
- `read_cmos`, `bcd_to_dec`, `print_2_digits`: gestión de la hora.
- `read_line`: entrada con edición básica (Backspace).
- `strcmp`, `skip_spaces`, `print_string`, `print_newline`: herramientas de texto.

### 6.7 Relleno final
`times STAGE2_TOTAL_SIZE - ($ - $$) db 0`: obliga al archivo a ocupar exactamente seis sectores (3 KiB), coincidiendo con la lectura de Stage 1.

---

## 7. Kernel (`kernel.asm`)

1. **Cabecera ELF**
   - Identificador `0x7F 'ELF'`, tipo ejecutable (`dw 2`), arquitectura x86 (`dw 3`).
   - Entrada (`dd KERNEL_LOAD_PHYS`) y puntero al programa (`dd phdr - $$`).

2. **Program Header (`phdr`)**
   - Tipo `1` (PT_LOAD), offset `payload - $$`, direcciones virtual/física = `KERNEL_LOAD_PHYS`.
   - Tamaños en memoria/archivo: `payload_end - payload`.
   - Flags `5` (ejecutable + legible) y alineación 0x1000.

3. **Payload**
   - Inicializa `EDI = 0xB8000`, `ESI = kernel_msg`, `AH = 0x1F` (color).
   - Bucle `lodsb` → prueba de cero → escribe `AX` en `[EDI]` y avanza 2 bytes (texto de video).
   - Tras imprimir la cadena, ejecuta `hlt` en bucle infinito.

4. **Datos y relleno**
   - `kernel_msg db 'Kernel ELF en modo protegido!', 0`.
   - `times KERNEL_TOTAL_BYTES - ($ - $$) db 0` ocupa los sectores reservados.

El kernel es deliberadamente minimalista: demuestra que la CPU ya está en modo protegido y que el ELF ejecuta código propio sin regresar a Stage 2.

---

## 8. Scripts y pruebas

### 8.1 Construcción
```bat
> build.bat
```
1. Ensambla `boot.asm`, `stage2.asm`, `kernel.asm`.
2. Concatena los binarios en `boot.img` mediante `copy /b`.

### 8.2 Ejecución
Antes de invocar QEMU, define qué se va a comprobar (por ejemplo, “verificar que `boot` carga el kernel y la salida se queda en el mensaje del kernel”).  
Luego ejecuta:
```bat
> run.bat
```
Secuencia a validar:
1. Mensajes de Stage 1.
2. Prompt del shell y funcionamiento de `clear`, `reboot`, `time`, `echo`.
3. Comando `boot`: mensajes de carga, pantalla renovada y texto “Kernel ELF en modo protegido!”. La sesión debe quedarse en ese mensaje (bucle `hlt`).

---

## 9. Posibles mejoras
1. Añadir más comandos al shell (por ejemplo, exploración de memoria o lectura de otros sectores).
2. Implementar controladores básicos en el kernel (teclado en modo protegido, PIT para temporizadores).
3. Migrar la carga de disco a LBA o soportar sistemas de archivos (FAT, ext2).
4. Automatizar pruebas con QEMU (`-serial stdio`) para capturar la salida y compararla con expectativas.

---

Con esta estructura (visión global → detalle por módulo → proceso de pruebas) podrás navegar fácilmente por el código ensamblador y entender qué hace cada instrucción dentro del flujo completo de arranque.
