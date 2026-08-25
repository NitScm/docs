---
title: The audit vault
description: A record of your own authorization decisions, held somewhere you cannot edit it — and an honest account of what that does and does not prove.
sidebar:
  order: 2
---

Every time somebody pushes, nit decides. It decides per file, against the rules
in your policy bundle, and it writes down what it decided: who, what, when,
under which rule.

That record is already in your database. The vault is a second copy, held by us,
that **you cannot modify** — and neither can we.

## Why a second copy is worth anything

Your own copy answers your questions perfectly well. It stops being enough the
moment somebody else is asking.

An auditor does not want a report you generated. They want to know that the
record could not have been adjusted between the event and the report. A database
you administer cannot answer that, however careful you are, because the question
is not about your care.

## What we hold, and what we cannot do to it

Your deployment signs every batch of records before sending it, with a key it
generated. **We are given only the public half.**

That is not a detail, it is the whole design:

- We can check that a record came from your deployment.
- We **cannot produce** a record that passes that check.

If we used a shared secret, we would hold the key we verify with — and a
customer disputing a record would be told *"our copy is signed"* by the party
holding the key that signed it. That is not evidence of anything. An auditor
asks that question first.

So what you are buying is **retention, custody and non-repudiation**. Not
verification: we never see your code, and we cannot re-derive whether the policy
really refused that file. We record what your own deployment attested, and we
make it something neither side can quietly change afterwards.

## What crosses, and what never does

Your source never leaves your network. What we receive is a list of decisions:

```
occurred_at  2026-08-25T18:44:12Z
actor        bob
action       push.denied_path
repository   backend-api
branch       main
path         secrets/prod.env
effect       deny
rule_id      secrets-are-platform-only
```

A path list describes your repository, which is exactly what read rules exist to
hide. So how much of one crosses is **your choice**, set on each deployment:

| Setting | What we receive |
| --- | --- |
| `full` | Every path, as decided |
| `denials` | Paths only on a refusal |
| `hashed` | A keyed digest, comparable but not readable |

`denials` is the usual answer: those are the paths an auditor reads, and the
person who was refused already knows them. With `hashed`, the key stays on your
deployment — so we cannot reverse a path we store, not even by guessing common
filenames.

In the console, a decision whose path was withheld says so. It does not show an
empty column: a blank in an audit trail reads as data loss.

## What it does not prove

A signature proves that what we hold is what you sent. It says nothing about
what we do **not** hold — a service that quietly dropped a batch would still
verify perfectly on everything left.

So every batch also carries a number, and the check walks them:

```
Missing from the middle of a run:
  run_48d3b46de661… #2

Those batches were sent and are not held.
```

That catches anything lost between two batches you still have — including the
most recent, as soon as one more arrives.

**It does not catch** an entire sending run erased, or the last batch of a run
that never sent another. Your own database is the copy that would show those,
and `nitctl audit export` reads it. The console's Evidence screen says this in
as many words, because finding it out during an audit is worse than reading it
now.

## What happens when we are unreachable

Nothing, from your side. Your deployment keeps authorizing, developers keep
pushing, and refusals keep being refusals — the vault is never in the path of a
decision.

Records that could not be sent are in your database, where they always were, and
`nitctl audit export` sends them on afterwards.

Next: [checking the archive yourself](/enterprise/checking-it-yourself/), which
is the part that makes any of the above worth believing.
