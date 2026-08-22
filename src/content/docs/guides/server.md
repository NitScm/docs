---
title: Configuring the server
description: The configuration file, the environment, secrets, and the settings that matter most.
sidebar:
  order: 2
---

`nitd` is the control plane: the API, authorization, sync points, the queue, the
blob store and the audit log. It performs no git operation.

## Two rules

**Configuration is a file and environment variables. Policy is a bundle.**
Anything that decides *who may do what* lives in the policy bundle. Anything that
decides *how this process runs* is configuration. Nothing crosses that line:
there is no setting that grants access, and no policy rule that sets a port.

**A malformed setting stops the process.** A bad duration, a short signing key, a
misspelled key in the file — the binary refuses to start and says which setting
is wrong and where. Falling back to a default nobody chose is how a deployment
ends up running something nobody intended.

## Layers

Lowest to highest: **defaults → file → environment**.

The environment wins because that is what a container orchestrator injects, and
because an operator debugging a host expects `NIT_LOG_LEVEL=debug nitd` to work
whatever the file says.

## The configuration file

```sh
nitctl config init                       # writes /etc/nit/nit.yaml, mode 600
```

The generated file is fully commented. It is looked for in this order, first
match wins:

1. `-config <path>`
2. `$NIT_CONFIG`
3. `./nit.yaml`, `./nit.yml`
4. `$XDG_CONFIG_HOME/nit/nit.yaml`
5. `$HOME/.config/nit/nit.yaml`
6. `/etc/nit/nit.yaml`, `/etc/nit/nit.yml`

Working directory first, so a developer can run a checkout without touching the
system; `/etc/nit` last, so a package's file is the fallback rather than the
override.

A file named explicitly with `-config` or `$NIT_CONFIG` that does not exist is an
**error**, not a fallback: an operator who named a file meant that file.

```yaml title="/etc/nit/nit.yaml"
server:
  addr: ":8080"
  admin_groups: [platform]
  cors_origins: []
  event_max_wait: 30s

database:
  url_file: /run/secrets/nit-database-url

policy:
  dir: /etc/nit/policy
  reload: 30s

storage:
  blob_dir: /var/lib/nit/blobs
  work_dir: /var/lib/nit/work
  max_patch_bytes: 104857600
  pull_ttl: 24h

queue:
  lease_duration: 60s
  max_attempts: 3
  poll: 1s
  reap_every: 30s

security:
  sync_key_file: /etc/nit/sync.key

log:
  level: info
```

A misspelled key is refused, naming the field:

```
nitd: configuration file /etc/nit/nit.yaml: yaml: unmarshal errors:
  line 2: field adr not found in type bootstrap.fileServer
```

## Seeing what is in force

```sh
nitctl config show
```

```
file: /etc/nit/nit.yaml

SETTING                    FROM         VALUE
addr                       file         127.0.0.1:8080
database.url               file         postgres://nit:***@db:5432/nit
forge.token                default      (not set)
log.level                  env          DEBUG
queue.lease_duration       file         5m0s
queue.poll                 default      1s
security.sync_key          file         (set)
server.admin_groups        file         platform
```

The **FROM** column answers "why is this setting what it is?" — the question
asked at the worst possible moment, whose honest answer otherwise needs three
places checked. Secrets are never printed, only whether they are set and which
layer supplied them.

## Secrets

Every secret has three forms:

| Secret | Inline | From a file | Environment |
| --- | --- | --- | --- |
| Database URL | `database.url` | `database.url_file` | `NIT_DATABASE_URL_FILE` |
| Signing key | `security.sync_key` | `security.sync_key_file` | `NIT_SYNC_KEY_FILE` |
| Forge token | `forge.token` | `forge.token_file` | `NIT_FORGE_TOKEN_FILE` |

**Prefer the file form.** Docker secrets, Kubernetes secrets and systemd's
`LoadCredential` all deliver a secret as a file; reading it directly means the
value never appears in `docker inspect`, in a crash dump, or in a configuration
file something else might back up. Trailing whitespace is trimmed, so the newline
every mount adds does not become part of your signing key.

**A file carrying an inline secret must be mode 600.** nit refuses to read a
group- or world-readable one:

```
nitd: configuration file /etc/nit/nit.yaml is mode 0644 and contains secrets;
run: chmod 600 /etc/nit/nit.yaml — or move the secrets to sync_key_file, url_file and token_file
```

Refusing is deliberately louder than warning: a warning in a start-up log is a
warning nobody sees. A passwordless database URL is not a secret, and a file
using only the `_file` indirections needs no special mode.

### The signing key

```sh
openssl rand -base64 32 > /etc/nit/sync.key && chmod 600 /etc/nit/sync.key
```

At least 32 bytes, **shared by every replica**, and there is deliberately no
default and no generated fallback.

A key generated at start-up would differ between replicas and across restarts,
silently invalidating every client's sync token — which, to a developer, looks
like their workspace mysteriously demanding a full resynchronization.

Rotating it invalidates every sync token in existence; every workspace needs one
`nit pull` to recover. Survivable, but not free. Treat it like a database
password.

## The settings that matter most

### `policy.dir`

A checkout of your policy repository, mounted read-only. Reread every
`policy.reload`. A bundle that does not compile is **not applied** — the last
good one stays in force.

### `server.admin_groups`

Groups allowed to read the operations API — `/v1/admin/*`,
`nitctl stats|tasks|audit`, the web console. Empty means nobody, and non-members
get **404** rather than 403.

It is server configuration rather than a policy rule on purpose: the console is
the tool for diagnosing a broken bundle, and putting the permission to use it
*inside* the bundle would make that tool depend on the thing it exists to debug.

### `storage.blob_dir`

**Must be the same directory for `nitd` and every worker.** `nitd` writes the
authorized patch there and a worker reads it back. Separate directories produce
`missing_patch` on every push — the single most common deployment mistake.

On one host that means the same path; across hosts, a shared volume.

### `server.cors_origins`

Only needed when the console is served from a different origin than the API.
Serve them from the same host — the console image proxies `/v1` to the control
plane — and leave this empty.

There is **no wildcard**. The API is bearer-authenticated, so `*` would let any
page a developer happens to visit call it with their credentials.

### `server.event_max_wait`

How long a client's long poll is held open before the server answers with no
change. If you sit behind a load balancer with a 30-second idle timeout, set this
below it, or the balancer will cut off exactly the request that is working
correctly.

## Migrations

```sh
nitctl migrate            # applies pending migrations, then exits
nitctl migrate -status    # lists what the binary carries
```

Never applied on boot. A schema change is a deployment step an operator decides
to take; a server that migrated on start-up would happily run half-rolled-out DDL
from several replicas at once.

Each migration runs in a transaction with the row that records it, so a failure
leaves neither partial schema nor a false record of success. A session advisory
lock serializes concurrent operators.

## Checking a deployment

```sh
nitctl config show                  # every value, and which layer supplied it
nitctl config path                  # which file would be read
nitctl policy validate ./policy     # the bundle compiles
curl -s localhost:8080/healthz      # protocol and policy version in force
```

`/healthz` is unauthenticated and reports the policy version, which is what makes
a rolling deploy diagnosable.

## Next

- [Running workers](/guides/workers/) — the other half.
- [Configuration settings](/reference/configuration/) — every key and variable.
- [Going to production](/guides/production/).
