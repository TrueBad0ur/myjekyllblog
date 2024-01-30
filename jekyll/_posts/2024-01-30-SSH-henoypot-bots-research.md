---
title: SSH honepot bots results [eng]
published: true
tags: [ "research", "honeypot" ]
image: /assets/previews/27.jpg
layout: page
pagination: 
  enabled: true
---

Some time ago I finally found one pretty simple setup for the ssh honeypot

What I was looking for:

1. log command
2. emulate OS (or some simple commands)

I have [already monitored](https://t.me/reverse_dungeon/307) top logins/passwords when bots are trying to brute force

And also for [top countries](https://t.me/reverse_dungeon/3262) from which bots are connecting

So now is the most interesting part: what they want?


### [](#header-3)Setup

```bash
git clone https://github.com/TrueBad0ur/ssh-honeypot.git
```

In my default docker-compose config the service will be running on the host's port 22

In the case you have ssh running on it - change it in the config

To monitor data in the database I prefer using [litecli](https://github.com/dbcli/litecli)

As we have volumes we can just do the following:

```bash
litecli app/db/honeypot.db

select * from `Command`
select * from `Login`
```

```bash
docker compose up
```

### [](#header-3)Data

