---
title: Going to production
description: Topologies, systemd, and the checklist to work through before anyone depends on nit.
sidebar:
  order: 7
---

:::caution[Check the shape of your workload first]
nit serializes pushes per branch, and every task clones from scratch. It scales
across many repositories and many branches; it does **not** scale on one very
busy branch, and that limit is architectural rather than a matter of tuning.

Read `docs/SCALING.md` in the repository before committing a monorepo where a
large team pushes to a single trunk. It also documents the ceilings that arrive
next, and how audit retention is applied.
:::

## Before anything else: the forge

nit's guarantees end the moment a developer can push to the same branch directly.
Everything below assumes these three are true:

1. **nit's machine account is the only writer.** Everyone else has read at most.
2. **The branches nit manages are protected**, with that account as the only
   permitted pusher.
3. **The repositories are private.**

See [Connecting a forge](/guides/forges/) for the per-forge detail, and audit the
ways around them — CI jobs with write permission, deploy keys, admins who can
bypass branch protection.

## Topology

### One host

Everything on one machine, which is fine for a team and a handful of
repositories.

```sh
cd nit/deploy/production
cp .env.example .env && chmod 600 .env
$EDITOR .env

docker compose -f compose.base.yaml -f compose.github.yaml up -d
```

### Several hosts

- **`nitd`**: any number of replicas behind a load balancer. Stateless apart from
  the database. They **must share `security.sync_key`**, or a token minted by one
  and rejected by another makes the deployment fail at random.
- **Workers**: any number, on machines with git, disk and forge access. They need
  the same database, bundle and key — and **the same blob storage as `nitd`**.
- **The policy bundle**: deployed to every host, as a git checkout your
  deployment updates.

The blob store is the constraint that shapes the topology. `nitd` writes the
authorized patch and a worker reads it back; today that means a shared volume,
until the store grows an object-storage backend.

## Secrets

Deliver them as **files**, not as environment values:

```yaml
database:
  url_file: /run/secrets/nit-database-url
security:
  sync_key_file: /run/secrets/nit-sync-key
forge:
  token_file: /run/secrets/nit-forge-token
```

Docker secrets, Kubernetes secrets and systemd's `LoadCredential` all deliver a
secret as a file. Reading it directly means the value never appears in
`docker inspect`, in a crash dump, or in a configuration file something else
might back up.

The equivalent environment variables are `NIT_DATABASE_URL_FILE`,
`NIT_SYNC_KEY_FILE` and `NIT_FORGE_TOKEN_FILE`. When both an inline value and a
file are set, the file wins: a deployment that mounts a secret meant it.

### The signing key

```sh
openssl rand -base64 32 > /etc/nit/sync.key && chmod 600 /etc/nit/sync.key
```

Generate it **once**, share it across every replica, and treat it like a database
password. Rotating it invalidates every sync token in existence; every workspace
needs one `nit pull` to recover.

## systemd

```ini title="/etc/systemd/system/nitd.service"
[Unit]
Description=nit control plane
After=network-online.target postgresql.service

[Service]
Type=exec
User=nit
ExecStart=/usr/local/bin/nitd -config /etc/nit/nit.yaml
Restart=always
RestartSec=5

LoadCredential=sync-key:/etc/nit/sync.key

NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/nit

[Install]
WantedBy=multi-user.target
```

Point nit at the credential with `Environment=NIT_SYNC_KEY_FILE=%d/sync-key` in
the unit. **nit does not expand variables inside configuration values** — `%d`
is a systemd specifier, expanded by systemd in its own file — so a
`sync_key_file: ${CREDENTIALS_DIRECTORY}/sync-key` in `nit.yaml` would be read
as a literal path and fail. Write the resolved path instead if you prefer the
file: `LoadCredential` mounts it at `/run/credentials/nitd.service/sync-key`.

The worker unit is the same with `ExecStart=/usr/local/bin/nit-worker`;
`ReadWritePaths=/var/lib/nit` covers both the shared blob directory and its own
scratch space. For an SSH remote it also carries the key and
`git.ssh_command` — see [the worked example](/guides/example-github-ssh/).

## TLS and exposure

`nitd` binds to loopback by default. Put a TLS terminator in front of it.

If that terminator has an idle timeout, set `server.event_max_wait` **below** it —
the event endpoint holds a response open by design, and a proxy that cuts it off
breaks exactly the request that is working correctly.

Nothing else needs to be public. The console is an internal tool; the forge is
reachable by nit, not necessarily by anyone else.

## Deploying a change

```sh
nitctl migrate            # first, and separately
# then roll out the new binaries
```

Migrations are **never** applied on boot. A schema change is a deployment step an
operator takes; a server that migrated on start-up would happily run
half-rolled-out DDL from several replicas at once.

During a rolling deploy, `curl /healthz` on each replica reports the policy
version it is serving — which is how you spot two of them disagreeing.

## The checklist

**The forge**
- [ ] nit's machine account is the only writer
- [ ] Branch protection lists only that account
- [ ] Repositories are private
- [ ] No CI job, deploy key or admin bypass writes to those branches
- [ ] The forge token belongs to a machine identity, scoped to those repositories

**Secrets**
- [ ] `security.sync_key` is 32+ bytes, generated once, shared by every replica
- [ ] Secrets are delivered as files, not environment values
- [ ] Any configuration file holding an inline secret is mode 600
- [ ] `.env` files are mode 600 and not in version control

**Configuration**
- [ ] `storage.blob_dir` is one volume shared by `nitd` and every worker
- [ ] `queue.lease_duration` exceeds a clone of your largest repository
- [ ] `server.admin_groups` names the operators — and nobody else
- [ ] `server.cors_origins` is empty unless the console is on another origin
- [ ] `nitctl config show` reads the way you expect, on every host

**Policy**
- [ ] The bundle is a git repository with review required
- [ ] `nitctl policy validate` runs in its CI
- [ ] `nitctl policy explain` has been run for the cases you care about
- [ ] Every rule has a `description` a developer can act on
- [ ] `admin` is granted to somebody, or nobody can ever change CI

**Operations**
- [ ] The database is backed up — sync points and the audit trail live there
- [ ] On MySQL or MariaDB: the application account has no `DROP` privilege, and
      a backup is taken before every `nitctl migrate`
- [ ] The policy repository is backed up
- [ ] Somebody knows to check `nitctl stats` when developers say pushes are slow
- [ ] `/healthz` is monitored
- [ ] A retention period is decided and applied — `nitctl audit prune` is the
      only thing that removes audit records, and nothing runs it for you
- [ ] The branches your team actually pushes to are not one shared trunk

**Before opening it to developers**
- [ ] Walked through `docs/VALIDATION.md` against the real deployment
- [ ] A push touching a confidential path was refused, and the forge did not move
- [ ] A clone genuinely lacks the files it should lack
- [ ] The audit trail shows all of the above

## What to expect operationally

**Nothing breaks when a worker dies.** Its lease lapses, the reaper returns the
task, another worker takes it. The developer sees a slower push.

**Nothing breaks when a policy change is bad.** It does not compile, so it is not
applied; the last good bundle stays in force and the failure is logged.

**A pushed change is never half-applied.** Either the whole patch lands or the
push is refused; the final publish uses `--force-with-lease`, so a change that
did not come through nit cannot be silently overwritten either.

**Developers will hit `stale_sync_point`.** It means "pull first" and it is
normal, in the same way `git push` rejections are normal.

## Next

- [Day-to-day operations](/guides/operations/) — running it once it is up.
- [Configuration settings](/reference/configuration/) — every key.
