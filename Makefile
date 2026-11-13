NAME   := stardust
MINGW_BIN := C:/MinGW/mingw64/bin

CC     := $(MINGW_BIN)/g++.exe
ASMCC  := $(MINGW_BIN)/nasm.exe
OBJCOPY := $(MINGW_BIN)/objcopy.exe

CFLAGS := -Os -nostdlib -fno-asynchronous-unwind-tables -std=c++20
CFLAGS += -fno-ident -fpack-struct=8 -falign-functions=1 -s -w -mno-sse
CFLAGS += -ffunction-sections -falign-jumps=1 -falign-labels=1 -fno-jump-tables
CFLAGS += -Wl,-s,--no-seh,--enable-stdcall-fixup -masm=intel -fno-exceptions
CFLAGS += -fms-extensions -fPIC -Iinclude -Wl,-Tscripts/linker.ld

x64: nasm64 bin/obj/main.x64.obj bin/obj/resolve.x64.obj
	@ echo "compiling x64 project"
	@ $(CC) bin/obj/main.x64.obj bin/obj/resolve.x64.obj bin/obj/entry.x64.obj bin/obj/utils.x64.obj -o bin/$(NAME).x64.exe $(CFLAGS)
	@ $(OBJCOPY) --dump-section .text=bin/$(NAME).x64.bin bin/$(NAME).x64.exe
	@ del /Q bin\$(NAME).x64.exe 2>nul

bin/obj/main.x64.obj: src/main.cc
	@ echo "-> compiling $<"
	@ $(CC) -o bin/obj/main.x64.obj -c src/main.cc $(CFLAGS)

bin/obj/resolve.x64.obj: src/resolve.cc
	@ echo "-> compiling $<"
	@ $(CC) -o bin/obj/resolve.x64.obj -c src/resolve.cc $(CFLAGS)

nasm64:
	@ $(ASMCC) -f win64 src/asm/entry.x64.asm -o bin/obj/entry.x64.obj
	@ $(ASMCC) -f win64 src/asm/utils.x64.asm -o bin/obj/utils.x64.obj

clean:
	@ del /Q bin\obj\*.obj 2>nul
	@ del /Q bin\*.exe 2>nul
	@ del /Q bin\*.bin 2>nul
	@ echo "removed object files"
