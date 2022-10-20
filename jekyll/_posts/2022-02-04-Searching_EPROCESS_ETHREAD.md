---
title: Ищем EPROCESS и ETHREAD, отнимаем байтики
published: true
tags: [ "windows", "internals" ]
image: /assets/previews/6.jpg
layout: page
pagination: 
  enabled: true
---

Каждый процесс представлен структурой EPROCESS (executive process block) в ядре. EPROCESS указывает на число связанных структур, например: у каждого процесса есть 1 или более потоков, которые представляются структурой ETHREAD.

EPROCESS указывает на PEB (process environment block) в адресном пространстве процесса

ETHREAD указывает на TEB (thread environment block) в адресном пространстве процесса

```

      	           _______________________
                  |  Process environment  |
             ---> |      block (PEB)      | <---------
             |    |_______________________|          |
             |                                       |
             |                                       |
             |                                   ______________
             |                                  | Thread       |
             |                                  | environment  |
             |                                  | Block (TEB)  |
             |                                  |______________|
             |                                       ^
             |                                       |
User-Mode: Process Address Spase                     |
----------------------------------------------------------------
Kernel-Mode: System Address Space                    |
             |                                       |
             |                                       |
             |                                       |
             |                                       |
        __________________                           |
       |  Process block   |                          |
       |    EPROCESS      |                       KTHREAD
       |__________________|                          |
             |                                       |
             |           _______________             |
             |          | Thread block  |--->...     |
             ---------->|    ETHREAD    |------------|
                        |_______________|



```

## [](#header-2)Что есть в PEB и TEB

### [](#header-3)PEB - Process Environment Block

* базовая информация об образе (базовый адрес, значение версии, список модулей)
* информации о куче в процессе
* переменные среды
* параметры командной строки
* путь для поиска DLL

#### [](#header-4)Чтобы отобразить:

```js
!peb
dt nt!_PEB
```

#### [](#header-4)Чтобы посмотреть для чужого процесса:

```js
kd> .process /p ffffe20fb340e080; !peb 10f90d5000
предварительно получив список процессов с адресами: 
!process 0 0
```

### [](#header-3)TEB - Thread Environment Block

* информация о стеке (база стека, лимит стека)
* TLS (thread local storage) массив

#### [](#header-4)Чтобы отобразить:

```js
!teb
dt nt!_TEB
```

#### [](#header-4)Посмотреть потоки другого процесса:

```js
kd> !process 0 4 processname.exe
kd> dt nt!_KTHREAD ffffe20faeb39080
```

## [](#header-2)Получаем руками все процессы:

#### [](#header-4)Общая идея примерно такая:

1. Из **PsActiveProcessHead** получаем адрес, где лежит head списка процессов
2. Само значение, которое мы получили, уже является ссылкой на следующий объект списка (то есть FLINK - forward link)
3. Адрес, который мы получили - это структура LIST_ENTRY, в которой два поля: на след объект и на предыдущий, сам по себе этот полученный адрес лежит в середине структуры процесса в ActiveProcessLinks
4. Получаем начало структуры процесса отнимая от полученного адреса сдвиг до начала

```js
kd> x nt!PsActiveProcessHead
fffff803`5f01df60 nt!PsActiveProcessHead = <no type information>

kd> dq fffff803`5f01df60
fffff803`5f01df60  ffffca86`79a5b488 ffffca86`806b5788
fffff803`5f01df70  00000000`000001f4 00000000`00000000
fffff803`5f01df80  00000000`00000000 00000000`00000000
fffff803`5f01df90  fffff803`5ed07ea0 00000000`00000000

kd> dt nt!_EPROCESS
...
+0x448 ActiveProcessLinks : _LIST_ENTRY
...

kd> ?ffffca86`79a5b488 - 0x448
Evaluate expression: -58796061380544 = ffffca86`79a5b040

kd> dt nt!_EPROCESS ffffca86`79a5b040
(как прувнуть, что всё ок)
...
+0x5a8 ImageFileName    : [15]  "System"
```

#### [](#header-4)Как получить следующие в списке процессы?

1. Берём значение из ActiveProcessLinks
2. Первый адрес - flink, второй - blink
3. Отнимаем оффсет
4. Дампим структуру

#### [](#header-4)Автоматизация:

```js
dt nt!_EPROCESS -l ActiveProcessLinks.Flink ffffca86`79a5b040
```

## [](#header-2)Получаем руками все потоки процесса:

```js
kd> !process 0 0
...
PROCESS ffffca8680630080
    SessionId: 1  Cid: 19cc    Peb: 002ff000  ParentCid: 0abc
    DirBase: 135b3000  ObjectTable: ffffb60d17072980  HandleCount:  57.
    Image: threads.exe
...

kd> dt nt!_EPROCESS ffffca8680630080
...
+0x5e0 ThreadListHead   : _LIST_ENTRY [ 0xffffca86`818bc9e8 - 0xffffca86`7bf5e9e8 ]
...

kd> dt nt!_ETHREAD
...
+0x4e8 ThreadListEntry  : _LIST_ENTRY
...

kd> ?0xffffca86`818bc9e8 - 0x4e8
Evaluate expression: -58795928861440 = ffffca86`818bc500

kd> dt nt!_ETHREAD -l ThreadListEntry.Flink -y Thread ffffca86`818bc500
...
ThreadListEntry.Flink at 0xffffca86`818bc500
+0x4e8 ThreadListEntry : _LIST_ENTRY [ 0xffffca86`851e59e8 - 0xffffca86`80630660 ]
...
ThreadListEntry.Flink at 0xffffca86`851e5500
+0x4e8 ThreadListEntry : _LIST_ENTRY [ 0xffffca86`7e37c9e8 - 0xffffca86`818bc9e8 ]
...
ThreadListEntry.Flink at 0xffffca86`7e37c500
+0x4e8 ThreadListEntry : _LIST_ENTRY [ 0xffffca86`7bf5e9e8 - 0xffffca86`851e59e8 ]
...
ThreadListEntry.Flink at 0xffffca86`7bf5e500
+0x4e8 ThreadListEntry : _LIST_ENTRY [ 0xffffca86`80630660 - 0xffffca86`7e37c9e8 ]
...
```

#### [](#header-4)напочитать:

[Английская статья, откуда брал почти весь материал и пара ссылок на структуры / Understanding LIST_ENTRY Lists and Its Importance in Operating Systems - Meena Chockalingam](https://www.codeproject.com/Articles/800404/Understanding-LIST-ENTRY-Lists-and-Its-Importance)

[Ядерные и не только структуры](http://terminus.rewolf.pl/terminus/structures/ntdll/_EPROCESS_x64.html)

[Чего там с этими LIST_ENTRY то](https://blog.fearcat.in/a?ID=01550-e4fe17fe-3059-472f-97a7-7e77c7b72302)
