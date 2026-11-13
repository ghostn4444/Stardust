# Stardust — Windows Build (MinGW Toolchain)

Este repositório contém uma versão adaptada do [Stardust](https://github.com/Cracked5pider/Stardust) de **Cracked5pider**, configurada para compilar no **Windows 10/11** usando a toolchain **MinGW-w64** em vez do ambiente Linux/Clang original.

O Stardust é um **template de shellcode 32/64-bit position-independent (PIC)** escrito em C++20. Ele não é um beacon nem um loader por si só — é a base sobre a qual você constrói seu implante, cuidando da resolução de APIs via PEB, hashing em tempo de compilação e strings "cruas".

---

## Sumário

- [Visão Geral](#-visão-geral)
- [Diferenças em relação ao projeto original](#-diferenças-em-relação-ao-projeto-original)
- [Dependências e Versões](#-dependências-e-versões)
- [Estrutura do Projeto](#-estrutura-do-projeto)
- [Modo de Operação](#-modo-de-operação)
- [Compilação](#-compilação)
- [Customização](#-customização)
- [Teste](#-teste)
- [Limitações Conhecidas](#-limitações-conhecidas)
- [Créditos](#-créditos)

---

## Visão Geral

O Stardust gera **shellcode position-independent** para Windows x64 (e x86, quando a toolchain de 32 bits está disponível). O shellcode resultante:

- Não depende de IAT (Import Address Table);
- Resolve módulos e APIs em tempo de execução caminhando pela **PEB** (Process Environment Block);
- Usa **hashing FNV-1a em tempo de compilação** para evitar strings em texto claro no binário final;
- Suporta strings "cruas" via a função `symbol<>()`;
- É extraído da seção `.text` de um executável intermediário via `objcopy`.

O resultado final é um arquivo `.bin` (ex.: `stardust.x64.bin`, ~750–800 bytes em modo release) pronto para ser injetado por qualquer loader PIC.

---

## Diferenças em relação ao projeto original

O projeto original foi desenhado para ser compilado no **Linux** com **Clang** e alvo cruzado MinGW-w64 (`x86_64-w64-mingw32`). No Windows, o Clang usa por padrão o linker **LLD**, que **não suporta scripts de linker GNU** (`-Tscripts/linker.ld`) — resultando no erro:

```
lld: error: unknown argument: -Tscripts/linker.ld
```

Esta versão resolve o problema **substituindo o Clang pelo `g++` do MinGW-w64**, que usa o GNU `ld` nativamente e aceita o script de linker sem alterações. As demais flags e a estrutura do projeto foram preservadas.

| Item | Original (Linux) | Esta versão (Windows) |
|------|------------------|------------------------|
| Compilador | `clang -target x86_64-w64-mingw32` | `g++.exe` (MinGW-w64) |
| Linker | GNU `ld` (via Clang) | GNU `ld` (via g++) |
| Script de linker | `scripts/linker.ld` | `scripts/linker.ld` (inalterado) |
| Extração do shellcode | `objcopy` | `objcopy.exe` (MinGW) |
| Build | `make` / `make debug` | `make x64` / `make clean` |

---

## Dependências e Versões

| Ferramenta | Versão usada | Observação |
|------------|--------------|------------|
| **Windows** | 10 / 11 (x64) | Testado em Windows 10 |
| **MinGW-w64 (UCRT)** | `g++` 16.1.0 (Brecht Sanders, r3) | Localização: `C:/MinGW/mingw64/bin` |
| **NASM** | 2.16.03 | Montagem dos stubs `entry.x64.asm` / `utils.x64.asm` |
| **objcopy** | Incluído no MinGW-w64 | Extrai a seção `.text` do PE intermediário |
| **GNU Make** | Incluído no MinGW-w64 (`mingw32-make`) | Executado via `make` no PATH |

>  **Atenção**: o `g++` deve ser de **64 bits** para compilar a versão x64. A versão x86 exige uma toolchain cruzada `i686-w64-mingw32-g++`, que **não está incluída** no MinGW-w64 padrão de 64 bits — veja [Limitações Conhecidas](#-limitações-conhecidas).

### Verificação rápida do ambiente

```cmd
g++ --version
nasm --version
objcopy --version
make --version
```

---

## Estrutura do Projeto

```
Stardust/
├── bin/
│   ├── obj/                  # Objetos intermediários (.x64.obj)
│   └── stardust.x64.bin      # Shellcode final (gerado)
├── include/
│   ├── common.h              # Classe instance, symbol<>, hash_string, DBG_PRINTF
│   ├── constexpr.h           # Hashing em tempo de compilação
│   ├── macros.h              # D_APIs, RESOLVE_TYPE, RESOLVE_IMPORT
│   ├── memory.h              # Utilitários de memória
│   ├── native.h              # Estruturas nativas (PEB, TEB, etc.)
│   └── resolve.h             # resolve::module, resolve::api
├── scripts/
│   └── linker.ld             # Script de linker (layout PIC)
├── src/
│   ├── main.cc               # Lógica do shellcode (instance::start)
│   ├── resolve.cc            # Implementação da resolução de módulos/APIs
│   └── asm/
│       ├── entry.x64.asm     # Stub de entrada x64
│       ├── entry.x86.asm     # Stub de entrada x86
│       ├── utils.x64.asm     # RipStart / RipData (x64)
│       └── utils.x86.asm     # RipStart / RipData (x86)
├── test/
│   └── stomper.cc            # Loader de teste (executa o .bin)
├── Makefile                  # Build adaptado para Windows/MinGW
└── README.md
```

---

## ⚙️ Modo de Operação

O fluxo de execução do shellcode é:

### 1. Entrada (`entry`)

O stub em assembly (`entry.x64.asm`) chama `entry(void* args)`, definida em `src/main.cc`:

```cpp
extern "C" auto declfn entry(_In_ void* args) -> void {
    stardust::instance().start(args);
}
```

### 2. Inicialização (`instance::instance`)

- Calcula o **endereço base** e o **tamanho** do shellcode via `RipStart()` e `RipData()`;
- Resolve os módulos `ntdll.dll` e `kernel32.dll` caminhando pela **PEB** (`resolve::module`);
- Chama `RESOLVE_IMPORT` para preencher automaticamente os ponteiros das APIs declaradas em `common.h`.

### 3. Execução (`instance::start`)

É aqui que você coloca a lógica do seu implante. Por padrão (nesta versão), o shellcode executa a calculadora:

```cpp
auto declfn instance::start(_In_ void* arg) -> void {
    kernel32.WinExec(
        symbol<const char*>("C:\\Windows\\System32\\calc.exe"),
        SW_SHOW
    );
}
```

### 4. Resolução de APIs

- **Módulos**: `resolve::module(expr::hash_string<wchar_t>(L"ntdll.dll"))` — o hash é calculado em tempo de compilação;
- **Funções**: `RESOLVE_API(handle, MessageBoxA)` — o macro calcula o hash do nome e converte o ponteiro para o tipo correto;
- **Strings**: `symbol<const char*>("texto")` — garante que a string seja incluída na seção de dados do shellcode e referenciada corretamente.

### 5. Extração do shellcode

O Makefile:
1. Compila `main.cc` e `resolve.cc` em objetos `.x64.obj`;
2. Monta `entry.x64.asm` e `utils.x64.asm` com NASM;
3. Linka tudo com o script `linker.ld` em `bin/stardust.x64.exe`;
4. Extrai a seção `.text` com `objcopy --dump-section .text=bin/stardust.x64.bin`;
5. Remove o `.exe` intermediário.

O aviso `ld.exe: ... .text: section below image base` é **esperado** — indica que o layout PIC foi aplicado corretamente.

---

## Compilação

### Build release (x64)

```cmd
make clean
make x64
```

Saída esperada:
```
-> compiling src/main.cc
-> compiling src/resolve.cc
compiling x64 project
```

Resultado: **`bin/stardust.x64.bin`** (shellcode PIC x64).

### Build debug (x64)

```cmd
make x64-debug
```

Ativa `DBG_PRINTF` (via `DbgPrint`), visível com ferramentas como **DebugView**. **Nota**: a versão debug pode exigir ajustes no código-fonte para compilar com GCC (ver [Limitações Conhecidas](#-limitações-conhecidas)).

### Limpeza

```cmd
make clean
```

Remove objetos, `.exe` intermediários e `.bin`.

---

## Customização

Para alterar o comportamento do shellcode, edite **`src/main.cc`** (função `instance::start`) e, se necessário, **`include/common.h`** (para declarar novas APIs).

### Exemplo: adicionar `CreateProcessA`

**1. Em `include/common.h`**, dentro da struct `kernel32`:

```cpp
struct {
    D_API( LoadLibraryA )
    D_API( GetProcAddress )
    D_API( WinExec )
    D_API( CreateProcessA )   // adicionado
};
```

E na inicialização:

```cpp
} kernel32 = {
    RESOLVE_TYPE( LoadLibraryA ),
    RESOLVE_TYPE( GetProcAddress ),
    RESOLVE_TYPE( WinExec ),
    RESOLVE_TYPE( CreateProcessA )   // adicionado
};
```

**2. Em `src/main.cc`**, substitua `instance::start`:

```cpp
auto declfn instance::start(_In_ void* arg) -> void {
    STARTUPINFOA si = {};
    PROCESS_INFORMATION pi = {};
    si.cb = sizeof(si);

    kernel32.CreateProcessA(
        symbol<const char*>("C:\\Windows\\System32\\notepad.exe"),
        nullptr, nullptr, nullptr, FALSE, 0, nullptr, nullptr,
        &si, &pi
    );
}
```

### Regras fundamentais

| Regra | Motivo |
|-------|--------|
| Toda string deve usar `symbol<const char*>("...")` | O shellcode não tem tabela de relocação/import normal |
| Toda API deve ser declarada em `common.h` (`D_API`) e resolvida (`RESOLVE_TYPE` + `RESOLVE_IMPORT`) | Não há IAT; a resolução é manual via PEB |
| Não use exceções C++ (`-fno-exceptions` está ativo) | Shellcode não tem runtime de exceções |
| Evite alocações dinâmicas da CRT | O shellcode é `-nostdlib` |

---

## Teste

O projeto inclui `test/stomper.cc`, um loader mínimo que executa o `.bin`:

```cmd
g++.exe test\stomper.cc -o test\stomper.x64.exe -w
.\test\stomper.x64.exe bin\stardust.x64.bin
```

Se o shellcode estiver correto, a **calculadora** será aberta.

> Se o `stomper.x64.exe` pré-compilado reportar "não é compatível com a versão do Windows", **recompile-o** com o comando acima usando o seu próprio MinGW — o binário incluído no repositório pode ter sido gerado com outra toolchain.

---

## Limitações Conhecidas

1. **Versão x86 não compila** com o MinGW-w64 padrão de 64 bits. É necessário instalar uma toolchain cruzada `i686-w64-mingw32-g++` (ex.: via MSYS2 `mingw-w64-i686-gcc`) e ajustar o Makefile. O alvo `make x86` falhará com `i386 architecture ... incompatible with i386:x86-64 output` enquanto isso não for feito.

2. **Build debug (`make x64-debug`) pode falhar** com GCC devido a `invalid conversion from 'const char*' to 'char*'` na macro `DBG_PRINTF`. O Clang original tolera essa conversão; o GCC é mais rigoroso. Solução: alterar `PCH` para `const char*` em `common.h`, ou remover o `symbol<PCH>` ao redor de `__FUNCTION__`.

3. **Aviso do linker** `section below image base` é **normal e esperado** — não é erro.

4. **`make stomper`** pode não regenerar o `.exe` se o alvo não estiver no Makefile adaptado. Use o comando manual de recompilação acima.

---

## Créditos

- **Projeto original**: [Cracked5pider/Stardust](https://github.com/Cracked5pider/Stardust) — template de shellcode PIC 32/64-bit em C++20.
- **Adaptação para Windows/MinGW**: ajuste do Makefile para usar `g++` do MinGW-w64 em vez de Clang/LLD, contornando a incompatibilidade com scripts de linker GNU.
- **Referências da comunidade**: discussões sobre build no Windows com CMake e GCC, e sobre a incompatibilidade do Clang/MSVC com o código do Stardust.

---

## 📄 Licença

O Stardust original não declara licença explícita no repositório. Esta adaptação mantém o mesmo espírito: **uso restrito a pesquisa de segurança, testes autorizados e ambientes controlados**. Não use em sistemas sem permissão explícita.

---

> **Aviso legal**: este projeto é destinado a **pesquisa de segurança ofensiva**, **red teaming autorizado** e **estudo de internals do Windows**. O uso indevido é de responsabilidade exclusiva do usuário.
