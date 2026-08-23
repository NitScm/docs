---
title: Day-to-day operations
description: Managing tokens, watching the queue, reading the audit trail, and diagnosing the things that go wrong.
sidebar:
  order: 6
---

## Tokens

```sh
nitctl token create -user alice -label laptop -ttl 720h
nitctl token list   -user alice
nitctl token revoke -id <session-id>
```

Only the SHA-256 of a token is stored. It is shown once and there is no recovery
path: a lost token is reissued, not retrieved.

A token can only be issued to someone the **bundle** declares — a typo produces
an error rather than a credential for an account that authorizes nothing.

Revocation is immediate. A second revoke keeps the first instant, because for an
incident timeline *when a credential was first cut off* is the fact that matters.

### Removing someone

Take them out of the bundle. Authentication then fails with `user_not_in_policy`
and every grant is gone.

Their history stays: nit never deletes a user row, because a deleted row would
take the audit trail with it. Revoke their tokens too, for tidiness.

## Watching the queue

```sh
export NIT_SERVER=https://nit.example.com
export NIT_TOKEN=nit_…

nitctl stats
```

```
policy:       sha256:f6040b6d6a8381dc
repositories: 12

queued:       3
running:      1
succeeded:    1847
failed:       2

busy branches:   1
denials (24h):   6
```

Two numbers mean something is wrong *right now*: **queued** climbing, and
**branches busy** staying high. Everything else is history.

**Denials (24h)** is a trend, not an alarm. A number that climbs is usually the
policy fighting the team — some subtree's ownership no longer matches who works
on it — rather than anybody attacking anything.

```sh
nitctl tasks -state queued
nitctl tasks -state failed -limit 20
nitctl tasks -repository backend-api -kind push
```

```
TASK                                   KIND   STATE      USER    REPOSITORY@BRANCH      DURATION   NOTE
9ccf9693-56d4-4bec-838b-079867bcf379   pull   succeeded  bob     backend-api@main       38ms
be59af45-9694-416e-ace2-da5cffc7f145   push   running    carol   backend-api@feature/x  2m14s      worker-2
56c8b3f7-a0a1-4971-b5ba-3f18389b08bb   push   failed     dave    data-platform@main     1.2s       conflict
```

`NOTE` carries the error code for a failure, the queue position for a wait, or
the worker holding the lease for a running task.

## The audit trail

```sh
nitctl audit -limit 20
nitctl audit -user bob -since 24h
nitctl audit -repository backend-api -since 168h
nitctl audit -request <request-id> -json
```

```
WHEN                 ACTOR   ACTION             REPOSITORY@BRANCH   PATH                RULE
2026-07-31 00:35:29  bob     push.applied       backend-api@main
2026-07-31 00:35:28  bob     push.accepted      backend-api@main
2026-07-31 00:33:14  bob     push.denied_path   backend-api@main    secrets/prod.env    secrets-are-platform-only
2026-07-31 00:33:14  bob     push.rejected      backend-api@main
```

| Action | Means |
| --- | --- |
| `push.accepted` | Authorization passed; the task was queued |
| `push.rejected` | Refused; nothing was queued |
| `push.denied_path` | One refused path, with the rule that refused it |
| `push.applied` | The change landed on the forge |
| `pull.requested` | A pull was queued |
| `pull.delivered` | A filtered patch was produced |

Every record carries the **policy version** in force at the time, so a past
decision can be replayed against exactly the rules that produced it: find the
version, check out that commit of the policy repository, run
`nitctl policy explain`.

### Following one operation end to end

Every request carries an id that appears in the API log, on the task, and in the
audit trail. Given a developer's error message:

```sh
nitctl audit -request 01J8Z3Q2M7C4V9K1
```

That is the whole thread: what was asked, what was refused, which rule refused
it, and which task it became.

### Starting from a commit on the forge

Every commit nit publishes carries trailers, so an investigation can start from
the forge rather than from a developer's report:

```sh
git log -1 --format='%(trailers:key=Nit-Request,valueonly)' <sha>
nitctl audit -request 01J8Z3Q2M7C4V9K1
```

`Nit-User` is the bundle identity, `Nit-Policy-Version` is the bundle that
authorized it — check out that commit of the policy repository and
`nitctl policy explain` replays the decision exactly.

`Nit-Dropped` appears only when the author used `--drop-unauthorized`. It is the
only signal on the forge that a commit is not what its author wrote, and worth a
scan when something upstream does not build:

```sh
git log --format='%h %an %(trailers:key=Nit-Dropped,valueonly)' | grep -v ' $'
```

Nit trailers cannot be forged from a commit message — the worker strips any
`Nit-…:` line an author wrote before appending the real ones.

Records are append-only at the database level: a trigger refuses `UPDATE`,
`DELETE` and `TRUNCATE` with an error, so an application bug cannot rewrite
history.

## Retention

`nitctl audit prune` removes records older than a cutoff. It is the only way to
empty the table, and it goes to the database directly — there is no endpoint,
because nothing a request can reach may delete evidence.

```sh
nitctl audit prune -keep-days 365          # reports, deletes nothing
nitctl audit prune -keep-days 365 -yes     # deletes
```

Without `-yes` it counts and stops. There is no undo, and the audit trail is the
record that nit enforced anything.

```
cutoff:  2025-08-23T09:24:08Z
matched: 201 record(s) older than that
removed 201 record(s)
```

**The purge records itself.** Two rows survive it — `audit.purge_started` with
the cutoff and the count, and `audit.purge_completed` with what was removed —
naming whoever ran it. A purge interrupted halfway therefore leaves a `started`
with no `completed`, which is exactly what an auditor needs to see; the
alternative is a gap in the trail that nothing explains.

**The append-only protection is restored afterwards.** On PostgreSQL the guard
is lifted and restored inside each batch's transaction, so no other session ever
observes it off. On MySQL and MariaDB that is not possible — dropping a trigger
is DDL and commits immediately — so there is a window, and a purge killed inside
it leaves the table unprotected. The next `nitctl audit prune` reports that
loudly and closes it:

```
WARNING: the append-only protection was already absent when this started.
a previous purge did not finish, and audit_log has accepted deletions since.
```

:::tip[Choose the cutoff from your obligations, not from disk]
Growth is linear in activity and modest: a push writes one row plus one per
denied path in the submitted changeset, and a pull writes two regardless of how
many files were withheld. The reason to prune is a retention period you are
required to honour, not usually a volume problem.
:::

:::caution[Partitioning is an option, not the default]
`DROP PARTITION` removes rows without firing any trigger, on all three engines —
so partitioning `audit_log` turns "deleting audit records requires deliberately
lifting a guard" into "one `ALTER TABLE`". It makes a prune O(1), and it weakens
what it makes manageable. On MySQL and MariaDB it also costs `audit_log` its
four foreign keys, which those engines refuse on a partitioned table.

Take it knowingly, or not at all.
:::

## Rolling out a policy change

1. Pull request against the policy repository; CI runs
   `nitctl policy validate`.
2. Merge; your deployment updates the checkout on each host.
3. Every `policy.reload` (30 s by default), `nitd` rereads it.
4. `curl /healthz` reports the version in force.

A bundle that does not compile is **not applied**: the last good one stays in
force and the failure is logged loudly. During a rolling deploy, comparing
`/healthz` across replicas is how you spot two of them serving different bundles.

## Things that go wrong

| Symptom | Cause |
| --- | --- |
| `missing_patch` on every push | `nitd` and the worker have different `blob_dir`. It must be one shared volume. |
| Tasks stay `queued` | No worker running, or its `-queues` excludes that kind. |
| Tasks retry forever without failing | `lease_duration` is shorter than a clone takes. |
| `no sync token signing key` | `sync_key_file` names a path that is not there, or the key is under 32 bytes. |
| `not found` from `nitctl stats` | The account is not in `admin_groups`. |
| A developer gets `unknown_sync_point` | Their workspace has never pulled. `nit pull`. |
| A developer gets `stale_sync_point` | Their workspace is behind. `nit pull`. |
| A setting seems ignored | `nitctl config show` — the environment overrides the file. |

### A branch that will not move

```sh
nitctl tasks -repository backend-api -state running
```

If a task has been running far longer than a clone should take, its worker is
probably gone. The lease will lapse within `lease_duration` and the reaper will
return it to the queue. If it does not, check that a reaper is running — it lives
in `nitd`, and `reap_every` governs it.

### A push that keeps failing

```sh
nitctl tasks -state failed -json | head -40
```

`conflict` means the patch no longer applies onto upstream. That is permanent —
retrying would conflict identically — so the task fails immediately rather than
burning its attempt budget. The developer pulls, resolves, and pushes again.

## Backups

| What | Why |
| --- | --- |
| PostgreSQL | Sync points, the audit trail, the queue |
| The policy bundle repository | Your authorization rules, with their history |
| `storage.blob_dir` | Only in flight; patches are disposable once applied |
| `security.sync_key` | Losing it makes every workspace resynchronize once |

Losing the database loses sync points, which means every workspace resynchronizes
— survivable — and the audit trail, which is not. Back it up like the record it
is.

`storage.work_dir` is scratch. Never back it up.

## Next

- [The web console](/guides/console/) — the same data, in a browser.
- [nitctl](/reference/nitctl/) — every command.
