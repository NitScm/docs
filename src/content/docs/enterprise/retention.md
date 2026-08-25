---
title: Retention and legal hold
description: How long records are kept, what was deleted and under which rule, and how to stop deletion the day your counsel asks.
sidebar:
  order: 4
---

Your account has a retention period. Records older than it are deleted, and the
deletion is recorded.

## What "older than" means

A batch is kept for your retention period **after we received it**, not after
the decision was made.

Ours is the only clock we can vouch for. A deployment whose clock is wrong would
otherwise keep records past what was agreed, or lose them early — and neither is
something you would find out about.

It also means that if you fill an old gap — sending records from months ago with
`nitctl audit export` — they get the full period from the day they arrive, not
from the day they happened. The error is in the direction of keeping.

## Whole batches, never half of one

Deletion removes a whole signed batch at a time.

A batch is one signature over one body. Removing the records inside it that have
aged out, and keeping the rest, would leave a body whose signature no longer
matches what is stored — evidence turned into something that fails its own
check. So a batch ages as a unit.

In practice this means the boundary moves in steps of a few records rather than
one at a time. Nothing is kept longer than a batch's worth past the period.

## What was deleted, and why

This is the part that matters, and it is on the **Retention** screen:

| Ran (UTC) | Everything before | Policy | Batches | Records |
| --- | --- | --- | --- | --- |
| 2026-08-25 16:40 | 2026-05-27 | 90 days | 4 | 8 |

Without it, *"March is missing"* and *"March was deleted on the first of July
under your ninety-day policy"* are the same observation from your side. One is a
service working. The other is data loss — and it is you who would have to explain
the gap to your auditor.

A sweep that removed nothing writes nothing, so the entries you can see are the
ones that answer a question.

## Changing the period

Lengthening it is a support request and takes effect immediately.

Shortening it is destructive, and the mistake is a typo — `30` where `3650` was
meant deletes ten years of evidence within the hour. So the change is counted
first and refused until confirmed:

```
$ nit-vault account retention -id acct_… -days 90
nit-vault: 4 batch(es) holding 8 record(s) are older than 90 days and would be
deleted by the next sweep; re-run with -yes if that is what you mean

the current policy is 3650 days
```

You are told the number before anybody touches anything.

## Legal hold

**Nothing is deleted while a hold is in place, whatever the policy says.**

You place it yourself, from the Retention screen, and it takes effect
immediately. It is self-service on purpose: a hold is needed the day your counsel
says so, and a customer who has to open a support ticket to stop deletion is a
customer whose evidence goes while they wait.

While it stands, the console shows it on the Retention screen and in the sidebar
on every page — so nobody has to remember whether somebody placed one.

A retention policy running normally during litigation destroys evidence somebody
was legally required to keep, and *"our system deleted it on schedule"* is not a
defence anybody has ever accepted.

Only an account owner can place or release one. See
[People and access](/enterprise/access/).

## Suspension does not delete anything

If an account is suspended — a lapsed invoice, an ended contract — we stop
accepting new records and **keep every one already held**. You can still sign in
and read them.

Your obligation to produce your audit trail outlives your relationship with us.
Deleting evidence over a billing state would make this a worse place to keep
records than your own database, which is the opposite of the point.
