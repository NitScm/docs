---
title: Install
description: A complete nit environment with a Gitea forge in one command, or a build from source.
sidebar:
  order: 2
---

The fastest way to see nit working is the development stack: PostgreSQL, a Gitea
acting as the forge, the control plane, a worker, the web console and Swagger UI
— with a seeded repository and three accounts whose access deliberately differs.

## The development stack

:::note[What you need]
Docker with Compose v2. Nothing else — no Go toolchain, no database, no forge
account.
:::

```sh
git clone https://github.com/NitScm/nit
cd nit/deploy/dev

docker compose up -d
docker compose logs -f bootstrap
```

The `bootstrap` service creates the Gitea account and repository, seeds it,
writes the policy bundle, applies the database schema, issues tokens, and prints
what to do next. Give it a minute the first time — it builds the images.

When it finishes:

| | |
| --- | --- |
| Web console | http://localhost:4200 |
| API | http://localhost:8080 |
| Swagger UI | http://localhost:8081 |
| Gitea | http://localhost:3000 — `nit-admin` / `nit-admin-password` |

### The three accounts

| User | Group | Can see |
| --- | --- | --- |
| `alice` | platform | Everything, including `secrets/`, `infra/production/` and CI |
| `bob` | backend | `src/server`, `src/shared`, `docs` — no secrets |
| `carol` | frontend | `src/ui`, `src/shared`, `docs` — no secrets |

Their tokens are in the bootstrap output, and afterwards:

```sh
docker compose exec nitd cat /var/lib/nit/tokens
```

:::caution
The passwords and the signing key in `dev/compose.yaml` are fixed and public on
purpose — the printed instructions have to be able to include them. Never copy
that file to a real deployment. Use `deploy/production/` instead.
:::

### Signing in to the console

Open http://localhost:4200, leave **Server** empty, and paste **alice's** token.

Alice is in the `platform` group, which is what the server's `NIT_ADMIN_GROUPS`
names. Bob and carol sign in successfully but every page reports "not found" —
the operations API is invisible to a non-operator, and that is deliberate.

### Getting the CLI

The `nit` binary is inside the image; copy it out, or build it (below).

```sh
docker compose cp nitd:/usr/local/bin/nit ./nit
sudo mv nit /usr/local/bin/
```

Then follow [Your first workspace](/start/first-steps/).

### Stopping

```sh
docker compose down -v      # -v also removes the volumes
```

## From source

You need **Go 1.25** and **git**.

```sh
git clone https://github.com/NitScm/nit
cd nit

make build       # bin/nit bin/nitd bin/nit-worker bin/nitctl
make test        # needs no infrastructure
export PATH="$PWD/bin:$PATH"
```

Four binaries come out:

| Binary | Runs where |
| --- | --- |
| `nit` | A developer's machine |
| `nitd` | The control plane — the API |
| `nit-worker` | Anywhere with git, disk and access to the forge |
| `nitctl` | An operator's machine, or the server |

To bring up a server you also need PostgreSQL 13+ and a policy bundle. The
shortest path:

```sh
createdb nit

nitctl config init                        # writes /etc/nit/nit.yaml, mode 600
openssl rand -base64 32 > /etc/nit/sync.key && chmod 600 /etc/nit/sync.key
$EDITOR /etc/nit/nit.yaml                 # database.url, policy.dir, admin_groups

nitctl config show                        # every value, and where it came from
nitctl migrate
nitd &
nit-worker &
```

See [Configuring the server](/guides/server/) for what goes in that file, and
[Writing a policy bundle](/guides/policy-bundles/) for the bundle.

## Containers, for a real deployment

`deploy/production/` carries a forge-agnostic Compose base plus one overlay per
forge:

```sh
cd nit/deploy/production
cp .env.example .env && chmod 600 .env
$EDITOR .env

docker compose -f compose.base.yaml -f compose.gitea.yaml  up -d
docker compose -f compose.base.yaml -f compose.github.yaml up -d
docker compose -f compose.base.yaml -f compose.gitlab.yaml up -d
```

Read [Going to production](/guides/production/) before you do — there are three
things about the forge that have to be true, or nit's guarantees do not hold.

## Verifying an installation

`docs/VALIDATION.md` in the nit repository is a step-by-step walkthrough that
proves each property in turn — read filtering, refused pushes, the CI guard, the
audit trail, recovery from a dead worker — with the output you should see at each
step.

## Next

- [Your first workspace](/start/first-steps/) — clone, change something, push it.
- [Your first policy](/start/first-policy/) — write the rules from scratch.
