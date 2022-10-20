---
title: Немного о прерываниях, их обработке и есесна ядре
published: true
tags: [ "windows", "internals" ]
image: /assets/previews/4.jpg
layout: page
pagination: 
  enabled: true
---

Тут будет перевод одной статейки для погружения в теорию:

[статейка](https://codemachine.com/articles/interrupt_dispatching.html)

## [](#header-2)Interrupt Dispatching Internals

Microsoft изменили способ обработки прерываний в последних версиях Windows. Были опубликованы некоторые [публичные ресёрчи](http://phrack.org/issues/65/4.html) по обработке прерываний на старых версиях Windows и на 32-битных системах, однако не так много информации можно найти о том, как это работает в современном мире. В этой статье я попытаюсь привести описание обработки исключений на 64-битной Windows 10, в особенности Windows 10 RS1 Anniversary Update Build 10.0.10586

Прерывания используются операционными системами, чтобы получать сообщения об ивентах, происходящих на оборудовании. Обработка исключений - это механизм, в котором процессор передаёт контроль исполнения программному обеспечению, чтобы обработать событие на оборудовании. Прерывания обрабатываются ядром Windows, которое сначала выполняет некоторые служебные действия перед передачей контроля исполнения драйверам железа, которые в свою очередь регистрируют ISR (функции обработчика прерывания). IDT (Interrupt Descriptor Table) - это основная структура, задействованная в обработке исключений и её формат [устанавливает разработчик процессора](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-3c-part-3-manual.pdf). IDT должна быть заполнена на этапе загрузки и соответственно должна использоваться процессором для обработки прерываний, приходящих с устройств

### [](#header-3)IDTR Register

У процессоров есть встроенный регистр, называемый IDTR, который Windows заполняет виртуальным адресом IDT в ядре, который он устанавливает для каждого процессора на этапе загрузки.

![IDTR Structure](/assets/idtr_structure.png)

Значение регистра IDTR для каждого процессора. На мульти процессорной системе каждый процессор имеет свой IDTR регистр, который указывает на локальную приватную копию IDT

```js
0: kd> ~0
0: kd> r @idtr
idtr=fffff8051ae62000

0: kd> ~1
1: kd> r @idtr
idtr=ffffb70107dad000

1: kd> ~2
2: kd> r @idtr
idtr=ffffb701077ea000
```

### [](#header-3)Interrupt Descriptor Table

IDT содержит всего 256 значений, некоторые из которых используются для исключений, некоторые для программных прерываний, а остальные для прерываний железа. Индекс в IDT, по которому выбирают конкретный элемент, называется вектором прерывания. Формат каждого элемента IDT описывается разработчиком процессора.

![TrapGate Structure](/assets/trapgate.png)

Ядро Windows определяет структуру KIDTENTRY64, которая представляет собой один элемент IDT на 64-битном процессоре. Используя вывод предыдущей команды "r @idtr", мы можем вывести нулевой элемент IDT, на который указывает IDTR


```js
0: kd> ~0
0: kd> r @idtr
idtr=fffff8051ae62000
0: kd> dt nt!_KIDTENTRY64 fffff8051ae62000
   +0x000 OffsetLow        : 0x1c00
   +0x002 Selector         : 0x10
   +0x004 IstIndex         : 0y000
   +0x004 Reserved0        : 0y00000 (0)
   +0x004 Type             : 0y01110 (0xe)
   +0x004 Dpl              : 0y00
   +0x004 Present          : 0y1
   +0x006 OffsetMiddle     : 0x1800
   +0x008 OffsetHigh       : 0xfffff805
   +0x00c Reserved1        : 0
   +0x000 Alignment        : 0x18008e00`00101c00
```

Комбинация OffsetHigh, OffsetMiddle и OffsetLow даёт нам виртуальный адрес, куда процессор передаст поток выполнения, когда произойдёт прерывание. В выводе выше виртуальный адрес - 0xfffff80518001c00. Это совпадает с выводом "!idt 0" и указывает на фукнцию KiDivideErrorFault(). Значение поля Type в выводе выше (0xe) показывает, что поле в IDT представляет собой Interrupt Gate

```js
0: kd> !idt 0

Dumping IDT: fffff8051ae62000

00:	fffff80518001c00 nt!KiDivideErrorFault
```

Первые N элементов в IDT нужны для обработки исключений и определены разработчиком процессора. Остальные элементы или используются для программных прерываний, или для хардварных, или не используются вовсе. В выводе "!idt" хардварные прерывания очень просто определить: у них есть указатель на структуру KINTERRUPT. "!idt -a" показывает значения всей IDT

```js
0: kd> !idt -a

Dumping IDT: fffff8051ae62000

00:	fffff80518001c00 nt!KiDivideErrorFault
01:	fffff80518001f40 nt!KiDebugTrapOrFault	Stack = 0xFFFFF8051AEA0000
02:	fffff80518002440 nt!KiNmiInterrupt	Stack = 0xFFFFF8051AE92000
03:	fffff80518002900 nt!KiBreakpointTrap
04:	fffff80518002c40 nt!KiOverflowTrap
05:	fffff80518002f80 nt!KiBoundFault
06:	fffff805180034c0 nt!KiInvalidOpcodeFault
07:	fffff805180039c0 nt!KiNpxNotAvailableFault
08:	fffff80518003cc0 nt!KiDoubleFaultAbort	Stack = 0xFFFFF8051AE8B000
09:	fffff80518003fc0 nt!KiNpxSegmentOverrunAbort
0a:	fffff805180042c0 nt!KiInvalidTssFault
0b:	fffff805180045c0 nt!KiSegmentNotPresentFault
0c:	fffff80518004980 nt!KiStackFault
0d:	fffff80518004cc0 nt!KiGeneralProtectionFault
0e:	fffff80518005000 nt!KiPageFault
0f:	fffff80517ff99e8 nt!KiIsrThunk+0x78
10:	fffff80518005640 nt!KiFloatingErrorFault
11:	fffff80518005a00 nt!KiAlignmentFault
12:	fffff80518005d40 nt!KiMcheckAbort	Stack = 0xFFFFF8051AE99000
13:	fffff80518006840 nt!KiXmmException
14:	fffff80518006c00 nt!KiVirtualizationException
15:	fffff80518007100 nt!KiControlProtectionFault
16:	fffff80517ff9a20 nt!KiIsrThunk+0xB0
17:	fffff80517ff9a28 nt!KiIsrThunk+0xB8
18:	fffff80517ff9a30 nt!KiIsrThunk+0xC0
19:	fffff80517ff9a38 nt!KiIsrThunk+0xC8
1a:	fffff80517ff9a40 nt!KiIsrThunk+0xD0
1b:	fffff80517ff9a48 nt!KiIsrThunk+0xD8
1c:	fffff80517ff9a50 nt!KiIsrThunk+0xE0
1d:	fffff80517ff9a58 nt!KiIsrThunk+0xE8
1e:	fffff80517ff9a60 nt!KiIsrThunk+0xF0
1f:	fffff80517ffb220 nt!KiApcInterrupt
20:	fffff80517ffce00 nt!KiSwInterrupt
```

В этой статье мы сфокусируемся на хардварных прерываниях, соответственно последние элементы IDT. hex значение в первой колонке - это вектор или индекс прерывания, по которому и находится конкретное прерывание в IDT. Как было сказано ранее, каждый элемент IDT указывает на набор инструкций, которые будут выполнены, как один из этапов обработки исключения.

Давайте возьмём второй элемент в хардварной части IDR, вектор 0x50

```js
0: kd> !idt 50

Dumping IDT: fffff8051ae62000

50:	fffff80517ff9bf0 dxgkrnl!DpiFdoLineInterruptRoutine (KINTERRUPT ffffb70107b9c500)
```

Выведем IDT 0x50, используя IDTR

```js
0: kd> dt nt!_KIDTENTRY64 @idtr+0x50*0x10
   +0x000 OffsetLow        : 0x9bf0
   +0x002 Selector         : 0x10
   +0x004 IstIndex         : 0y000
   +0x004 Reserved0        : 0y00000 (0)
   +0x004 Type             : 0y01110 (0xe)
   +0x004 Dpl              : 0y00
   +0x004 Present          : 0y1
   +0x006 OffsetMiddle     : 0x17ff
   +0x008 OffsetHigh       : 0xfffff805
   +0x00c Reserved1        : 0
   +0x000 Alignment        : 0x17ff8e00`00109bf0
   
0: kd> dt @idtr + @@c++(0x50 * sizeof(nt!_KIDTENTRY64)) nt!_KIDTENTRY64 
   +0x000 OffsetLow        : 0x9bf0
   +0x002 Selector         : 0x10
   +0x004 IstIndex         : 0y000
   +0x004 Reserved0        : 0y00000 (0)
   +0x004 Type             : 0y01110 (0xe)
   +0x004 Dpl              : 0y00
   +0x004 Present          : 0y1
   +0x006 OffsetMiddle     : 0x17ff
   +0x008 OffsetHigh       : 0xfffff805
   +0x00c Reserved1        : 0
   +0x000 Alignment        : 0x17ff8e00`00109bf0
```

Когда появляется прерывание, исполнение кода передаётся в 0xfffff80517ff9bf0
Этот адрес указывает на исполняемую страницу памяти в NTOSKRNL и содержит следующие инструкции:

```js
0: kd> u 0xfffff80517ff9bf0 L3
	nt!KiIsrThunk+0x280:
	fffff805`17ff9bf0 6a50            push    50h
	fffff805`17ff9bf2 55              push    rbp
	fffff805`17ff9bf3 e989050000      jmp     nt!KiIsrLinkage (fffff805`17ffa181)
```

Переменная KiIsrThunk из NTOSKRNL указывает на ядреную страницу кода, которая содержит 256 темплейтов, похожих на инструкции выше. После push interrupt vector (0x50) в этом случае и содержимого RBP регистра на стек, KiIsrThunk заглушка передаёт управление KiIsrLinkage(). Это 2 элемента на стеке используются функцией KiIsrLinkage() через структуру KTRAP_FRAME.

#### [](#header-4)KiIsrLinkage()

KiIsrLinkage() выполняет множество служебных задач:

* Сохраняет контекст изменяемого регистра в части KTRAP_FRAME, созданном в стеке
* Проверяет, выполнял ли во время прерывания процессор инструкции внтури конкретного региона функции ExpInterlockedPopEntrySList() и, если выполнял, он сбрасывает регистр RIP на допустимую инструкцию возобновления цикла в функции
* Проверяет, выключены ли прерывания и, если это так, багчекает систему на с кодом остановки TRAP_CAUSE_UNKNOWN
* Получает указатель на структуру прерывания, ассоциированную с прерыванием и обрабатывает прерывание
* Восстанавливает котекст изменяемого регистра из KTRAP_FRAME
* Возвращается из прерывания

Интересно, что большинство частей функции KiIsrLinkage() созданы из макросов, многие из которых доступны в заголовочном файле WDK kxamd64.inc, например GENERATE_INTERRUPT_FRAME, ENTER_INTERRUPT, EXIT_INTERRUPT и RESTORE_TRAP_STATE

#### [](#header-4)KINTERRUPT

Структура KINTERRUPT - основной ключ к обработке прерываний, она содержит всю информацию, необходимую для вызова ISR(interrupt service routine), зарегистрированной драйвером. KiIsrLinkage() определяет, где находится структура KINTERRUPT, связанная с вектором прерывания, используя его, как индекс в массиве указателей структур KINTERRUPT, находищихся в KPCR.CurrentPrcb.InterruptObject[]. Функция KiGetInterruptObjectAddress() из NTOSKRNL получает указатель на объект KINTERRUPT, показано ниже:

```js
0: kd> uf nt!KiGetInterruptObjectAddress
	nt!KiGetInterruptObjectAddress:
	fffff805`17f771d0 65488b142520000000 mov   rdx,qword ptr gs:[20h]
	fffff805`17f771d9 4881c240310000  add     rdx,3140h
	fffff805`17f771e0 8bc1            mov     eax,ecx
	fffff805`17f771e2 488d04c2        lea     rax,[rdx+rax*8]
	fffff805`17f771e6 c3              ret
```

```js
0: kd> !idt 50
Dumping IDT: fffff8051ae62000
50:	fffff80517ff9bf0 dxgkrnl!DpiFdoLineInterruptRoutine (KINTERRUPT ffffb70107b9c500)

0: kd> dt @$pcr nt!_KPCR -a Prcb.InterruptObject[50]
   +0x180 Prcb                     : 
      +0x3140 InterruptObject          : [80] 0xffffb701`07b9c500 Void

0: kd> dt nt!_KINTERRUPT 0xffffb70107b9c500
   +0x000 Type             : 0n22
   +0x002 Size             : 0n288
   +0x008 InterruptListEntry : _LIST_ENTRY [ 0x00000000`00000000 - 0x00000000`00000000 ]
   +0x018 ServiceRoutine   : 0xfffff805`1b051e60     unsigned char  dxgkrnl!DpiFdoLineInterruptRoutine+0
   +0x020 MessageServiceRoutine : (null) 
   +0x028 MessageIndex     : 0
   +0x030 ServiceContext   : 0xffff990e`5377a030 Void
   +0x038 SpinLock         : 0
   +0x040 TickCount        : 0
   +0x048 ActualLock       : 0xffff990e`530eea10  -> 0
   +0x050 DispatchAddress  : 0xfffff805`17ff8c70     void  nt!KiInterruptDispatch+0
   +0x058 Vector           : 0x50
   +0x05c Irql             : 0x5 ''
   +0x05d SynchronizeIrql  : 0x5 ''
   +0x05e FloatingSave     : 0 ''
   +0x05f Connected        : 0x1 ''
   +0x060 Number           : 0
   +0x064 ShareVector      : 0x1 ''
   +0x065 EmulateActiveBoth : 0 ''
   +0x066 ActiveCount      : 0
   +0x068 InternalState    : 0n0
   +0x06c Mode             : 0 ( LevelSensitive )
   +0x070 Polarity         : 0 ( InterruptPolarityUnknown )
   +0x074 ServiceCount     : 0
   +0x078 DispatchCount    : 0
   +0x080 PassiveEvent     : (null) 
   +0x088 TrapFrame        : 0xfffff805`1ae6e520 _KTRAP_FRAME
   +0x090 DisconnectData   : (null) 
   +0x098 ServiceThread    : (null) 
   +0x0a0 ConnectionData   : 0xffff990e`53931cc0 _INTERRUPT_CONNECTION_DATA
   +0x0a8 IntTrackEntry    : 0xffff990e`532cc500 Void
   +0x0b0 IsrDpcStats      : _ISRDPCSTATS
   +0x110 RedirectObject   : (null) 
   +0x118 PhysicalDeviceObject : 0xffff990e`50fc2360 Void
```

Поля структуры KINTERRUPT, которые относятся к обработке прерываний:

| Название     | Описание          |
|:-------------|:------------------|
| DispatchAddress| Указатель на начальный программный обработчик прерываний в NTOSKRNL (KiChainedDispatch() ) для общих прерываний и KiInterruptDispatch() для других |
| ServiceRoutine | Указатель на программный обработчик прерываний, зарегистрированный драйвером с помощью API ядра IoConnectInterrupt() или IoConnectInterruptEx() |
| MessageServiceRoutine | Используется только для MSI (message signaled interrupts - прерывания, инициируемые сообщениями), т.е. прерывания, которые доставляются путём записи в зарезервированные участи памяти вместо переключения аппаратных линий. Эти прерывания показываются, как отрицательные числа в device manager'e. Для таких прерываний ServiceRoutine указывает на ядерную функцию KiInterruptMessageDispatch(), которая вызывает ISR, связанную с драйвером в MessageServiceRoutine |
| MessageIndex | Индекс MSI, передаваемый, как параметр в ISR у MessageServiceRoutine |

В старых версиях Windows KINTERRUPT аллоцировалась из исполняемого невыгружаемого пула памяти, так как содержала начальный код обработки, который был зарегистрирован прямо в IDT. Из-за перехода к механизму из KiIsrThunk() и KiIsrLinkage(), описанному выше, начальная заглушка для прерывания теперь находится в исполняемой памяти в NTOSKRNL и, соответственно, структуре KINTERRUPT больше не нужно быть аллоцированной из исполняемой памяти. Структуры KINTERRUPT теперь пре-аллоцируются и хранятся в списке в KPCR.Prcb.InterruptObjectPool. Функция KeAllocateInterrupt() забирает пре-аллоцированную структуру KINTERRUPT из списка, когда вызывается для аллокации новой структуры KINTERRUPT. Когда этот список заканчивается, алооцируется ещё одна страница со структурами с помощью MmAllocateIndependentPages(), и добалвяет их в список.

#### [](#header-4)Interrupt Dispatching

Одним из важных шагов, предпринятых KiIsrLinkage, является вызов функции в KINTERRUPT.DispatchAddress, что приводит к вызову либо KiInterruptDispatch(), либо KiChainedDispatch(). Обе эти функции вызываются с указателем на структуру KINTERRUPT, как будто у них есть доступ ко всей информации, относящейся к обработке прерывания.

Новые системы используют APIC (Advanced Programmable Interrupt Controller) для обработки прерываний с устройств. Устройства отправляют свои прерывания на процессор с помощью IRQ линий. Однако, устройств больше, чем IRQ линий. Общие прерывания убирают проблему позволяя использовать одни и те же IRQ линии множеству устройств. Когда IRQ шарится, множество драйверов регистрирует свои ISR'ы для одного и того же IRQ и вектора прерывания. Из этого вытекает множественная структура KINTERRUPT, соответствующая устройствам, которые делят прерывание, и на них ссылаются вместе с помощью их полей KINTERRUPT.InterruptListEntry. Увидеть это можно с помощью "!idt -a", когда одному вектору прерывания соответствует множество структур KINTERRUPT, связанных с ним. KiChainedDispatch() обрабатывает прерывания, которые шарятся с множеством устройств, а KiInterruptDispatch() обрабатывает остальные прерывания.

Функции KiInterruptDispatch() и KiChainedDispatch меняются в зависимости от стека прерывания процессора, указатель на который хранится в KPCR.Prb.IsrStack. Этот стек аллоцируется функцией MmAllocateIsrStack(). Размер ISR стека 0x7000 байт, как определено переменными ISR_STACK_SIZE и PAGE_SIZE в заголовочном файле ksamd64.inc WDK. Непосредственный переход на стек ISR происходит с помощью макроса SWITCH_TO_ISR_STACK и также доступен в ksamd64.inc.

Как только выполнение перешло на стек ISR, функции KiInterruptDispatch() и KiChainedDispatch() передают выполнение следующей стадии, вызывая KiInterruptSubDispatch() или KiScanInterruptObjectList() соответственно.

KiInterruptSubDispatch() вызывает KiCallInterruptServiceRoutine() для одиночной структуры KINTERRUPT.

KiScanInterruptObjectList() итерируется по всем объектам KINTERRUPT, зарегистрированным для одного вектора прерывания, используя список KINTERRUPT.InterruptListEntry и вызывает KiCallInterruptServiceRoutine() для каждого KINTERRUPT в цепочке.

KiCallInterruptServiceRoutine() выполняет следующие задачи:
* Помечает прерывание, как активное в KINTERRUPT.IsrDpcStats.IsrActive
* Записывает время начала ISR в KINTERRUPT.IsrDpcStats.IsrTimeStart
* Получает спин-блокировку прерывания в KINTERRUPT.ActualLock
* Вызывает драйвер, зарегистрированный ISR в KINTERRUPT.ServiceRoutine
* Записывает длительность ISR в KINTERRUPT.IsrDpcStats.IsrTime
* Если ISR была прервана другой ISR с большим уровнем IRQL, он подстраивает IsrTime для точного учёта времени
* Помечает прерывание как неактивное в KINTERRUPT.IsrDpcStats.IsrActive
* Инкрементирует счётчик экземпляров прерываний в IsrCount

Драйвер, который регистрировал ISR, может сообщить вызывающей функции KiCallInterruptServiceRoutine(), забрал ли он на обработку прерывание, вернув TRUE. Это становится важным в случае пошареных прерываний, где решение вызвать ISR в следующем KINTERRUPT в цепочке или нет зависит от того, забрал ли текущий ISR прерывание на обработку.
Следующая диаграмма показывает все структуры, описанные выше и отношения между ними.

![KiInterrupt Structure](/assets/Kiinterstr.png)

Как и в предыдущих версиях Windows 64, и IDTR, и содержимое IDT защищено PatchGuard (kernel patch protection). Делая структуру KINTERRUPT неисполняемой и удаляю код обработки из структуры, мы закрываем ещё один вектор subversion. Однако, даже с этими новыми изменениями в обработке исключений всё равно возможно для драйвера ядра хукнуть ISR в системе для реализации своего функционала, например для кейлоггера. ISR драйвера в поле KINTERRUPT.ServiceRoutine может быть заменено указателем на хук-функцию и PatchGuard этого не заметит. Так же не заметит, если KINTERRUPT, хранящийся в KPCR.Prcb.InterruptObject[] будет заменён клонированной структурой KINTERRUPT, который будет вести к выполнению кода.

IDT - Interrupt Descriptor Table (таблица дескрипторов прерываний)
Там хранятся элементы \_KIDENTRY или \_KIDENTRY64 соответственно
В каждой из них есть ссылка на ISR (Interrupt Service Routine) - непостредственно функция, которая вызывается

### [](#header-3)Вторая статья и практика-практика-практика

Механизм прерываний - ещё один важный элемент уровня железа

Прерывания можно рассматривать, как события уровня железа, использующиеся для сигнализирования процессору, что что-то требует немедленного внимания
* Прерывания устройств
Устройства (сетевая карта, клавиатура и тд) вызовут прерывание, чтобы
сигнализировать процессору, что у них есть новая информация для обработки
(входящий сетевой пакет, нажатие на клавишу и тд)
* Ловушки / исключения
Эти вещи обычно происходят, когда процессор сталкивается с ошибкой,
такой как деление на ноль или ошибка страницы
* Программные прерывания
Это такие прерывания, которые генерируются программами, например INT 2E (syscall)
используется для перехода из user mode в kernel mode. INT 3 используется
для генерации программного брейкпоинта и тд Значение, которое идёт за инструкцией INT называется вектором прерывания, это просто индекс в IDT (Interrupt Descriptor Table). IDT ассоциирует вектор прерывания с конкретной функцией, которая будет обрабатывать вызванное прерывание. В WDK (Windows Driver Kit) такая функция называется ISR (Interrupt Service Routine)

С точки зрения железа прерывания обрабатываются конкретным куском железа, называемым PIC (Programmable Interrupt Controller - контроллер прерываний). Сейчас у нас обычно стоит новая версия PIC - APIC (Advanced Programmable Interrupt Controller), встроенная прямо в процессов

Плюсы APIC:
* Поддержка многопроцессорности
* Больше линий прерываний (256 vs 15 для PIC)

Для каждого CPU свой APIC, и каждый APIC может коммуницировать с другими APIC'ами через IPI (Inter-processor interrupt message)

Одна большая задача в обработке прерываний, которую выполняет APIC - это управление приоритетами прерываний. Каждой линии прерываний выдан свой приоритет и APIC проверяет, что ни один входящий запрос на прерывание с приоритетом ниже или равным текущему обрабатываемому прерыванию не достигнет процессор, обычно это называют Interrupt Masking

Заметьте, что некоторые особые прерывания не могут был замаскированы и всегда будут достигать процессор, они называются NMI (Non-maskable interrupt). Они обычно предназначены для неустранимого сбоя оборудования, что означает, что у вас серьёзные проблемы с железом.

Прерывания, приходящие от устройств, сначала обрабатываются I/O APIC, специальным чипом, встроенным в чипсет, его роль - распределять прерывания по локальным APIC'ам всех CPU, таким образом включая SMP (Symmetric multiprocessing - Симметричная многопроцессорность)

![APIC Structure](/assets/APIC.png)

Когда прерывание достигает CPU, процессор и процедура прерывания ОС сохранят стостояние значения регистров в стеке ядра, чтобы можно было восстановить предыдущий поток выполнения и продолжить исполнение кода. Этот набор сохраняемых регистров и некотороая дополнителья информация (например код ошибки) обычно называются Trap Frame (.trap в windbg)

Углубимся немного в механизм обработки прерываний. Откуда процессор знает, где расположения IDT? Ответ - в регистре IDTR. 48-битный регистр делится на две части: 16-бит - IDT limit и 32-бита - base address

Максимальное количество записей в IDT - 256. Каждая запись - 8 бит, содержит флаги, сегментные селекторы, gate type и оффсет или адрес ISR.

Оффсет тоже разделён на две части: биты 0..15 - для младших битив и 48..63 - для старших битов

В винде IDT entry - это \_KIDTENTRY

```js
kd> dt nt!_KIDTENTRY
   +0x000 Offset           : Uint2B
   +0x002 Selector         : Uint2B
   +0x004 Access           : Uint2B
   +0x006 ExtendedOffset   : Uint2B
```

Чтобы отобразить IDT в windbg есть !idt

```js
kd> !idt

Dumping IDT: 8003f400

30:	806f5d50 hal!HalpClockInterrupt
31:	89ec9044 i8042prt!I8042KeyboardInterruptService (KINTERRUPT 89ec9008)

38:	806efef0 hal!HalpProfileInterrupt
39:	89fed174 ACPI!ACPIInterruptServiceRoutine (KINTERRUPT 89fed138)

	         NDIS!ndisMIsr (KINTERRUPT 89f228d8)

3a:	89f24044 VIDEOPRT!pVideoPortInterrupt (KINTERRUPT 89f24008)

	         USBPORT!USBPORT_InterruptService (KINTERRUPT 89eae008)

3b:	8a01d6c4 VBoxGuest+0x27c0 (KINTERRUPT 8a01d688)

portcls!CKsShellRequestor::`scalar deleting destructor'+0x26 (KINTERRUPT 89f179c0)

3c:	89ead564 i8042prt!I8042MouseInterruptService (KINTERRUPT 89ead528)

3e:	89fea9d4 atapi!IdePortInterrupt (KINTERRUPT 89fea998)

3f:	8a03d044 atapi!IdePortInterrupt (KINTERRUPT 8a03d008)
```

Например разберём поближе i8042prt!I8042KeyboardInterruptService
Для проверки, что это такое вообще (ну вдруг мы по названию не догадались) поставим бряку на него

```js
kd> u i8042prt!I8042KeyboardInterruptService
i8042prt!I8042KeyboardInterruptService:
f76a7495 6a18            push    18h
f76a7497 68a8a76af7      push    offset i8042prt!`string'+0x154 (f76aa7a8)
f76a749c e8fa000000      call    i8042prt!_SEH_prolog (f76a759b)
f76a74a1 8b7d0c          mov     edi,dword ptr [ebp+0Ch]
f76a74a4 8b7728          mov     esi,dword ptr [edi+28h]
f76a74a7 837e3001        cmp     dword ptr [esi+30h],1
f76a74ab 0f8582130000    jne     i8042prt!I8042KeyboardInterruptService+0xa2 (f76a8833)
f76a74b1 a100a96af7      mov     eax,dword ptr [i8042prt!Globals (f76aa900)]

kd> bu i8042prt!I8042KeyboardInterruptService

kd> bl
     0 e Disable Clear  f76a7495     0001 (0001) i8042prt!I8042KeyboardInterruptService
kd> g

Breakpoint 0 hit
i8042prt!I8042KeyboardInterruptService:
f76a7495 6a18            push    18h
```

![KIS Structure](/assets/kisbreak.png)

Мы нажали на любую кнопку --> наш брейкпоинт сработал

Но давайте доберёмся до кода в статике, ведь то, что написано в выводе команды !idt (31: 89ec9044 i8042prt! …) не совпадает с фактическим адресом ISR
Каждый элемент IDT занимает 8 байт, мы решили, что нам нужен индекс 31 (такой индекс у нужной нам функции), что нам нужно сделать?

idtr + 0x31 * 8 -->
```js
kd> r idtr
idtr=8003f400

kd> dd @idtr+8*0x31
8003f588 - 00089044 89ec8e00 0008dd14 804d8e00 --> 0x89ec9044
8003f598 - 0008dd1e 804d8e00 0008dd28 804d8e00
8003f5a8 - 0008dd32 804d8e00 0008dd3c 804d8e00
8003f5b8 - 0008dd46 804d8e00 0008fef0 806e8e00
8003f5c8 - 0008d174 89fe8e00 00084044 89f28e00
8003f5d8 - 0008d6c4 8a018e00 0008d564 89ea8e00
8003f5e8 - 0008dd82 804d8e00 0008a9d4 89fe8e00
8003f5f8 - 0008d044 8a038e00 0008dda0 804d8e00

```

И так наш ISR адрес 0x89ec9044, но мы же вроде бы только что дампили I8042KeyboardInterruptService и его адрес был 0xf76a7495, непонятно

Чтож, перед тем, как вызывать ISR'ры драйверов системе нужно выполнить некоторые задачи: маскирование прерываний с более низким приоритетом в APIC, поднятие уровня IRQL и тд

Так что вместо того, чтобы заполнить IDT ISR'ами, система заполняет их glue кодом или же иначе функциями-темплейтами

Каждая темплейт-функция взята (скопирована) из KiInterruptTemplate функции и динамически модифицирована, чтобы подходить соответствующему ISR'у

Давайте посмотрим на темплейт нашей KeyboardInterruptService:
![KiInterruptTemplate Structure](/assets/KiInterruptTemplate.png)

Мы можем заметить, что почти весь код скопирован с оригинального KiInterruptTemplate. Однако есть одна интересная особенность:
темплейт функции клавиатуры вызывает KiInterruptDispatch и кладёт в EDI адрес 0x89EC9008

Этот адрес указывает на interrupt object с типом _KINTERRUPT:
```js
kd> dt nt!_KINTERRUPT 0x89EC9008
   +0x000 Type             : 0n22
   +0x002 Size             : 0n484
   +0x004 InterruptListEntry : _LIST_ENTRY [ 0x89ec900c - 0x89ec900c ]
   +0x00c ServiceRoutine   : 0xf76a7495     unsigned char  i8042prt!I8042KeyboardInterruptService+0
   +0x010 ServiceContext   : 0x89f259d0 Void
   +0x014 SpinLock         : 0
   +0x018 TickCount        : 0xffffffff
   +0x01c ActualLock       : 0x89f25a90  -> 0
   +0x020 DispatchAddress  : 0x804da8e8     void  nt!KiInterruptDispatch+0
   +0x024 Vector           : 0x31
   +0x028 Irql             : 0x1a ''
   +0x029 SynchronizeIrql  : 0x1a ''
   +0x02a FloatingSave     : 0 ''
   +0x02b Connected        : 0x1 ''
   +0x02c Number           : 0 ''
   +0x02d ShareVector      : 0 ''
   +0x030 Mode             : 1 ( Latched )
   +0x034 ServiceCount     : 0
   +0x038 DispatchCount    : 0xffffffff
   +0x03c DispatchCode     : [106] 0x56535554
```

Как видно выше, как раз в ServiceRoutine хранится адрес ISR
Если мы теперь посмотрим на KiInterruptDispatch мы увидим, что он вызывает interrupt object ServiceRoutine

```js
kd> u nt!KiInterruptDispatch L30
nt!KiInterruptDispatch:
804da8e8 ff05c4f5dfff    inc     dword ptr ds:[0FFDFF5C4h]
804da8ee 8bec            mov     ebp,esp
804da8f0 8b4724          mov     eax,dword ptr [edi+24h]
804da8f3 8b4f29          mov     ecx,dword ptr [edi+29h]
804da8f6 50              push    eax
804da8f7 83ec04          sub     esp,4
804da8fa 54              push    esp
804da8fb 50              push    eax
804da8fc 51              push    ecx
804da8fd ff1504764d80    call    dword ptr [nt!_imp__HalBeginSystemInterrupt (804d7604)]
804da903 0bc0            or      eax,eax
804da905 7436            je      nt!KiInterruptDispatch+0x55 (804da93d)
804da907 83ec0c          sub     esp,0Ch
804da90a 833d0c23568000  cmp     dword ptr [nt!PPerfGlobalGroupMask (8056230c)],0
804da911 c745f400000000  mov     dword ptr [ebp-0Ch],0
804da918 752b            jne     nt!KiInterruptDispatch+0x5d (804da945)
804da91a 8b771c          mov     esi,dword ptr [edi+1Ch]
804da91d 8b4710          mov     eax,dword ptr [edi+10h]
804da920 50              push    eax
804da921 57              push    edi
804da922 ff570c          call    dword ptr [edi+0Ch]

kd> dt nt!_KINTERRUPT 0x89EC9008
...
   +0x00c ServiceRoutine   : 0xf76a7495     unsigned char  i8042prt!I8042KeyboardInterruptService+0
...
```

Вся структура вызовов:
![Interrupt Call Structure](/assets/interruptcallstr.png)

И как создаётся interrupt object?

Это роль драйвера заполнить структуру, вызвав IoConnectInterrupt

#### [](#header-4)Добавим ещё немного экспериментов:

Давайте посмотрим на прерывание и исключение деления на ноль

Оно у нас самое первое в таблице IDT

```js
kd> !idt -a

Dumping IDT: 8003f400

00:	804df370 nt!KiTrap00
01:	804df4eb nt!KiTrap01
02:	Task Selector = 0x0000
03:	804df8bd nt!KiTrap03
04:	804dfa40 nt!KiTrap04
05:	804dfba1 nt!KiTrap05
06:	804dfd22 nt!KiTrap06
07:	804e038a nt!KiTrap07
```

Поставим бряку ```bu nt!KiTrap00```

И на машине скомпилим какой-нибудь такой код:

```c
#include <stdio.h>
#include <Windows.h>

int main() {
	sleep(5);
	printf("Go!\n");
	int x = 10;
	int y;
	scanf("%f", &y);
	printf("%f",  x / y);
	return 0;
}
```

Вводим ноль и Viola! брякаемся
```js
kd> !process 0 0
Failed to get VadRoot
PROCESS 897cf578  SessionId: 0  Cid: 06ac    Peb: 7ffdc000  ParentCid: 0e48
    DirBase: 825e9000  ObjectTable: e2c24c78  HandleCount:   7.
    Image: Untitled1.exe
    
kd> .process /i 897cf578 
You need to continue execution (press 'g' <enter>) for the context
to be switched. When the debugger breaks in again, you will be in
the new process context.
ReadVirtual: 8a01c688 not properly sign extended

kd> g
Break instruction exception - code 80000003 (first chance)
nt!RtlpBreakWithStatusInstruction:
804e351a cc              int     3
ReadVirtual: 8a01c688 not properly sign extended

00401500 55              push    ebp
00401501 89e5            mov     ebp,esp
00401503 83e4f0          and     esp,0FFFFFFF0h
00401506 83ec20          sub     esp,20h
00401509 e8b2090000      call    00401ec0
0040150e c7042405000000  mov     dword ptr [esp],5
00401515 e8b6100000      call    004025d0
0040151a c7042400404000  mov     dword ptr [esp],404000h
00401521 e832110000      call    00402658                    <-- printf("Go!\n")
00401526 c744241c0a000000 mov     dword ptr [esp+1Ch],0Ah
0040152e 8d442418        lea     eax,[esp+18h]
00401532 89442404        mov     dword ptr [esp+4],eax
00401536 c7042404404000  mov     dword ptr [esp],404004h
0040153d e81e110000      call    00402660                    <-- scanf
00401542 8bd9            mov     ebx,ecx
00401544 2418            and     al,18h
00401546 8b44241c        mov     eax,dword ptr [esp+1Ch]
0040154a 99              cdq
0040154b f7f9            idiv    eax,ecx
0040154d 89442404        mov     dword ptr [esp+4],eax
00401551 c7042404404000  mov     dword ptr [esp],404004h
00401558 e80b110000      call    00402668
0040155d b800000000      mov     eax,0
00401562 c9              leave
```

Падаем в обработку
![KiTrap Structure](/assets/KiTrap.png)

```js
...
804df3ea 55              push    ebp
804df3eb e8b6431400      call    nt!Ki386CheckDivideByZeroTrap (806237a6)
...
```

### [](#header-3)Посмотрим на 64-битную 10-ку

Тут всё выглядит поинтереснее, мб из-за отсутствия дебаг символом на XP'хе, а мб и нет

```js
kd> !idt

Dumping IDT: fffff80335462000

00:	fffff80330a01c00 nt!KiDivideErrorFault
01:	fffff80330a01f40 nt!KiDebugTrapOrFault	Stack = 0xFFFFF803354A0000
02:	fffff80330a02440 nt!KiNmiInterrupt	Stack = 0xFFFFF80335492000
03:	fffff80330a02900 nt!KiBreakpointTrap
04:	fffff80330a02c40 nt!KiOverflowTrap
05:	fffff80330a02f80 nt!KiBoundFault
06:	fffff80330a034c0 nt!KiInvalidOpcodeFault
07:	fffff80330a039c0 nt!KiNpxNotAvailableFault
08:	fffff80330a03cc0 nt!KiDoubleFaultAbort	Stack = 0xFFFFF8033548B000
09:	fffff80330a03fc0 nt!KiNpxSegmentOverrunAbort
0a:	fffff80330a042c0 nt!KiInvalidTssFault
0b:	fffff80330a045c0 nt!KiSegmentNotPresentFault
0c:	fffff80330a04980 nt!KiStackFault
0d:	fffff80330a04cc0 nt!KiGeneralProtectionFault
0e:	fffff80330a05000 nt!KiPageFault
10:	fffff80330a05640 nt!KiFloatingErrorFault
11:	fffff80330a05a00 nt!KiAlignmentFault
12:	fffff80330a05d40 nt!KiMcheckAbort	Stack = 0xFFFFF80335499000
13:	fffff80330a06840 nt!KiXmmException
14:	fffff80330a06c00 nt!KiVirtualizationException
15:	fffff80330a07100 nt!KiControlProtectionFault
1f:	fffff803309fb220 nt!KiApcInterrupt
20:	fffff803309fce00 nt!KiSwInterrupt
29:	fffff80330a07600 nt!KiRaiseSecurityCheckFailure
2c:	fffff80330a07940 nt!KiRaiseAssertion
2d:	fffff80330a07c80 nt!KiDebugServiceTrap
2f:	fffff803309fd3c0 nt!KiDpcInterrupt
30:	fffff803309fb7c0 nt!KiHvInterrupt
31:	fffff803309fbaa0 nt!KiVmbusInterrupt0
32:	fffff803309fbd80 nt!KiVmbusInterrupt1
33:	fffff803309fc060 nt!KiVmbusInterrupt2
34:	fffff803309fc340 nt!KiVmbusInterrupt3
35:	fffff803309f9b18 nt!HalpInterruptCmciService (KINTERRUPT fffff803312f2f40)
36:	fffff803309f9b20 nt!HalpInterruptCmciService (KINTERRUPT fffff803312f3180)
50:	fffff803309f9bf0 dxgkrnl!DpiFdoLineInterruptRoutine (KINTERRUPT ffffa600bf1fb500)
60:	fffff803309f9c70 USBPORT!USBPORT_InterruptService (KINTERRUPT ffffa600bf1fb780)
70:	fffff803309f9cf0 VBoxGuest+0x22e0 (KINTERRUPT ffffa600bf1fbb40)
80:	fffff803309f9d70 storport!RaidpAdapterInterruptRoutine (KINTERRUPT ffffa600bf1fbc80)
	                 HDAudBus!HdaController::Isr (KINTERRUPT ffffa600bf1fb640)
90:	fffff803309f9df0 i8042prt!I8042MouseInterruptService (KINTERRUPT ffffa600bf1fb8c0)
a0:	fffff803309f9e70 i8042prt!I8042KeyboardInterruptService (KINTERRUPT ffffa600bf1fba00)
b0:	fffff803309f9ef0 ACPI!ACPIInterruptServiceRoutine (KINTERRUPT ffffa600bf1fbdc0)
ce:	fffff803309f9fe0 nt!HalpIommuInterruptRoutine (KINTERRUPT fffff803312f3ba0)
d1:	fffff803309f9ff8 nt!HalpTimerClockInterrupt (KINTERRUPT fffff803312f3960)
d2:	fffff803309fa000 nt!HalpTimerClockIpiRoutine (KINTERRUPT fffff803312f3840)
d7:	fffff803309fa028 nt!HalpInterruptRebootService (KINTERRUPT fffff803312f3600)
d8:	fffff803309fa030 nt!HalpInterruptStubService (KINTERRUPT fffff803312f33c0)
df:	fffff803309fa068 nt!HalpInterruptSpuriousService (KINTERRUPT fffff803312f32a0)
e1:	fffff803309fd8b0 nt!KiIpiInterrupt
e2:	fffff803309fa080 nt!HalpInterruptLocalErrorService (KINTERRUPT fffff803312f34e0)
e3:	fffff803309fa088 nt!HalpInterruptDeferredRecoveryService (KINTERRUPT fffff803312f3060)
fd:	fffff803309fa158 nt!HalpTimerProfileInterrupt (KINTERRUPT fffff803312f3a80)
fe:	fffff803309fa160 nt!HalpPerfInterrupt (KINTERRUPT fffff803312f3720)
```

Возьмём снова наш обработчик клавиатуры по оффсету a0

```js
kd> dt _kidtentry64 (idtr + (0xa0*0x10))
ntdll!_KIDTENTRY64
   +0x000 OffsetLow        : 0x9e70
   +0x002 Selector         : 0x10
   +0x004 IstIndex         : 0y000
   +0x004 Reserved0        : 0y00000 (0)
   +0x004 Type             : 0y01110 (0xe)
   +0x004 Dpl              : 0y00
   +0x004 Present          : 0y1
   +0x006 OffsetMiddle     : 0x309f
   +0x008 OffsetHigh       : 0xfffff803
   +0x00c Reserved1        : 0
   +0x000 Alignment        : 0x309f8e00`00109e70
```

Найдём ISR entry point для него, теперь для 64 бит схема немного другая:

OffsetHigh + OffsetMiddle + OffsetLow

0xfffff803309f9e70

```js
Offset: 0xfffff803309f9e70
fffff803`309f9e70 6aa0            push    0FFFFFFFFFFFFFFA0h
fffff803`309f9e72 55              push    rbp
fffff803`309f9e73 e909030000      jmp     nt!KiIsrLinkage (fffff803`309fa181)
```

Если в табличке !idt искать KINTERRUPT не хочется, можно сделать так:
```js
kd> dt @$pcr nt!_KPCR -a Prcb.InterruptObject[0xa0]
   +0x180 Prcb                       : 
      +0x3140 InterruptObject            : [160] 0xffffa600`bf1fba00 Void
      
      
kd> dt nt!_KINTERRUPT ffffa600bf1fba00
   +0x000 Type             : 0n22
   +0x002 Size             : 0n288
   +0x008 InterruptListEntry : _LIST_ENTRY [ 0x00000000`00000000 - 0x00000000`00000000 ]
   +0x018 ServiceRoutine   : 0xfffff803`36096790     unsigned char  i8042prt!I8042KeyboardInterruptService+0
   +0x020 MessageServiceRoutine : (null) 
   +0x028 MessageIndex     : 0
   +0x030 ServiceContext   : 0xffffcf8b`4e304040 Void
   +0x038 SpinLock         : 0
   +0x040 TickCount        : 0
   +0x048 ActualLock       : 0xffffcf8b`4e3041a0  -> 0
   +0x050 DispatchAddress  : 0xfffff803`309f8c70     void  nt!KiInterruptDispatch+0
   +0x058 Vector           : 0xa0
   +0x05c Irql             : 0xa ''
   +0x05d SynchronizeIrql  : 0xa ''
   +0x05e FloatingSave     : 0 ''
   +0x05f Connected        : 0x1 ''
   +0x060 Number           : 0
   +0x064 ShareVector      : 0 ''
   +0x065 EmulateActiveBoth : 0 ''
   +0x066 ActiveCount      : 0
   +0x068 InternalState    : 0n0
   +0x06c Mode             : 1 ( Latched )
   +0x070 Polarity         : 0 ( InterruptPolarityUnknown )
   +0x074 ServiceCount     : 0
   +0x078 DispatchCount    : 0
   +0x080 PassiveEvent     : (null) 
   +0x088 TrapFrame        : 0xfffffb82`3ab14a20 _KTRAP_FRAME
   +0x090 DisconnectData   : (null) 
   +0x098 ServiceThread    : (null) 
   +0x0a0 ConnectionData   : 0xffffcf8b`4e467d00 _INTERRUPT_CONNECTION_DATA
   +0x0a8 IntTrackEntry    : 0xffffcf8b`4ccac690 Void
   +0x0b0 IsrDpcStats      : _ISRDPCSTATS
   +0x110 RedirectObject   : (null) 
   +0x118 PhysicalDeviceObject : (null) 
```

#### [](#header-4)напочитать:

[Ориг статья с экспериментами](http://trapframe.github.io/just-enough-kernel-to-get-by)

[https://www.ired.team/miscellaneous-reversing-forensics/windows-kernel-internals/interrupt-descriptor-table-idt](https://www.ired.team/miscellaneous-reversing-forensics/windows-kernel-internals/interrupt-descriptor-table-idt)

[https://vivek-arora.com/?p=801](https://vivek-arora.com/?p=801)

[https://www.ired.team/miscellaneous-reversing-forensics/windows-kernel-internals/glimpse-into-ssdt-in-windows-x64-kernel](https://www.ired.team/miscellaneous-reversing-forensics/windows-kernel-internals/glimpse-into-ssdt-in-windows-x64-kernel)

[https://codemachine.com/articles/interrupt_dispatching.html](https://codemachine.com/articles/interrupt_dispatching.html)
