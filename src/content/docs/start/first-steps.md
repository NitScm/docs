---
title: Your first workspace
description: Log in, clone a filtered projection, change something, push it — and watch a push be refused.
sidebar:
  order: 3
---

This walks a developer through a full cycle. It assumes the
[development stack](/start/install/) is running and you have **bob's** token —
he owns `src/server` and `docs`, and cannot read `secrets/`.

## 1. Log in

```sh
nit login http://localhost:8080
# Token for http://localhost:8080: nit_…
```

```
Logged in to http://localhost:8080 as bob
Credential stored in /home/you/.nit/credentials.json
```

The token is verified before it is stored. A credential that does not work fails
here, not three commands later on an unrelated screen.

The file is mode `600` and keyed by server, so one machine can talk to a staging
and a production deployment without the tokens overwriting each other.

## 2. Clone

```sh
nit clone backend-api
```

```
  registering the workspace
  waiting for the server to prepare the changes
  downloading 273 bytes
Cloned backend-api into /home/you/backend-api
3 file(s) updated
2 file(s) withheld by policy
```

Two files were withheld. Look at what actually arrived:

```sh
cd backend-api
find . -type f -not -path './.git/*' -not -path './.nit/*'
```

```
./docs/readme.md
./src/server/api.go
./src/ui/app.ts
```

```sh
ls secrets
# ls: cannot access 'secrets': No such file or directory
```

**This is the whole point.** `secrets/` is not encrypted, not greyed out, not
permission-denied. It is not there. There is nothing on this disk to leak.

:::note[Why is the count reported but not the names?]
Naming the withheld files would leak the structure the read rules exist to hide.
The count is reported at all because a developer who does not know something was
withheld will mistake a missing file for a deleted one.
:::

### What the clone left behind

It is an ordinary git repository with one commit:

```sh
git log -1 --format='%s%n%b'
```

```
nit: sync backend-api@main

Nit-Upstream-Commit: 5e0deb3c78c35440c00a4978483da66fd5219f7f
Nit-Policy-Version: sha256:f6040b6d6a8381dc
Nit-Workspace: f9e428ab-3a8d-42c8-a2d7-6ef5a0ac61bc
```

That commit is your **sync point**: the upstream commit whose projection you are
holding. The trailers make it recoverable from git history alone, which survives
a deleted `.nit/state.json`.

## 3. Change something and push

Work normally. Commit normally.

```sh
echo '// reviewed' >> src/server/api.go
git commit -am 'annotate the handler'
```

Check what would happen before committing to it:

```sh
nit push --check
```

```
  uploading 164 bytes
1 file(s) would be pushed, 0 refused
```

`--check` runs the authorization and queues nothing. The forge does not move.
Now push for real:

```sh
nit push -m 'annotate the handler'
```

```
  uploading 164 bytes
  running
Pushed 1 file(s) to backend-api@main as 978464d55d39
```

The commit that landed upstream is authored by **bob**, from the authenticated
session — not from anything the client claimed. The author field of a git commit
is free text, and a system that trusted it would let anyone attribute a change to
a colleague.

:::tip[nit pushes commits, not your working tree]
Like `git push`. Uncommitted changes are not included, and nit says so rather
than leaving you to wonder where your change went.
:::

## 4. Try what you may not do

```sh
mkdir -p secrets && echo 'TOKEN=stolen' > secrets/prod.env
git add -A && git commit -m 'take a secret'

nit push -m 'should not land'
```

```
nit: the patch touches paths you may not change

  secrets/prod.env (create)
      refused by rule secrets-are-platform-only
      Production secrets are owned by the platform team.
```

Exit status is 1, the forge did not move, and nothing was queued — so the refusal
cost no clone on the server.

Note what the message contains: the path, the action it needed, **the rule that
refused it**, and that rule's own message to you. A denial nobody can act on
becomes a support ticket, so rules carry a `description` and nit shows it.

Undo the attempt:

```sh
git reset --hard HEAD~1
```

## 5. Pull a colleague's work

Someone else changes `docs/readme.md` and rotates `secrets/prod.env`.

```sh
nit pull
```

```
  waiting for the server to prepare the changes
  downloading 173 bytes
Updated backend-api@main to 81d30159ee92
1 file(s) updated
1 file(s) withheld by policy
```

The readable change arrived. The confidential one did not — and still is not on
your disk.

:::note[Pull is rebase, not merge]
If you have local commits, nit applies the incoming patch to your sync commit and
**replays your commits on top**, exactly as `git pull --rebase` does. A local
commit whose change already landed upstream — which is what happens after a push
the server rebased — is recognized as already applied and dropped, instead of
conflicting with itself.

A pull refuses to run against a dirty working tree, for the same reason git does.
:::

## 6. Know where you are

```sh
nit status
```

```
repository: backend-api
branch:     main
server:     http://localhost:8080
workspace:  f9e428ab-3a8d-42c8-a2d7-6ef5a0ac61bc
sync:       190e4b2fec37
changes:    nothing to push
```

## Two messages you will meet

**"Your change landed, but the branch has moved on. Run: nit pull"**

Your push succeeded. But something else landed while it was queued and your
change was rebased onto it, so your workspace no longer matches upstream — it is
missing a colleague's commit. This is a normal outcome, not an error. Pull, and
carry on.

**`stale_sync_point` — "your workspace is behind; run: nit pull"**

You are pushing from a base your workspace has moved off. Pull first.

## Next

- [Filtered projections](/concepts/filtered-projections/) — why any of this
  works the way it does.
- [Your first policy](/start/first-policy/) — write the rules yourself.
- [nit — the developer CLI](/reference/nit/) — every command and flag.
