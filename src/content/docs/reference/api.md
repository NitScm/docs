---
title: The HTTP API
description: Endpoints, authentication, and the OpenAPI description the server serves about itself.
sidebar:
  order: 4
---

Every deployment serves its own machine-readable description:

```sh
curl https://nit.example.com/openapi.yaml
```

That is an OpenAPI 3.0.3 document, embedded in the binary and served
unauthenticated. Point Swagger UI, Redoc or a client generator at it. It is the
authority; this page is the orientation.

:::tip[It cannot drift]
A test walks every route the server registers and fails if the spec does not
describe it, and walks every path in the spec and fails if no route serves it.
A documented API that has quietly stopped matching the server is worse than none.
:::

## Two surfaces

**The developer API** — `/v1/push`, `/v1/pull`, `/v1/tasks/…` — is what the
`nit` CLI speaks.

**The operations API** — `/v1/admin/…` — is what `nitctl` and the console read.
It is **read-only, permanently**: everything that changes authorization goes
through the policy bundle. It is restricted to `server.admin_groups`, and
everyone else gets **404**, not 403.

## Authentication

```http
Authorization: Bearer nit_…
```

Every endpoint except `/healthz` and `/openapi.yaml`. Tokens are issued with
[`nitctl token create`](/reference/nitctl/#nitctl-token) and stored only as
SHA-256.

**Identity comes from the token, never from the request.** The patch's `From:`
line is sender-controlled and is ignored: what lands upstream is authored by the
authenticated user.

## Errors

Every non-2xx response carries the same body:

```json
{
  "code": "unauthorized_paths",
  "message": "2 path(s) are not authorized for this user",
  "denials": [
    {
      "path": "secrets/prod.env",
      "action": "write",
      "rule_id": "secrets-are-platform-only",
      "reason": "write not permitted",
      "description": "Production secrets are owned by the platform team."
    }
  ]
}
```

**Branch on `code`, never on `message`.** `code` is stable; `message` is for
people. `retry_after` appears when the request may succeed later unchanged.

See [Error codes](/reference/errors/) for the full list.

## Meta

| | |
| --- | --- |
| `GET /healthz` | Liveness. Unauthenticated — a load balancer has no token. Reports the protocol version and the policy version in force. |
| `GET /openapi.yaml` | This description. Unauthenticated. |
| `GET /v1/whoami` | The authenticated identity: user, email, groups, policy version. |
| `GET /v1/repositories` | Repositories the caller can read something in. |
| `GET /v1/workspaces` | The caller's workspaces. |
| `POST /v1/workspaces` | Register a checkout. |

`/healthz` reporting the policy version is what lets you compare replicas during
a rolling deploy.

`/v1/repositories` lists what the caller can read *something* in — not the whole
bundle. A repository they can read nothing in does not exist, as far as they are
concerned.

## Pushing

```
POST /v1/blobs      upload the compressed patch
POST /v1/push       submit it
GET  /v1/tasks/{id} poll, or:
GET  /v1/tasks/{id}/events   long poll until it finishes
```

The patch goes up **separately** from the decision. `/v1/blobs` takes the zstd
stream and returns a handle; `/v1/push` references that handle. Authorization
therefore runs on a body the server already holds, and a retry does not
re-upload megabytes.

`/v1/push` responds **before** anything reaches the forge:

- **`202`** — authorized, queued. The body carries the task id.
- **`403 unauthorized_paths`** — refused, with every denial. Nothing was queued;
  the forge did not move.
- **`409 branch_busy`** — another operation holds the branch, with
  `retry_after`.

The whole push is refused or the whole push lands. There is no partial state,
unless the client explicitly asked for `drop_unauthorized`.

## Pulling

```
POST /v1/pull                request the upstream diff
GET  /v1/tasks/{id}/events   wait
GET  /v1/tasks/{id}/patch    download the filtered patch
```

The response reports a **count** of withheld files and never their paths. Naming
them would leak the structure the read rules exist to hide.

A generated patch stays fetchable for `storage.pull_ttl` (24 h by default), then
`410 patch_expired`.

## Sync tokens

Every push and pull carries an opaque, HMAC-signed **sync token**.

A developer's workspace is a *filtered projection*: files they may not read are
absent, so its trees and commit hashes differ from upstream and a local hash
exists nowhere on the forge. The server therefore records which upstream commit
produced a workspace's current state and hands back a token for it.

The client stores it and returns it verbatim. It is not a commit id; it is not
parseable; **the signature is what stops a client naming a base of its choosing**
and having its patch applied there.

Two codes concern it:

| | |
| --- | --- |
| `stale_sync_point` | The workspace is behind. Pull. |
| `unknown_sync_point` | No sync point at all. Clone. |

## Long polling

```
GET /v1/tasks/{id}/events
```

Held open until the task finishes or `server.event_max_wait` elapses (30 s by
default), then answered anyway so the client reconnects.

If you put a proxy in front of `nitd`, set `event_max_wait` **below** its idle
timeout — otherwise the proxy severs exactly the request that is working
correctly.

## Operations

| | |
| --- | --- |
| `GET /v1/admin/stats` | Queue depth, task counts, busy branches, recent denials |
| `GET /v1/admin/tasks` | List tasks — `state`, `kind`, `repository`, `limit` |
| `GET /v1/admin/tasks/{id}` | One task, **with the spec its worker was given** |
| `GET /v1/admin/audit` | Who did what, when, under which rule |
| `GET /v1/admin/policy` | The compiled bundle in force |

`/v1/admin/tasks/{id}` returning the raw spec is what lets an operator tell "nit
decided something surprising" from "the forge did something surprising".

`/v1/admin/audit` accepts `user`, `repository`, `request_id`, `since`, `until`
and `limit`. `request_id` is the one that follows a single operation end to end.

## Versioning

```json
{"protocol_version": "1", "policy_version": "sha256:f6040b6d6a8381dc"}
```

`nit login` checks the protocol version and says plainly which side to upgrade,
rather than letting the mismatch become a confusing failure three commands
later.

## Trying it

```sh
export NIT_TOKEN=nit_…

curl -s localhost:8080/healthz | jq
curl -s -H "Authorization: Bearer $NIT_TOKEN" localhost:8080/v1/whoami | jq
curl -s -H "Authorization: Bearer $NIT_TOKEN" localhost:8080/v1/admin/stats | jq
```

To browse it:

```sh
docker run --rm -p 8081:8080 \
  -e SWAGGER_JSON_URL=http://localhost:8080/openapi.yaml \
  swaggerapi/swagger-ui
```

## Next

- [Error codes](/reference/errors/) — every `code` and what to do about it.
- [Push and pull](/concepts/push-and-pull/) — what these calls mean.
