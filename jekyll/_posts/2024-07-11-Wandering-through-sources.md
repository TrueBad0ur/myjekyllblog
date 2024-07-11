---
title: Wandering through sources [eng]
published: true
tags: [ "devops", "source" ]
image: /assets/previews/29.jpg
layout: page
pagination: 
  enabled: true
---

## [](#header-2)Funny moments found in sources

#### [](#header-4)Pause containers? Pause containers!

Quoting official k8s documentation:
> In a Kubernetes Pod, an infrastructure or “pause” container is first created to host the container. In Linux, the cgroups and namespaces that make up a pod need a process to maintain their continued existence; the pause process provides this. Containers that belong to the same pod, including infrastructure and worker containers, share a common network endpoint (same IPv4 and / or IPv6 address, same network port spaces). Kubernetes uses pause containers to allow for worker containers crashing or restarting without losing any of the networking configuration.

Soooo the source code for it can be found at [this](https://github.com/kubernetes/kubernetes/tree/master/build/pause) link

And the actual C functions source there is pretty simple:
```c
#include <stdio.h>
#include <unistd.h>

int main() {
  pid_t pid;
  pid = fork();
  if (pid == 0) {
    while (getppid() > 1)
      ;
    printf("Child exiting: pid=%d ppid=%d\n", getpid(), getppid());
    return 0;
  } else if (pid > 0) {
    printf("Parent exiting: pid=%d ppid=%d\n", getpid(), getppid());
    return 0;
  }
  perror("Could not create child");
  return 1;
}
```
This code fragment creates a child process using the fork() function.
The child process (pid == 0) is looped as long as its parent process (getppid() > 1) exists.
If the parent process terminates, the child process also terminates, displaying the appropriate message.

```c
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define STRINGIFY(x) #x
#define VERSION_STRING(x) STRINGIFY(x)

#ifndef VERSION
#define VERSION HEAD
#endif

static void sigdown(int signo) {
  psignal(signo, "Shutting down, got signal");
  exit(0);
}

static void sigreap(int signo) {
  while (waitpid(-1, NULL, WNOHANG) > 0)
    ;
}

int main(int argc, char **argv) {
  int i;
  for (i = 1; i < argc; ++i) {
    if (!strcasecmp(argv[i], "-v")) {
      printf("pause.c %s\n", VERSION_STRING(VERSION));
      return 0;
    }
  }

  if (getpid() != 1)
    /* Not an error because pause sees use outside of infra containers. */
    fprintf(stderr, "Warning: pause should be the first process\n");

  if (sigaction(SIGINT, &(struct sigaction){.sa_handler = sigdown}, NULL) < 0)
    return 1;
  if (sigaction(SIGTERM, &(struct sigaction){.sa_handler = sigdown}, NULL) < 0)
    return 2;
  if (sigaction(SIGCHLD, &(struct sigaction){.sa_handler = sigreap,
                                             .sa_flags = SA_NOCLDSTOP},
                NULL) < 0)
    return 3;

  for (;;)
    pause();
  fprintf(stderr, "Error: infinite loop terminated\n");
  return 42;
}
```

Signal handling: sigdown terminates the process when SIGINT or SIGTERM signals are received, and sigreap handles the termination of child processes.
Waiting loop: The main loop in main() uses pause() to have the process wait indefinitely for signals until one of the specified events occurs.


```c
  return 42;
```
The return of error code 42 at the end of the pause container has a humorous connotation and is a reference to the science fiction novel "Hitchhiker's Guide to the Galaxy" by Douglas Adams. In this novel, the number 42 is the answer to "The ultimate question of life, the universe and everything".

In the context of a pause container, returning 42 instead of the usual error codes such as 1 or 0 has no particular significance to the functioning of the program, but adds an element of irony and a reference to popular culture. This is often seen among developers as a way to "liven up" the code a bit.