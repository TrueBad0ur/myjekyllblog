---
title: Windows Threads Priorities [eng]
published: true
tags: [ "windows", "lab" ]
image: assets/previews/17.jpg
layout: page
pagination: 
  enabled: true
---

### [](#header-3) Links

[Original workshop](https://intuit.ru/studies/courses/10471/1078/lecture/16577?page=1)

[Process Explorer](https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer)

[CpuStres](https://learn.microsoft.com/en-us/sysinternals/downloads/cpustres)

[Clockres](https://learn.microsoft.com/en-us/sysinternals/downloads/clockres)

### [](#header-3) Determine the value of the system timer interval

Duration of the system timer interval - `KeMaximumIncrement`

Choose first processor - `~0`


```js
0: kd> dd KeMaximumIncrement
8278cab4  0002625a 00001388 0002625a 0002625a
8278cac4  60010001 00000002 00000002 00000002
```

This variable stores the duration of the system timer interval in hundreds of nanoseconds

0x2625a = 156250

1ns = 10^−9s

1ms = 10^–3s

156250 hunders of ns = 156250 * 100 * 10^–9s = 0.015625s = 15,625ms

To check it we can use clockres

```js
C:\Users\IEUser\Desktop>Clockres.exe

Clockres v2.1 - Clock resolution display utility
Copyright (C) 2016 Mark Russinovich
Sysinternals

Maximum timer interval: 15.625 ms
Minimum timer interval: 0.500 ms
Current timer interval: 15.625 ms
```

### [](#header-3) Determine the value of quantum given to threads

```js
1: kd> !process 0 0 explorer.exe
PROCESS 8738f030  SessionId: 1  Cid: 0ac8    Peb: 7ffdf000  ParentCid: 0aa8
    DirBase: df7d0440  ObjectTable: 91e5ca78  HandleCount: 812.
    Image: explorer.exe

1: kd> dt nt!_KPROCESS 8738f030 QuantumReset
   +0x061 QuantumReset : 36 '$'
```

The value of the QuantumReset field is 36 units, which is 12 system timer intervals - the default quantum value for Windows server operating systems.

### [](#header-3) Change the value of the quantum

`My Computer – Properties - Advanced – Settings - Performance - Performance Options - Advanced - Processor scheduling - choose Programs`

```js
0: kd> dt nt!_KPROCESS 8738f030 QuantumReset
   +0x061 QuantumReset : 6 ''
```

### [](#header-3) Determine the values of the priority class and base priority of the process

```js
0: kd> dt nt!_EPROCESS 8738f030 PriorityClass
   +0x17b PriorityClass : 0x2 ''
```

[Priority Class values line 399](https://github.com/HighSchoolSoftwareClub/Windows-Research-Kernel-WRK-/blob/26b524b2d0f18de703018e16ec5377889afcf4ab/WRK-v1.2/public/sdk/inc/ntpsapi.h)

```c
#define PROCESS_PRIORITY_CLASS_UNKNOWN      0
#define PROCESS_PRIORITY_CLASS_IDLE         1
#define PROCESS_PRIORITY_CLASS_NORMAL       2
#define PROCESS_PRIORITY_CLASS_HIGH         3
#define PROCESS_PRIORITY_CLASS_REALTIME     4
#define PROCESS_PRIORITY_CLASS_BELOW_NORMAL 5
#define PROCESS_PRIORITY_CLASS_ABOVE_NORMAL 6
```

```js
0: kd> dt nt!_KPROCESS 8738f030 BasePriority
   +0x060 BasePriority : 8 ''
```

### [](#header-3) Change the base priority of a process

In Process Explorer right click on explorer.exe - Set Priority - High

```js
0: kd> dt nt!_EPROCESS 850ff030 PriorityClass
   +0x17b PriorityClass : 0x3 ''
0: kd> dt nt!_KPROCESS 850ff030 BasePriority
   +0x060 BasePriority : 13 ''
```

In Process Explorer right click on explorer.exe - Set Priority - Real Time

```js
1: kd> dt nt!_EPROCESS 850ff030 PriorityClass
   +0x17b PriorityClass : 0x4 ''
1: kd> dt nt!_KPROCESS 850ff030 BasePriority
   +0x060 BasePriority : 24 ''
```

### [](#header-3) Explore the structure of KPRCB (Kernel Processor Control Block)

Choose processor - `~0` (obviously you should set 2 or more processors in your virtual machine settings)

`dt nt!_kprcb`

```js
0: kd> !prcb
PRCB for Processor 0 at 80b96120:
Current IRQL -- 28
Threads--  Current 82780d00 Next 00000000 Idle 82780d00
Processor Index 0 Number (0, 0) GroupSetMember 1
Interrupt Count -- 0003766c
Times -- Dpc    00000003 Interrupt 00000003 
         Kernel 00010c6e User      00000104 
```

Values of KPRCB structure:

```js
0: kd> dt nt!_kprcb 80b96120
   +0x000 MinorVersion     : 1
   +0x002 MajorVersion     : 1
   +0x004 CurrentThread    : 0x82780d00 _KTHREAD
   +0x008 NextThread       : (null) 
   +0x00c IdleThread       : 0x82780d00 _KTHREAD
   +0x010 LegacyNumber     : 0 ''
```

Note the pointers to the current thread (CurrentThread), next thread (NextThread), and idle thread (IdleThread).

In the example in the figure, you can see that the pointers of the current thread and the idle thread are the same, i.e. the processor is currently busy with the idle thread

### [](#header-3) Examine the queue of threads to execute

In Clockres there are 4 already created threads. Set them all active, change Ideal CPU to 0, Activity to maximum, Priority to Highest(it's not very important, you can choose which you want, but don't set all to Time Critical, it's a bad idea :) )

```js
0: kd> dt nt!_kprcb 8350a120 ReadySummary DispatcherReadyListHead
   +0x31ec ReadySummary            : 0
   +0x3220 DispatcherReadyListHead : [32] _LIST_ENTRY [ 0x80b99340 - 0x80b99340 ]
```

The ReadySummary field shows the priorities for which there are threads ready to run

For Time Critical for example it will be:

0x700 = 00000000000000000000011100000000

Binary 1s in this field indicate the priorities for which there are currently queues of ready threads

The ReadySummary field is used to speed up the search for the queue of threads with the highest priority: the system does not look through all the queues for each priority, but first looks at the ReadySummary field to find the ready thread with the highest priority. In this example, this is a thread with a priority of 15.

The DispatcherReadyListHead field indicates queues of ready threads.

This field is an array of elements of type LIST_ENTRY (see file public\sdk\inc\ntdef.h, line 1084). The dimension of the array coincides with the number of priorities in the system - 32.

To view the contents of the array, enter the following command in the debugger:

Do not forget to change processor `~0`

```js
0: kd> dd 8350a120+3220
80b99340  80b99340 80b99340 80b99348 80b99348
80b99350  80b99350 80b99350 80b99358 80b99358
80b99360  80b99360 80b99360 80b99368 80b99368
80b99370  80b99370 80b99370 871086b4 871086b4
80b99380  8585452c 8737b0a4 87432594 857ce46c
80b99390  80b99390 80b99390 80b99398 80b99398
80b993a0  80b993a0 80b993a0 80b993a8 80b993a8
80b993b0  87034adc 87034adc 872c40a4 87406bd4


80b993b8  872c40a4 87406bd4
0: kd> dt nt!_LIST_ENTRY -l Flink 80b993b8
 [ 0x872c40a4 - 0x87406bd4 ]
   +0x000 Flink            : 0x872c40a4 _LIST_ENTRY [ 0x8719a714 - 0x80b993b8 ]
   +0x004 Blink            : 0x87406bd4 _LIST_ENTRY [ 0x80b993b8 - 0x8729fdbc ]

Flink at 0x872c40a4
---------------------------------------------
 [ 0x8719a714 - 0x80b993b8 ]
   +0x000 Flink            : 0x8719a714 _LIST_ENTRY [ 0x84fbfc64 - 0x872c40a4 ]
   +0x004 Blink            : 0x80b993b8 _LIST_ENTRY [ 0x872c40a4 - 0x87406bd4 ]

Flink at 0x8719a714
---------------------------------------------
 [ 0x84fbfc64 - 0x872c40a4 ]
   +0x000 Flink            : 0x84fbfc64 _LIST_ENTRY [ 0x87094ad4 - 0x8719a714 ]
   +0x004 Blink            : 0x872c40a4 _LIST_ENTRY [ 0x8719a714 - 0x80b993b8 ]

Flink at 0x84fbfc64
---------------------------------------------
 [ 0x87094ad4 - 0x8719a714 ]
   +0x000 Flink            : 0x87094ad4 _LIST_ENTRY [ 0x84f63094 - 0x84fbfc64 ]
   +0x004 Blink            : 0x8719a714 _LIST_ENTRY [ 0x84fbfc64 - 0x872c40a4 ]

Flink at 0x87094ad4
---------------------------------------------
 [ 0x84f63094 - 0x84fbfc64 ]
   +0x000 Flink            : 0x84f63094 _LIST_ENTRY [ 0x84f61094 - 0x87094ad4 ]
   +0x004 Blink            : 0x84fbfc64 _LIST_ENTRY [ 0x87094ad4 - 0x8719a714 ]

Flink at 0x84f63094
---------------------------------------------
 [ 0x84f61094 - 0x87094ad4 ]
   +0x000 Flink            : 0x84f61094 _LIST_ENTRY [ 0x8729fdbc - 0x84f63094 ]
   +0x004 Blink            : 0x87094ad4 _LIST_ENTRY [ 0x84f63094 - 0x84fbfc64 ]

Flink at 0x84f61094
---------------------------------------------
 [ 0x8729fdbc - 0x84f63094 ]
   +0x000 Flink            : 0x8729fdbc _LIST_ENTRY [ 0x87406bd4 - 0x84f61094 ]
   +0x004 Blink            : 0x84f63094 _LIST_ENTRY [ 0x84f61094 - 0x87094ad4 ]

Flink at 0x8729fdbc
---------------------------------------------
 [ 0x87406bd4 - 0x84f61094 ]
   +0x000 Flink            : 0x87406bd4 _LIST_ENTRY [ 0x80b993b8 - 0x8729fdbc ]
   +0x004 Blink            : 0x84f61094 _LIST_ENTRY [ 0x8729fdbc - 0x84f63094 ]

```

```js
1: kd> dt nt!_KTHREAD WaitListEntry
   +0x074 WaitListEntry : _LIST_ENTRY

0: kd> dt nt!_KTHREAD 0x872c40a4-74 Process
   +0x150 Process : 0x871a3b18 _KPROCESS

0: kd> dd 0x872c40a4-74+150 L1
872c4180  871a3b18

0: kd> dt nt!_EPROCESS 871a3b18 ImageFileName
   +0x16c ImageFileName : [15]  "svchost.exe"

```

```js
0x8719a714
0x87406bd4

0: kd> dd 0x8719a714-74+150 L1
0: kd> dt nt!_EPROCESS 873cbd20 ImageFileName
   +0x16c ImageFileName : [15]  "CPUSTRES.EXE"

0: kd> dd 0x87406bd4-74+150 L1
0: kd> dt nt!_EPROCESS 873cbd20 ImageFileName
   +0x16c ImageFileName : [15]  "CPUSTRES.EXE"

```
