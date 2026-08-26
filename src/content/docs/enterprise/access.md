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

## Signing in with your own directory

If your company already has one — Entra ID, Okta, Ping, Google Workspace, an
Active Directory — your people can sign in with it instead of holding another
password.

Tell us your issuer, the client id you registered for us, and which email
domains it answers for. From then on, everybody at those domains signs in
through your directory.

### What that changes for you

**One place to switch somebody off.** Disable an account in your directory and
they stop being able to sign in here, immediately. There is no local password
that keeps working, because a federated account has none — it is closed, not
merely empty. That is the point of buying single sign-on, and a quiet fallback
would defeat it.

**No secret of yours sits in our database.** We register as a *public client*
with PKCE, so there is no client secret to give us and nothing in our tables
that could be used against your directory. It is the same rule as your signing
key: we hold only the half that cannot be used to act as you.

**Nothing you send us grants anybody anything.** Your directory tells us who
somebody is. It does not tell us what they may do here.

### The part that surprises people, and why it is deliberate

Roles are not read from your groups.

Most services will happily map a group called `vault-owners` onto the owner role.
It is convenient, and it means a group renamed by an administrator who has never
heard of this product can silently hand somebody the power to change your
retention policy and lift a legal hold.

So the role stays here, granted by invitation, changed on the Access screen by
one of your owners. What you get in exchange is that we can tell you who granted
what and when — which is difficult to say about a permission that arrived from
somewhere else.

The thing you actually wanted from group mapping still works: switch somebody
off in your directory and they are out, whatever their role here says.

### What we will refuse

- **An address outside the domains you gave us.** Your directory speaks for your
  people, not for anybody else's.
- **An address your directory says is unverified.** That is how somebody claims
  a colleague's.
- **Somebody nobody invited.** They get no access rather than a default one.
- **Somebody who already has an account here that your directory does not fully
  cover** — an outside auditor, for instance, who reads two customers' trails.
  We will not hand one company's directory control of another company's access.
  That case is resolved on purpose rather than automatically.

## Group membership from your directory

The section above is about *signing in*. This one is a different thing that uses
the same directory: your deployment reading **who is in a team**, so that a rule
can say "the payments team owns `src/billing`" without anybody maintaining a
list of five hundred names.

You name the groups you want read, and only those. A directory serves your whole
company; a bundle refers to a handful, and reading the rest would be collecting
people's names for no reason.

In the bundle they arrive under a prefix of their own:

```yaml
- id: payments
  description: The payments team
  includes: [idp:payments]     # membership from your directory
  members: [break-glass]       # and one named here, deliberately
```

**A group in your directory cannot take over a group your rules name.** The
rules reference `payments`, the name in the reviewed file. `idp:` is a namespace
no file in the bundle may write into, and nothing else is matched by name. So
somebody creating a group called `payments` in your directory grants themselves
nothing — which matters, because the people who administer your directory are
usually not the people who review your policy.

**Removing somebody works, which is the thing you are buying.** Take them out of
the group and they lose the access within the refresh interval, with no pull
request involved. Somebody disabled in your directory is dropped whether or not
anyone remembered to remove them from the group.

**A group that disappears becomes empty, not an outage.** If your directory
renames a group, or is unreachable when your deployment restarts, the include
resolves to nobody: whoever is named directly still has their access, everybody
else loses theirs, and it is logged. The alternative — refusing to serve — trades
a narrowing for an outage.

**It is one credential, and it is read-only.** Unlike signing in, this is a
background job with nobody present to authorise it, so it authenticates with a
service account. That account can read who is in a group. It cannot create a
person or change one.

**Your CI does not need any of this.** A bundle that names `idp:` groups
compiles without a directory — those groups are simply empty. `nitctl policy
validate`, `test` and `diff` run on a laptop and in a pull request with no
directory credential, and what they validate is the floor of what the bundle
permits, never the ceiling.

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
