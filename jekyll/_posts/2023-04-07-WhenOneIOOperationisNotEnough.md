---
title: I/O Rings – When One I/O Operation is Not Enough [ru]
published: true
tags: [ "kernelexploitation", "windows", "translation" ]
image: assets/previews/21.jpg
layout: page
pagination: 
  enabled: true
---

Перевод вот этой статьи: [I/O Rings – When One I/O Operation is Not Enough](https://windows-internals.com/i-o-rings-when-one-i-o-operation-is-not-enough)

# [](#header-1) I/O Rings – When One I/O Operation is Not Enough

## [](#header-2) Введение

Обычно я пишу о функциях или методах обеспечения безопасности в Windows. Но сегодняшний блог не имеет прямого отношения к каким-либо темам безопасности, кроме обычных дополнительных рисков, которые вносит любой новый системный вызов. Однако это интересное дополнение к миру ввода-вывода в Windows, которое может быть полезным для разработчиков, и я подумал, что будет интересно рассмотреть его и написать о нем. Все это означает, что если вы ищете новый эксплойт или технику обхода EDR, вам лучше сэкономить время и посмотреть другие статьи на [этом сайте](https://windows-internals.com).

Для тех троих из вас, кто все еще читает, давайте поговорим о кольцах ввода-вывода!

Кольца ввода/вывода - это новая функция в предварительных сборках Windows. Это реализация [кольцевого буфера](https://en.wikipedia.org/wiki/Circular_buffer) в Windows - кольцевой буфер, в данном случае используемый для постановки в очередь нескольких операций ввода-вывода одновременно, чтобы позволить приложениям пользовательского режима, выполняющим множество операций ввода-вывода, делать это за одно действие вместо перехода от пользовательского режима к ядру и обратно для каждого отдельного запроса.

Эта новая возможность добавляет много новых функций и внутренних структур данных, поэтому, чтобы постоянно не прерывать блог новыми структурами данных, я не буду приводить их как часть постов, но их определения есть в примере кода в конце. Я покажу только несколько внутренних структур данных, которые не используются в примере кода.

## [](#header-2) Использование колец ввода/вывода

Текущая реализация колец ввода/вывода поддерживает только операции чтения и позволяет ставить в очередь до 0x10000 операций за раз. Для каждой операции вызывающая сторона должна предоставить дескриптор целевого файла, выходной буфер, смещение в файле и объем памяти для чтения. Все это делается в нескольких новых структурах данных, которые будут рассмотрены позже. Но сначала вызывающая сторона должна инициализировать свое кольцо ввода-вывода.

### [](#header-3) Создание и инициализация кольца ввода/вывода

Для этого система предоставляет новый системный вызов - NtCreateIoRing. Эта функция создает экземпляр нового типа объекта IoRing, описанного здесь как IORING_OBJECT:

```cpp
typedef struct _IORING_OBJECT
{
  USHORT Type;
  USHORT Size;
  NT_IORING_INFO Info;
  PSECTION SectionObject;
  PVOID KernelMappedBase;
  PMDL Mdl;
  PVOID MdlMappedBase;
  ULONG_PTR ViewSize;
  ULONG SubmitInProgress;
  PVOID IoRingEntryLock;
  PVOID EntriesCompleted;
  PVOID EntriesSubmitted;
  KEVENT RingEvent;
  PVOID EntriesPending;
  ULONG BuffersRegistered;
  PIORING_BUFFER_INFO BufferArray;
  ULONG FilesRegistered;
  PHANDLE FileHandleArray;
} IORING_OBJECT, *PIORING_OBJECT;
```

NtCreateIoRing получает одну новую структуру в качестве параметра - IO_RING_STRUCTV1. Эта структура содержит информацию о текущей версии, которая в настоящее время может быть только 1, требуемом и рекомендуемом флагах (оба в настоящее время не поддерживают никаких значений, кроме 0) и запрашиваемом размере очереди отправки и очереди завершения.

Функция получает эту информацию и выполняет следующие действия:
* Проверяет все входные и выходные аргументы - их адреса, выравнивание по размеру и т.д.
* Проверяет запрашиваемый размер очереди отправки и рассчитывает объем памяти, необходимый для очереди отправки, исходя из запрашиваемого количества записей.
* * Если SubmissionQueueSize больше 0x10000, возвращается новый статус ошибки STATUS_IORING_SUBMISSION_QUEUE_TOO_BIG.
* Проверяет размер очереди завершений и вычисляет объем памяти, необходимый для нее.
* * Очередь завершений ограничена 0x20000 записей, и код ошибки STATUS_IORING_COMPLETION_QUEUE_TOO_BIG возвращается, если запрашивается большее число.
* Создает новый объект типа IoRingObjectType и инициализирует все поля, которые могут быть инициализированы на данном этапе - флаги, размер и маску очереди отправки, событие и т.д.
* Создает раздел для очередей, отображает его в системном пространстве и создает MDL для его поддержки. Затем создает ту же секцию в пространстве пользователя. Эта секция будет содержать объекты очереди отправки и объекты очереди завершения и будет использоваться приложением для передачи параметров всех запрошенных операций ввода-вывода ядру и получения кодов состояния.
* Инициализирует выходную структуру с адресом очереди отправки и другими данными, которые будут возвращены вызывающей стороне.

После успешного возврата NtCreateIoRing вызывающая программа может записать свои данные в предоставленную очередь отправки. Очередь будет иметь заголовок очереди, за которым следует массив структур NT_IORING_SQE, каждая из которых представляет одну запрошенную операцию ввода-вывода. Заголовок описывает, какие записи должны быть обработаны в данный момент:

![IOring](/assets/post_images/14.png)

Заголовок очереди описывает, какие записи должны быть обработаны с помощью полей Head и Tail. Head указывает индекс последней необработанной записи, а Tail - индекс, на котором следует остановить обработку. Tail - Head должно быть меньше общего числа записей, а также равно или больше числа записей, которые будут запрошены в вызове NtSubmitIoRing.

Каждая запись очереди содержит данные о запрашиваемой операции: дескриптор файла, смещение файла, ,начальный адрес выходного буфера, смещение и количество данных для чтения.  Она также содержит поле OpCode для указания запрашиваемой операции.

## [](#header-2) Коды операций колец ввода/вывода

Существует четыре возможных типа операций, которые могут быть запрошены вызывающей стороной:

* IORING_OP_READ: запрашивает, чтобы система считала данные из файла в выходной буфер. Дескриптор файла будет считан из поля FileRef в элемент очереди отправки. Он будет интерпретирован либо как дескриптор файла, либо как индекс в предварительно зарегистрированном массиве дескрипторов файлов, в зависимости от того, установлен ли флаг IORING_SQE_PREREGISTERED_FILE (1) в поле Flags элемента очереди. Вывод будет записан в выходной буфер, указанный в поле Buffer элемента очереди. Подобно FileRef, это поле может вместо этого содержать индекс в предварительно зарегистрированном массиве выходных буферов, если установлен флаг IORING_SQE_PREREGISTERED_BUFFER (2).
* IORING_OP_REGISTERED_FILES: запрашивает предварительную регистрацию дескрипторов файлов для последующей обработки. В этом случае поле Buffer элемента очереди указывает на массив файловых дескрипторов. Запрошенные дескрипторы файлов будут продублированы и помещены в новый массив, в поле FileHandleArray элемента очереди. Поле FilesRegistered будет содержать количество файловых дескрипторов.
* IORING_OP_REGISTERED_BUFFERS: запрашивает предварительную регистрацию выходных буферов для данных файла, которые будут прочитаны. В этом случае поле Buffer в записи должно содержать массив структур IORING_BUFFER_INFO, описывающих адреса и размеры буферов, в которые будут считываться данные файла:
```cpp
typedef struct _IORING_BUFFER_INFO
{
    PVOID Address;
    ULONG Length;
} IORING_BUFFER_INFO, *PIORING_BUFFER_INFO;
```
Адреса и размеры буферов будут скопированы в новый массив и помещены в поле BufferArray очереди отправки. Поле BuffersRegistered будет содержать количество буферов.
* IORING_OP_CANCEL: запрашивает отмену ожидающей операции для файла. Как и в IORING_OP_READ, FileRef может быть дескриптором или индексом в массиве дескрипторов файлов в зависимости от флагов. В данном случае поле Buffer указывает на IO_STATUS_BLOCK, который должен быть отменен для файла.

Все эти варианты могут быть немного запутанными, поэтому здесь приведены иллюстрации для 4 различных сценариев чтения, основанных на запрошенных флагах:

Флаги равны 0, поле FileRef используется как дескриптор файла, а поле Buffer - как указатель на выходной буфер:

![IOring](/assets/post_images/15.png)

Флаг IORING_SQE_PREREGISTERED_FILE (1) запрошен, поэтому FileRef рассматривается как индекс массива предварительно зарегистрированных дескрипторов файлов, а Buffer - как указатель на выходной буфер:

![IOring](/assets/post_images/16.png)

Запрашивается флаг IORING_SQE_PREREGISTERED_BUFFER (2), поэтому FileRef является дескриптором файла, а Buffer рассматривается как индекс в массиве предварительно зарегистрированных выходных буферов:

![IOring](/assets/post_images/17.png)

Оба флага IORING_SQE_PREREGISTERED_FILE и IORING_SQE_PREREGISTERED_BUFFER установлены, поэтому FileRef рассматривается как индекс в предварительно зарегистрированный массив дескрипторов файлов, а Buffer - как индекс в предварительно зарегистрированном массив буферов:

![IOring](/assets/post_images/18.png)

## [](#header-2) Отправка и обработка запросов колец ввода/вывода

После того, как вызывающая сторона установила все свои элементы в очереди отправки, она может вызвать NtSubmitIoRing для отправки своих запросов в ядро для обработки в соответствии с запрошенными параметрами. Внутри NtSubmitIoRing перебирает все записи и вызывает IopProcessIoRingEntry, передавая объект IoRing и текущий элемент очереди. Запись обрабатывается в соответствии с заданным OpCode, а затем вызывается IopIoRingDispatchComplete для заполнения очереди завершения. Очередь завершения, как и очередь отправки, начинается с заголовка, содержащего Head и Tail, за которым следует массив записей. Каждая запись представляет собой структуру IORING_CQE - она содержит значение UserData из элемента очереди отправки, а также статус и информацию из IO_STATUS_BLOCK для данной операции:
```cpp
typedef struct _IORING_CQE
{
    UINT_PTR UserData;
    HRESULT ResultCode;
    ULONG_PTR Information;
} IORING_CQE, *PIORING_CQE;
```

Как только все запрошенные элементы завершены, система устанавливает событие в IoRingObject->RingEvent. Пока не все элементы завершены, система будет ждать события, используя таймаут, полученный от вызывающей стороны, и проснется, когда все запросы будут завершены, что вызовет сигнал о событии, или когда истечет таймаут.

Поскольку может быть обработано несколько записей, статус, возвращаемый вызывающей стороне, будет либо статусом ошибки, указывающим на невозможность обработки записей, либо возвращаемым значением от KeWaitForSingleObject. Коды состояния для отдельных операций можно найти в очереди завершения - поэтому не путайте получение кода STATUS_SUCCESS от NtSubmitIoRing с успешными операциями чтения!

## [](#header-2) Использование колец ввода/вывода, официальный путь

Как и другие системные вызовы, эти новые функции IoRing не документированы и не предназначены для прямого использования. Вместо этого KernelBase.dll предлагает удобные функции-обертки, которые получают простые в использовании аргументы и внутренне обрабатывают все недокументированные функции и структуры данных, которые необходимо передать ядру. Существуют функции для создания, запроса, отправки и закрытия IoRing, а также вспомогательные функции для создания записей в очереди для четырех различных операций, которые обсуждались ранее.

### [](#header-3) CreateIoRing

CreateIoRing получает информацию о флагах и размерах очереди, а внутри вызывает NtCreateIoRing и возвращает дескриптор экземпляра IoRing:
```cpp
HRESULT
CreateIoRing (
    _In_ IORING_VERSION IoRingVersion,
    _In_ IORING_CREATE_FLAGS Flags,
    _In_ UINT32 SubmissionQueueSize,
    _In_ UINT32 CompletionQueueSize,
    _Out_ HIORING* Handle
);
```

Этот новый тип дескриптора фактически является указателем на недокументированную структуру, содержащую структуру, возвращаемую из NtCreateIoRing, и другие данные, необходимые для управления этим экземпляром IoRing:
```cpp
typedef struct _HIORING
{
    ULONG SqePending;
    ULONG SqeCount;
    HANDLE handle;
    IORING_INFO Info;
    ULONG IoRingKernelAcceptedVersion;
} HIORING, *PHIORING;
```
Все остальные функции IoRing будут получать этот дескриптор в качестве первого аргумента.

После создания экземпляра IoRing приложению необходимо создать элементы очередей для всех запрошенных операций ввода-вывода. Поскольку внутренняя структура очередей и структуры записей очередей не документированы, KernelBase.dll экспортирует вспомогательные функции для их построения, используя входные данные, предоставленные вызывающей стороной. Для этого существует четыре функции:

1. BuildIoRingReadFile
2. BuildIoRingRegisterBuffers
3. BuildIoRingRegisterFileHandles
4. BuildIoRingCancelRequest

Каждая функция create добавляет новый элемент очереди в очередь отправки с требуемым опкодом и данными. Их названия делают их назначение достаточно очевидным, но давайте рассмотрим их по очереди для ясности:

### [](#header-3) BuildIoRingReadFile

```cpp
HRESULT
BuildIoRingReadFile (
    _In_ HIORING IoRing,
    _In_ IORING_HANDLE_REF FileRef,
    _In_ IORING_BUFFER_REF DataRef,
    _In_ ULONG NumberOfBytesToRead,
    _In_ ULONG64 FileOffset,
    _In_ ULONG_PTR UserData,
    _In_ IORING_SQE_FLAGS Flags
);
```

Функция получает дескриптор, возвращаемый CreateIoRing, а затем два указателя на новые структуры данных. Обе эти структуры имеют поле Kind, которое может быть либо IORING_REF_RAW, что указывает на то, что предоставленное значение является необработанной ссылкой, либо IORING_REF_REGISTERED, что указывает на то, что значение является индексом в предварительно зарегистрированном массиве. Второе поле представляет собой объединение значения и индекса, в качестве которого будет предоставлен дескриптор файла или буфер.

### [](#header-3) BuildIoRingRegisterFileHandles and BuildIoRingRegisterBuffers

```cpp
HRESULT
BuildIoRingRegisterFileHandles (
    _In_ HIORING IoRing,
    _In_ ULONG Count,
    _In_ HANDLE const Handles[],
    _In_ PVOID UserData
);

HRESULT
BuildIoRingRegisterBuffers (
    _In_ HIORING IoRing,
    _In_ ULONG Count,
    _In_ IORING_BUFFER_INFO count Buffers[],
    _In_ PVOID UserData
);
```

Эти две функции создают элементы очереди отправки для предварительной регистрации дескрипторов файлов и выходных буферов. Обе получают дескриптор, возвращаемый из CreateIoRing, счетчик предварительно зарегистрированных файлов/буферов в массиве, массив дескрипторов или буферов для регистрации и UserData.

В BuildIoRingRegisterFileHandles, Handles является указателем на массив файловых дескрипторов, а в BuildIoRingRegisterBuffers, Buffers является указателем на массив структур IORING_BUFFER_INFO, содержащих начальный адрес и размер буфера.

### [](#header-3) BuildIoRingCancelRequest

```cpp
HRESULT
BuildIoRingCancelRequest (
    _In_ HIORING IoRing,
    _In_ IORING_HANDLE_REF File,
    _In_ PVOID OpToCancel,
    _In_ PVOID UserData
);
```

Как и другие функции, BuildIoRingCancelRequest получает в качестве первого аргумента дескриптор, который был возвращен из CreateIoRing. Вторым аргументом снова является указатель на структуру IORING_REQUEST_DATA, которая содержит дескриптор (или индекс в массиве дескрипторов файлов) файла, операция с которым должна быть отменена. Третий и четвертый аргументы - это выходной буфер и UserData, которые должны быть помещены в запись очереди.

После того, как все записи очереди были построены с помощью этих функций, очередь может быть отправлена:

### [](#header-3) SubmitIoRing

```cpp
HRESULT
SubmitIoRing (
    _In_ HIORING IoRingHandle,
    _In_ ULONG WaitOperations,
    _In_ ULONG Milliseconds,
    _Out_ PULONG SubmittedEntries
);
```

Функция получает тот же дескриптор в качестве первого аргумента, который использовался для инициализации IoRing и очереди отправки. Затем она получает количество записей для отправки, время в миллисекундах для ожидания завершения операций и указатель на выходной параметр, который будет получать количество записей, которые были отправлены.

### [](#header-3) GetIoRingInfo

```cpp
HRESULT
GetIoRingInfo (
    _In_ HIORING IoRingHandle,
    _Out_ PIORING_INFO IoRingBasicInfo
);
```

Этот API возвращает информацию о текущем состоянии IoRing с новой структурой:

```cpp
typedef struct _IORING_INFO
{
  IORING_VERSION IoRingVersion;
  IORING_CREATE_FLAGS Flags;
  ULONG SubmissionQueueSize;
  ULONG CompletionQueueSize;
} IORING_INFO, *PIORING_INFO;
```

Он содержит версию и флаги IoRing, а также текущий размер очередей отправки и завершения.

Когда все операции с IoRing завершены, его нужно закрыть с помощью CloseIoRing, которая получает дескриптор в качестве единственного аргумента, закрывает дескриптор объекта IoRing и освобождает память, используемую для структуры.

Пока я не смог найти в системе ничего, что использовало бы эту функцию, но после выхода 21H2 я ожидаю, что Windows-приложения с интенсивным вводом-выводом начнут использовать ее, вероятно, в основном в серверных и azure-средах.

## [](#header-2) Заключение

Пока что не существует публичной документации по этому новому дополнению к миру ввода-вывода в Windows, но, надеюсь, когда 21H2 выйдет в конце этого года, мы увидим, что все это будет официально документировано и будет использоваться как Windows, так и приложениями сторонних производителей. При разумном использовании это может привести к значительному повышению производительности приложений, в которых часто выполняются операции чтения. Как и каждая новая функция и системный вызов, это может иметь неожиданные последствия для безопасности. Одна ошибка уже была обнаружена hFiref0x, который первым публично упомянул эту функцию и сумел вывести систему из строя, отправив неверный параметр в NtCreateIoRing - ошибка, которая с тех пор была исправлена. Более внимательное изучение этих функций, вероятно, приведет к новым открытиям и интересным побочным эффектам этого нового механизма.

## [](#header-2) Code

Вот небольшой пример, демонстрирующий два способа использования колец ввода/вывода - либо через официальный API KernelBase, либо через внутренний API ntdll. Чтобы код скомпилировался правильно, убедитесь, что он связан с onecoreuap.lib (для функций KernelBase) или ntdll.lib (для функций ntdll):

```cpp
#include <ntstatus.h>
#define WIN32_NO_STATUS
#include <Windows.h>
#include <cstdio>
#include <ioringapi.h>
#include <winternal.h>

typedef struct _IO_RING_STRUCTV1
{
    ULONG IoRingVersion;
    ULONG SubmissionQueueSize;
    ULONG CompletionQueueSize;
    ULONG RequiredFlags;
    ULONG AdvisoryFlags;
} IO_RING_STRUCTV1, *PIO_RING_STRUCTV1;

typedef struct _IORING_QUEUE_HEAD
{
    ULONG Head;
    ULONG Tail;
    ULONG64 Flags;
} IORING_QUEUE_HEAD, *PIORING_QUEUE_HEAD;

typedef struct _NT_IORING_INFO
{
    ULONG Version;
    IORING_CREATE_FLAGS Flags;
    ULONG SubmissionQueueSize;
    ULONG SubQueueSizeMask;
    ULONG CompletionQueueSize;
    ULONG CompQueueSizeMask;
    PIORING_QUEUE_HEAD SubQueueBase;
    PVOID CompQueueBase;
} NT_IORING_INFO, *PNT_IORING_INFO;

typedef struct _NT_IORING_SQE
{
    ULONG Opcode;
    ULONG Flags;
    HANDLE FileRef;
    LARGE_INTEGER FileOffset;
    PVOID Buffer;
    ULONG BufferSize;
    ULONG BufferOffset;
    ULONG Key;
    PVOID Unknown;
    PVOID UserData;
    PVOID stuff1;
    PVOID stuff2;
    PVOID stuff3;
    PVOID stuff4;
} NT_IORING_SQE, *PNT_IORING_SQE;

EXTERN_C_START
NTSTATUS
NtSubmitIoRing (
    _In_ HANDLE Handle,
    _In_ IORING_CREATE_REQUIRED_FLAGS Flags,
    _In_ ULONG EntryCount,
    _In_ PLARGE_INTEGER Timeout
    );

NTSTATUS
NtCreateIoRing (
    _Out_ PHANDLE pIoRingHandle,
    _In_ ULONG CreateParametersSize,
    _In_ PIO_RING_STRUCTV1 CreateParameters,
    _In_ ULONG OutputParametersSize,
    _Out_ PNT_IORING_INFO pRingInfo
    );

NTSTATUS
NtClose (
    _In_ HANDLE Handle
    );

EXTERN_C_END

void IoRingNt() {
    NTSTATUS status;
    IO_RING_STRUCTV1 ioringStruct;
    NT_IORING_INFO ioringInfo;
    HANDLE handle;
    PNT_IORING_SQE sqe;
    LARGE_INTEGER timeout;
    HANDLE hFile = NULL;
    ULONG sizeToRead = 0x200;
    PVOID *buffer = NULL;
    ULONG64 endOfBuffer;

    ioringStruct.IoRingVersion = 1;
    ioringStruct.SubmissionQueueSize = 1;
    ioringStruct.CompletionQueueSize = 1;
    ioringStruct.AdvisoryFlags = IORING_CREATE_ADVISORY_FLAGS_NONE;
    ioringStruct.RequiredFlags = IORING_CREATE_REQUIRED_FLAGS_NONE;

    status = NtCreateIoRing(&handle,
                            sizeof(ioringStruct),
                            &ioringStruct,
                            sizeof(ioringInfo),
                            &ioringInfo);
    if (!NT_SUCCESS(status)) {
        printf("Failed creating IO ring handle: 0x%x\n", status);
        goto Exit;
    }

    ioringInfo.SubQueueBase->Tail = 1;
    ioringInfo.SubQueueBase->Head = 0;
    ioringInfo.SubQueueBase->Flags = 0;

    hFile = CreateFile(L"C:\\Windows\\System32\\notepad.exe",
                       GENERIC_READ,
                       0,
                       NULL,
                       OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL,
                       NULL);

    if (hFile == INVALID_HANDLE_VALUE) {
        printf("Failed opening file handle: 0x%x\n", GetLastError());
        goto Exit;
    }

    sqe = (PNT_IORING_SQE)((ULONG64)ioringInfo.SubQueueBase + sizeof(IORING_QUEUE_HEAD));
    sqe->Opcode = 1;
    sqe->Flags = 0;
    sqe->FileRef = hFile;
    sqe->FileOffset.QuadPart = 0;
    buffer = (PVOID*)VirtualAlloc(NULL, sizeToRead, MEM_COMMIT, PAGE_READWRITE);
    if (buffer == NULL) {
        printf("Failed allocating memory\n");
        goto Exit;
    }
    sqe->Buffer = buffer;
    sqe->BufferOffset = 0;
    sqe->BufferSize = sizeToRead;
    sqe->Key = 1234;
    sqe->UserData = nullptr;

    timeout.QuadPart = -10000;

    status = NtSubmitIoRing(handle, IORING_CREATE_REQUIRED_FLAGS_NONE, 1, &timeout);
    if (!NT_SUCCESS(status)) {
        printf("Failed submitting IO ring: 0x%x\n", status);
        goto Exit;
    }
    printf("Data from file:\n");
    endOfBuffer = (ULONG64)buffer + sizeToRead;
    for (; (ULONG64)buffer < endOfBuffer; buffer++) {
        printf("%p ", *buffer);
    }
    printf("\n");

Exit:
    if (handle) {
        NtClose(handle);
    }

    if (hFile) {
        NtClose(hFile);
    }

    if (buffer) {
        VirtualFree(buffer, NULL, MEM_RELEASE);
    }
}

void IoRingKernelBase() {
    HRESULT result;
    HIORING handle;
    IORING_CREATE_FLAGS flags;
    IORING_HANDLE_REF requestDataFile;
    IORING_BUFFER_REF requestDataBuffer;
    UINT32 submittedEntries;
    HANDLE hFile = NULL;
    ULONG sizeToRead = 0x200;
    PVOID *buffer = NULL;
    ULONG64 endOfBuffer;

    flags.Required = IORING_CREATE_REQUIRED_FLAGS_NONE;
    flags.Advisory = IORING_CREATE_ADVISORY_FLAGS_NONE;
    result = CreateIoRing(IORING_VERSION_1, flags, 1, 1, &handle);
    if (!SUCCEEDED(result)) {
        printf("Failed creating IO ring handle: 0x%x\n", result);
        goto Exit;
    }

    hFile = CreateFile(L"C:\\Windows\\System32\\notepad.exe",
                       GENERIC_READ,
                       0,
                       NULL,
                       OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL,
                       NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        printf("Failed opening file handle: 0x%x\n", GetLastError());
        goto Exit;
    }
    requestDataFile.Kind = IORING_REF_RAW;
    requestDataFile.Handle = hFile;
    requestDataBuffer.Kind = IORING_REF_RAW;
    buffer = (PVOID*)VirtualAlloc(NULL,
                                  sizeToRead,
                                  MEM_COMMIT,
                                  PAGE_READWRITE);
    if (buffer == NULL) {
        printf("Failed to allocate memory\n");
        goto Exit;
    }
    requestDataBuffer.Buffer = buffer;
    result = BuildIoRingReadFile(handle,
                                 requestDataFile,
                                 requestDataBuffer,
                                 sizeToRead,
                                 0,
                                 NULL,
                                 IOSQE_FLAGS_NONE);
    if (!SUCCEEDED(result)) {
        printf("Failed building IO ring read file structure: 0x%x\n", result);
        goto Exit;
    }

    result = SubmitIoRing(handle, 1, 10000, &submittedEntries);
    if (!SUCCEEDED(result)) {
        printf("Failed submitting IO ring: 0x%x\n", result);
        goto Exit;
    }
    printf("Data from file:\n");
    endOfBuffer = (ULONG64)buffer + sizeToRead;

    for (; (ULONG64)buffer < endOfBuffer; buffer++) {
        printf("%p ", *buffer);
    }
    printf("\n");

Exit:
    if (handle != 0) {
        CloseIoRing(handle);
    }

    if (hFile) {
        NtClose(hFile);
    }

    if (buffer) {
        VirtualFree(buffer, NULL, MEM_RELEASE);
    }
}

int main() {
    IoRingKernelBase();
    IoRingNt();
    ExitProcess(0);
}
```