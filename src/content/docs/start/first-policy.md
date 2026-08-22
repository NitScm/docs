---
title: Your first policy
description: Write a policy bundle from nothing, check it says what you meant, and put it in force.
sidebar:
  order: 4
---

A **policy bundle** is a directory of YAML files. It is where all authorization
lives, and it is the only place: no setting, no environment variable and no
console button grants anyone access to anything.

That is deliberate. Rules belong in files so they get pull requests, review,
history, blame and rollback — the same treatment as the code they protect.

## The shape

```
policy/
├── users.yaml
├── groups.yaml
├── repositories.yaml
└── repositories/
    └── backend-api/
        └── rules.yaml
```

Let us build one for a team where the backend and frontend own their own code,
and nobody but the platform team may see production secrets.

## 1. People

```yaml title="policy/users.yaml"
- id: alice
  email: alice@example.com

- id: bob
  email: bob@example.com

- id: carol
  email: carol@example.com
  # An account you can switch off without deleting the history it owns.
  disabled: false
```

The `id` is nit's own identity for a person. It never changes, even when their
forge account is renamed.

:::caution
`email` is used to attribute history and to verify commit authorship. It is
**never** used to authenticate: identity always comes from the session token,
because the author field of a commit is free text that anyone can forge.
:::

## 2. Groups

```yaml title="policy/groups.yaml"
- id: interns
  description: Interns, supervised access
  members: [carol]

- id: backend
  description: Backend engineers
  members: [bob]
  # Every member of `interns` is also a member of `backend`.
  includes: [interns]

- id: platform
  description: Owns secrets, infrastructure and CI
  members: [alice]
```

`includes` absorbs another group. Membership is resolved transitively, once, when
the bundle is compiled — so carol gets everything backend gets, plus whatever is
granted to interns specifically.

Inclusion cycles are rejected at load time.

## 3. Repositories

```yaml title="policy/repositories.yaml"
- id: backend-api
  remote: https://github.com/acme/backend-api.git
  forge: github
  default_branch: main
```

`remote` is the upstream URL. nit is the only account that writes to it.

## 4. Rules

This is where the thinking happens.

```yaml title="policy/repositories/backend-api/rules.yaml"
# Everyone reads the code.
- id: everyone-reads-the-code
  subject: { type: any }
  paths: [src/, docs/, README.md]
  actions: [read]
  effect: allow

# Teams own their subtrees.
- id: backend-owns-server
  subject: { type: group, id: backend }
  paths: [src/server/, src/shared/]
  actions: [read, write, create, delete]
  effect: allow
  description: Backend engineers own src/server and src/shared.

- id: frontend-owns-ui
  subject: { type: group, id: frontend }
  paths: [src/ui/, src/shared/]
  actions: [read, write, create, delete]
  effect: allow
  description: Frontend engineers own src/ui and src/shared.

# Nobody outside the platform team may even *read* these.
- id: secrets-are-platform-only
  subject: { type: any }
  except:
    - { type: group, id: platform }
  paths: [secrets/, infra/production/]
  actions: [read, write, create, delete, admin]
  effect: deny
  description: >-
    Production secrets and infrastructure are owned by the platform team.
    Open a request in #platform to have a change applied.

# The platform team, including `admin` — which the guards require.
- id: platform-owns-everything
  subject: { type: group, id: platform }
  paths: ["**"]
  actions: [read, write, create, delete, admin]
  effect: allow

# Nobody pushes straight to main.
- id: no-direct-push-to-main
  subject: { type: any }
  except:
    - { type: group, id: platform }
  paths: ["**"]
  refs: [refs/heads/main]
  actions: [write, create, delete]
  effect: deny
  description: main is updated through pull requests only.
```

### The four things to understand

**Deny always wins, and the default is deny.** Every matching rule is
considered — there is no first-match — so rules can be reordered, split or
regrouped without changing behaviour. Anything no rule allows is refused.

**`except` is how you write an exemption.** Because deny wins, "nobody may read
`secrets/`, except the platform team" *cannot* be a universal deny plus a team
allow: the deny would swallow the allow. Listing every non-exempt group instead
would fail open the day someone creates a new group. `except` is the safe form.

**A trailing slash means a subtree.** `secrets/` covers that directory and
everything under it — and the directory entry itself, so a symlink placed at
exactly `secrets` is covered too. Anything without a trailing slash is a glob:
`**/*.env`, `src/*.go`, `{docs,site}/**`.

**Write implies read.** An allow rule granting `write`, `create` or `delete`
must also grant `read`, and the bundle is rejected if it does not. Writing a file
you cannot see means overwriting content blind, and you cannot produce a diff
against a file that is absent from your workspace.

## 5. Check it before anyone depends on it

```sh
nitctl policy validate ./policy
```

```
bundle ok
  version:      sha256:f6040b6d6a8381dc
  repositories: 1
```

That version is a content hash of the whole bundle. It is stamped on every
decision, so any past decision can be replayed against exactly the rules that
produced it.

Now ask it questions:

```sh
nitctl policy explain ./policy \
  -repo backend-api -user bob -path secrets/prod.env -action read
```

```
bob on secrets/prod.env (backend-api)
groups: backend

  DENY  read    denied by rule secrets-are-platform-only (denied_by_rule: secrets/)
          Production secrets are owned by the platform team.
```

And check the exemption actually works:

```sh
nitctl policy explain ./policy \
  -repo backend-api -user alice -path secrets/prod.env -action read
```

```
alice on secrets/prod.env (backend-api)
groups: platform

  ALLOW read    allowed by rule platform-owns-everything (allowed_by_rule: **)
```

:::tip[Put `nitctl policy validate` in your policy repository's CI]
A bundle that does not compile must never reach production. `nitd` refuses to
start on one, and a running server keeps serving the last good bundle rather than
reloading a broken one — but catching it in review is better than either.
:::

## 6. Put it in force

Point the server at the directory and it is live:

```yaml title="/etc/nit/nit.yaml"
policy:
  dir: /etc/nit/policy
  reload: 30s
```

The bundle is reread every `reload`. A bundle that does not compile is **not
applied**: the last good one stays in force, and the failure is logged loudly.

The intended shape is a checkout of a policy repository, updated by your
deployment — so a change to who can see what is a pull request, with a reviewer.

## Next

- [The authorization model](/concepts/authorization/) — the full rule language.
- [Guards](/concepts/guards/) — the protections that path rules cannot express.
- [Writing a policy bundle](/guides/policy-bundles/) — patterns for real teams.
