---
title: Some staff about Virtual / Physical Memory
published: false
tags: [ "windows", "lab" ]
image: assets/previews/18.jpg
layout: page
pagination: 
  enabled: true
---

### [](#header-3) Links

[Original workshop](https://intuit.ru/studies/courses/10471/1078/lecture/16579?page=1)
[Windows Research Kit WRK](https://github.com/HighSchoolSoftwareClub/Windows-Research-Kernel-WRK-/tree/26b524b2d0f18de703018e16ec5377889afcf4ab)

## [](#header-2) Theory

### [](#header-3) Virtual Memory

All processes in Windows OS are provided with the most important resource - virtual memory. All data, with which processes work directly, is stored in virtual memory

The name "virtual" comes from the fact that the process does not know the real (physical) location of memory - it can be located both in random access memory (RAM) and on disk. The operating system provides a process with virtual address space (VAS) of a certain size, and the process can work with memory cells at any virtual addresses in this space without "thinking" about where the data is actually stored

The size of virtual memory is theoretically limited by the bitness of the operating system. In practice, a particular operating system implementation sets limits below the theoretical limit. For example, for 32-bit systems (x86) that use 32-bit registers and variables for addressing, the theoretical maximum is 4 GB (2^32 bytes = 4,294,967,296 bytes = 4 GB). However, only half of this memory is available to processes - 2 GB, the other half is given to system components. On 64-bit (x64) systems, the theoretical limit is 16 exabytes (2^64 bytes = 16,777,216 TB = 16 EB). At the same time, 8 TB is allocated to processes, the same amount is given to the system, the rest of the address space is not used in current versions of Windows

### [](#header-3) Implementation of Virtual Memory in Windows

On the image you can see the implementation scheme of virtual memory in a 32-bit Windows operating system. As already noted, the process is provided with a virtual address space of 4 GB, of which 2 GB located at lower addresses (0000 0000 - 7FFF FFFF), the process can use at its discretion (user VAS), and the remaining two gigabytes (8000 0000 - FFFF FFFF) are allocated to system data structures and components (system VAS). Note that each process has its own user VAP, and the system VAP is the same for all processes

![Virtual Memory](/assets/post_images/VirtualMemory.png)

Virtual memory is divided into blocks of the same size - virtual pages. On Windows there are large pages (x86 - 4 MB, x64 - 2 MB) and small pages (4 KB). Physical memory (RAM) is also divided into pages exactly the same size as virtual memory. The total number small virtual pages of a process on 32-bit systems is 1,048,576 (4 GB / 4 KB = 1,048,576)

Typically, processes do not use the entire amount of virtual memory, but only a small part of it. Accordingly, it does not make sense (and often not possible) to allocate a page in physical memory for each virtual page of all processes. Instead, RAM (say, "resident") holds a limited number of pages that are directly required by the process. This subset of process virtual pages located in physical memory is called the process's working set

Those of virtual pages which are not yet required by the process can be unloaded to the disk by the OS, into a special file called the paging file (page file)

How does the process know where the required page is currently located? For this, special data structures are used - page tables

### [](#header-3) Structure of the virtual address space

Let's consider what elements the virtual address space of a process consists of in 32-bit Windows

A user Virtual Address Space contains an executable image of the process, dynamic-link libraries (DLLs), a process heap, and thread stacks

When the program starts, a process is created, the code and data of the program (executable image) are loaded into memory, necessary dynamically linked libraries (DLL) for the program are loaded too. A heap is formed - an area in which a process can allocate memory to dynamic data structures (structures whose size is not known in advance, but is determined during program execution). The default heap size is 1 MB, but can be changed when the application is compiled or during process execution. In addition, each thread is provided with a stack to store local variables and function parameters, also by default 1 MB in size

![Structure of Virtual Memory](/assets/post_images/structure_virtual.png)

### [](#header-3) Process Memory Allocation

There are several ways to allocate virtual memory to processes using the Windows API. Let's consider two main ways - using the VirtualAlloc function and using the heap

1 - The WinAPI function VirtualAlloc allows you to reserve and transfer virtual memory to a process. When reserving, the requested range of virtual address space is assigned to the process (assuming that there are enough free pages in the user VAS), the corresponding virtual pages become reserved (reserved), but the process does not have access to this memory - an exception will be thrown when the process tries to read or write. To gain access, a process must commit memory to reserved pages, which then become committed

Note that virtual memory areas are reserved at addresses that are a multiple of the memory allocation granularity constant MM_ALLOCATION_GRANULARITY (file base\ntos\inc\mm.h, line 54). This value is 64 KB. In addition, the size of the reserved area must be a multiple of the page size (4 KB)

The WinAPI function VirtualAlloc uses the kernel function NtAllocateVirtualMemory (file base\ntos\mm\allocvm.c, line 173) to allocate memory

2 - For more flexible memory allocation, there is a process heap, which is managed by the heap manager. Heaps are used by the WinAPI function HeapAlloc, as well as the C language operator malloc and the C++ new operator. The heap manager allows a process to allocate memory at a granularity of 8 bytes (on 32-bit systems) and uses the same kernel functions as VirtualAlloc to serve these requests

Virtual address descriptors

Virtual Address Descriptors (VADs) are used to store information about reserved memory pages. Each descriptor contains data about one reserved memory area and is described by the MMVAD structure (file base\ntos\mm\mi.h, line 3976)

The boundaries of the area are defined by two fields - StartingVpn (starting VPN) and EndingVpn (end VPN). VPN (Virtual Page Number) is the virtual page number; pages are simply numbered starting from zero. If the page size is 4 KB, then the VPN is obtained from the virtual address of the beginning of the page by discarding the lower 12 bits (or 3 hexadecimal digits). For example, if a virtual page starts at 0x340000, then the VPN for that page is 0x340

Virtual address descriptors for each process are organized into a balanced binary AVL tree. For this the MMVAD structure has fields pointing to the left and right children: LeftChild and RightChild

To store information about the state of the memory area for which the descriptor is responsible, the MMVAD structure contains the VadFlags flags field


### [](#header-3) Address translation

Translation of a virtual address is the process of identifying the real (physical) location of a memory cell with a given virtual address, i.e. the transformation of a virtual address into a physical one. The principle of translation is shown on the image below, here we will look at the details of translation and implementation details

Information about the correspondence of virtual addresses to physical ones is stored in page tables. The system maintains many page records for each process: if the page size is 4 KB, then more than a million records are required to store information about all virtual pages in a 32-bit system (4 GB / 4 KB = 1,048,576). These page entries are grouped into Page Tables and are called PTEs (Page Table Entry). Each table contains 1024 entries, so the maximum number of page tables for a process is 1024 (1,048,576 / 1024 = 1024). Half of the total - 512 tables - are responsible for the user VAS, the other half - for the system VAS

Page tables are stored in virtual memory. Information about the location of each of the page tables is stored in the Page Directory, the only one for the process. The entries in this directory are called PDEs (Page Directory Entry). Thus, the translation process is two-stage: first, the PDE entry in the Page Directory is determined by the virtual address, then the corresponding page table is found from this entry, the PTE entry of which points to the required page in physical memory

How does the process know where the Page Directory is stored in memory? The DirectoryTableBase field of the KPROCESS structure is responsible for this (file base\ntos\inc\ke.h, line 958, first element of the array)

![Translation of addresses](/assets/post_images/translation.png)

PDE and PTE records are represented by the MMPTE_HARDWARE structure (base\ntos\mm\i386\mi386.h, line 2508) containing the following main fields:

* Valid flag (one-bit field): if the virtual page is located in physical memory, Valid = 1
* Accessed flag: if the page was accessed for reading, Accessed = 1
* Dirty flag: if the content of the page has been changed (a write operation has been performed), Dirty = 1
* LargePage flag: if the page is large (4 MB), LargePage = 1
* Owner flag: if the page is accessible from user mode, Owner = 1
* PageFrameNumber - 20 bit field: indicates the page frame number (PFN, Page Frame Number)

The PageFrameNumber field stores the number of an entry in the PFN database, a system structure responsible for information about physical memory pages. The PFN record is represented by the MMPFN structure (file base\ntos\mm\mi.h, line 1710)

### [](#header-3) Page Exceptions

A page can reside either in physical memory (RAM) or on disk in a paging file.

If the PTE entry has the Valid flag set to 1, then the page is in physical memory and can be accessed. Otherwise (Valid = 0), the page is not available to the process. When trying to access such a page, a page fault occurs and the MmAccessFault function is called (file base\ntos\mm\mmfault.c, line 101)

There are many reasons for page faults, we will consider only one - the page has been swapped out to a page file (paging file). In this case, the PTE record has the MMPTE_SOFTWARE type (file base\ntos\mm\i386\mi386.h, line 2446) and has a 20-bit PageFileHigh field instead of the PageFrameNumber field, which is responsible for the location of the page in the page file.

Page files are described by the MMPAGING_FILE structure (base\ntos\mm\mi.h, line 4239), which has the following fields:

* Size – current file size (in pages)
* MaximumSize, MinimumSize – maximum and minimum file sizes (in pages)
* FreeSpace, CurrentUsage – number of free and used pages
* PageFileName – file name
* PageFileNumber – file number
* FileHandle – file handle

On 32-bit Windows, up to 16 swap files up to 4095 MB each are supported. The list of paging files is located in the HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PagingFiles registry key. The corresponding system array MmPagingFile[MAX_PAGE_FILES] of type PMMPAGING_FILE is described in the file base\ntos\mm\mi.h (line 8045)

### [](#header-3) Memory limits


Virtual Memory restrictions

| Type of memory | 32-bit Windows | 64-bit Windows | 
|:----|:----|:----|
| Virtual Address Space | 4GB | 16TB (16 000 GB) |
| User VAS | 2GB (up to 3GB in case of using special keys while booting) | 8TB |
| System VAS | 2GB (1 to 2 GB in case of using special keys while booting) | 8TB |


Physical Memory restrictions in client versions

| Windows version | 32-bit | 64-bit |
|:----|:----|:----|
| Windows XP | 512MB (Starter) to 4GB (Professional) | 128GB (Professional) |
| Windows Vista | 1GB (Starter) to 4GB (Ultimate) | 8GB (Home Basic) to 128GB (Ultimate) |
| Windows 7 | 2GB (Starter) to 4GB (Ultimate) | 8GB (Home Basic) to 192GB (Ultimate) |


Physical Memory restrictions in server versions

| Windows version | 32-bit | 64-bit |
|:----|:----|:----|
| Windows Server 2003 R2 | 4GB (Standard) to 64GB (Datacenter) | 32GB (Standard) to 1TB (Datacenter) |
| Windows Server 2008 | 4GB (Web Server) to 64GB (Datacenter) | 32GB (Web Server) to 1TB (Datacenter) |
| Windows Server 2008 R2 | no 32-bit versions | 8GB (Foundation) to 2TB (Datacenter) |

## [](#header-2) Practice / Workshop

### [](#header-3) Determine the values of system variables that are responsible for the boundaries of the areas of the virtual address space (VAS)

Determine the values of 4 system variables:

MmHighestUserAddress – maximum address of user VAS
MmSystemRangeStart – starting address of system VAS
MiSystemCacheEndExtra – ending address of system cache area or starting address of page table area
MmNonPagedSystemStart – starting address of system PTE

```js
0: kd> dd MmHighestUserAddress L1
827b284c  7ffeffff

0: kd> dd MmSystemRangeStart L1
827b2850  80000000
```

So the variable MmHighestUserAddress = 7FFE FFFF

Note that the upper bound of the user VAS does not reach the system VAS start address 80000000. The 64 KB area (80000000 - 7FFEFFFF = 64 KB) is reserved by the system and is not available to user processes