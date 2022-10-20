---
title: Скрываемся в списке процессов в ядре
published: true
tags: [ "windows", "internals", "lab" ]
image: /assets/previews/2.jpg
layout: page
pagination: 
  enabled: true
---

Попробуем скрыть процесс в ядре, чтобы в юзерспейсе пользователь не увидел его. Идём по мануалу [Manipulating ActiveProcessLinks to unlink processes in userland](https://www.ired.team/miscellaneous-reversing-forensics/windows-kernel-internals/manipulating-activeprocesslinks-to-unlink-processes-in-userland)

Про \_EPROCESS мы уже знаем из лабы выше. Двухсвязный список, тип \_LIST_ENTRY и всё такое. Задача у нас довольно простая, но хочется проделать это руками: переписать указатели так, чтобы спрятать наш процесс:

![EPROCESS Structure](/assets/EPROCESS.png)

Находим адрес процесса (notepad.exe) и берём его FLINK и BLINK

```js
kd> dt _eprocess fffffa80047ce060
nt!_EPROCESS
...
   +0x188 ActiveProcessLinks : _LIST_ENTRY [ 0xfffffa80`061457d8 - 0xfffffa80`070f9c88 ]
...

kd> dq fffffa80047ce060+0x188 L2
fffffa80`047ce1e8  fffffa80`061457d8 fffffa80`070f9c88
```

Можем глянуть, куда указывают флинк и блинк:
```js
kd> dt _eprocess fffffa80`061457d8-0x188
nt!_EPROCESS
...
   +0x2e0 ImageFileName    : [15]  "mscorsvw.exe"
...

kd> dt _eprocess fffffa80`070f9c88-0x188
nt!_EPROCESS
...
    +0x2e0 ImageFileName    : [15]  "taskhost.exe"
...
```

Получим пиды окружающих наш процесс процессов:
```js
kd> dt _eprocess fffffa8006145650
nt!_EPROCESS
...
   +0x180 UniqueProcessId  : 0x00000000`00000a4c Void
   +0x188 ActiveProcessLinks : _LIST_ENTRY [ 0xfffff800`02a38940 - 0xfffffa80`047ce1e8 ]
...

kd> dt nt!_EPROCESS fffffa80070f9b00
...
   +0x180 UniqueProcessId  : 0x00000000`00000994 Void
   +0x188 ActiveProcessLinks : _LIST_ENTRY [ 0xfffffa80`047ce1e8 - 0xfffffa80`070375c8 ]
...


kd> dd fffffa8006145650+188-8 L1
fffffa80`061457d0  00000a4c

kd> dd fffffa80070f9b00+188-8 L1
fffffa80`070f9c80  00000994
```

| Image | PID | EPROCESS | ActiveProcessLinks | FLINK | BLINK | 
|:------|:------|:---------------------------|:------------------------|:-------------------------|:----------------------|
| taskhost.exe | 994 | fffffa80070f9b00 | fffffa80070f9c88 | fffffa80047ce1e8 | fffffa80070375c8 |
| notepad.exe | 854 | fffffa80047ce060 | fffffa80047ce1e8 | fffffa80061457d8 | fffffa80070f9c88 |
| mscorsvw.exe | a4c | fffffa8006145650 | fffffa80061457d8 | fffff80002a38940 | fffffa80047ce1e8 |

Очевидно, нам нужна немного другая табличка)

| Image | PID | EPROCESS | ActiveProcessLinks | FLINK | BLINK | 
|:------|:------|:---------------------------|:------------------------|:-------------------------|:----------------------|
| taskhost.exe | 994 | fffffa80070f9b00 | fffffa80070f9c88 | ~~fffffa80047ce1e8~~ fffffa80061457d8 | fffffa80070375c8 |
| ~~notepad.exe~~ | ~~854~~ | ~~fffffa80047ce060~~ | ~~fffffa80047ce1e8~~ | ~~fffffa80061457d8~~ | ~~fffffa80070f9c88~~ |
| mscorsvw.exe | a4c | fffffa8006145650 | fffffa80061457d8 | fffff80002a38940 | ~~fffffa80047ce1e8~~ fffffa80070f9c88 |

```js
kd> eq fffffa80`070f9c88 fffffa80`061457d8
kd> eq fffffa80`061457d8+8 fffffa80`070f9c88
```

![Porcesses list](/assets/processes.png)
