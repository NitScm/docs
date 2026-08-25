---
title: What the enterprise edition is for
description: What the commercial edition adds, who needs it, and — said plainly — who does not.
sidebar:
  order: 1
---

nit is free and open source, and it is complete. Per-file read and write control
inside a repository, a policy bundle reviewed like code, a control plane and
workers you run yourself. Nothing in this section is needed to use any of that.

This page is about what a company buys on top, and it starts with the case for
not buying.

## If you are one person, or five, you do not need this

You edit your policy bundle by hand. You have a disk. Nobody asks you to prove
anything to anyone. The free edition does the whole job, and paying for the
commercial one would buy you nothing you can point at.

We would rather say that here than have you find out after an invoice.

## Three reasons a company buys, and one of them is the real one

### You already have a directory

You have Okta, or Entra, or Active Directory. That is where the truth about who
works for you lives.

In the free edition somebody copies team membership into a YAML file by hand.
The day an employee leaves, they stay in that file until a person remembers to
remove them. That is not a convenience we are selling you — it is a hole we are
closing.

### You are large

A hundred workers. Object storage instead of a shared disk. One projection cache
across the whole fleet instead of one per process. None of this is a feature you
demonstrate to anybody; it is the difference between a deployment that holds and
one that does not.

[Running it at scale](/enterprise/at-scale/) covers what changes.

### You have to prove something to somebody else

An auditor, a client, a regulator. They ask: *show me who could touch this file,
and why that change was refused.*

You have the answer — it is in your own database. But it is **your** database,
the one you can modify. A record you can edit proves nothing to a third party.

This is the reason that matters, and it is the only one you cannot solve
yourself. Everything else on this page you could build. A record of your own
decisions that you are unable to alter, you cannot — by definition.

That is [the audit vault](/enterprise/audit-vault/), and it is what the
commercial edition is really for.

## Where the line falls

**Open: the decision. Closed: the administration of what feeds it.**

The rule that says *only the platform team touches production secrets* is
public, readable, and verifiable by anyone. Your policy bundle stays in your git
repository, reviewed like code, and nothing here changes that.

What is paid is connecting that rule to your company directory, and keeping the
record of its decisions somewhere you cannot reach.

## What is in this section

| Page | What it covers |
| --- | --- |
| [The audit vault](/enterprise/audit-vault/) | What it holds, what it proves, and what it does not |
| [Checking it yourself](/enterprise/checking-it-yourself/) | Verifying the archive with a key we do not have |
| [Retention and legal hold](/enterprise/retention/) | How long records are kept, and stopping deletion |
| [People and access](/enterprise/access/) | Roles, invitations, and credentials for machines |
| [Running it at scale](/enterprise/at-scale/) | Object storage, shared caches, your directory |
| [Trying the whole thing](/enterprise/try-it/) | The full stack on one machine, in one command |
