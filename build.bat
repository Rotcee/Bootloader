@echo off
echo Ensamblando boot.asm...
nasm -f bin -o boot.bin boot.asm
if %errorlevel% neq 0 (
    echo Error al ensamblar boot.asm
    exit /b 1
)

echo Ensamblando stage2.asm...
nasm -f bin -o stage2.bin stage2.asm
if %errorlevel% neq 0 (
    echo Error al ensamblar stage2.asm
    exit /b 1
)

echo Ensamblando fs_table.asm...
nasm -f bin -o fs_table.bin fs_table.asm
if %errorlevel% neq 0 (
    echo Error al ensamblar fs_table.asm
    exit /b 1
)

echo Ensamblando data.asm...
nasm -f bin -o data.bin data.asm
if %errorlevel% neq 0 (
    echo Error al ensamblar data.asm
    exit /b 1
)

echo Creando imagen de disco boot.img...
copy /b boot.bin + stage2.bin + fs_table.bin + data.bin boot.img

echo Proceso de compilacion finalizado.
