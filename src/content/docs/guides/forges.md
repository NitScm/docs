---
title: Connecting a forge
description: GitHub, GitLab, Gitea — and the three things that have to be true whichever one you use.
sidebar:
  order: 4
---

nit's git operations are plain **clone, fetch and push**. Any remote git can
already talk to works: GitHub, GitLab, Gitea, Bitbucket, Azure DevOps, Gerrit, or
a bare repository over SSH.

## The three things that have to be true

Before any of the per-forge detail, this. **nit's guarantees end the moment a
developer can push to the same branch directly.**

1. **nit's machine account is the only writer.** Everyone else gets read access
   at most.
2. **The branches nit manages are protected**, with that account as the only
   permitted pusher.
3. **The repository is private.** nit hides files *inside* a repository; it
   cannot hide a public one.

Without those, a developer who wants a file they may not read simply clones it
from the forge, and nit has authorized nothing.

:::danger[This is not optional]
It is the assumption everything else rests on. If you cannot make nit the only
writer, nit is not the right tool for that repository.
:::

## In the bundle

```yaml title="policy/repositories.yaml"
- id: backend-api
  remote: https://github.com/acme/backend-api.git
  forge: github
  default_branch: main
```

`forge` selects a driver. An unrecognized value falls back to the **generic**
driver, which:

- injects the token into an `https://` remote as HTTP basic auth;
- leaves `ssh://` and local paths alone, so git resolves the credential from its
  own configuration.

A specific driver only becomes worth writing for the shortcuts — reading a branch
tip without cloning, opening a merge request — and neither is needed for push and
pull to work.

## GitHub

Cloud or Enterprise; only the remote host differs.

```yaml
- id: backend-api
  remote: https://github.com/acme/backend-api.git
  forge: github
  default_branch: main
```

**The credential.** A fine-grained personal access token, a GitHub App
installation token, or a machine user's classic token with `repo` scope. Scope it
to exactly the repositories in the bundle.

**Locking the repository down:**

1. Settings → Collaborators: nit's machine account gets **Write**; developers get
   **Read** at most.
2. Settings → Branches → add a rule for the branches nit manages. Enable
   *Restrict who can push* and list only the machine account.
3. Settings → General: the repository is **Private**.

:::caution[Watch for the ways around it]
GitHub Actions with `contents: write`, deploy keys with write access, and admins
who can bypass branch protection are all doors past nit. Audit them the same way
you audit collaborators.
:::

```sh
docker compose -f compose.base.yaml -f compose.github.yaml up -d
```

## GitLab

```yaml
- id: backend-api
  remote: https://gitlab.com/acme/backend-api.git
  forge: gitlab
  default_branch: main
```

**The credential.** A project or group access token with `write_repository`, or a
deploy token. Not a person's token: it should cover exactly the repositories in
the bundle, and it should not stop working when someone leaves.

**Locking the project down:**

1. The machine account has **Maintainer** (or Developer with push rights);
   everyone else has at most **Reporter**.
2. Settings → Repository → Protected branches: only that account may push.
3. The project is **Private**.

```sh
docker compose -f compose.base.yaml -f compose.gitlab.yaml up -d
```

## Gitea

Gitea can run inside the same stack, which is what the development environment
does. Then nit reaches it over the compose network and it never has to be exposed
for nit to work:

```yaml
- id: backend-api
  remote: http://gitea:3000/acme/backend-api.git
  forge: gitea
  default_branch: main
```

**The credential.** An access token with `write:repository`, from the machine
account's Settings → Applications → Generate Token.

**Locking it down:** close registration, give the machine account write on the
repository and everyone else read, and protect the branches nit manages.

```sh
docker compose -f compose.base.yaml -f compose.gitea.yaml up -d
```

## Anything else

Copy the GitLab overlay, change the comment, set the token. That is the whole
adaptation — the generic driver handles the rest.

### SSH remotes

```yaml
- id: backend-api
  remote: ssh://git@git.example.com/acme/backend-api.git
  forge: generic
```

Leave `forge.token` empty and give git its configuration instead:

```yaml title="nit.yaml"
git:
  ssh_command: >-
    ssh -i /run/secrets/nit-ssh-key
    -o IdentitiesOnly=yes
    -o UserKnownHostsFile=/etc/nit/ssh/known_hosts
    -o StrictHostKeyChecking=yes
    -o BatchMode=yes
```

`known_hosts` is not optional. Without it git cannot verify the host, and a
worker that accepts any host key will happily push your repository to whoever
answers.

[The worked example](/guides/example-github-ssh/) walks the whole thing through
against GitHub, with a validation dataset.

### A local path

Useful for testing. git treats a bare repository on disk exactly as it treats a
remote:

```yaml
- id: backend-api
  remote: /srv/git/backend-api.git
  forge: generic
```

## Verifying a connection

```sh
nitctl policy validate ./policy       # the remote is well-formed
nitctl tasks -limit 5                 # push something and watch it land
nitctl audit -limit 5
```

If a push reaches the worker and fails, the task detail carries the reason:

```sh
nitctl tasks -state failed -json
```

A clone failure deliberately reports only the branch it was cloning, without the
underlying git message — because the authenticated remote is a credential and git
quotes the URL it was given.

To see more, raise the log level on the worker and look at its own output:

```sh
NIT_LOG_LEVEL=debug nit-worker
```

## Next

- [Going to production](/guides/production/) — topologies and the security
  checklist.
- [Running workers](/guides/workers/) — sizing and scaling.
