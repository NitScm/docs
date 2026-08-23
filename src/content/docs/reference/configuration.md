---
title: Configuration settings
description: Every setting, its file key, its environment variable and its default.
sidebar:
  order: 3
---

Three rules run through all of it.

**Configuration is a file and environment variables; policy is a bundle.**
Anything that decides *who may do what* lives in the [policy
bundle](/guides/policy-bundles/). Anything that decides *how this process runs*
is configuration. Nothing crosses that line: there is no setting that grants
access, and no policy rule that sets a port.

**Layers, lowest to highest: defaults, file, environment.** The environment wins
because that is what an orchestrator injects, and because an operator debugging
a host expects `NIT_LOG_LEVEL=debug nitd` to work whatever the file says.

**A malformed setting stops the process.** A bad duration, a short signing key,
a misspelled key: the binary refuses to start and says which setting is wrong
and where. Silently falling back to a default nobody chose is how a deployment
ends up running something nobody intended.

## The file

```sh
nitctl config init            # a fully commented starter file, mode 600
nitctl config path            # which file would be read
nitctl config show            # every effective value, and where it came from
```

Looked for in this order, first match wins:

1. `-config <path>` on `nitd` or `nit-worker`
2. `$NIT_CONFIG`
3. `./nit.yaml`, `./nit.yml`
4. `$XDG_CONFIG_HOME/nit/nit.yaml`
5. `$HOME/.config/nit/nit.yaml`
6. `/etc/nit/nit.yaml`, `/etc/nit/nit.yml`

Working directory first so a developer can run a checkout without touching the
system; `/etc/nit` last so a package's file is the fallback rather than the
override.

A file named explicitly with `-config` or `$NIT_CONFIG` that does not exist is
an **error**, not a fallback: an operator who named a file meant that file.

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
  mirror_budget_bytes: 21474836480
  max_patch_bytes: 104857600
  pull_ttl: 24h

queue:
  lease_duration: 60s
  max_attempts: 3
  poll: 1s
  reap_every: 30s

security:
  sync_key_file: /etc/nit/sync.key

forge:
  token_file: /run/secrets/nit-forge-token

log:
  level: info
```

A misspelled key is refused, naming the field:

```
nitd: configuration file /etc/nit/nit.yaml: yaml: unmarshal errors:
  line 2: field adr not found in type bootstrap.fileServer
```

`nitd` and `nit-worker` read the **same** configuration, on purpose. Two
processes that disagree about the database, the bundle or the signing key fail
in ways that are very hard to diagnose.

## Required

| File key | Variable | |
| --- | --- | --- |
| `database.url` | `NIT_DATABASE_URL` | PostgreSQL DSN |
| `security.sync_key` | `NIT_SYNC_KEY` | Sync token signing key, **32 bytes minimum** |
| `policy.dir` | `NIT_POLICY_DIR` | Directory holding the policy bundle |

### Secrets

Every secret has an inline form and a `_file` twin. **Prefer the file.**

| Secret | File key | Variable |
| --- | --- | --- |
| Database URL | `database.url_file` | `NIT_DATABASE_URL_FILE` |
| Signing key | `security.sync_key_file` | `NIT_SYNC_KEY_FILE` |
| Forge token | `forge.token_file` | `NIT_FORGE_TOKEN_FILE` |

Docker secrets, Kubernetes secrets and systemd's `LoadCredential` all deliver a
secret as a file. Reading it directly means the value never appears in
`docker inspect`, in a crash dump, or in a configuration file something else
might back up. Trailing whitespace is trimmed, so the newline every mount adds
does not become part of your signing key.

Setting **both forms of the same secret in the file** is an error rather than a
precedence question nobody should have to remember. Across layers, the file
indirection wins: a deployment that mounted a secret meant it.

A configuration file carrying an **inline** secret must be mode 600:

```
nitd: configuration file /etc/nit/nit.yaml is mode 0644 and contains secrets;
run: chmod 600 /etc/nit/nit.yaml — or move the secrets to sync_key_file, url_file and token_file
```

Refusing is deliberately louder than warning: a warning in a start-up log is a
warning nobody sees. A file using only the `_file` indirections holds no secret
and needs no special mode.

### The signing key

```sh
openssl rand -base64 32
```

A sync token is a client's claim about which upstream commit its patch was
computed against, and the server applies that patch on top of whatever the token
names. **The signature is what stops a client naming a base of its choosing.**

There is deliberately **no default and no generated fallback**. A key generated
at start-up would differ between replicas and across restarts, silently
invalidating every client's token — which, to a developer, looks like their
workspace mysteriously demanding a full resynchronization.

Generate it once, share it across every replica, treat it like a database
password. Rotating it invalidates every sync token in existence; every workspace
needs one `nit pull` to recover.

## Storage

| File key | Variable | Default | |
| --- | --- | --- | --- |
| `storage.blob_dir` | `NIT_BLOB_DIR` | `./var/blobs` | Patch payloads |
| `storage.work_dir` | `NIT_WORK_DIR` | `./var/work` | A worker's git mirrors and task worktrees |
| `storage.mirror_budget_bytes` | `NIT_MIRROR_BUDGET_BYTES` | `21474836480` (20 GiB) | Disk the mirrors may occupy before the least recently used are evicted; `0` disables eviction |

**`blob_dir` must be shared between `nitd` and every worker.** `nitd` writes the
authorized patch there and the worker reads it back; two processes with two
separate directories produce `missing_patch` on every push. On one host that
means the same path; across hosts, a shared volume.

`work_dir` is scratch, local to each worker, never backed up, and **belongs to
one worker process** — two workers sharing one would race on the same mirror.

It holds a bare mirror per repository, kept between tasks, plus one worktree per
concurrent task. Only the worktrees free their disk on their own, so size the
volume as `mirror_budget_bytes` plus the largest repository × concurrency. See
[Running workers](/guides/workers/#sizing-and-why-mirrors-are-evicted).

## Behaviour

| File key | Variable | Default | |
| --- | --- | --- | --- |
| `log.level` | `NIT_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |
| `storage.max_patch_bytes` | `NIT_MAX_PATCH_BYTES` | `104857600` | Ceiling on a patch, compressed **and** decompressed |
| `storage.pull_ttl` | `NIT_PULL_TTL` | `24h` | How long a generated pull patch stays fetchable |
| `policy.reload` | `NIT_POLICY_RELOAD` | `30s` | How often the bundle is reread |
| `queue.lease_duration` | `NIT_LEASE_DURATION` | `60s` | How long a worker may hold a task without a heartbeat |
| `queue.max_attempts` | `NIT_MAX_ATTEMPTS` | `3` | Retries before a task fails for good |
| `queue.poll` | `NIT_QUEUE_POLL` | `1s` | How often an idle worker asks for work |
| `queue.reap_every` | `NIT_REAP_EVERY` | `30s` | How often abandoned tasks return to the queue |

Durations accept Go syntax: `90s`, `5m`, `2h`.

`max_patch_bytes` is checked on both the compressed and the decompressed size,
because a decompression bomb is small until it is not.

**`lease_duration` is the setting most likely to need changing** — see
[Running workers](/guides/workers/#sizing-the-lease).

## `nitd` only

| File key | Variable | Default | |
| --- | --- | --- | --- |
| `server.addr` | `NIT_ADDR` | `:8080` | Listen address |
| `server.admin_groups` | `NIT_ADMIN_GROUPS` | *(empty)* | Groups allowed to read the operations API |
| `server.cors_origins` | `NIT_CORS_ORIGINS` | *(empty)* | Browser origins allowed to call the API |
| `server.event_max_wait` | `NIT_EVENT_MAX_WAIT` | `30s` | How long a long poll is held open |

The two lists are YAML sequences in the file and comma-separated in the
environment.

### `admin_groups`

Empty means the operations API is reachable by nobody. Non-members get **404**,
not 403.

It is server configuration rather than a policy rule on purpose: the console is
the tool for diagnosing a broken bundle, and putting the permission to use it
*inside* the bundle would make that tool depend on the thing it exists to debug.

### `cors_origins`

Only needed when the console is served from a different origin than the API.
Serve them from the same host — as the console's nginx does — and leave this
empty.

There is **no wildcard**. The API is bearer-authenticated, so `*` would let any
page a developer happens to visit call it with their credentials.

```yaml
server:
  cors_origins: ["http://localhost:4200"]   # development only
```

### `event_max_wait`

The CLI holds a long poll open while it waits for a task; the server answers
after this long even if nothing changed, and the client reconnects. Shorter
means more reconnections. Longer risks an intermediate proxy closing the
connection first — behind a load balancer with a 30-second idle timeout, set
this below it.

## `nit-worker` only

| File key | Variable | Default | |
| --- | --- | --- | --- |
| `forge.token` | `NIT_FORGE_TOKEN` | *(empty)* | Credential nit pushes with, over HTTPS |
| `git.ssh_command` | `NIT_GIT_SSH_COMMAND` | *(empty)* | Passed to every git invocation as `GIT_SSH_COMMAND` |

### SSH remotes

```yaml
git:
  ssh_command: >-
    ssh -i /run/secrets/nit-ssh-key
    -o IdentitiesOnly=yes
    -o UserKnownHostsFile=/etc/nit/ssh/known_hosts
    -o StrictHostKeyChecking=yes
    -o BatchMode=yes
```

Leave `forge.token` unset for an SSH remote: the key does that job, and an
unused secret is one more thing to rotate.

`git.ssh_command` is a **passthrough, not an abstraction.** There is
deliberately no `ssh_key` setting — a key path would cover only the simplest
case, and agents, `ProxyJump`, per-host keys and non-standard ports would still
be git's business. It exists so a deployment can keep everything in one file and
read it back with `nitctl config show`, not so nit manages keys.

Empty leaves the inherited environment untouched, so a host already configured
through `~/.ssh/config` keeps working. A configured value **overrides** an
inherited `GIT_SSH_COMMAND`: a setting that silently did nothing on a host that
exports one would be worse than no setting at all.

:::caution[A key with a passphrase cannot work unattended]
Workers run git with `GIT_TERMINAL_PROMPT=0`, so a prompt becomes an error — the
right outcome, since the alternative is a worker hanging with a branch leased.
Use an agent and pass `SSH_AUTH_SOCK`, or an unencrypted key readable only by
the worker's user.
:::

| Flag | Default | |
| --- | --- | --- |
| `-queues` | `push,pull` | Which task kinds this worker takes |
| `-concurrency` | `1` | Runners in this process |
| `-name` | hostname | Identifier recorded on leases and in logs |
| `-config` | *(the search order)* | Configuration file |

## `nitd` flags

| Flag | Default | |
| --- | --- | --- |
| `-config` | *(the search order)* | Configuration file |

Everything else is a setting, so that a container's command line does not become
a second place to look.

## Verifying

```sh
nitctl config path
nitctl config show
```

```
file: /etc/nit/nit.yaml

SETTING                     FROM         VALUE
addr                        file         127.0.0.1:8080
database.url                file         postgres://postgres:***@localhost:5432/nit
log.level                   env          DEBUG
policy.reload               default      30s
queue.lease_duration        file         5m0s
security.sync_key           file         (set)
server.admin_groups         file         platform
```

The `FROM` column is the point of the command: it answers *why is this setting
what it is?* Secrets are never printed — only whether they are set and which
layer supplied them.

Run it **on every host**, including inside the containers. A worker with a
different `blob_dir` from `nitd` is the single most common misconfiguration, and
this is what shows it.

## Next

- [Going to production](/guides/production/) — how these settings fit a
  deployment.
- [nitctl](/reference/nitctl/) — the commands that read them.
