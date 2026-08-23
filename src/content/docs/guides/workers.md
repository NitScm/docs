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
| Disk | `storage.work_dir`, sized for the mirrors plus your largest repository × concurrency |
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

For HTTPS remotes it is injected into the URL per fetch and per push, and never
written to disk. For SSH remotes,
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
messages, which is why a fetch failure reports only the branch it was fetching.

## Sizing the lease

This is the setting most likely to need changing.

```yaml
queue:
  lease_duration: 60s
```

A worker holds a task under a lease with a TTL, kept alive by a heartbeat. The
lease has to survive the longest gap the worker can go without heartbeating,
which in practice means **it has to survive the initial clone of a repository**
— the first task on a repository builds its mirror, and one whose mirror was
evicted builds it again.

**Too short** and a large repository loses its task mid-flight: the lease lapses,
another worker claims the same task, and the first is cut off by its own fencing
check. The symptom is tasks that retry forever without ever failing.

**Too long** and a crashed worker blocks its branch for that long, because
nothing may claim a partition that is still leased.

Start at `60s`. Size it for the cold case, not the warm one: once a mirror
exists a task fetches a delta in seconds, but the task that has to build the
mirror pays for the whole repository. If that takes minutes, raise the lease to
comfortably exceed it — `5m` for a large monorepo is reasonable — and accept the
matching recovery delay after a crash.

:::tip[How to tell]
`nitctl tasks -state running` shows `duration` and the lease holder. If tasks
regularly show high attempt counts and keep restarting, the lease is too short.
:::

## Scaling

Concurrency comes from running **several runners**, not from fanning out inside
one. Each runner holds one worktree at a time, on top of the shared mirrors,
which keeps a worker's disk something an operator can predict.

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

### A release does not cost one pass per developer

A worker shares a filtered projection between users whose **read rights are
identical**. Everyone in the same groups, with the same exemptions, at the same
ref, under the same bundle, receives the same bytes — so the first pull after a
release does the work and the rest are served from it, diff included.

The cost of a release is therefore the number of distinct rights profiles, not
the number of developers. In most organisations that is a handful.

Two things are worth knowing about it:

- **The sharing is per worker.** Four workers means the work happens at most
  four times, not once. Whether a shared cache is worth its complexity is a
  question the audit trail answers: every pull records `reused_projection` in
  its detail, so the hit rate is measurable rather than assumed.
- **A policy change invalidates everything**, because the fingerprint includes
  the bundle version. The first pull after a policy edit pays full price, which
  is the correct behaviour and not a bug to report.

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
cancelled, so a long fetch aborts rather than pushing work nobody owns.

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

A worker keeps a **bare mirror per repository** in `storage.work_dir` and cuts a
**detached worktree per task** from it. The mirror is fetched before each task,
so a task pays for the delta rather than for a whole clone.

Worktrees are never shared or reused. A task that dies mid-apply leaves a dirty
one, and inheriting it would not produce a broken build — it would produce a
wrong commit on the forge under a developer's name. Each task gets a fresh
worktree and it is removed with `--force` afterwards, whatever state was left
behind.

No credential is written to disk. The mirror is created empty and filled by a
fetch whose URL is passed per call, and the push targets that URL rather than a
stored remote.

### Sizing, and why mirrors are evicted

A clone returned its disk when the task ended. A mirror does not — that is what
makes it fast — so without a ceiling a worker that has seen enough repositories
fills its volume, including with mirrors nobody has pushed to in a year.

`storage.mirror_budget_bytes` caps what the mirrors may occupy, 20 GiB by
default. Past it, the least recently used mirrors are removed until the rest
fit. A mirror whose worktree is still in use is never among them.

```yaml
storage:
  work_dir: /var/lib/nit/work
  mirror_budget_bytes: 21474836480   # 20 GiB; 0 disables eviction
```

Size the volume as the budget **plus** the largest repository × concurrency:
the budget covers mirrors, and the worktrees in flight sit on top of it.

Setting the budget below the size of a single large repository is worse than
useless — that repository is evicted after every task and cloned again on the
next. The setting bounds a working set; it does not conjure disk.

:::caution[A `work_dir` belongs to one worker process]
Mirrors are locked per repository within a process. Two workers pointed at the
same directory would race on the same mirror. Give each its own.
:::

## Next

- [Connecting a forge](/guides/forges/) — GitHub, GitLab, Gitea and anything else.
- [Day-to-day operations](/guides/operations/) — reading the queue.
