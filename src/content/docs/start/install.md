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

## Released binaries

Every release publishes signed-by-checksum archives and Linux packages at
[github.com/NitScm/nit/releases](https://github.com/NitScm/nit/releases). The
binaries are static and need no runtime beyond **git**.

### Ubuntu and Debian

```sh
VERSION=0.1.0
curl -LO "https://github.com/NitScm/nit/releases/download/v${VERSION}/nit_${VERSION}_linux_amd64.deb"
sudo apt install "./nit_${VERSION}_linux_amd64.deb"

nit version
```

The package installs all four binaries into `/usr/bin` and declares a
dependency on `git`, so apt refuses rather than leaving you with a worker that
fails on its first task.

On an ARM machine — a Raspberry Pi, an AWS Graviton instance — replace `amd64`
with `arm64`.

### Fedora, RHEL and openSUSE

```sh
VERSION=0.1.0
sudo rpm -i "https://github.com/NitScm/nit/releases/download/v${VERSION}/nit_${VERSION}_linux_amd64.rpm"
```

### Any Linux, or macOS

Two archives, split by who runs what. `nit_…` carries **`nit` and `nitctl`** —
the tools a person runs. `nit-server_…` carries **`nitd` and `nit-worker`**.

Neither carries the engineering documents from the repository's `docs/`. Those
are written for people modifying nit, and a copy on disk drifts from this site
and from the binary it shipped with. What you are reading is the current one.

```sh
VERSION=0.1.0
OS=linux            # or: darwin
ARCH=amd64          # or: arm64

curl -LO "https://github.com/NitScm/nit/releases/download/v${VERSION}/nit_${VERSION}_${OS}_${ARCH}.tar.gz"
curl -LO "https://github.com/NitScm/nit/releases/download/v${VERSION}/checksums.txt"

sha256sum --check --ignore-missing checksums.txt

tar xzf "nit_${VERSION}_${OS}_${ARCH}.tar.gz"
sudo install -m 0755 nit nitctl /usr/local/bin/
```

For a server, swap `nit_` for `nit-server_` — or install the `.deb` or `.rpm`
above, which carry all four binaries and declare the dependency on git.

Check the checksum before running anything. It takes one command, and it is the
only step that distinguishes the archive you meant to download from one you
did not.

### Windows

Developers on Windows get `nit` and `nitctl`. Download
`nit_<version>_windows_amd64.zip` from the releases page, or:

```powershell
$Version = '0.1.0'
$Arch    = 'amd64'      # or: arm64 on a Surface Pro X or similar

Invoke-WebRequest -Uri "https://github.com/NitScm/nit/releases/download/v$Version/nit_${Version}_windows_$Arch.zip" -OutFile nit.zip
Invoke-WebRequest -Uri "https://github.com/NitScm/nit/releases/download/v$Version/checksums.txt" -OutFile checksums.txt

# Verify before extracting.
(Get-FileHash nit.zip -Algorithm SHA256).Hash.ToLower()
Select-String -Path checksums.txt -Pattern "windows_$Arch.zip"

Expand-Archive nit.zip -DestinationPath "$env:LOCALAPPDATA\nit"
```

Then put it on your `PATH`, for this session and the next:

```powershell
$env:Path += ";$env:LOCALAPPDATA\nit"
[Environment]::SetEnvironmentVariable(
    'Path',
    [Environment]::GetEnvironmentVariable('Path', 'User') + ";$env:LOCALAPPDATA\nit",
    'User')

nit version
```

You also need **git for Windows** — nit produces and applies patches, it does
not reimplement git.

:::note[Why only two binaries on Windows]
`nitd` and `nit-worker` are server components. They compile for Windows, but a
worker's whole job is to clone, apply, rebase and push through a real git, and
that path has not been exercised there. A published binary is a claim that it
works; that claim is not made until it is tested. Run the server side on Linux
— which is what the Compose stacks above do.
:::

### With Go

If you already have Go 1.25, this is the shortest route on any platform, and
the binary still reports its version — the toolchain stamps the module version
and the revision even without a release build.

```sh
go install github.com/NitScm/nit/cmd/nit@latest
go install github.com/NitScm/nit/cmd/nitctl@latest
```

### Confirming what you installed

```sh
nit version
```

```
nit v0.1.0 (a1b2c3d4e5f6) built 2026-08-22T21:00:00Z go1.25.11 linux/amd64
```

Quote that line in a bug report. A build that cannot say which build it is
turns every report into a guess — which is why `dev (unknown)` appears instead
of nothing when a binary was built outside a release.

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

To bring up a server you also need a database and a policy bundle. PostgreSQL
13+ is recommended; MySQL 8.0.16+ and MariaDB 10.6+ are supported too, and
[Configuration](/reference/configuration/#which-database) covers what differs.
The shortest path:

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
