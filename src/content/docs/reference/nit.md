---
title: nit
description: Every command and flag of the developer CLI.
sidebar:
  order: 1
---

The CLI a developer runs. It **never talks to the forge**: it produces a patch
against its sync point, hands it to the control plane, and applies whatever
filtered patch comes back. Upstream credentials live on the server, so a
developer machine never holds one.

```
nit login <server-url> [-token <token>]
nit clone <repository> [directory] [-branch <branch>] [-server <url>] [-label <label>]
nit pull
nit push -m <message> [--check] [--drop-unauthorized]
nit status
nit whoami [-server <url>]
```

Progress goes to stderr and results to stdout, so output stays pipeable.
Interrupting with Ctrl-C is safe: the flows are ordered so a cancellation never
records a sync point for work that did not land. It exits `130`.

## `nit login`

```sh
nit login https://nit.example.com
nit login https://nit.example.com -token nit_…
```

| Flag | Default | |
| --- | --- | --- |
| `-token` | *(read from stdin)* | The token to store |

Stores a credential for a server, in `~/.config/nit/credentials.json` at mode
600.

The token is **verified before it is written**, against `/v1/whoami`. Storing an
unverified credential means the failure surfaces later, during a push, where it
is indistinguishable from half a dozen other problems.

The server's protocol version is checked too. A mismatch is reported plainly —
"the server speaks protocol X, this CLI speaks Y; upgrade one of them" — rather
than becoming a confusing failure three commands later.

## `nit clone`

```sh
nit clone backend-api
nit clone backend-api ./api -branch develop
```

| Flag | Default | |
| --- | --- | --- |
| `-server` | `$NIT_SERVER` | Which server. Optional if you have exactly one stored credential |
| `-branch` | the repository's default | Branch to track |
| `-label` | *(none)* | A name for this workspace, visible to operators |

Creates a workspace holding a **filtered projection**: a real git repository
containing only what you may read.

```
Cloned backend-api into ./backend-api
128 file(s) updated
9 file(s) withheld by policy
```

The count of withheld files is shown; their paths are not. Naming them would
leak the structure the read rules exist to hide — but a developer who does not
know something was withheld will mistake a missing file for a deleted one.

The result is not a clone of upstream and shares no commit hash with it. Do not
add a git remote pointing at the forge.

## `nit pull`

```sh
nit pull
```

Fetches the authorized upstream diff since your sync point and applies it.

Your local commits are preserved: the diff is applied at the sync commit and
your work is rebased on top. Uncommitted changes are left alone, so commit or
stash before pulling if they conflict.

```
Updated backend-api@main to 4f2a9c1b7e30
14 file(s) updated
2 file(s) withheld by policy
```

`Already up to date` means the branch has not moved.

The sync point only advances **after** the patch has applied. A pull that fails
halfway can simply be run again.

## `nit push`

```sh
nit push -m "Add rate limiting to the ingest endpoint"
nit push -m "…" --check
nit push -m "…" --drop-unauthorized
```

| Flag | | |
| --- | --- | --- |
| `-m` | *required, except with `--check`* | The commit message that lands upstream |
| `--check` | | Authorize without submitting anything |
| `--drop-unauthorized` | | Drop refused files instead of refusing the push |

Everything you have committed since the sync point is packaged, compressed and
submitted. It lands upstream as **one commit**, authored by your authenticated
identity — never by the `From:` line in the patch, which the sender controls.

```
Pushed 7 file(s) to backend-api@main as 4f2a9c1b7e30
```

That commit carries `Nit-User`, `Nit-Request`, `Nit-Task`,
`Nit-Policy-Version`, `Nit-Base-Commit` and `Nit-Workspace` trailers, so it can
be traced from the forge alone — see
[what lands on the forge](/concepts/push-and-pull/#what-lands-on-the-forge).
Any line beginning `Nit-…:` in **your** message is stripped before they are
appended.

### When something is refused

The whole push is refused. Nothing lands.

```
nit: 2 path(s) are not authorized for this user

  secrets/prod.env (write)
      refused by rule secrets-are-platform-only
      Production secrets are owned by the platform team.
  .github/workflows/ci.yml (write)
      guard: ci-configuration
      CI configuration changes the meaning of every future review.
```

Every denial carries the rule that refused it and its author's message. That is
the difference between a policy people can work with and one that produces
support tickets.

**Fail-closed is the point.** Silently dropping the refused files would publish
a commit that compiles differently from the one you tested, under your name.

### `--check`

Runs the authorization without submitting anything. Nothing is queued, nothing
is stored, no worker runs.

```
7 file(s) would be pushed, 0 refused
```

Cheap enough for a pre-commit hook, and the fastest way to find out whether a
change is going to be a problem before you build on it.

### `--drop-unauthorized`

Opt in, per push, to landing the authorized part and dropping the rest.

```
Pushed 5 file(s) to backend-api@main as 4f2a9c1b7e30
2 file(s) were dropped:
  secrets/prod.env (write not permitted)
```

Useful for a formatting sweep across a repository you partly own. Know what you
are asking for: **what lands is not what you committed**, and you will need
`nit pull` afterwards. The upstream commit records it as a `Nit-Dropped` trailer,
which is the only sign of it visible on the forge.

### After the push

```
Your change landed, but the branch has moved on. Run: nit pull
```

Either the branch moved while your task ran, or files were dropped. Your
workspace no longer matches upstream and has to resynchronize before you can
push again.

## `nit status`

```sh
nit status
```

```
repository: backend-api
branch:     main
server:     https://nit.example.com
workspace:  ws_7c1e9f2a
sync:       4f2a9c1b7e30
changes:    2841 bytes to push
            (uncommitted changes are not included)
```

`sync` is the local commit your sync point refers to — not an upstream hash;
those two universes never share one.

## `nit whoami`

```sh
nit whoami
nit whoami -server https://nit.example.com
```

```
user:   alice <alice@example.com>
groups: backend, platform
policy: sha256:f6040b6d6a8381dc
```

Inside a workspace the server is known. Outside one it is taken from `-server`,
then `$NIT_SERVER`, then your single stored credential if you have exactly one.

`policy` is the bundle version the server is enforcing — worth quoting when you
report that a rule is not behaving as you expect.

## Environment

| | |
| --- | --- |
| `NIT_SERVER` | Default server for `clone` and `whoami` |

## Files

| | |
| --- | --- |
| `~/.config/nit/credentials.json` | Tokens, keyed by server, mode 600 |
| `.nit/` in a workspace | Repository, branch, server, workspace id and sync token |

The sync token is **opaque and signed**. Editing `.nit/` does not move your sync
point; it only breaks the workspace.

## Exit codes

| | |
| --- | --- |
| `0` | Success |
| `1` | Any failure, with the reason on stderr |
| `130` | Interrupted |

## Next

- [Error codes](/reference/errors/) — what each one means and what to do.
- [Push and pull](/concepts/push-and-pull/) — what happens between the commands.
