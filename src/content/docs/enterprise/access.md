---
title: People and access
description: Who can read your trail, what each role may do, and the difference between a person and a credential a machine holds.
sidebar:
  order: 5
---

Two kinds of thing can read your audit trail, and they are deliberately not
interchangeable.

## People

Somebody signs in with an email and a password, and carries a role.

There are three, and each exists because something would otherwise be
ungrantable:

| Role | Can |
| --- | --- |
| **auditor** | Read the trail, the evidence and the retention record |
| **admin** | That, plus register and revoke deployments and read tokens |
| **owner** | That, plus manage people and place a legal hold |

An auditor is the person an engagement is opened for. They must be able to read
everything and change nothing — including the retention policy of the thing they
are auditing.

There is no fourth role, because a fourth would need a job nobody has yet, and a
role nobody can explain is a role people assign by guessing.

### Joining

**There is no sign-up.** An account holds one customer's audit trail, and the
only people in it are people already in it said belong.

An owner invites somebody by email. The invitation is a link, shown once — we
keep only its digest, so nobody can read it back afterwards, including us. You
deliver it; we do not send email on your behalf.

Accepting it asks for a name and a password of at least twelve characters.
Length and nothing else: a rule demanding a digit and a symbol pushes people
towards `Password1!` and is worth less than four more characters.

### One person, several customers

An auditor at an accounting firm reads the trails of several clients. That is one
person with one password, and signing in asks which trail:

> **Which trail?**
> You have access to more than one. Reading the wrong customer's trail is not a
> mistake this will make for you.

Ending one engagement removes that one membership and touches nothing else.

### Removing somebody

Their access ends at once, not when their session happens to expire. A person
removed while still signed in would otherwise keep reading, which is the whole
thing removing them was meant to prevent.

The last owner cannot leave or be demoted. An account with no owner has nobody
who can invite one, and the only way back would be us reaching into the
database — a position you should never be put in.

## Read tokens

For a script, a SIEM forwarder, an export job.

A read token **can read your trail and can never write one**. That is worth
saying precisely, because the other side is unusual: the endpoint that receives
records has no credential at all. A batch is believed because it verifies against
a key we cannot use, so there is nothing to steal that would let anybody write
into your history.

A token is shown once and stored only as a digest. Give it an expiry when it is
for a fixed engagement; it stops working on its own, which is what makes handing
one to an outside auditor comfortable.

The Access screen shows when each was last used — the question to answer before
revoking one.

## Two things we cannot do

- **We cannot read your passwords.** They are stored with argon2id, salted; the
  table gives a support engineer nothing they could sign in with.
- **We cannot write a record in your name.** Your deployment holds the only key
  that can. See [checking it yourself](/enterprise/checking-it-yourself/).
