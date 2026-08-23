---
title: nitctl
description: Every command and flag of the operator console.
sidebar:
  order: 2
---

The operator's tool: it validates policy bundles, explains decisions, issues
tokens, applies migrations, and inspects the queue and the audit trail.

```
nitctl config show|path|init
nitctl policy validate|explain|show <bundle-dir>
nitctl migrate -dsn <postgres-dsn> [-status]
nitctl token create|list|revoke
nitctl stats
nitctl tasks
nitctl audit
```

Two families, with different needs:

- `stats`, `tasks`, `audit` go through the **API** and need `NIT_SERVER` and an
  admin `NIT_TOKEN`. They are deliberately the same endpoints the web console
  calls, so the API is exercised from day one and the UI can never need a
  capability `nitctl` lacks.
- `config`, `policy`, `migrate`, `token` are run **on the server** and read the
  configuration file and the database directly.

## `nitctl config`

```sh
nitctl config path                       # which file would be read
nitctl config show                       # every effective value, and where it came from
nitctl config init                       # write a commented starter file, mode 600
nitctl config init -config ./nit.yaml -force
```

| Flag | | |
| --- | --- | --- |
| `-config` | `/etc/nit/nit.yaml` for `init` | Which file |
| `-force` | | Overwrite an existing file (`init` only) |

```
file: /etc/nit/nit.yaml

SETTING                     FROM         VALUE
addr                        file         127.0.0.1:8080
database.url                file         postgres://postgres:***@localhost:5432/nit
log.level                   env          DEBUG
policy.reload               default      30s
security.sync_key           file         (set)
```

The `FROM` column answers *why is this setting what it is?* — the question an
operator asks at the worst possible moment, whose honest answer otherwise needs
three places checked.

Secrets are never printed: only whether they are set and which layer supplied
them. A database URL keeps its host and user and loses its password.

## `nitctl policy`

### `validate`

```sh
nitctl policy validate ./policy
```

```
bundle ok
  version:      sha256:f6040b6d6a8381dc
  repositories: 12
```

Compiles the bundle and reports every problem it contains — not the first one.
Fixing errors one round-trip at a time is how a validator becomes something
people stop running.

Run it in the policy repository's CI.

### `explain`

```sh
nitctl policy explain ./policy -repo backend-api -user alice -path secrets/prod.env
nitctl policy explain ./policy -repo backend-api -user alice -path src/main.go -action write
nitctl policy explain ./policy -repo backend-api -user alice -path src/main.go -ref refs/heads/main
```

| Flag | | |
| --- | --- | --- |
| `-repo` | *required* | Repository id |
| `-user` | *required* | User id |
| `-path` | *required* | Repository-relative path |
| `-action` | every action | `read`, `write`, `create`, `delete` or `admin` |
| `-ref` | | Fully qualified ref, e.g. `refs/heads/main` |

```
alice on secrets/prod.env (backend-api)
groups: backend

  DENY  read    denied by rule secrets-are-platform-only
          Production secrets are owned by the platform team.
  DENY  write   denied by rule secrets-are-platform-only
  ...
```

The bundle directory comes **first**, before the flags. Go's flag package stops
parsing at the first non-flag argument, so a positional after the flags would be
silently ignored — a silence that would make `explain` lie.

The decision names the rule that produced it, in both directions: a grant is as
worth attributing as a denial.

### `show`

```sh
nitctl policy show ./policy
```

Lists every repository, its remote and default branch, and every rule with its
effect, subject, paths and actions. This is the bundle as nit compiled it, not
as you wrote it — which is the version worth checking.

## `nitctl migrate`

```sh
nitctl migrate                  # uses the configured database.url
nitctl migrate -dsn postgres://nit@localhost/nit
nitctl migrate -status          # list migrations without applying anything
```

| Flag | | |
| --- | --- | --- |
| `-dsn` | `database.url`, then `$NIT_DATABASE_URL` | PostgreSQL DSN |
| `-status` | | List, do not apply |

Migrations are **never** applied at start-up. A schema change is a deployment
step an operator decides to take; a server that migrated on boot would happily
run half-rolled-out DDL from several replicas at once.

## `nitctl token`

```sh
nitctl token create -user alice -label laptop -ttl 720h
nitctl token list   -user alice
nitctl token revoke -id 7c1e9f2a-…
```

| Flag | Default | |
| --- | --- | --- |
| `-user` | | Policy user id (`create`, `list`) |
| `-label` | | Free text, typically a machine name |
| `-ttl` | `720h` | How long it stays valid |
| `-id` | | Session id (`revoke`) |
| `-dsn` | `database.url` | PostgreSQL DSN |
| `-policy` | `policy.dir` | Policy bundle directory |

```
session: 7c1e9f2a-3b4c-4d5e-8f90-a1b2c3d4e5f6
user:    alice
expires: 2026-08-30T12:00:00Z

nit_R4nD0m…

This token is shown once and is not recoverable. Store it with:
  nit login <server-url>
```

Only the SHA-256 is stored. There is no recovery path: a lost token is reissued,
not retrieved.

A token can only be issued to someone **the bundle declares**, so a typo
produces an error rather than a credential for an account that authorizes
nothing.

Issuing is an operator action rather than self-service. A device flow against
the forge is the obvious next step; until then the trust chain stays short
enough to reason about.

## `nitctl stats`

```sh
export NIT_SERVER=https://nit.example.com
export NIT_TOKEN=nit_…

nitctl stats
nitctl stats -json
```

```
policy:       sha256:f6040b6d6a8381dc
repositories: 12

queued:       3
running:      1
succeeded:    1847
failed:       2

busy branches:   1
denials (24h):   6
```

Two numbers mean something is wrong *right now*: **queued** climbing, and
**busy branches** staying high.

## `nitctl tasks`

```sh
nitctl tasks
nitctl tasks -state queued
nitctl tasks -state failed -limit 20 -json
nitctl tasks -repository backend-api -kind push
```

| Flag | Default | |
| --- | --- | --- |
| `-state` | all | `queued`, `running`, `succeeded`, `failed` |
| `-kind` | both | `push` or `pull` |
| `-repository` | all | Repository id |
| `-limit` | `50` | Maximum rows |
| `-json` | | Raw JSON |

```
TASK                                   KIND   STATE      USER    REPOSITORY@BRANCH      DURATION   NOTE
be59af45-9694-416e-ace2-da5cffc7f145   push   running    carol   backend-api@feature/x  2m14s      worker-2
56c8b3f7-a0a1-4971-b5ba-3f18389b08bb   push   failed     dave    data-platform@main     1.2s       conflict
```

`NOTE` carries the error code for a failure, the queue position for a wait, or
the worker holding the lease for a running task.

## `nitctl audit`

```sh
nitctl audit -limit 20
nitctl audit -user bob -since 24h
nitctl audit -repository backend-api -since 168h
nitctl audit -request 01J8Z3Q2M7C4V9K1 -json
```

| Flag | Default | |
| --- | --- | --- |
| `-user` | all | Actor |
| `-repository` | all | Repository id |
| `-request` | | Request id — follows one operation end to end |
| `-since` | all time | A duration, e.g. `24h` |
| `-limit` | `50` | Maximum rows |
| `-json` | | Raw JSON |

```
WHEN                 ACTOR   ACTION             REPOSITORY@BRANCH   PATH                RULE
2026-07-31 00:35:29  bob     push.applied       backend-api@main
2026-07-31 00:33:14  bob     push.denied_path   backend-api@main    secrets/prod.env    secrets-are-platform-only
```

## Environment

| | |
| --- | --- |
| `NIT_SERVER` | Server for `stats`, `tasks`, `audit` |
| `NIT_TOKEN` | Admin token for the same |
| `NIT_DATABASE_URL` | Fallback DSN for `migrate` and `token` |
| `NIT_POLICY_DIR` | Fallback bundle directory for `token` |
| `NIT_CONFIG` | Configuration file to read |

With `NIT_SERVER` set and no `NIT_TOKEN`, `nitctl` reuses the credential
`nit login` stored — so an operator with a developer install does not paste a
token twice.

## `not found`

```
nitctl: not found; is this account in one of the server's NIT_ADMIN_GROUPS?
```

The token is valid; the account is not in `server.admin_groups`. It is a 404
rather than a 403 deliberately: the existence of an operations API is not
something an ordinary developer needs confirmed.

## Next

- [Configuration settings](/reference/configuration/) — every key.
- [Day-to-day operations](/guides/operations/) — these commands in context.
