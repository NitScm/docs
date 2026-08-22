---
title: The authorization model
description: Rules, subjects, actions, patterns and effects — and the three properties that make a policy reviewable.
sidebar:
  order: 2
---

Every decision nit makes answers one question:

> May this **subject** perform this **action** on this **path** of this
> **repository**, at this **ref**?

## How a decision is reached

1. An unknown repository is denied.
2. A disabled account is denied.
3. **Every** rule of the repository is considered — there is no first-match.
4. If any matching rule denies → **deny**.
5. Otherwise, if any matching rule allows → **allow**.
6. Otherwise → **deny**.

Three properties follow, and each of them exists for a reason.

### Order-independent

Rules can be reordered, split across files or regrouped without changing
behaviour. A policy whose meaning depends on line order cannot be reviewed: a
reviewer would have to hold the whole file in their head to know what a diff
does.

### Deny always wins

An allow rule can never override a deny. That makes "these paths are off limits"
a statement you can make once and rely on, rather than something a later rule
might quietly undo.

It also means an exemption cannot be an allow rule — see
[`except`](#exemptions-except) below.

### Closed by default

Anything no rule allows is refused. A path nobody thought about is not readable,
and adding a file to a repository does not silently expose it.

## Subjects

```yaml
subject: { type: user, id: alice }
subject: { type: group, id: backend }
subject: { type: any }
```

`any` matches every authenticated caller. It is how you state repository-wide
baselines — "everyone reads `docs/`", "nobody touches `.github/`" — without
enumerating groups, which would fail open every time someone adds one.

### Exemptions: `except`

```yaml
- id: secrets-are-platform-only
  subject: { type: any }
  except:
    - { type: group, id: platform }
  paths: [secrets/]
  actions: [read, write, create, delete, admin]
  effect: deny
```

Because deny always wins, "nobody may read `secrets/`, except the platform team"
**cannot** be written as a universal deny plus a team allow — the deny would
swallow the allow.

The alternative, enumerating every non-exempt group in the deny rule, fails open
the day someone creates a new group. `except` is the safe form, and it is the
only one that stays correct as the organization grows.

An `except` entry of type `any` is rejected: it would disable the rule silently.

## Actions

| Action | Covers |
| --- | --- |
| `read` | Seeing the file at all — a denied read means it is **absent** from the workspace |
| `write` | Modifying an existing file |
| `create` | Adding a new file, or being the destination of a rename or copy |
| `delete` | Removing a file, or being the source of a rename |
| `admin` | Structural changes — see [Guards](/concepts/guards/) |

`read` and `write` alone would not be enough. Deleting a file is not writing it,
and a reviewer granting write access to a config directory rarely means "and you
may delete everything in it".

### How a change maps to actions

| What the patch does | Requires |
| --- | --- |
| add | `create` on the new path |
| modify | `read` + `write` on the path |
| delete | `read` + `delete` on the path |
| rename | `read` + `delete` on the source, `create` on the destination |
| copy | `read` on the source, `create` on the destination |

**A rename must hold on both sides.** Otherwise renaming becomes a way to move a
file out of a protected subtree.

### Write implies read

An **allow** rule granting `write`, `create` or `delete` must also grant `read`.
The bundle is rejected if it does not.

Writing a file you cannot see means overwriting content blind, and you cannot
produce a diff against a file that is absent from your workspace.

A **deny** rule may of course name `write` alone — that is exactly how
"read-only for this team" is expressed.

## Path patterns

| Form | Matches |
| --- | --- |
| `secrets/` | **Subtree**: the directory entry itself and everything under it |
| `**/*.env` | A glob, for files scattered across the tree |
| `src/*.go` | `*` does not cross `/` |
| `src/**/*.go` | `**` crosses `/` |
| `{docs,site}/**` | Alternation |
| `**` | Everything |

A trailing slash is the **explicit** marker for a subtree. Nothing is inferred
from the presence of a dot in the last segment — a rule that changes meaning
because a directory was named `v1.0` is an incident waiting to happen.

Subtree patterns match the directory entry itself as well as its contents, so
`secrets/` also covers a symlink or a submodule placed at exactly `secrets`.

Patterns are repository-relative: no leading `/`, no `.` or `..` segments, no
backslashes.

## Refs

```yaml
- id: no-direct-push-to-main
  subject: { type: any }
  except: [{ type: group, id: platform }]
  paths: ["**"]
  refs: [refs/heads/main]
  actions: [write, create, delete]
  effect: deny
```

`refs` restricts a rule to matching refs; empty means every ref. It is how branch
protection is expressed.

Note that `read` is left out above: the branch is protected against writes, not
hidden.

## What is validated, and when

A bundle is compiled and fully checked **at load time**, not at request time. A
malformed rule cannot fail open when someone is waiting for an answer.

Rejected at load:

- an **allow** rule granting write without read;
- a group inclusion cycle;
- a reference to a user, group or repository that does not exist;
- duplicate ids;
- an invalid or non-relative pattern;
- an `except` entry of type `any`.

Because everything is checked up front, evaluation itself cannot fail — it
returns a decision, never an error.

## Every decision is attributable

A decision carries the rule that produced it, the pattern that matched, that
rule's `description`, and the **version of the bundle** it came from.

That is what makes the audit trail worth having. "Why did this push pass on
March 12?" is answerable: find the record, read the rule id and the policy
version, check out that version of the policy repository.

It is also what makes a denial actionable. Compare:

```
403 Forbidden
```

with:

```
secrets/prod.env (create)
    refused by rule secrets-are-platform-only
    Production secrets are owned by the platform team.
    Open a request in #platform to have a change applied.
```

The second is why rules carry a `description`, and why you should write them.

## Next

- [Guards](/concepts/guards/) — the holes path rules cannot see.
- [Writing a policy bundle](/guides/policy-bundles/) — patterns for real teams.
