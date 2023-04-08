---
title: One Year to I/O Ring&#58; What Changed? [ru]
published: true
tags: [ "kernelexploitation", "windows", "translation" ]
image: assets/previews/22.jpg
layout: page
pagination: 
  enabled: true
---

Перевод вот этой статьи: [One Year to I/O Ring: What Changed?](https://windows-internals.com/one-year-to-i-o-ring-what-changed)

# [](#header-1) One Year to I/O Ring: What Changed?

Прошло чуть больше года с тех пор, как первая версия кольца ввода/вывода была представлена в Windows. Начальная версия была представлена в Windows 21H2, и я сделал все возможное, чтобы задокументировать ее [здесь](https://windows-internals.com/i-o-rings-when-one-i-o-operation-is-not-enough), со сравнением с [Linux io_uring](https://kernel.dk/io_uring.pdf) [здесь](https://windows-internals.com/ioring-vs-io_uring-a-comparison-of-windows-and-linux-implementations). Microsoft также задокументировала [функции Win32](https://learn.microsoft.com/en-us/windows/win32/api/ioringapi). С момента появления первоначальной версии эта функция развивалась и получила довольно значительные изменения и обновления, поэтому она заслуживает последующего поста, в котором все они будут задокументированы и объяснены более подробно.

## [](#header-2) Новые поддерживаемые операции

Рассматривая изменения, первое и самое очевидное, что мы можем увидеть, это то, что теперь поддерживаются две новые операции - write и flush:

![IOring](/assets/post_images/19.png)

Они позволяют использовать кольцо ввода/вывода для выполнения операций записи и сброса. Эти новые операции обрабатываются аналогично операциям чтения, которые поддерживались с первой версии колец ввода/вывода, и направляются соответствующим функциям ввода/вывода. В KernelBase.dll были добавлены новые функции-обертки для постановки запросов на эти операции в очередь: BuildIoRingWriteFile и BuildIoRingFlushFile, а их определения можно найти в заголовочном файле ioringapi.h (доступен в предварительной версии SDK):

```cpp
STDAPI
BuildIoRingWriteFile (
    _In_ HIORING ioRing,
    IORING_HANDLE_REF fileRef,
    IORING_BUFFER_REF bufferRef,
    UINT32 numberOfBytesToWrite,
    UINT64 fileOffset,
    FILE_WRITE_FLAGS writeFlags,
    UINT_PTR userData,
    IORING_SQE_FLAGS sqeFlags
);

STDAPI
BuildIoRingFlushFile (
    _In_ HIORING ioRing,
    IORING_HANDLE_REF fileRef,
    FILE_FLUSH_MODE flushMode,
    UINT_PTR userData,
    IORING_SQE_FLAGS sqeFlags
);
```

Аналогично BuildIoRingReadFile, обе эти операции создают элемент в очереди отправки с запрошенным полем OpCode и добавляют ее в очередь отправки. Очевидно, что для новых операций необходимы различные флаги и опции, такие как flushMode для операций flush или writeFlags для операций записи. Чтобы справиться с этим, структура NT_IORING_SQE теперь содержит объединение для входных данных, которые интерпретируются в соответствии с запрошенным OpCode - новая структура доступна в общедоступных символах, а также в конце этого поста.

Одно небольшое изменение ядра, добавленное для поддержки операций записи, можно увидеть в IopIoRingReferenceFileObject:

![IOring](/assets/post_images/20.png)

Появилось несколько новых аргументов и дополнительный вызов ObReferenceFileObjectForWrite. Зондирование различных буферов в различных функциях также изменилось в зависимости от типа операций.

## [](#header-2) Событие завершения работы пользователя

Еще одно интересное изменение, которое также было введено - это возможность регистрации пользовательского события для уведомления о каждой новой завершенной операции. В отличие от CompletionEvent колец ввода/вывода, которое получает сигнал только после завершения всех операций, новое опциональное пользовательское событие будет получать сигнал для каждой новой завершенной операции, позволяя приложению обрабатывать результаты по мере их записи в очередь завершения.

Для поддержки этой новой функциональности был создан еще один системный вызов: NtSetInformationIoRing:
```cpp
NTSTATUS
NtSetInformationIoRing (
    HANDLE IoRingHandle,
    ULONG IoRingInformationClass,
    ULONG InformationLength,
    PVOID Information
);
```

Как и другие процедуры NtSetInformation*, эта функция получает дескриптор объекта IoRing, класс информации, длину и данные. В настоящее время действителен только один информационный класс: 1. Структура IORING_INFORMATION_CLASS, к сожалению, не находится в общедоступных символах, поэтому мы не можем знать ее официального названия, но я назову ее IoRingRegisterUserCompletionEventClass. Несмотря на то, что в настоящее время поддерживается только один класс, в будущем, возможно, будут поддерживаться и другие информационные классы. Интересным моментом здесь является то, что функция использует глобальный массив IopIoRingSetOperationLength для получения ожидаемой длины информации для каждого класса информации:

![IOring](/assets/post_images/21.png)

В настоящее время массив имеет только две записи: 0, который на самом деле не является действительным классом и возвращает длину 0, и запись 1, которая возвращает ожидаемый размер 8. Эта длина соответствует ожиданию функции получить дескриптор события (дескрипторы имеют размер 8 байт на x64). Это может быть намеком на то, что в будущем планируется использовать больше информационных классов, или просто другой выбор кодировки.

После необходимых входных проверок функция обращается к кольцу ввода-вывода, хэндл которого был отправлен в функцию. Затем, если информационный класс является IoRingRegisterUserCompletionEventClass, вызывает IopIoRingUpdateCompletionUserEvent с предоставленным дескриптором события. IopIoRingUpdateCompletionUserEvent ссылается на событие и помещает указатель в IoRingObject->CompletionUserEvent. Если дескриптор события не предоставлен, поле CompletionUserEvent очищается:

![IOring](/assets/post_images/22.png)

## [](#header-2) RE уголок

Попутно заметим, что эта функция может выглядеть довольно большой и слегка угрожающей, но большая ее часть - это просто код синхронизации, гарантирующий, что только один поток может редактировать поле CompletionUserEvent кольца ввода/вывода в любой момент и предотвращающий условия гонки. И на самом деле, компилятор заставляет функцию выглядеть больше, чем она есть на самом деле, поскольку он распаковывает макросы, так что если мы попытаемся восстановить исходный код, эта функция будет выглядеть намного чище:

```cpp
NTSTATUS
IopIoRingUpdateCompletionUserEvent (
    PIORING_OBJECT IoRingObject,
    PHANDLE EventHandle,
    KPROCESSOR_MODE PreviousMode
    )
{
    PKEVENT completionUserEvent;
    HANDLE eventHandle;
    NTSTATUS status;
    PKEVENT oldCompletionEvent;
    PKEVENT eventObj;

    completionUserEvent = 0;
    eventHandle = *EventHandle;
    if (!eventHandle ||
        (eventObj = 0,
        status = ObReferenceObjectByHandle(
                 eventHandle, PAGE_READONLY, ExEventObjectType, PreviousMode, &eventObj, 0),
        completionUserEvent = eventObj,
        !NT_SUCCESS(status))
    {
        KeAcquireSpinLockRaiseToDpc(&IoRingObject->CompletionLock);
        oldCompletionEvent = IoRingObject->CompletionUserEvent;
        IoRingObject->CompletionUserEvent = completionUserEvent;
        KeReleaseSpinLock(&IoRingObject->CompletionLock);
        if (oldCompletionEvent)
        {
            ObDereferenceObjectWithTag(oldCompletionEvent, 'tlfD');
        }
        return STATUS_SUCCESS;
    }
    return status;
}
```

Вот и все, около шести строк фактического кода. Но это не суть важно, поэтому давайте вернемся к теме: новому CompletionUserEvent.

## [](#header-2) Вернемся к событию завершения работы пользователя

В следующий раз мы сталкиваемся с CompletionUserEvent, когда запись IoRing завершается, в IopCompleteIoRingEntry:

![IOring](/assets/post_images/23.png)

В то время как обычное событие завершения работы кольца ввода-вывода сигнализируется только после завершения всех операций, событие CompletionUserEvent сигнализируется при других условиях. Взглянув на код, мы видим следующую проверку:

![IOring](/assets/post_images/24.png)

Каждый раз, когда операция кольца ввода-вывода завершается и записывается в очередь завершения, поле CompletionQueue->Tail увеличивается на единицу (здесь упоминается как newTail). Поле CompletionQueue->Head содержит индекс последней записи о завершении, которая была записана, и увеличивается каждый раз, когда приложение обрабатывает другую запись (если вы используете PopIoRingCompletion, он будет делать это внутренне, в противном случае вам нужно увеличивать его самостоятельно). Итак, (newTail - Head) % CompletionQueueSize вычисляет количество завершенных записей, которые еще не были обработаны приложением. Если это количество равно единице, это означает, что приложение обработало все завершенные записи, кроме последней, которая завершается сейчас. В этом случае функция ссылается на CompletionUserEvent и затем вызывает KeSetEvent для подачи сигнала.

Такое поведение позволяет приложению следить за завершением всех отправленных операций, создавая поток, целью которого является ожидание пользовательского события и обработка каждой новой завершенной записи по мере ее завершения. Это гарантирует, что голова и хвост очереди завершения всегда одинаковы, поэтому следующая завершаемая запись будет сигнализировать о событии, оно будет обрабатывать запись, и так далее. Таким образом, основной поток приложения может продолжать выполнять другую работу, но все операции ввода-вывода обрабатываются рабочим потоком как можно быстрее.

Конечно, это не является обязательным. Приложение может решить не регистрировать пользовательское событие и просто ждать завершения всех событий. Но эти два события позволяют различным приложениям выбрать наиболее подходящий для них вариант, создавая механизм завершения операций ввода-вывода, который можно настроить под различные нужды.

В KernelBase.dll есть функция для регистрации события завершения работы пользователя: SetIoRingCompletionEvent. Ее сигнатуру можно найти в ioringapi.h:

```cpp
STDAPI
SetIoRingCompletionEvent (
    _In_ HIORING ioRing,
    _In_ HANDLE hEvent
);
```

Используя этот новый API и зная, как работает это новое событие, мы можем создать демонстрационное приложение, которое будет выглядеть примерно так:

```cpp
HANDLE g_event;

DWORD
WaitOnEvent (
    LPVOID lpThreadParameter
    )
{
    HRESULT result;
    IORING_CQE cqe;

    WaitForSingleObject(g_event, INFINITE);
    while (TRUE)
    {
        //
        // lpThreadParameter is the handle to the ioring
        //
        result = PopIoRingCompletion((HIORING)lpThreadParameter, &cqe);
        if (result == S_OK)
        {
            /* do things */
        }
        else
        {
            WaitForSingleObject(g_event, INFINITE);
            ResetEvent(g_event);
        }
    }
    return 0;
}

int
main ()
{
    HRESULT result;
    HIORING ioring = NULL;
    IORING_CREATE_FLAGS flags;

    flags.Required = IORING_CREATE_REQUIRED_FLAGS_NONE;
    flags.Advisory = IORING_CREATE_ADVISORY_FLAGS_NONE;
    result = CreateIoRing(IORING_VERSION_3, flags, 0x10000, 0x20000, &ioring);

    /* Queue operations to ioring... */

    //
    // Create user completion event, register it to the ioring
    // and create a thread to wait on it and process completed operations.
    // The ioring handle is sent as an argument to the thread.
    //
    g_event = CreateEvent(NULL, FALSE, FALSE, NULL);
    result = SetIoRingCompletionEvent(handle, g_event);
    thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)WaitOnEvent, ioring, 0, &threadId);
    result = SubmitIoRing(handle, 0, 0, &submittedEntries);

    /* Clean up... */

    return 0;
}
```

## [](#header-2) Сливаем предшествующие операции

Событие завершения работы пользователя - это очень хорошее дополнение, но это не единственное улучшение колец ввода/вывода, связанное с ожиданием. Еще одно улучшение можно найти, посмотрев на перечисление NT_IORING_SQE_FLAGS:

```cpp
typedef enum _NT_IORING_SQE_FLAGS
{
    NT_IORING_SQE_FLAG_NONE = 0x0,
    NT_IORING_SQE_FLAG_DRAIN_PRECEDING_OPS = 0x1,
} NT_IORING_SQE_FLAGS, *PNT_IORING_SQE_FLAGS;
```

Просматривая код, мы можем найти проверку NT_IORING_SQE_FLAG_DRAIN_PRECEDING_OPS в самом начале IopProcessIoRingEntry:

![IOring](/assets/post_images/25.png)

Эта проверка происходит до выполнения любой обработки, чтобы проверить, содержит ли запись очереди отправки флаг NT_IORING_SQE_FLAG_DRAIN_PRECEDING_OPS. Если да, то вызывается IopIoRingSetupCompletionWait для установки параметров ожидания. Сигнатура функции выглядит следующим образом:

```cpp
NTSTATUS
IopIoRingSetupCompletionWait (
    _In_ PIORING_OBJECT IoRingObject,
    _In_ ULONG SubmittedEntries,
    _In_ ULONG WaitOperations,
    _In_ BOOL SetupCompletionWait,
    _Out_ PBYTE CompletionWait
);
```

Внутри функции есть множество проверок и вычислений, которые являются одновременно очень техническими и очень скучными, поэтому я избавлю себя от необходимости объяснять их, а вас - от необходимости читать утомительное объяснение, перейдем к хорошим частям. По сути, если функция получает -1 в качестве WaitOperations, она игнорирует аргумент SetupCompletionWait и подсчитывает количество операций, которые уже были представлены и обработаны, но еще не завершены. Это число помещается в IoRingObject->CompletionWaitUntil. Она также устанавливает IoRingObject->SignalCompletionEvent в TRUE и возвращает TRUE в выходном аргументе CompletionWait.

Если функция выполнилась успешно, IopProcessIoRingEntry затем вызовет IopIoRingWaitForCompletionEvent, который будет работать до тех пор, пока IoRingObject->CompletionEvent не получит сигнал. Теперь самое время вернуться к проверке, которую мы видели ранее в IopCompleteIoRingEntry:

![IOring](/assets/post_images/26.png)

Если SignalCompletionEvent установлен (а он установлен, потому что IopIoRingSetupCompletionWait установил его) и количество завершенных событий равно IoRingObject->CompletionWaitUntil, IoRingObject->CompletionEvent получит сигнал, чтобы отметить, что все ожидающие события завершены. SignalCompletionEvent также очищается, чтобы избежать повторного сигнала о событии, когда оно не запрашивается.

При вызове из IopProcessIoRingEntry, IopIoRingWaitForCompletionEvent получает таймаут NULL, что означает, что он будет ждать неопределенное время. Это то, что следует учитывать при использовании флага NT_IORING_SQE_FLAG_DRAIN_PRECEDING_OPS.

Итак, установка флага NT_IORING_SQE_FLAG_DRAIN_PRECEDING_OPS в записи очереди отправки позволит убедиться, что все предшествующие операции завершены до того, как эта запись будет обработана. Это может понадобиться в некоторых случаях, когда одна операция ввода-вывода зависит от предыдущей.

Но ожидание ожидающих операций происходит еще в одном случае: При отправке кольца ввода/вывода. В своем первом сообщении о кольцах ввода/вывода в прошлом году я определил сигнатуру NtSubmitIoRing следующим образом:

```cpp
NTSTATUS
NtSubmitIoRing (
    _In_ HANDLE Handle,
    _In_ IORING_CREATE_REQUIRED_FLAGS Flags,
    _In_ ULONG EntryCount,
    _In_ PLARGE_INTEGER Timeout
    );
```

В итоге мое определение оказалось не совсем точным. Более правильным названием для третьего аргумента было бы WaitOperations, поэтому точная подпись будет такой:

```cpp
NTSTATUS
NtSubmitIoRing (
    _In_ HANDLE Handle,
    _In_ IORING_CREATE_REQUIRED_FLAGS Flags,
    _In_opt_ ULONG WaitOperations,
    _In_opt_ PLARGE_INTEGER Timeout
    );
```

Почему это важно? Потому что число, которое вы передаете в WaitOperations, используется не для обработки записей кольца (они обрабатываются полностью на основе SubmissionQueue->Head и SubmissionQueue->Tail), а для запроса количества операций для ожидания. Таким образом, если WaitOperations не равно 0, NtSubmitIoRing вызовет IopIoRingSetUpCompletionWait перед выполнением любой обработки:

![IOring](/assets/post_images/27.png)

Однако функция вызывается с параметром SetupCompletionWait=FALSE, поэтому функция не будет настраивать параметры ожидания, а только выполнит проверку на достоверность количества операций ожидания. Например, количество операций ожидания не может быть больше, чем количество операций, которые были отправлены. Если проверка не прошла, NtSubmitIoRing не обработает ни одну из записей и вернет ошибку, обычно STATUS_INVALID_PARAMETER_3.

Позже мы снова увидим обе функции после того, как операции будут обработаны:

![IOring](/assets/post_images/28.png)

IopIoRingSetupCompletionWait вызывается снова, чтобы пересчитать количество операций, которые необходимо дождаться, принимая во внимание любые операции, которые могли быть уже завершены (или уже дождались, если любой из SQE имел флаг, упомянутый ранее). Затем вызывается IopIoRingWaitForCompletionEvent для ожидания IoRingObject->CompletionEvent, пока все запрошенные события не будут завершены.
В большинстве случаев приложения предпочитают либо отправлять 0 в качестве аргумента WaitOperations, либо устанавливать его на общее количество отправленных операций, но могут быть случаи, когда приложение хочет ждать только часть отправленных операций, поэтому оно может выбрать меньшее число для ожидания.

## [](#header-2) В поисках багов

Сравнение одного и того же фрагмента кода в разных сборках - интересный способ найти ошибки, которые были исправлены. Иногда это уязвимости безопасности, которые были исправлены, иногда - обычные старые ошибки, которые могут повлиять на стабильность или надежность кода. Код кольца ввода-вывода в ядре получил много изменений за последний год, так что это хороший шанс поохотиться за старыми ошибками.

Одну ошибку, на которой я хотел бы остановиться, довольно легко обнаружить и понять, но это забавный пример того, как различные части системы, которые кажутся совершенно несвязанными, могут столкнуться неожиданным образом. Это функциональная ошибка (не ошибка безопасности), которая не позволяла процессам WoW64 использовать некоторые возможности кольца ввода-вывода.

Мы можем найти свидетельства этой ошибки при рассмотрении IopIoRingDispatchRegisterBuffers и IopIoRingDispatchRegisterFiles. При просмотре новой сборки мы можем увидеть часть кода, которой не было в предыдущих версиях:

![IOring](/assets/post_images/29.png)

Это проверка того, является ли процесс, регистрирующий буферы или файлы, процессом WoW64 - 32-битным процессом, запущенным поверх 64-битной системы. Поскольку Windows теперь поддерживает ARM64, этот процесс WoW64 может быть как приложением x86, так и ARM32.

Забегая вперед, можно сказать, почему эта информация имеет значение. В дальнейшем мы видим два случая, когда проверяется isWow64:

![IOring](/assets/post_images/30.png)

В первом случае размер массива вычисляется для проверки на недопустимые размеры, если вызывающая сторона - UserMode.

![IOring](/assets/post_images/31.png)

Этот второй случай происходит при итерации по входному буферу для регистрации буферов в массиве, который будет храниться в объекте кольца ввода-вывода. В этом случае немного сложнее понять, на что мы смотрим из-за того, как здесь обрабатываются структуры, но если мы посмотрим на дизассемблерный листинг, то это может стать немного понятнее:

![IOring](/assets/post_images/32.png)

Блок слева - это случай WoW64, а блок справа - нативный случай. Здесь мы видим разницу в смещении, по которому осуществляется доступ к переменной bufferInfo (r8 в дизассемблере). Чтобы получить некоторый контекст, bufferInfo считывается из записи очереди отправки:

bufferInfo = Sqe->RegisterBuffers.Buffers;

При регистрации буфера SQE будет содержать структуру NT_IORING_OP_REGISTER_BUFFERS:

```cpp
typedef struct _NT_IORING_OP_REGISTER_BUFFERS
{
    /* 0x0000 */ NT_IORING_OP_FLAGS CommonOpFlags;
    /* 0x0004 */ NT_IORING_REG_BUFFERS_FLAGS Flags;
    /* 0x000c */ ULONG Count;
    /* 0x0010 */ PIORING_BUFFER_INFO Buffers;
} NT_IORING_OP_REGISTER_BUFFERS, *PNT_IORING_OP_REGISTER_BUFFERS;
```

Все подструктуры находятся в общедоступных символах, поэтому я не буду приводить их все здесь, но в данном случае следует сосредоточиться на IORING_BUFFER_INFO:

```cpp
typedef struct _IORING_BUFFER_INFO
{
    /* 0x0000 */ PVOID Address;
    /* 0x0008 */ ULONG Length;
} IORING_BUFFER_INFO, *PIORING_BUFFER_INFO; /* size: 0x0010 */
```

Эта структура содержит адрес и длину. Адрес имеет тип PVOID, и именно здесь кроется ошибка. PVOID не имеет фиксированного размера во всех системах. Это указатель, и поэтому его размер зависит от размера указателя в системе. На 64-битных системах это 8 байт, а на 32-битных - 4 байта. Однако процессы WoW64 не полностью осознают, что они работают на 64-битной системе. Существует целый механизм эмуляции 32-битной системы для процесса, чтобы 32-битные приложения могли нормально выполняться на 64-битном оборудовании. Это означает, что когда приложение вызывает BuildIoRingRegisterBuffers для создания массива буферов, оно вызывает 32-битную версию функции, которая использует 32-битные структуры и 32-битные типы. Поэтому вместо 8-байтового указателя он будет использовать 4-байтовый указатель, создавая структуру IORING_BUFFER_INFO, которая выглядит следующим образом:

```cpp
typedef struct _IORING_BUFFER_INFO
{
    /* 0x0000 */ PVOID Address;
    /* 0x0004 */ ULONG Length;
} IORING_BUFFER_INFO, *PIORING_BUFFER_INFO; /* size: 0x008 */
```

Это, конечно, не единственный случай, когда ядро получает аргументы размером с указатель от вызывающего пользователя, и существует механизм, предназначенный для обработки таких случаев. Поскольку ядро не поддерживает 32-битное исполнение, эмуляция WoW64 позже отвечает за перевод входных аргументов системных вызовов из 32-битных размеров и типов в 64-битные типы, ожидаемые ядром. Однако в данном случае буферный массив не посылается в качестве входного аргумента системного вызова. Он записывается в общую секцию кольца ввода/вывода, которая считывается непосредственно ядром, никогда не проходя через DLL трансляции WoW64. Это означает, что трансляция аргументов в массиве не выполняется, и ядро напрямую читает массив, предназначенный для 32-битного ядра, где аргумент Length находится не по ожидаемому смещению. В ранних версиях кольца ввода/вывода это означало, что ядро всегда пропускало длину буфера и интерпретировало адрес следующей записи как длину последней записи, что приводило к ошибкам.

В новых сборках ядро знает о другой форме структуры, используемой процессами WoW64, и интерпретирует ее правильно: Оно считает, что размер каждой записи составляет 8 байт вместо 0x10, и считывает только первые 4 байта в качестве адреса, а следующие 4 байта - в качестве длины.

Такая же проблема возникала при предварительной регистрации дескрипторов файлов, поскольку HANDLE также имеет размер указателя. IopIoRingDispatchRegisterFiles теперь имеет те же проверки и обработку, чтобы процессы WoW64 также могли успешно регистрировать дескрипторы файлов.

## [](#header-2) Другие изменения

Есть несколько более мелких изменений, которые не настолько велики или значительны, чтобы занимать отдельный раздел в этом посте, но все же заслуживают почетного упоминания:

* Успешное создание нового объекта кольца ввода/вывода будет генерировать событие ETW, содержащее всю информацию об инициализации кольца ввода/вывода.
* IoringObject->CompletionEvent получил повышение с типа NotificationEvent до SynchronizationEvent.
* Текущая версия кольца ввода/вывода - 3, поэтому новые кольца, созданные для последних сборок, должны использовать эту версию.
* Поскольку разные версии кольца ввода/вывода поддерживают разные возможности и операции, KernelBase.dll экспортирует новую функцию: IsIoRingOpSupported. Она получает дескриптор HIORING и номер операции, и возвращает булево значение, указывающее, поддерживается ли операция в данной версии.

## [](#header-2) Структуры данных

В Windows 11 22H2 (сборка 22577) произошла еще одна интересная вещь: почти все структуры внутреннего кольца ввода-вывода доступны в общедоступных символах! Это означает, что больше нет необходимости мучительно перепроектировать структуры и пытаться угадать имена полей и их назначение. Некоторые структуры получили значительные изменения с 21H2, так что отсутствие необходимости заново их разрабатывать - это здорово.

Поскольку структуры находятся в символах, нет необходимости добавлять их сюда. Однако структуры из общедоступных символов не всегда легко найти с помощью простого поиска в Google - я настоятельно рекомендую воспользоваться поиском на GitHub или просто напрямую использовать ntdiff. В какой-то момент люди неизбежно будут искать некоторые из этих структур данных, найдут структуры REd в моем старом сообщении, которые больше не являются точными, и пожалуются, что они устарели. Чтобы избежать этого, хотя бы временно, я размещу здесь только обновленные версии структур, которые были в старом сообщении, но буду настоятельно рекомендовать вам получать актуальные структуры из символов - те, что здесь, наверняка скоро изменятся (правка: спустя один билд некоторые из них уже изменились). Итак, вот некоторые структуры из Windows 11 build 22598:

```cpp
typedef struct _NT_IORING_INFO
{
    IORING_VERSION IoRingVersion;
    NT_IORING_CREATE_FLAGS Flags;
    ULONG SubmissionQueueSize;
    ULONG SubmissionQueueRingMask;
    ULONG CompletionQueueSize;
    ULONG CompletionQueueRingMask;
    PNT_IORING_SUBMISSION_QUEUE SubmissionQueue;
    PNT_IORING_COMPLETION_QUEUE CompletionQueue;
} NT_IORING_INFO, *PNT_IORING_INFO;

typedef struct _NT_IORING_SUBMISSION_QUEUE
{
    ULONG Head;
    ULONG Tail;
    NT_IORING_SQ_FLAGS Flags;
    NT_IORING_SQE Entries[1];
} NT_IORING_SUBMISSION_QUEUE, *PNT_IORING_SUBMISSION_QUEUE;

typedef struct _NT_IORING_SQE
{
    enum IORING_OP_CODE OpCode;
    enum NT_IORING_SQE_FLAGS Flags;
    union
    {
        ULONG64 UserData;
        ULONG64 PaddingUserDataForWow;
    };
    union
    {
        NT_IORING_OP_READ Read;
        NT_IORING_OP_REGISTER_FILES RegisterFiles;
        NT_IORING_OP_REGISTER_BUFFERS RegisterBuffers;
        NT_IORING_OP_CANCEL Cancel;
        NT_IORING_OP_WRITE Write;
        NT_IORING_OP_FLUSH Flush;
        NT_IORING_OP_RESERVED ReservedMaxSizePadding;
    };
} NT_IORING_SQE, *PNT_IORING_SQE;

typedef struct _IORING_OBJECT
{
    USHORT Type;
    USHORT Size;
    NT_IORING_INFO UserInfo;
    PVOID Section;
    PNT_IORING_SUBMISSION_QUEUE SubmissionQueue;
    PMDL CompletionQueueMdl;
    PNT_IORING_COMPLETION_QUEUE CompletionQueue;
    ULONG64 ViewSize;
    BYTE InSubmit;
    ULONG64 CompletionLock;
    ULONG64 SubmitCount;
    ULONG64 CompletionCount;
    ULONG64 CompletionWaitUntil;
    KEVENT CompletionEvent;
    BYTE SignalCompletionEvent;
    PKEVENT CompletionUserEvent;
    ULONG RegBuffersCount;
    PIORING_BUFFER_INFO RegBuffers;
    ULONG RegFilesCount;
    PVOID* RegFiles;
} IORING_OBJECT, *PIORING_OBJECT;
```

Одна структура, которой нет в символах, - это структура HIORING, которая представляет собой дескриптор ioring в KernelBase. Она немного изменилась с 21H2, поэтому здесь представлена версия 22H2:

```cpp
typedef struct _HIORING
{
    HANDLE handle;
    NT_IORING_INFO Info;
    ULONG IoRingKernelAcceptedVersion;
    PVOID RegBufferArray;
    ULONG BufferArraySize;
    PVOID FileHandleArray;
    ULONG FileHandlesCount;
    ULONG SubQueueHead;
    ULONG SubQueueTail;
} HIORING, *PHIORING;
```

## [](#header-2) Заключение

Эта функция появилась всего несколько месяцев назад, но уже получила несколько очень интересных дополнений и улучшений, призванных сделать ее более привлекательной для приложений с большим объемом операций ввода-вывода. Она уже находится в версии 3, и, вероятно, в ближайшем будущем мы увидим еще несколько версий, возможно, с поддержкой новых типов операций или расширенной функциональности. Тем не менее, ни одно приложение пока не использует этот механизм, по крайней мере, в настольных системах.

Это одно из самых интересных дополнений к Windows 11, но, как и любой новый кусок кода, оно все еще имеет некоторые ошибки, например, ту, которую я показал в этой статье. Стоит следить за кольцами ввода/вывода, чтобы увидеть, как они будут использоваться (или, может быть, злоупотребляться?) по мере того, как Windows 11 станет более широко адаптированной и приложения начнут использовать все новые возможности, которые она предлагает.