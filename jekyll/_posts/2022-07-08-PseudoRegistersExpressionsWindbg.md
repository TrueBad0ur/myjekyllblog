---
title: Pseudo-Registers and Expressions in WinDbg [eng]
published: true
tags: [ "windbg" ]
image: /assets/previews/9.jpg
layout: page
pagination: 
  enabled: true
---

* Virtual registers provided by the debugger
* Begin with a dollar sign ($)

### [](#header-3)1) Automatic pseudo-registers
* are set by the debugger to certain useful values
* examples: $ra, $peb, $teb, ..

### [](#header-3)2) User-defined pseudo-registers
* there are twenty user-defined registers: $t0, $t1, $t2, .., $t19
* integer variables that can be used to store intermediate data
* can additionally hold type-information
* r? assigns a typed result to an lvalue
* * r? $t0 = @peb-&gt;ProcessParameter
* * * Assigns a typed value to $t0
* * * $t0’s type is remembered so it can be used in further expressions
* * ?? @$t0-&gt;CommandLine

## [](#header-2)Automatic Pseudo-Registers


| Команда        | Пояснение к ней |
|:-------------|:------------------|
| $ra | Return address currently on the stack<br>Useful in execution commands, i.e.: "g $ra" |
| $ip | The instruction pointer<br>x86 = EIP, Itanium = IIP, x64 = RIP |
| $exentry | Entry point of the first executable of the current process |
| $retreg | Primary return value register<br>x86 = EAX, Itanium = ret0, x64 = rax |
| $csp | Call stack pointer<br>X86 = ESP, Itanium = BSP, x64 = RSP |
| $peb | Address of the process environment block (PEB) |
| $teb | Address of the thread environment block (TEB) of current thread |
| $tpid | Process ID (PID) |
| $tid | Thread ID (tID) |
| $ptrsize | Size of a pointer |
| $pagesize | Number of bytes in one page of memory |

## [](#header-2)Expressions

### [](#header-3)MASM expressions

* evaluated by the ? command
* each symbol is treated as an addresses (the numerical value of a symbol is the memory address of that symbol to get its value you must dereference it with poi)
* source line expressions can be used (myfile.c:43)
* the at sign for register values is optional (eax or @eax are both fine)
* used in almost all examples in WinDbg’s help
* the only expression syntax used prior to WinDbg version 4.0 of Debugging Tools
* The numerical value of any symbol is its memory address
* Any operator can be used with any number
* Numerals: are interpreted according to the current radix: n \[8 \| 10 \| 16\]<br>Can be overridden by a prefix: 0x (hex), 0n (decimal), 0t (octal), 0y (binary)

### [](#header-3)C++ expressions
* evaluated by the ?? command
* symbols are understood as appropriate data types
* source line expressions cannot be used
* the at sign for register values is required (eax will not work)
* The numerical value of a variable is its actual value
* Operators can be used only with corresponding data types
* A symbol that does not correspond to a C++ data type will result in a syntax error
* Data structures are treated as actual structures and must be used accordingly. They do not have numerical values.
* The value of a function name or any other entry point is the memory address, treated as a function pointer
* Numerals: the default is always decimal<br>Can be overridden by a prefix: 0x (hex), 0 (=zero- octal)

MASM operations are always byte based. C++ operations follow C++ type rules (including the scaling of<br>pointer arithmetic). In both cases numerals are treated internally as ULON64 values

```js
kd> ?? @$teb->ClientId
struct _CLIENT_ID
   +0x000 UniqueProcess    : 0x00000000`000001ac Void
   +0x008 UniqueThread     : 0x00000000`00001758 Void


kd> .process /p ffff8a06a72452c0
kd> r? $t0 = @$peb->ProcessParameters
kd> ?? @$t0->CommandLine
struct _UNICODE_STRING
 ""C:\Windows\system32\cmd.exe" "
   +0x000 Length           : 0x3c
   +0x002 MaximumLength    : 0x3e
   +0x008 Buffer           : 0x000001ab`8c572280  ""C:\Windows\system32\cmd.exe" "
```

## [](#header-2)GFlags

* GFlags enables and disables features by editing the Windows registry
* GFlags can set system-wide or image-specific settings
* Image specific settings are stored in:
* * HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ImageFileName\GlobalFlag
* The OS reads these settings and adopts its functionality accordingly
* GFlags can be run from the command line or by using a dialog box
* We can also use !gflags in WinDbg to set or display the global flags
* With GFlags we can enable:
* * heap checking
* * heap tagging
* * Loader snaps
* * Debugger for an Image (automatically attached each time an Image is started)
* * Application verifier:
* * * is a runtime verification tool for Windows applications
* * * is monitoring an application's interaction with the OS
* * * profiles and tracks:
* * * * Microsoft Win32 APIs (heap, handles, locks, threads, DLL load/unload, and more)
* * * * Exceptions
* * * * Kernel objects
* * * * Registry
* * * * File system
* * * with !avrf we get access to this tracking information

**Note:** Under the hood Application Verifier injects a number of DLLs (verifier.dll, vrfcore.dll, vfbasics.dll, vfcompat.dll, and more) into the target application. More precisely: It sets a registry key according to the selected tests for the image in question. The windows loader reads this registry key and loads the specified DLLs into the applications address space while starting it.

## [](#header-2)Application Verifier Variants

### [](#header-3)GFlags Application Verifier:
* Only verifier.dll is injected into the target process
* verifier.dll is installed with Windows XP
* Offers a very limited subset of Application Verifier options
* Probably this option in GFlags is obsolete and will eventually be removed (?)

### [](#header-3)Application Verifier:
* Can freely be downloaded and installed from the MS website
* Additionally installs vrfcore.dll, vfbasics.dll, vfcompat.dll, and more into Windows\System32
* Enables much more test options and full functionality of the !avrf extension

#### [](#header-4)напочитать:

[Pseudo-Register Syntax](https://docs.microsoft.com/en-us/windows-hardware/drivers/debugger/pseudo-register-syntax)
[Common windbg commands](http://windbg.info/doc/1-common-cmds.html)
