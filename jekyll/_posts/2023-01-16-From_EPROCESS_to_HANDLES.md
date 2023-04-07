---
title: From _EPROCESS to HANDLES
published: false
tags: [ "windows", "lab" ]
image: assets/previews/19.jpg
layout: page
pagination: 
  enabled: true
---

### [](#header-3) Links

[Windows Process Internals: A few Concepts to know before jumping on Memory Forensics [Part 5] – A Journey in to the Undocumented Process Handle Structures](https://eforensicsmag.com/windows-process-internals-a-few-concepts-to-know-before-jumping-on-memory-forensics-part-5-a-journey-in-to-the-undocumented-process-handle-structures-_handle_table-_handle_table_entry/)

[A Light on Windows 10's "OBJECT_HEADER->TypeIndex"](https://medium.com/@ashabdalhalim/a-light-on-windows-10s-object-header-typeindex-value-e8f907e7073a)

## [](#header-2) Theory

All the info is in these two articles, so go on
Each process in Windows has it's own handles. When you open a file you create a handle in kernel to this file (smth like index in table)

```
   _EPROCESS           _HANDLE_TABLE
 _____________        ________________           Pointers to                                                                   _object_header
|             |      |                |       handle table entries                                                  ----> ________________________
|             |      |----------------|   -> ______________________                                                 |    |                        |
|             |  --> |   TableCode    | _/  |      Reserved        | 0x00                                           |    |      TypeIndex         | ---
|-------------|  |   |----------------|     |   (Handle Entry 1)   | 0x04 ------                                    |    |                        |   |
| ObjectTable |---   |                |     |   (Handle Entry 2)   | 0x08      |                                    |    |                        |   |
|-------------|      |                |     |   (Handle Entry 3)   | 0x0C      |          _handle_table_entry       |    |                        |   |
|             |      |                |     |   (Handle Entry 4)   | 0x10      |      __________________________    |    |        Object          |   |
|             |      |________________|     |   (Handle Entry...)  |           ----> |     | ObjectPointerBits  | ---    |________________________|   |
|             |                             |                      |                 |_____|____________________|                                     |
|_____________|                             |                      |                 |                          |              _object_type           |
                                            |  (Handle Entry 256)  | 0x100           |__________________________|         ________________________    |
                                            ------------------------                                                     |                        |   |
                                                                                                                         |          Name          |<---
                                                                                                                         |                        |
                                                                                                                         |                        |
                                                                                                                         |________________________|
```

## [](#header-2) Practice

We'll create a program with two File Handles and check it out in kernel

```cpp
#include <Windows.h>
#include <string>

int main() {
    HANDLE hFile = CreateFile(L"C:\\NewFile.txt", GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE)
        return 2;
    __debugbreak();

    HANDLE hFile1 = CreateFile(L"C:\\NewFile1.txt", GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile1 == INVALID_HANDLE_VALUE)
        return 2;
    __debugbreak();

    CloseHandle(hFile);
    CloseHandle(hFile1);
	return 0;
```

BTW if you loaded pdb into windbg you won't be able to recompile you VS project, so you need to unload module:

```js
// You can use !reload -u
kd> !reload -u
Unloaded all modules
```

Then we need to reload out modules (also user space ones):

```js
kd> .reload
Connected to Windows 10 19041 x86 compatible target at (Mon Jan 16 11:49:06.183 2023 (UTC + 3:00)), ptr64 FALSE
Loading Kernel Symbols
...............................................................
................................................................
...............................
Loading User Symbols
......
Loading unloaded module list
.........
*** WARNING: Unable to verify checksum for test.exe
```

Via windbg features we can do it like this:

```js
kd> !process 0 0
PROCESS 8eb71040  SessionId: 1  Cid: 0a10    Peb: 00464000  ParentCid: 16f4
    DirBase: dffef460  ObjectTable: 8ee746c0  HandleCount:  40.
    Image: test.exe
```
```js
kd> !handle 0 3 8eb71040 File

00a0: Object: d1c0eae8  GrantedAccess: 00120196 Entry: b2f09140
Object: d1c0eae8  Type: (897fe730) File
    ObjectHeader: d1c0ead0 (new version)
        HandleCount: 1  PointerCount: 1
        Directory Object: 00000000  Name: \NewFile.txt {HarddiskVolume2}
```
```js
kd> dt nt!_handle_table_entry b2f09140
   +0x000 VolatileLowValue : 0n-775886127
   +0x000 LowValue         : 0n-775886127
   +0x000 InfoTable        : 0xd1c0ead1 _HANDLE_TABLE_ENTRY_INFO
   +0x004 HighValue        : 0n1180054
   +0x004 NextFreeHandleEntry : 0x00120196 _HANDLE_TABLE_ENTRY
   +0x004 LeafHandleValue  : _EXHANDLE
   +0x000 Unlocked         : 0y1
   +0x000 Attributes       : 0y00
   +0x000 ObjectPointerBits : 0y11010001110000001110101011010 (0x1a381d5a)
   +0x004 RefCountField    : 0n1180054
   +0x004 GrantedAccessBits : 0y0000100100000000110010110 (0x120196)
   +0x004 ProtectFromClose : 0y0
   +0x004 NoRightsUpgrade  : 0y0
   +0x004 RefCnt           : 0y00000 (0)
```
```js
kd> dt nt!_OBJECT_HEADER d1c0ead0
   +0x000 PointerCount     : 0n1
   +0x004 HandleCount      : 0n1
   +0x004 NextToFree       : 0x00000001 Void
   +0x008 Lock             : _EX_PUSH_LOCK
   +0x00c TypeIndex        : 0xe1 ''
   +0x00d TraceFlags       : 0 ''
   +0x00d DbgRefTrace      : 0y0
   +0x00d DbgTracePermanent : 0y0
   +0x00e InfoMask         : 0x4c 'L'
   +0x00f Flags            : 0x40 '@'
   +0x00f NewObject        : 0y0
   +0x00f KernelObject     : 0y0
   +0x00f KernelOnlyAccess : 0y0
   +0x00f ExclusiveObject  : 0y0
   +0x00f PermanentObject  : 0y0
   +0x00f DefaultSecurityQuota : 0y0
   +0x00f SingleHandleEntry : 0y1
   +0x00f DeletedInline    : 0y0
   +0x010 ObjectCreateInfo : 0x96477d80 _OBJECT_CREATE_INFORMATION
   +0x010 QuotaBlockCharged : 0x96477d80 Void
   +0x014 SecurityDescriptor : (null) 
   +0x018 Body             : _QUAD
```
d1c0ead0 --> ea

+0x00c TypeIndex        : 0xe1 ''

db nt!ObHeaderCookie L1 -> 8410a7fc  2e

ea ^ e1 ^ 2e = 25
```js
kd> dt nt!_object_type poi(nt!ObTypeIndexTable + (25 * 4))
Evaluate expression: 37 = 00000025
```
```js
kd> dt nt!_object_type poi(nt!ObTypeIndexTable + (25 * 4))
   +0x000 TypeList         : _LIST_ENTRY [ 0x897fe730 - 0x897fe730 ]
   +0x008 Name             : _UNICODE_STRING "File"
   +0x010 DefaultObject    : 0x0000005f Void
   +0x014 Index            : 0x25 'Unknown format characterUnknown format control character
   +0x018 TotalNumberOfObjects : 0x1bde
   +0x01c TotalNumberOfHandles : 0x58c
   +0x020 HighWaterNumberOfObjects : 0x1ebe
   +0x024 HighWaterNumberOfHandles : 0x72b
   +0x028 TypeInfo         : _OBJECT_TYPE_INITIALIZER
   +0x080 TypeLock         : _EX_PUSH_LOCK
   +0x084 Key              : 0x656c6946
   +0x088 CallbackList     : _LIST_ENTRY [ 0x897fe7b8 - 0x897fe7b8 ]
```

Win7:
```js
kd> !handle 0 3 852944f8 File
0020: Object: 85a6ff80  GrantedAccess: 00120196 Entry: 9c8ef040
Object: 85a6ff80  Type: (851eb6e0) File
    ObjectHeader: 85a6ff68 (new version)
        HandleCount: 1  PointerCount: 1
        Directory Object: 00000000  Name: \NewFile.txt {HarddiskVolume2}
```
```js
kd> !process 0 0
PROCESS 852944f8  SessionId: 1  Cid: 0f9c    Peb: 7ffdd000  ParentCid: 0c04
    DirBase: 53bc1000  ObjectTable: 98f5d020  HandleCount:  12.
    Image: test.exe
```
```js
kd> dt nt!_EPROCESS 852944f8 ObjectTable
   +0x0f4 ObjectTable : 0x98f5d020 _HANDLE_TABLE
```
```js
kd> dt nt!_HANDLE_TABLE 0x98f5d020 
   +0x000 TableCode        : 0x9c8ef000
```
```js
kd> dd /c1 0x9c8ef000 L30
...
9c8ef040  85a6ff69
9c8ef044  00120196
...
```
```js
kd> dt nt!_handle_table_entry 9c8ef040
   +0x000 Object           : 0x85a6ff69 Void
   +0x000 ObAttributes     : 0x85a6ff69
   +0x000 InfoTable        : 0x85a6ff69 _HANDLE_TABLE_ENTRY_INFO
   +0x000 Value            : 0x85a6ff69
   +0x004 GrantedAccess    : 0x120196
   +0x004 GrantedAccessIndex : 0x196
   +0x006 CreatorBackTraceIndex : 0x12
   +0x004 NextFreeTableEntry : 0x120196
```

_OBJECT_HEADER from windbg commands is 85a6ff68(right)

Here is 85a6ff69(wrong), looks like I didn't xor or smth smwhr :(
```js
kd> dt nt!_object_header 0x85a6ff68
   +0x000 PointerCount     : 0n1
   +0x004 HandleCount      : 0n1
   +0x004 NextToFree       : 0x00000001 Void
   +0x008 Lock             : _EX_PUSH_LOCK
   +0x00c TypeIndex        : 0x1c ''            <----------------
   +0x00d TraceFlags       : 0 ''
   +0x00e InfoMask         : 0xc ''
   +0x00f Flags            : 0x40 '@'
   +0x010 ObjectCreateInfo : 0x86e32300 _OBJECT_CREATE_INFORMATION
   +0x010 QuotaBlockCharged : 0x86e32300 Void
   +0x014 SecurityDescriptor : (null) 
   +0x018 Body             : _QUAD
```
```js
kd> dps nt!ObTypeIndexTable
829490c0  00000000
829490c4  bad0b0b0
829490c8  85147cc8
829490cc  85147c00
829490d0  85147b38
829490d4  851478f0
829490d8  851477b0
829490dc  851476e8
...
```
?0x1c * 4 = 70
nt!ObTypeIndexTable + 70 = 851eb6e0
```js
kd> dd /c1 nt!ObTypeIndexTable + 70 
82949130  851eb6e0
```
```js
kd> dt nt!_OBJECT_TYPE 851eb6e0
   +0x000 TypeList         : _LIST_ENTRY [ 0x851eb6e0 - 0x851eb6e0 ]
   +0x008 Name             : _UNICODE_STRING "File"
   +0x010 DefaultObject    : 0x0000005c Void
   +0x014 Index            : 0x1c ''
   +0x018 TotalNumberOfObjects : 0xca8
   +0x01c TotalNumberOfHandles : 0x335
   +0x020 HighWaterNumberOfObjects : 0xcbe
   +0x024 HighWaterNumberOfHandles : 0x363
   +0x028 TypeInfo         : _OBJECT_TYPE_INITIALIZER
   +0x078 TypeLock         : _EX_PUSH_LOCK
   +0x07c Key              : 0x656c6946
   +0x080 CallbackList     : _LIST_ENTRY [ 0x851eb760 - 0x851eb760 ]
```