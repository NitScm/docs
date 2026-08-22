---
title: Filtered projections
description: The one idea that explains everything else about how nit behaves — and why your local commit hashes mean nothing to the server.
sidebar:
  order: 1
---

If you read one concept page, read this one. Almost every surprising thing about
nit follows from it.

## Your clone is not the repository

When files are filtered out of a developer's checkout, their working tree differs
from upstream. Different tree, different tree hash — and therefore **different
commit hashes**.

```
  upstream commit 5e0deb3           bob's local commit a1b2c3d
  ───────────────────────           ───────────────────────────
  src/server/api.go                 src/server/api.go
  src/ui/app.ts                     src/ui/app.ts
  docs/readme.md                    docs/readme.md
  secrets/prod.env
```

Bob's commit `a1b2c3d` **exists nowhere on the forge**. It never will. It
describes a tree that only ever existed on his machine.

So a protocol that says *"send me your last commit and I will diff from it"* is
broken by construction. The server has never heard of that hash and never can.

## The sync point

nit records, for each workspace, the **upstream commit whose filtered projection
produced its current state**, and hands the client an opaque token for it.

```
  bob's workspace  ──── sync token ────▶  upstream commit 5e0deb3
```

Everything is expressed relative to that token:

- **pull** = the filtered diff between the sync point and upstream's tip
- **push** = apply the patch on top of the sync point, then rebase onto the tip

Never relative to a local hash.

### The token is opaque, and signed

Store it, send it back, never parse it. Only the server interprets it.

It is signed with HMAC, and that is not decoration. The token is your claim about
which base your patch was computed against, and the server applies your patch on
top of whatever it names. Unsigned, a client could claim any base it liked —
including one whose projection it was never entitled to see.

Three checks run on every push, each closing a different hole:

1. **the signature** proves the server minted the token;
2. **the coordinates** prove it was minted for *this* workspace, repository and
   branch — so a token issued elsewhere cannot be replayed here;
3. **the comparison** against the stored sync point proves it is still current.

### It is recoverable from git alone

The synchronization commit nit creates in your checkout carries the same
information as trailers:

```
nit: sync backend-api@main

Nit-Upstream-Commit: 5e0deb3c78c35440c00a4978483da66fd5219f7f
Nit-Policy-Version: sha256:f6040b6d6a8381dc
Nit-Workspace: f9e428ab-3a8d-42c8-a2d7-6ef5a0ac61bc
```

So a deleted or corrupted `.nit/state.json` is not the end of the world:

```sh
git log --grep='^Nit-Upstream-Commit:'
```

The server remains the authority. The trailers are evidence, not truth.

## Why a workspace, and not just a machine

A sync point is keyed by **workspace**, not by user. A workspace is one checkout
on one machine.

That is why `nit clone` registers one, and why it is explicit rather than implied
by your first push: a typo in an id would otherwise silently start a second,
empty projection instead of failing.

A developer with a laptop and a desktop gets two workspaces with independent sync
points — which is exactly right, because the two machines genuinely are at
different points.

## Consequences you will meet

### "Your change landed, but the branch has moved on"

After a push, nit issues a new sync token **only if** nothing was rebased onto
and nothing was stripped.

The sync point means "the upstream commit whose projection is what this workspace
holds". That survives a push that landed alone and whole: your workspace is the
old projection plus your own changes, which is exactly the new projection.

It stops being true the moment something else is in the new commit. If a
colleague's commit landed while yours was queued and yours was rebased onto it,
upstream now contains work your workspace has never seen. Claiming otherwise
would make every later diff compute against a base you do not have.

So nit says so, and you pull. It is a normal outcome, not an error.

### `stale_sync_point`

You are pushing from a base your workspace has moved off. Pull first.

### A pull derives its base from *your* token

Not from the server's stored record — and the difference matters.

The two diverge whenever a pull is delivered and the client fails to apply it: a
crash, a full disk, an interrupted command. If the server diffed from its own
record it would hand you a patch assuming changes you never received; if it
refused the request as stale you would have **no way to catch up at all**,
because every later pull would be refused for the same reason.

Deriving the diff from where you say you are makes that case self-correcting. The
signature is what makes trusting your claim safe.

### `nit pull` rebases

Your history is a synchronization commit followed by whatever you have committed
since. A pull applies the incoming patch to the **sync commit**, then replays your
commits on top — `git pull --rebase`, and for the same reasons.

It also fixes a case that would otherwise be unresolvable, and it is the common
one: after a push the server rebased, your own change is already upstream. It
comes back in the next pull, and applying it on top of the local commit that
already contains it would conflict — with itself. Replayed instead, git
recognizes it as already applied and drops it, exactly as it does after your pull
request is merged.

## Prior art

This model — filtered views of a repository with a mapping back to real
history — is not unique to nit. [Josh](https://github.com/josh-project/josh)
solves a related problem with bidirectional commit mapping, in production. If you
are evaluating approaches, it is worth reading.

## Next

- [Push and pull](/concepts/push-and-pull/) — what actually happens, step by
  step.
- [The authorization model](/concepts/authorization/) — how the decisions are
  made.
