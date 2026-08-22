---
title: Running workers
description: What a worker does, how to size the lease, and how to scale them.
sidebar:
  order: 3
---

A worker is where all the git happens: clone, apply, rebase, push, and the
filtering that produces a pull.

```sh
nit-worker                          # takes both queues
nit-worker -queues=pull             # dedicated to read traffic
nit-worker -concurrency=4           # four runners in this process
nit-worker -name eu-west-1a         # identifier recorded on leases and in logs
```

It reads the **same configuration** as `nitd` — the same file, the same
variables. Two processes that disagree about the database, the bundle or the
signing key fail in ways that are very hard to diagnose.

## What it needs

| | |
| --- | --- |
| `git` | The job is clone, apply, rebase, push |
| Disk | `storage.work_dir`, sized for your largest repository × concurrency |
| The shared blob store | `storage.blob_dir`, the same one `nitd` writes to |
| Network access to the forge | And a credential for it |
| The database | The queue lives there |
| The policy bundle | A pull filters against the bundle in force |

### The forge credential

```yaml
forge:
  token_file: /run/secrets/nit-forge-token
```

nit is the **only writer** of the repositories it manages, so this is a machine
identity, not a person's. It should have write access to exactly the repositories
in the bundle and to nothing else. A person's token gives nit their whole
account, and stops working the day they leave.

For HTTPS remotes it is injected into the URL at clone time. For SSH remotes,
leave it empty — the generic driver leaves `ssh://` remotes untouched precisely
so git resolves the credential itself — and hand git its configuration:

```yaml
git:
  ssh_command: >-
    ssh -i /run/secrets/nit-ssh-key
    -o IdentitiesOnly=yes
    -o UserKnownHostsFile=/etc/nit/ssh/known_hosts
    -o StrictHostKeyChecking=yes
    -o BatchMode=yes
```

A passthrough, not a key manager: there is deliberately no `ssh_key` setting,
because a key path would cover only the simplest case while agents, `ProxyJump`
and per-host keys stayed git's business. Empty leaves the inherited environment
alone. See [the worked example](/guides/example-github-ssh/).

The authenticated URL is a credential. It never appears in logs or error
messages, which is why a clone failure reports only the branch it was cloning.

## Sizing the lease

This is the setting most likely to need changing.

```yaml
queue:
  lease_duration: 60s
```

A worker holds a task under a lease with a TTL, kept alive by a heartbeat. The
lease has to survive the longest gap the worker can go without heartbeating,
which in practice means **it has to survive a clone**.

**Too short** and a large repository loses its task mid-flight: the lease lapses,
another worker claims the same task, and the first is cut off by its own fencing
check. The symptom is tasks that retry forever without ever failing.

**Too long** and a crashed worker blocks its branch for that long, because
nothing may claim a partition that is still leased.

Start at `60s`. If your clones take minutes, raise it to comfortably exceed
them — `5m` for a large monorepo is reasonable — and accept the matching recovery
delay after a crash.

:::tip[How to tell]
`nitctl tasks -state running` shows `duration` and the lease holder. If tasks
regularly show high attempt counts and keep restarting, the lease is too short.
:::

## Scaling

Concurrency comes from running **several runners**, not from fanning out inside
one. Each runner holds one clone at a time, which keeps a worker's disk budget
something an operator can predict.

```sh
nit-worker -concurrency=4                        # one process, four runners
docker compose up -d --scale worker=4            # four containers
```

**Pushes still serialize per branch.** That is the queue's job, and no amount of
workers changes it. More workers buy throughput *across* branches and
repositories, never within one.

### Dedicating machines

```sh
nit-worker -queues=push        # writes only
nit-worker -queues=pull        # reads only
```

Useful when read traffic is bursty — a hundred developers running `nit pull`
after a release — and you do not want it competing with pushes for disk.

## What a worker does not do

**It does not re-derive authorization for a push.** The control plane already
decided, refused what had to be refused, and stored the *enforced* patch.
Re-deciding in the worker would only create a way for the two to disagree.

**It does filter a pull**, because what is readable has to be decided against the
bundle in force when the diff is produced, not when the request was accepted.

## Failure and recovery

**A worker that dies** releases its branch when the lease lapses. A reaper in
`nitd` returns abandoned tasks to the queue every `queue.reap_every`.

**A zombie worker** — one whose lease expired but whose process is still
running — cannot complete its task: every state transition presents a fencing
token, and the token changed when another worker claimed it. Its context is
cancelled, so a long clone aborts rather than pushing work nobody owns.

**A conflict** is permanent. If a patch no longer applies onto upstream, retrying
would conflict identically, so the task fails immediately with `conflict` and the
developer is told to pull and resolve. It does not burn its attempt budget
retrying something that cannot change.

**A failure after the push landed** never fails the task. Once `git push` has
succeeded, a sync point that cannot be advanced or an audit record that cannot be
written is logged loudly and the task still succeeds — because the queue retries
failed tasks, and retrying a task that already published would at best be a no-op
and at worst a duplicate commit.

## Clone strategy

Every task currently gets a fresh clone, removed afterwards.

A cache keyed by repository would be a large win on big repositories and is the
obvious next optimization. It is not there yet because a cache shared between
tasks that apply patches and rebase is also a way for one task's leftover state to
corrupt another's — a trade not worth taking before the correctness is settled.

Size `storage.work_dir` accordingly: largest repository × concurrency, with room
to spare.

## Next

- [Connecting a forge](/guides/forges/) — GitHub, GitLab, Gitea and anything else.
- [Day-to-day operations](/guides/operations/) — reading the queue.
