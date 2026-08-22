---
title: What nit does
description: The problem nit solves, the shape of the solution, and — just as importantly — what nit does not do.
sidebar:
  order: 1
---

nit is an authorization layer between your developers and your git forge.

It decides, **file by file**, what each person may read and write in a
repository, and it is the only thing that writes to the upstream. Developers
push and pull through nit; files they may not read never reach their machine,
and changes they may not make never reach the forge.

## The problem

Every git forge grants access per repository. GitHub, GitLab, Gitea, Bitbucket —
all of them. You can say "this person may write to this repository". None of them
can say "this person may not read `secrets/`".

That leaves two bad options.

**Split the repository** until its boundaries match your permission boundaries.
Now you have submodules, version skew between them, and changes that span three
repositories and cannot be reviewed in one place. The permissions are right and
the codebase is worse.

**Keep one repository** and accept that everyone who can clone it can read
everything in it — including the contractor you onboarded this morning, the
intern, and every CI job that ever ran.

Most teams pick the second and hope. It is why production credentials end up in
git history, and why "just delete the repository and start over" is a sentence
security teams have to say.

## The shape of the solution

A developer's checkout is a **filtered projection** of the real repository: the
files they may read, and nothing else. Not encrypted, not greyed out in a UI —
simply not on their disk.

```
  the forge                       bob's machine
  ─────────                       ─────────────
  src/server/api.go     ────▶     src/server/api.go
  src/ui/app.ts         ────▶     src/ui/app.ts
  docs/readme.md        ────▶     docs/readme.md
  secrets/prod.env        ✕
  infra/production/       ✕
  .github/workflows/      ✕
```

Bob works normally: he edits, commits, branches. When he pushes, nit checks the
patch against the rules before anything reaches the forge. When he pulls, nit
sends him only what he may see.

The forge itself is untouched. It stores an ordinary git repository, and nit is
the only account with write access to it.

## Two behaviours worth knowing up front

### A refused push is refused whole

If a patch touches any path its author may not write, **the entire push is
refused** — not stripped of the offending file.

Silently dropping the file would be worse than refusing. The author would
believe their change landed; upstream would receive a partial commit that may
not even build; and the next pull would restore the upstream version of the
dropped file, quietly reverting their work.

The refusal names every offending path, the rule that refused it, and that
rule's message to the developer — so the fix takes one round trip, not five.

### A pull is filtered, never refused

There is no meaningful way to "refuse" a pull. The developer receives what they
may read, and the report tells them **how many** files were withheld — without
naming them, because naming them would leak the very structure the read rules
exist to hide.

The count is reported at all because a developer who does not know something was
withheld will mistake a missing file for a deleted one.

## What nit does not do

Being clear about this early saves disappointment later.

**nit does not secure a repository other people can push to.** Its guarantees
end the moment a developer can write to the same branch directly. nit's machine
account must be the only writer; everyone else gets read access at most, and the
branches nit manages are protected. See
[Going to production](/guides/production/).

**nit does not hide a public repository.** It hides files *inside* a repository
from people who have access to it. A public repository is readable by everyone,
whatever nit says.

**nit is not a secret manager.** Keeping credentials out of git is still the
right answer; nit helps with the ones that are legitimately in there —
infrastructure definitions, customer data fixtures, unreleased work — and with
the ones you have not migrated yet.

**nit does not review code.** It enforces who may change what. Whether the
change is *good* is still your review process's job.

**nit does not hide history from someone who could once read it.** Removing a
path from someone's grants stops them receiving future changes to it. It does not
remove what is already in their local clone.

## Is nit for you?

It probably is if:

- one repository contains material with genuinely different audiences —
  production infrastructure, security-sensitive code, customer data, unreleased
  features;
- you have contractors, interns, or partner teams who need to work in the
  repository without seeing all of it;
- you have split repositories for permission reasons and regret it;
- you need to answer "who could have seen this file, and when?" with something
  better than a shrug.

It probably is not if:

- your repository has one audience, and everyone in it should see everything;
- your confidential material is already in a separate system, where it belongs;
- you cannot make nit the only writer of the repository.

## Next

- [Install](/start/install/) — a complete environment with a forge, in one
  command.
- [Filtered projections](/concepts/filtered-projections/) — the one idea that
  explains everything else about how nit behaves.
