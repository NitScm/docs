---
title: Writing a policy bundle
description: Layout, patterns that work for real teams, validation in CI, and the mistakes worth avoiding.
sidebar:
  order: 1
---

The bundle is where all authorization lives. This guide is about writing one that
still makes sense in a year.

If you have not written one at all yet, start with
[Your first policy](/start/first-policy/).

## Layout

```
policy/
├── users.yaml
├── groups.yaml
├── repositories.yaml
└── repositories/
    ├── backend-api/
    │   └── rules.yaml
    └── data-platform/
        └── rules.yaml
```

One `rules.yaml` per repository. Decoding is **strict**: an unknown field is an
error, not a shrug. A typo that silently disables a rule is the worst failure a
security policy can have.

## Keep it in its own repository

The bundle should be a git repository of its own, deployed to your nit hosts as a
checkout your deployment updates.

That gives you the whole point of files over rows: pull requests, reviewers,
history, blame, and `git revert` when a change turns out wrong.

```yaml title=".github/workflows/policy.yml"
name: policy
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: curl -fsSL https://example.com/nitctl -o /usr/local/bin/nitctl && chmod +x /usr/local/bin/nitctl
      - run: nitctl policy validate ./policy
```

A bundle that does not compile must never reach production. `nitd` refuses to
start on one and a running server keeps the last good bundle rather than
reloading a broken one — but catching it in review is better than either.

## Patterns that work

### Start from a deny, not from allows

Write the confidential areas first, then open up what people need. The reverse —
allowing broadly and then trying to claw back — leaves gaps you will not notice.

```yaml
# First: what nobody outside the platform team may see.
- id: production-is-platform-only
  subject: { type: any }
  except: [{ type: group, id: platform }]
  paths: [secrets/, infra/production/, ops/runbooks/]
  actions: [read, write, create, delete, admin]
  effect: deny
  description: Production material is owned by the platform team (#platform).

# Then: what everyone needs.
- id: everyone-reads-the-code
  subject: { type: any }
  paths: [src/, docs/, README.md]
  actions: [read]
  effect: allow
```

Because deny wins, the order in the file does not matter — but writing it this
way makes the review read correctly.

### Ownership by subtree

```yaml
- id: backend-owns-server
  subject: { type: group, id: backend }
  paths: [src/server/, src/shared/, migrations/]
  actions: [read, write, create, delete]
  effect: allow
  description: Backend engineers own the server, shared code and migrations.
```

Subtrees are the shape most teams actually have, and they survive refactoring
better than file lists.

### Contractors and partners

The case nit exists for. Give them exactly one subtree and nothing else:

```yaml
- id: contractors-see-only-their-module
  subject: { type: group, id: contractors }
  paths: [src/integrations/acme/]
  actions: [read, write, create, delete]
  effect: allow
```

They get no baseline read, because they are not in `any`… except they are. `any`
means *every authenticated subject*, contractors included. So if you have an
`everyone-reads-the-code` rule, exclude them from it:

```yaml
- id: everyone-reads-the-code
  subject: { type: any }
  except: [{ type: group, id: contractors }]
  paths: [src/, docs/]
  actions: [read]
  effect: allow
```

:::caution[This is the mistake to watch for]
`any` really does mean everyone. A baseline read rule written for "the team"
silently includes every account you add later, including the ones you added
precisely because they should see less.
:::

### Branch protection

```yaml
- id: no-direct-push-to-main
  subject: { type: any }
  except: [{ type: group, id: platform }]
  paths: ["**"]
  refs: [refs/heads/main]
  actions: [write, create, delete]
  effect: deny
  description: main is updated through pull requests only.

- id: interns-stay-off-release-branches
  subject: { type: group, id: interns }
  paths: ["**"]
  refs: [refs/heads/release/**]
  actions: [write, create, delete]
  effect: deny
```

Note `read` is absent from both: the branches are protected against writes, not
hidden.

### Credentials, wherever they are

```yaml
- id: no-credentials-anywhere
  subject: { type: any }
  paths: ["**/*.env", "**/*.pem", "**/id_rsa*", "**/*.p12"]
  actions: [read, write, create, delete, admin]
  effect: deny
  description: Credentials must not live in the repository.
```

No `except` on this one. If the platform team needs a credential in git, that is
a conversation, not an exemption.

### CI ownership

Guards already require `admin` on CI paths. This is the rule that grants it:

```yaml
- id: platform-owns-ci
  subject: { type: group, id: platform }
  paths: [.github/, .gitattributes, .gitmodules]
  actions: [read, write, create, delete, admin]
  effect: allow
```

Without a rule like this, **nobody** can change CI — which may well be what you
want for a while.

## Groups

```yaml
- id: interns
  members: [carol, dave]

- id: backend
  members: [bob]
  includes: [interns]     # every intern is also a backend member
```

`includes` absorbs another group. Use it for "everything X can do, plus more",
not for arbitrary nesting — inclusion cycles are rejected, and deep hierarchies
get hard to reason about faster than they look.

## Checking what you wrote

`validate` says it compiles. `explain` says what it *means*:

```sh
nitctl policy explain ./policy \
  -repo backend-api -user carol -path src/server/api.go -ref refs/heads/release/1.2
```

```
carol on src/server/api.go (backend-api)
groups: backend, interns

  ALLOW read    allowed by rule backend-owns-server (allowed_by_rule: src/server/)
  DENY  write   denied by rule interns-stay-off-release-branches (denied_by_rule: **)
          Interns do not push to release branches.
  DENY  create  denied by rule interns-stay-off-release-branches (denied_by_rule: **)
  DENY  delete  denied by rule interns-stay-off-release-branches (denied_by_rule: **)
  DENY  admin   denied (no_matching_rule)
```

Run `explain` for the cases you care about **before** merging a bundle change,
especially the ones you are sure about. `nitctl policy show` prints the whole
compiled bundle if you would rather read it all.

## Mistakes worth avoiding

**Granting write without read.** The bundle is rejected — writing a file you
cannot see means overwriting content blind. Deny rules may name write alone; that
is how "read-only" is expressed.

**Expecting an allow to override a deny.** It never does. Use `except`.

**Forgetting that a rename touches two paths.** Moving a file out of a protected
subtree needs `delete` on the source *and* `create` on the destination. That is
deliberate; it is a way out otherwise.

**Assuming a removed grant removes existing copies.** Taking a path away stops
someone receiving future changes to it. What is already in their clone stays
there.

**Writing rules with no `description`.** The description is what the developer
sees when the rule refuses them. Without one they get a rule id and a shrug, and
you get a support ticket.

## Rolling out a change

1. Open a pull request against the policy repository.
2. CI runs `nitctl policy validate`.
3. A reviewer reads the diff — order-independence means they only have to
   understand the changed rules, not the whole file.
4. Merge; your deployment updates the checkout.
5. `nitd` picks it up within `policy.reload` (30 s by default) — no restart.
6. `curl /healthz` reports the new policy version. During a rolling deploy this
   is how you tell whether two replicas are serving different bundles.

Widening access takes effect immediately. **Narrowing it does too** — but only
for future exchanges. Somebody who already cloned a file still has it.

## Next

- [The authorization model](/concepts/authorization/) — the full semantics.
- [Guards](/concepts/guards/) — what `admin` is for.
- [nitctl](/reference/nitctl/) — every command.
