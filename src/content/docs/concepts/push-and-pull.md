---
title: Push and pull
description: What actually happens between your machine, the control plane, a worker and the forge.
sidebar:
  order: 4
---

Both operations are asynchronous: the API accepts the request and queues work; a
worker does the git. That separation exists so a slow or hostile repository can
never hold an API request open.

## Push

```
 you                    nitd                      worker              forge
  │                      │                          │                   │
  │ git diff base..HEAD  │                          │                   │
  │─── upload patch ────▶│                          │                   │
  │─── PushRequest ─────▶│                          │                   │
  │                 verify sync point               │                   │
  │                 parse the patch                 │                   │
  │                 run the policy                  │                   │
  │◀── 403 + denials ────│  (if unauthorized)       │                   │
  │                 queue on repo:branch            │                   │
  │◀── task id ──────────│                          │                   │
  │                      │──── lease + task ───────▶│                   │
  │                      │                     clone at sync point      │
  │                      │                     apply the patch          │
  │                      │                     commit (squashed)        │
  │                      │                     rebase onto tip          │
  │                      │                          │──── push ────────▶│
  │                      │◀─── result + new sync ───│                   │
  │◀── event: done ──────│                          │                   │
  record the new sync point
```

### On your machine

```
git diff --binary --full-index --find-renames --no-ext-diff --no-textconv \
    $sync_point..HEAD
```

Each flag earns its place. `--binary` keeps binary files as deltas instead of
skipping them. `--full-index` is required for three-way application on the
server. `--no-ext-diff --no-textconv` stop *your* diff configuration from
changing what nit sees — an external differ could otherwise hide a change
entirely.

The patch is compressed with zstd and uploaded, addressed by the hash of its
bytes.

### On the control plane, in this order

1. **Deduplicate** on the request id. Networks fail mid-push; without this a
   retry becomes a second upstream commit.
2. **Verify the sync point.** Applying a patch to a base its author never had is
   how silent corruption starts.
3. **Decode** the patch — with a size ceiling, because a few kilobytes of crafted
   zstd expand to gigabytes.
4. **Authorize**, evaluating every section before answering.
5. **Refuse, or store the enforced patch and queue it.**

Authorization happens *before* anything is queued, so a refused push costs no
clone.

:::note[The worker applies the enforced patch, not yours]
In strip mode they differ. A worker applying the client's version would undo the
whole authorization pass, so the control plane stores what it authorized and the
worker reads that.
:::

### In the worker

Check out the **sync point** — not the current tip — apply the patch there,
commit as a single squashed commit, then rebase onto whatever landed meanwhile.

The final publish is `git push --force-with-lease=<branch>:<expected tip>`. That
is the real atomicity guarantee: the queue serializes nit's own work, but only
the forge can arbitrate against a change that did not come through nit at all.

### What lands on the forge

The commit is authored **and** committed as your authenticated identity — never
from the patch's `From:` line, which the sender controls — and it carries its own
provenance as git trailers:

```
Fix the ingest rate limiter

Nit-User: alice
Nit-Request: 01J8Z3Q2M7C4V9K1
Nit-Task: be59af45-9694-416e-ace2-da5cffc7f145
Nit-Policy-Version: sha256:f6040b6d6a8381dc
Nit-Base-Commit: 4f2a9c1b7e30
Nit-Workspace: ws_7c1e9f2a
Nit-Dropped: 2
```

The forge is the one record an auditor, a reviewer or a compliance export can
read without database access. Identity already survived the trip; the rest — 
which request, which bundle version authorized it, what it was built on, and
whether anything was dropped — would otherwise exist only in PostgreSQL.

`Nit-Dropped` appears **only in strip mode**, and is the only signal on the forge
that a commit is not what its author wrote.

They are real git trailers, so `git log --grep`, `git interpret-trailers` and the
forges' own parsers read them:

```sh
git log -1 --format='%(trailers:key=Nit-Request,valueonly)'
nitctl audit -request 01J8Z3Q2M7C4V9K1
```

:::caution[Your message cannot contain them]
Any line beginning `Nit-…:` is stripped from your commit message before the real
trailers are appended. A message is free text landing in the same commit, so
without that, `-m $'Fix it\n\nNit-User: bob'` would attribute your change to a
colleague in exactly the record that leaves the database.

A `Co-authored-by` block is safe: nit's trailers join it rather than starting a
new paragraph, so the forges keep rendering it.
:::

### Rejection versus stripping

Default is `reject`: the whole push is refused.

`nit push --drop-unauthorized` asks the server to strip instead. It exists
because some workflows genuinely want it, but it must be a per-push, explicit
choice — what lands upstream then differs from what you committed, and the
response enumerates exactly what was dropped so you can reconcile.

## Pull

```
 you                    nitd                      worker              forge
  │─── PullRequest ─────▶│                          │                   │
  │◀── task id ──────────│                          │                   │
  │                      │──── task ───────────────▶│                   │
  │                      │                     clone / fetch ◀──────────│
  │                      │                     diff sync..tip           │
  │                      │                     filter by read rules     │
  │                      │◀─── patch + next sync ───│                   │
  │─── GET events ──────▶│  (long poll, held open)  │                   │
  │◀── event: ready ─────│                          │                   │
  │─── GET patch ───────▶│                          │                   │
  apply, commit the sync marker, record next_sync
```

### The filtering happens in the worker

Unlike a push, nothing is authorized in the control plane. What is readable has
to be decided against the bundle in force when the diff is **produced**, not when
the request was accepted — a rule that changed while the task sat in the queue
must apply to what is about to be delivered.

A section is kept only if every path it touches is readable. A rename with one
unreadable side is dropped whole: emitting half of it would either delete a file
you cannot see or create one out of nowhere.

### The server never calls you back

Look at the direction of the last exchange. Your machine is behind NAT and a
firewall; it is not addressable. So the CLI holds a **long poll** open on the
task and fetches the patch itself.

No tunnels, no open ports, no agent on developer machines. Plain polling is the
documented fallback for clients that cannot hold a connection.

### Downloading through the task

Patches are fetched at `/v1/tasks/{id}/patch`, not from a content-addressed blob
endpoint.

Authorization is then "does this task belong to you?" — a question with an
answer. A bare `/blobs/{digest}` endpoint would make an unguessable identifier
the only thing standing between a filtered patch and the people it was filtered
*for*.

## The queue

Pushes to the same branch must not run concurrently. nit serializes them with a
queue rather than a lock held across the whole clone-apply-push cycle:

- **At most one task per `repository:branch` runs at a time.** That is what
  serializes a branch.
- **A push on a busy branch is queued, never refused.** You do not have to retry
  by hand; the CLI shows your position.
- **Pull tasks take no key at all** and run fully in parallel — they are
  read-only.
- **Workers hold a lease** with a TTL and a heartbeat, plus a fencing token. A
  worker that dies releases its branch when the lease lapses; the token stops a
  zombie from completing a task somebody else now owns.

A lock held for minutes would block a branch for minutes and strand it forever on
a crash. A queue does neither.

:::tip[The one setting to size]
`NIT_LEASE_DURATION` has to survive a clone of your largest repository. Too short
and a big repository loses its task mid-flight; too long and a crashed worker
blocks its branch for that long. See [Running workers](/guides/workers/).
:::

## Next

- [Architecture](/concepts/architecture/) — the components and how they scale.
- [Filtered projections](/concepts/filtered-projections/) — why the sync point
  is the base for all of this.
