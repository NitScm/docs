---
title: Architecture
description: The four components, what state lives where, and how each part scales.
sidebar:
  order: 5
---

## The components

```
                        ┌────────────┐
    nit (developer)     │            │      PostgreSQL
         ──────────────▶│    nitd    │◀──────────────
                        │            │
                        └─────┬──────┘
                              │ queue
                        ┌─────▼──────┐
                        │ nit-worker │───────────────▶  the forge
                        └────────────┘
```

| Binary | Role | Runs where |
| --- | --- | --- |
| `nit` | Developer CLI | A developer's machine |
| `nitd` | Control plane: API, authorization, sync points, queue, blobs, audit | One or more replicas |
| `nit-worker` | Clones, applies, filters, pushes | Anywhere with git, disk and forge access |
| `nitctl` | Operator CLI: policy, tokens, migrations, tasks, audit | An operator's machine or a server |

Plus an optional **web console**, which is a client of the same read-only
operations API that `nitctl` uses.

### Why `nitd` and `nit-worker` are separate

`nitd` performs **no git operation**. Everything that clones, applies or pushes
runs in a worker.

A repository can be enormous and a forge can be slow. If the API did that work,
one large clone would hold an HTTP request open and consume a connection for
minutes. Separating them also means they scale on different axes: `nitd` scales
with request rate, workers scale with disk and network.

### Why one worker binary rather than two

Push and pull share the clone handling, the patch pipeline and the sync point
bookkeeping — ninety percent of the code. Two binaries would double the
deployment surface for no gain.

Scaling is per queue instead:

```sh
nit-worker                     # takes both kinds
nit-worker -queues=pull        # a machine dedicated to read traffic
nit-worker -concurrency=4      # four runners, four concurrent clones
```

## Where state lives

### Policy: in files

Rules, groups and repositories live in a **bundle** — YAML in its own git
repository, reviewed through pull requests. Not in the database.

That is what gives authorization rules history, blame and rollback, and what
makes `nitctl policy validate` runnable in CI. A database row has none of those
properties, and "who granted this access, and when?" is the first question asked
after an incident.

The consequence, which is worth accepting knowingly: **the console cannot edit
rules.** Granting access is a pull request, not a click. That is slower on
purpose.

### Runtime state: in PostgreSQL

| Table | Holds |
| --- | --- |
| `tasks` | The queue, with leases and fencing tokens |
| `sync_points` | `(workspace, repository, branch) → upstream commit` |
| `workspaces` | One checkout on one machine |
| `sessions` | Authentication tokens, as hashes only |
| `artifacts` | Blob metadata, with TTLs |
| `audit_log` | Append-only, enforced by the database |
| `users`, `repositories` | Mirrors of the bundle, so records have something to reference |

The audit table carries `DO INSTEAD NOTHING` rules against `UPDATE` and `DELETE`,
so an application bug cannot rewrite history. Retention is an operational concern
and deliberately not the application's — but note that it is currently *nobody's*:
the table is not partitioned and nothing prunes it. See
[Day-to-day operations](/guides/operations/#the-audit-trail) for the purge that
works today, and `docs/SCALING.md` for why partitioning is the real answer.

### Patches: in a blob store

Content-addressed by the SHA-256 of their compressed bytes. That gives
deduplication, resumable transfer, and integrity checking the client can perform
itself.

Filesystem-backed today, behind an interface so object storage is a swap rather
than a rewrite.

:::caution[The blob store must be shared]
`nitd` writes the authorized patch and a worker reads it back. Separate
directories produce `missing_patch` on every push — the most common way to get a
deployment wrong.
:::

## Identity and authentication

Tokens are issued by an operator (`nitctl token create`) and only their SHA-256
is stored. A leaked database dump yields nothing usable, and there is no recovery
path for a lost token — it is reissued, not retrieved.

**Identity never comes from the patch.** The author field of a git commit is free
text; a system that trusted it would let anyone attribute a change to a
colleague. The commit that lands upstream is authored from the authenticated
session.

Authentication failures are distinguished — expired, revoked, disabled, not in
the policy bundle — because the right action differs for each, and answering
"unauthorized" to all of them is an operational problem rather than a security
feature.

## Scaling and failure

**`nitd`** is stateless apart from the database. Run as many replicas as you
like behind a load balancer. They must share `NIT_SYNC_KEY`, or a token minted by
one and rejected by another would make the deployment fail at random.

**Workers** scale horizontally. Pushes still serialize per branch — that is the
queue's job — so more workers buy throughput *across* branches and repositories,
never within one.

**A worker that dies** releases its branch when its lease lapses. A reaper
returns abandoned tasks to the queue, and the fencing token stops the dead
worker's process from completing a task another worker now owns.

**A bundle that does not compile** is not applied. The last good one stays in
force and the failure is logged loudly — failing open would grant access nobody
authorized, and failing closed would take an outage on every typo.

**Migrations are never applied on boot.** A schema change is a deployment step an
operator takes with `nitctl migrate`; a server that migrated on start-up would
happily run half-rolled-out DDL from several replicas at once.

## Multi-tenancy

nit ships single-tenant. A `tenant_id` is carried through the schema and the
domain types from the start, always `default`, so the capability can be added
without migrating everything — threading a tenant through a schema after the fact
is one of the most expensive migrations there is.

## Next

- [Going to production](/guides/production/) — topologies, security checklist.
- [Day-to-day operations](/guides/operations/) — what to look at, and when.
