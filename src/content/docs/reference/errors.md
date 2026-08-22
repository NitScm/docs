---
title: Error codes
description: Every code nit can return, what it means, and what to do about it.
sidebar:
  order: 5
---

Every failure carries a stable `code` and a human `message`. **Branch on the
code; read the message.**

```json
{
  "code": "stale_sync_point",
  "message": "the workspace is behind upstream; run: nit pull"
}
```

## Authorization

### `unauthorized_paths`

**403.** The patch touches paths you may not write. **The whole push was
refused** — nothing was queued, and the forge did not move.

```
nit: 2 path(s) are not authorized for this user

  secrets/prod.env (write)
      refused by rule secrets-are-platform-only
      Production secrets are owned by the platform team.
  .github/workflows/ci.yml (write)
      guard: ci-configuration
      CI configuration changes the meaning of every future review.
```

Every problem is listed, not just the first, so you fix them in one round trip.

`rule_id` names the rule that refused; `guard` appears instead when the refusal
came from a [structural guard](/concepts/guards/). Empty means nothing matched
and the default deny applied — which is a policy gap, not a mistake on your
part.

**What to do.** Split the commit and push what you own, or ask whoever owns the
rule. `nit push --check` tells you before you build on it. Pushing anyway with
`--drop-unauthorized` lands the authorized part and drops the rest — with the
consequence that what lands is not what you committed.

### `user_not_in_policy`

**403.** Your token is valid, but the bundle in force does not declare you.

Either you were removed, or the server is serving a bundle where you do not
exist yet. Ask an operator; `nitctl policy show` settles it in a second.

### `user_disabled`

**403.** The account is disabled. Contact an administrator.

### `not_found` from an admin endpoint

**404.** Your token is valid; you are not in `server.admin_groups`.

It is a 404 rather than a 403 deliberately: the existence of an operations API
is not something an ordinary developer needs confirmed.

## Authentication

| Code | | What to do |
| --- | --- | --- |
| `no_credentials` | 401 — no `Authorization` header | `nit login <server>` |
| `malformed_credentials` | 401 — not a bearer token | `nit login <server>` |
| `invalid_token` | 401 — no such token | `nit login <server>` |
| `token_expired` | 401 — past its TTL | Ask for a new one |
| `token_revoked` | 401 — revoked by an operator | Ask why before asking for another |

## Synchronization

### `stale_sync_point`

**409.** Your workspace is behind: the branch moved since you last synchronized.

```sh
nit pull
```

Normal, in the same way a rejected `git push` is normal. It appears more often
than in plain git because a nit push is serialized per branch, so two people
working on the same branch take turns rather than racing.

### `unknown_sync_point`

**409.** The server has no sync point for this workspace, repository and branch —
so it has nothing to apply your patch onto.

A workspace that has never pulled, or one whose registration was lost. `nit pull`
if the workspace is otherwise sound; clone again if it is not.

## Queue and tasks

### `branch_busy`

**409, with `retry_after`.** Another operation holds the branch. The request was
**not** queued and can be retried unchanged.

The CLI retries for you. Seeing it repeatedly on the same branch means a worker
is stuck — [`nitctl tasks -state running`](/guides/operations/#a-branch-that-will-not-move).

### `conflict`

The patch no longer applies onto upstream. The task fails **immediately** rather
than burning its attempt budget: retrying would conflict identically.

```sh
nit pull        # resolve, then push again
```

### `task_not_ready`

**409.** You asked for a task's result before it finished. Wait for it —
`GET /v1/tasks/{id}/events` is the endpoint for that.

### `unknown_task`

**404.** No such task, or it belongs to someone else.

### `no_patch` / `patch_expired`

**404 / 410.** The task produced no patch, or the patch outlived
`storage.pull_ttl` (24 h by default). Run the pull again.

### `missing_patch`

A worker could not find the stored patch. **Almost always a configuration
error:** `nitd` and the worker have different `storage.blob_dir`.

```sh
nitctl config show | grep blob_dir      # on both hosts
```

They must point at the same storage — the same path on one host, a shared volume
across hosts.

### `malformed_task`

A worker could not decode a task payload. Not something a developer can cause;
report it with the task id.

## Payload

| Code | | |
| --- | --- | --- |
| `patch_too_large` | 413 | Over `storage.max_patch_bytes`, compressed or decompressed. Split the change, or raise the limit. |
| `digest_mismatch` | 400 | The upload does not hash to the declared digest. Retry; if it persists, something is corrupting the transfer. |
| `unknown_blob` | 400 | The referenced upload is gone. Push again. |
| `bad_request` | 400 | Malformed body, missing field, undecodable patch. The message says which. |

The size limit is enforced on the **decompressed** size too, because a
decompression bomb is small until it is not.

## Protocol

### `unsupported_version`

The client and server speak different protocol versions.

```
nit: the server speaks protocol 2, this CLI speaks 1; upgrade one of them
```

`nit login` checks this up front, so the mismatch surfaces once rather than
becoming a confusing failure three commands later.

### `unknown_repository`

The repository is not in the bundle, or you can read nothing in it. Check the
spelling against `nit clone` output or the console; if it should be there, it is
a bundle change.

## Other

| Code | | |
| --- | --- | --- |
| `unknown_user` | 404 | No such user (operations queries) |
| `unknown_workspace` | 404 | No such workspace, or not yours |
| `internal` | 500 | A bug. The response says nothing more; the server log has the detail, keyed by request id. |

An `internal` response is deliberately opaque. Internal errors leak
implementation detail — table names, paths, upstream URLs — and an authenticated
attacker reads error messages closely. The request id in the response ties it to
the full detail in the log.

## Following one failure

Give an operator your request id:

```sh
nitctl audit -request 01J8Z3Q2M7C4V9K1
```

That is the whole thread: what was asked, what was refused, which rule refused
it, and which task it became.

## Next

- [Day-to-day operations](/guides/operations/) — diagnosing these from the
  server side.
- [Authorization](/concepts/authorization/) — why a denial says what it says.
