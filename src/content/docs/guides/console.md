---
title: The web console
description: Deploying and using the read-only operations console.
sidebar:
  order: 5
---

The console shows queue depth, tasks, the audit trail and the policy bundle in
force. It is a client of the same operations API `nitctl` uses.

## It is read-only, permanently

Everything that changes authorization goes through the policy bundle — authored
in files, reviewed like code, versioned and rollbackable.

A console that could edit rules would be a second path to the same decisions with
none of those properties, and it would be *the* path people used, because it is
the convenient one.

So granting access is a pull request, not a click. That is slower on purpose.

## Deploying it

```sh
docker build -t nit-console:local nit-console
docker run -p 8090:80 -e NIT_API_URL=http://nitd:8080 nit-console:local
```

nginx proxies `/v1`, `/healthz` and `/openapi.yaml` to `NIT_API_URL`, so the
console and the API share an origin. Two consequences, both good:

- the sign-in screen's **Server** field can be left empty;
- **no CORS configuration is needed at all** — the browser never makes a
  cross-origin request.

`server.cors_origins` on the server is only for the case where the two genuinely
live on different origins: `ng serve` during development, or a console hosted
separately.

In the production Compose stack:

```sh
docker compose -f compose.base.yaml -f compose.gitea.yaml --profile console up -d
```

## Who can use it

Members of the groups in `server.admin_groups`. Everyone else signs in
successfully — their token is valid — and every page reports "not found".

That is a 404 rather than a 403, deliberately: the existence of an operations API
is not something an ordinary developer needs confirmed.

```sh
nitctl token create -user alice -label console
```

## What is on each screen

### Overview

Queue depth, busy branches, task counts by state, and denials over the last day.

Only two of those numbers mean something is wrong *right now*: **queued** and
**branches busy**. A tile takes colour only when its number needs attention — a
dashboard where everything is coloured says nothing.

**Denials, 24h** is the one to watch over time. A number that climbs is usually
not an attack; it is the policy fighting the team, and a sign that some subtree's
ownership no longer matches who works on it.

### Tasks

Filterable by state, kind and repository. Each row carries the owner, the attempt
count and the lease holder, because the operator's question is not "did my push
land?" but "why is this branch stuck?".

A task's detail page shows the **raw spec the worker was given** and what it
reported — which is how you tell "nit decided something surprising" from "the
forge did something surprising" — plus the audit records for that operation.

### Audit

Who did what, when, and under which rule. Filter by user, repository, request id
or time window, and narrow to denials only.

Every record links to the task it belongs to: that is the path an investigation
actually walks.

### Policy

The compiled bundle rendered as a table, so nobody has to read YAML on a server:
repositories, their remotes, and every rule with its subject, exemptions, paths,
refs, actions and description.

Useful for answering "what does the deployment actually think the rules are?"
during a rolling deploy, when two replicas might be serving different versions.

## Security notes

**The token is kept in `localStorage`.** A bounded, deliberate choice — the
console is an internal tool and the API it reads is read-only — but it means any
script running on that origin can read it. The console therefore loads **nothing
from anywhere else**: no CDN, no analytics, no fonts. Its Content-Security-Policy
enforces that, and you should not relax it.

**Serve it over TLS**, same as the API.

**It is not a public surface.** Bind it to your internal network or put it behind
whatever you use for internal tools.

## Development

```sh
cd nit-console
pnpm install
pnpm start                # http://localhost:4200
```

The dev server proxies `/v1` and `/healthz` to `http://localhost:8080`, so the
front end and the API share an origin exactly as they do in production.

If you point it at a server on another host, that host needs your origin in
`server.cors_origins`:

```yaml
server:
  cors_origins: ["http://localhost:4200"]
```

## Next

- [Day-to-day operations](/guides/operations/) — the same data from `nitctl`.
- [The HTTP API](/reference/api/) — what the console calls.
