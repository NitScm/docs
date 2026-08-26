---
title: Policy for a large organisation
description: How five hundred engineers write and review the rules without one person becoming the bottleneck.
sidebar:
  order: 2
---

Writing a bundle for a team of eight is a paragraph of YAML. Writing one for five
hundred engineers is a different problem — not because the language changes, but
because nobody knows every rule any more, and the thing that keeps a policy
correct stops being memory and starts being process.

This is the order to do it in.

## 1. Start with groups, not rules

Almost no rule should name a person. Write `groups.yaml` first, and let `includes`
do the work:

```yaml
- id: everyone
  members: [alice, bob, ...]

- id: interns-backend
  members: [dev, erin]

- id: backend
  members: [alice, frank]
  includes: [interns-backend]      # every intern is also backend

- id: platform
- id: security
- id: contractors
```

Five hundred engineers become perhaps thirty groups. Membership is resolved
transitively once, when the bundle compiles.

The point is what this buys later: **somebody joining or leaving touches no
rule.** If your rules name people, every arrival is a change to authorization
logic, reviewed by whoever happens to be free.

## 2. One file per repository

The layout already does this for you:

```
users.yaml
groups.yaml
repositories.yaml
repositories/payments/rules.yaml
repositories/platform/rules.yaml
repositories/mobile/rules.yaml
```

Fifty repositories, fifty files. The payments team edits theirs; nobody waits
behind anybody.

**Pair it with `CODEOWNERS` on your forge.** It costs nothing and it is what stops
one file becoming a review bottleneck:

```
/repositories/payments/    @payments-team @security
/repositories/platform/    @platform-team @security
/groups.yaml               @security
/users.yaml                @it-ops
```

## 3. Write the denials first

Rule order carries no meaning — every matching rule is considered and deny always
wins — so write in the order that *reads*:

```yaml
- id: no-secrets-outside-security
  subject: {type: any}
  paths: ["config/secrets/**", "**/*.pem"]
  actions: [read]
  effect: deny
  except:
    - {type: group, id: security}
  description: Production credentials. Ask #security if you need one.

- id: backend-owns-payments
  subject: {type: group, id: backend}
  paths: ["payments/**"]
  actions: [read, write, create, delete]
  effect: allow
```

Two things in there matter more than they look.

**`except` is the reason this scales.** Without it, "nobody except security" has
to be written by enumerating every other group — and that rule then silently
grants access to every group created afterwards. A policy language that fails
*open* as the organisation grows is worse than one that fails closed loudly.

**`description` is not decoration.** It is shown to the person who was refused. A
denial somebody cannot understand becomes a support ticket, and at five hundred
people it becomes a queue.

## 4. Let the loader catch what a reviewer cannot

The bundle is rejected at load time for cyclic groups, references to things that
do not exist, duplicate ids, invalid patterns, an `except` of type `any`, and an
allow granting `write` without `read`.

That last one is worth knowing about: writing a file you cannot see means
overwriting content blind.

Run it on every change:

```bash
nitctl policy validate policy/
```

## 5. Review the effect, not the text

This is the step that matters most, and the one most teams skip.

A diff of the YAML tells a reviewer that four lines changed. It does not tell them
that one of those lines put twelve people into a group that reads `config/**` —
because the group is defined in another file and the rule granting it was not
touched.

```bash
nitctl policy diff origin/main:policy/ policy/ -exit-code
```

```
carol
  now allowed   read  payments  config/**   r-config   via backend
  DENY REMOVED  read  payments  secrets/**  r-secrets  via any

2 people can reach more than before.
```

Put that in a pull request comment. Nobody approves a widening without having read
who, and to what.

Note `DENY REMOVED`. Deny wins, so a deleted deny is *more* access — and deleting
lines never looks alarming in a text diff. That is why the report has four
directions rather than two.

## 6. Write down what must never change

`diff` shows what a change does. It does not stop a rule being deleted: the bundle
still compiles, every other rule still works, and nothing looks wrong until
somebody reads something they should not have.

Keep a file of expectations **beside** the bundle:

```yaml
- name: nobody outside security reads production secrets
  repository: payments
  path: config/secrets/prod.pem
  actions: [read]
  expect: deny
  rule: no-secrets-outside-security
  groups: [contractors, backend]
```

```bash
nitctl policy test policy/ policy-expectations.yaml
```

**Name the rule.** Everything is denied by default, so `expect: deny` on its own
holds whether the rule exists or not — a file of denial assertions stays green
after somebody deletes every deny in the bundle. `nitctl policy test` says so when
it happens, but naming the rule is what turns the warning into a failure.

Write expectations over **groups**, not people: the assertion is then about the
rule, and stays true as people join and leave. Membership changes are `diff`'s
job, and a test that broke on every hire would be deleted by the second month.

## 7. Answer one person's question in one command

```bash
nitctl policy explain policy/ \
  -repo payments -user carol -path config/secrets/prod.yaml
```

Paste the output into the ticket. It names the rule and its description, which is
usually the whole answer.

## 8. Stop maintaining `users.yaml` by hand

Five hundred people in one file is a merge-conflict hotspot and a queue at the
door of whoever owns it.

The [enterprise edition](/enterprise/access/) takes group membership from the
directory your company already runs — Okta, Entra, Active Directory — while the
**rules stay in git**. That split is deliberate: a directory has no review, no
history and no rollback, and an authorization rule that changes without all three
is the thing nit exists to replace.

In the bundle it is one line, and the group id carries an `idp:` prefix:

```yaml
- id: payments
  description: The payments team
  includes: [idp:payments]     # membership from the directory
  members: [break-glass]       # and one named here, deliberately
```

Two things about that prefix are worth knowing before you write it.

**The directory cannot reach a group your rules name.** `idp:` is a namespace no
file in the bundle may write into, and the rules reference `payments` — the name
in the reviewed file. Somebody creating a group called `payments` in the
directory grants themselves nothing. Whoever administers your directory is
usually not the set of people who review this bundle, and this is what keeps
those two jobs apart.

**A bundle that names a directory does not require one.** With nothing to supply
it, `idp:payments` compiles to an empty group. That is what lets the three CI
commands below run without a directory credential — which they should not have.
An empty group grants nobody anything, so what CI validates is the floor of what
the bundle permits, never the ceiling.

## What this looks like in CI

```bash
nitctl policy validate policy/
nitctl policy test policy/ policy-expectations.yaml
nitctl policy diff origin/main:policy/ policy/ -exit-code -json > diff.json
# post diff.json on the pull request
```

Three commands. The first says the bundle is well-formed, the second says it still
does what somebody wrote down, and the third puts the consequences in front of a
human before they approve them.
