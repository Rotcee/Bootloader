# Documentación integral del Bootloader

## 1. Panorama general
Este proyecto muestra, de forma incremental, cuatro hitos de arranque:
1. **Bootloader mínimo** (`boot.asm`) que utiliza las BIOS de 16‑bits para limpiar la pantalla e imprimir mensajes.
2. **Bootloader en dos fases** (`boot.asm` + `stage2.asm`) donde la primera etapa carga múltiples sectores y la segunda implementa un shell básico con entrada de teclado.
3. **Cargador de kernel ELF** (binario `kernel.asm`) que se almacena tras la segunda fase, se copia a memoria alta y se ejecuta en modo protegido.
4. **Inicialización de GDT y cambio a modo protegido** dentro de la segunda etapa antes de saltar al kernel.

El flujo es: BIOS carga `boot.bin` en 0x7C00 → Stage 1 limpia pantalla y carga Stage 2 (6 sectores) en 0x8000 → Stage 2 ofrece comandos (`clear`, `reboot`, `time`, `echo`, `boot`) → Al ejecutar `boot`, Stage 2 carga 4 sectores del kernel ELF en 0x10000, habilita la línea A20, carga una GDT plana y cambia a modo protegido → El kernel imprime un mensaje y se queda detenido en `hlt`.

## 2. Archivos y herramientas
| Archivo | Contenido |
| --- | --- |
| `boot.asm` | Primera etapa del bootloader (512 bytes). |
| `stage2.asm` | Segunda etapa/Shell + cargador del kernel. |
| `kernel.asm` | Kernel ELF de demostración (modo protegido). |
| `config.inc` | Constantes compartidas (segmentos, tamaños, offsets). |
| `build.bat` | Ensambla cada etapa y concatena `boot.img`. |
| `run.bat` | Inicia QEMU con `boot.img`. |
| `DOCUMENTACION.md` | Este documento. |

Requisitos: NASM (modo binario plano) y QEMU (`qemu-system-x86_64`). `build.bat` y `run.bat` asumen que ambas herramientas están en el PATH.

## 3. Configuración compartida (`config.inc` línea a línea)
1. Comentario descriptivo.
3. `STAGE2_SEGMENT equ 0x800`: segmento donde se cargará Stage 2 (dirección física 0x8000).
4. `STAGE2_SECTORS equ 6`: cantidad de sectores de 512 bytes reservados para Stage 2.
5. `STAGE2_BASE equ STAGE2_SEGMENT * 16`: conversión de segmento a dirección física.
6. `STAGE2_TOTAL_SIZE equ STAGE2_SECTORS * 512`: tamaño total asignado (3 KiB).
8‑9. Constantes para un buffer de disco alternativo (no usado actualmente).
11. `KERNEL_TOTAL_SECTORS equ 4`: el kernel ocupa 2 KiB (4 sectores).
12. `KERNEL_TOTAL_BYTES equ KERNEL_TOTAL_SECTORS * 512`: tamaño en bytes.
13. `KERNEL_FIRST_SECTOR equ STAGE2_SECTORS + 2`: sectores 0 y 1 son MBR y Stage 1; Stage 2 ocupa 6 sectores; por tanto el kernel comienza en el sector 8 (contando desde 1).
15. `KERNEL_LOAD_PHYS equ 0x00010000`: el kernel se coloca en la dirección física 64 KiB.
16. `KERNEL_STACK_TOP equ 0x00090000`: pila de modo protegido (576 KiB).
17. `KERNEL_LOAD_SEG` y 18. `KERNEL_LOAD_OFF`: conversión de la dirección física a segmento:offset para BIOS.

## 4. Stage 1 (`boot.asm`) explicación línea a línea
1. Incluye `config.inc` para reutilizar las constantes.
3‑4. Directivas NASM (`org 0x7c00`, `bits 16`): ubican el código en la dirección estándar del MBR y definen código de 16 bits.
6‑10. Limpian la pantalla con INT 10h, función 0x00 y modo de texto 80x25 (AL=0x03).
12‑17. Ajustan todos los segmentos (DS, ES, SS) a 0, y posicionan la pila en 0x7C00 (crece hacia abajo).
19‑27. Imprimen dos mensajes (`msg_welcome`, `msg_loading`) usando `print_string` y `print_newline`.
28‑31. Llaman a `load_stage2` y, si todo va bien, saltan mediante `jmp STAGE2_SEGMENT:0` para ejecutar la segunda fase cargada en 0x8000.
32‑47. Subrutinas `print_string` y `print_newline`: usan INT 10h, función 0x0E (teletipo) para escribir texto y saltos de línea.
49‑72. `load_stage2`: reinicia la unidad (INT 13h función 0x00), prepara ES:BX como 0x8000 y lee `STAGE2_SECTORS` sectores a partir del sector 2 (CHS 0,0,2) mediante INT 13h función 0x02. Si alguna llamada falla, imprime `msg_error` y se queda en un bucle infinito (`jmp $`).
79‑84. Datos (mensajes) y el sello del MBR (`0xAA55`). `times 510-($-$$) db 0` rellena el sector con ceros hasta llegar al offset 510.

## 5. Stage 2 (`stage2.asm`) explicación
El archivo incluye `config.inc`, se ensambla como código de 16 bits y ocupa exactamente 3 KiB gracias al relleno al final. A continuación se describen sus secciones clave:

### 5.1 Cabecera y pila (líneas 1‑20)
- `%include "config.inc"` / `[bits 16]`: reutilizan las constantes y especifican modo de 16 bits.
- Define constantes locales: `BUFFER_SIZE`, `CMD_NAME_MAX`, selectores GDT (`CODE_SEG`, `DATA_SEG`) y la dirección lineal del punto de entrada para modo protegido.
- `start_stage2`: carga `CS` en `DS` y `ES` (para direccionar sus datos), deshabilita interrupciones (`cli`), mueve `SS` a 0x7000 con `SP=0`, y vuelve a habilitar interrupciones (`sti`). Esto evita colisiones con la memoria de Stage 1.

### 5.2 Bucle del shell (líneas 21‑66)
- `shell_loop`: muestra el prompt, reinicia el contador del buffer y llama a `read_line` para recibir entrada desde el teclado BIOS (INT 16h).
- `run_command` divide la línea en `cmd_name` y argumentos (`args_ptr`), recortando espacios iniciales/finales para manejar comandos con argumentos (`echo <texto>`). Añade un terminador nulo al final del buffer para facilitar las comparaciones.

### 5.3 Router de comandos (líneas 70‑101)
- Compara `cmd_name` con cada cadena conocida mediante `strcmp`. Los comandos disponibles: `clear`, `reboot`, `time`, `echo` y `boot`. Al no encontrar coincidencia, imprime `msg_unknown`.

### 5.4 Implementación de comandos
- **`clear`** (líneas 103‑107): llama a INT 10h función 0x00 para reconfigurar el modo de texto.
- **`reboot`** (109‑111): invoca INT 19h (BIOS bootstrap).
- **`time`** (113‑120): usa `read_cmos` + `bcd_to_dec` + `print_2_digits` para mostrar la hora HH:MM:SS.
- **`echo`** (122‑130): imprime los argumentos o sólo un salto de línea.
- **`boot`** (132‑167): muestra `msg_loading_kernel`, llama a `load_kernel` (sector read), imprime `msg_kernel_loaded` cuando tiene éxito, y luego ejecuta `enter_protected_mode`. Si falla la lectura, muestra `msg_kernel_error`.

### 5.5 Subrutinas auxiliares
- `skip_spaces`, `print_colon`, `bcd_to_dec`, `print_2_digits`: funciones para parsear texto y formatear números sin usar divisiones por BIOS.
- `read_cmos`: emplea los puertos 0x70/0x71 para leer segundos, minutos y horas en formato BCD; espera a que el bit “update in progress” se libere antes de leer.
- `read_line`: obtiene entrada carácter por carácter desde INT 16h (teclado), soporta Backspace con eco en pantalla y mantiene un contador (`buffer_len`).
- `strcmp`: compara dos cadenas terminadas en cero; retorna con ZF=1 si son iguales.
- `print_string`, `print_newline`: versiones locales del teletipo BIOS.

### 5.6 Carga del kernel, GDT y modo protegido (líneas 315‑415)
- `load_kernel`: salva registros, prepara ES:BX con `KERNEL_LOAD_SEG:KERNEL_LOAD_OFF`, y lee `KERNEL_TOTAL_SECTORS` sectores a partir de `KERNEL_FIRST_SECTOR` usando INT 13h. Usa `stc/clc` para propagar éxito/fracaso.
- `enter_protected_mode`: deshabilita interrupciones, habilita A20 (`enable_a20` escribe en puerto 0x92), carga la dirección física de la GDT (`lgdt [gdt_descriptor]`), activa el bit PE del registro CR0 y efectúa un salto largo (`jmp dword CODE_SEG:PROTECTED_MODE_ENTRY_LINEAR`). Con esto se vacían las colas de instrucción y la CPU usa la nueva GDT.
- `gdt_start`…`gdt_end`: definen tres descriptores (nulo, código plano 32‑bits, datos plano 32‑bits). `gdt_descriptor` contiene el límite (tamaño-1) y la base absoluta (`STAGE2_BASE + gdt_start`), ya que Stage 2 reside físicamente en 0x8000.
- `[bits 32] protected_mode_entry`: ya en modo protegido, carga todos los segmentos con `DATA_SEG`, configura `ESP` en `KERNEL_STACK_TOP` y salta al kernel mediante `mov eax, KERNEL_LOAD_PHYS` seguido de `jmp eax`. El relleno final (`times STAGE2_TOTAL_SIZE - ($ - $$) db 0`) asegura que el archivo ocupa exactamente seis sectores, tal como espera Stage 1.

## 6. Kernel ELF (`kernel.asm`) explicación
1. `[bits 32]` indica código plano de 32 bits y se incluye `config.inc` para compartir constantes.
4. `[org KERNEL_LOAD_PHYS]` establece la dirección de enlace para que los encabezados ELF reflejen la dirección física real una vez cargados.
6‑22. `elf_header`: cabecera ELF mínima (identificador `0x7F 'ELF'`, tipo ejecutable `dw 2`, arquitectura x86 `dw 3`, punto de entrada = `KERNEL_LOAD_PHYS`, tabla de programas (`phdr`), etc.). Aunque la BIOS no lo usa, permite que herramientas reconozcan la imagen como ELF válido.
24‑32. `phdr`: único programa cargable que cubre la sección `payload`. Los campos `dd payload - $$` y `dd KERNEL_LOAD_PHYS` indican dónde se encuentra el segmento en el archivo y en memoria; los tamaños en memoria/archivo son `payload_end - payload`; las banderas `5` = ejecutable+legible, alineación 0x1000.
34‑47. `payload`: simple rutina que escribe `kernel_msg` directamente en memoria de video 0xB8000, usando color de texto `0x1F`, y queda detenida en un bucle `hlt`. Este bucle mantiene la CPU en reposo sin regresar al shell.
49‑52. Datos del mensaje (`kernel_msg`) y relleno hasta `KERNEL_TOTAL_BYTES`, de forma que los sectores reservados estén completamente ocupados.

## 7. Scripts de soporte
- `build.bat`:
  1. Ensambla cada archivo (`nasm -f bin`) y verifica errores.
  2. Combina `boot.bin + stage2.bin + kernel.bin` mediante `copy /b` para generar `boot.img`.
- `run.bat`: lanza `qemu-system-x86_64 -hda boot.img`. QEMU detecta automáticamente el formato RAW y muestra una advertencia (puede omitirse añadiendo `-drive file=boot.img,format=raw,if=floppy`).

## 8. Proceso de pruebas
1. Ejecutar `build.bat` tras cualquier cambio para regenerar `boot.img`.
2. Antes de cada prueba en QEMU, definir qué se va a verificar (por ejemplo: “comprobar que `boot` carga el kernel y se detiene en modo protegido”). Esto ayuda a aislar regresiones.
3. `run.bat` abre QEMU; validar:
   - Mensajes de Stage 1 (`Bootloader Fase 1...` y `Cargando Fase 2...`).
   - Prompt `> ` del shell y comandos `clear`, `reboot`, `time`, `echo`.
   - Comando `boot`: mensajes de carga, pantalla en blanco y texto del kernel en modo protegido. El sistema queda en el bucle `hlt` del kernel.

## 9. Próximos pasos sugeridos
- Añadir soporte para estructuras de disco más complejas (FAT, particiones), o lectura mediante LBA.
- Implementar controladores básicos en el kernel (teclado, temporizador PIT) para interactuar después del `boot`.
- Incorporar un verificador de checksum para Stage 2 y el kernel.
- Automatizar las pruebas con scripts de QEMU (`-serial stdio`) para capturar la salida y validar mensajes.

Con esta guía tienes una visión completa (general y detallada) de cada archivo ensamblador y de la secuencia completa de arranque. Cualquier desarrollo adicional se puede basar en estas secciones para extender el cargador o enriquecer el kernel.
