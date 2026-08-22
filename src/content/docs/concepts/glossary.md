---
title: Glossary
description: Every term nit uses, defined once.
sidebar:
  order: 6
---

## Core ideas

**Filtered projection**
: A developer's checkout: the files they may read, and nothing else. Because
files are missing, its trees and commit hashes differ from upstream and exist
nowhere on the forge. See
[Filtered projections](/concepts/filtered-projections/).

**Sync point**
: The upstream commit whose filtered projection produced a workspace's current
state. Recorded per `(workspace, repository, branch)`. Every exchange is
expressed relative to it, never relative to a local commit hash.

**Sync token**
: The opaque, signed handle a client holds for its sync point. Store it, send it
back, never parse it. The signature is what stops a client claiming a base it was
never given.

**Workspace**
: One checkout on one machine. It is the key of a sync point, which is why a
laptop and a desktop get one each — they genuinely are at different points.

**Policy bundle**
: The directory of YAML files where all authorization lives: users, groups,
repositories and rules. Versioned in git, reviewed like code, identified by a
content hash.

**Policy version**
: A SHA-256 over the whole bundle, stamped on every decision and every audit
record. It is what lets a past decision be replayed against exactly the rules
that produced it.

## Authorization

**Subject**
: The principal a rule applies to: a user, a group, or `any`. Resolved from the
authenticated session, with group membership expanded transitively.

**Rule**
: A grant or a refusal: a subject, some path patterns, optional ref patterns,
some actions, and an effect.

**Effect**
: `allow` or `deny`. Deny always wins, and anything unmatched is denied.

**`except`**
: Subjects carved out of a rule's subject. The only way to write an exemption to
a universal deny, because an allow rule would be swallowed by the deny.

**Action**
: `read`, `write`, `create`, `delete` or `admin`. See
[the authorization model](/concepts/authorization/).

**Subtree pattern**
: A path pattern ending in `/`, covering the directory entry itself and
everything under it. `secrets/`.

**Guard**
: A protection that path rules cannot express: CI definitions, `.gitattributes`,
`.gitmodules`, symlink creation, submodule pointers. Each requires the `admin`
action on top of ordinary write permission. See [Guards](/concepts/guards/).

**Protected path**
: A path a guard covers by default. The full list is
`enforce.DefaultProtectedPaths`.

## Operations

**Control plane**
: `nitd`. Owns the API, authorization, sync points, the queue, the blob store and
the audit log. Performs no git operation.

**Worker**
: `nit-worker`. Clones, applies patches, filters diffs and pushes to the forge.

**Task**
: One queued unit of work — a push or a pull. States: `queued`, `running`,
`succeeded`, `failed`, `cancelled`.

**Partition key**
: `repository:branch` for a push; empty for a pull. At most one task per non-empty
key runs at a time, which is what serializes a branch.

**Lease**
: A worker's exclusive, time-limited claim on a task, kept alive by a heartbeat.
It lapses if the worker dies, so a crash cannot strand a branch.

**Fencing token**
: The value a worker must present on every state transition. It stops a worker
whose lease expired from completing a task another worker now owns.

**Reaper**
: The loop that returns tasks with lapsed leases to the queue.

**Request id**
: A client-generated identifier that makes a submission idempotent. A retry
carrying the same id returns the original task rather than creating a second
upstream commit.

**Artifact**
: A stored patch — uploaded for a push, or generated for a pull. Content
addressed; pull artifacts have a TTL.

**Blob store**
: Where artifacts live. Must be shared between `nitd` and every worker.

## Deployment

**Forge**
: The git hosting provider: GitHub, GitLab, Gitea, or any remote git can talk to.
nit is the only account that writes to the repositories it manages.

**Forge token**
: The credential a worker pushes with. A machine identity, not a person's.

**Operations API**
: `/v1/admin/*`. Read-only, restricted to the groups in `NIT_ADMIN_GROUPS`.
`nitctl` and the web console are both clients of it.

**Admin group**
: A group whose members may read the operations API. Named in server
configuration rather than in the bundle, so a bad bundle cannot lock an operator
out of the tool for diagnosing it.

## Things that are *not* nit terms

**Repository**
: Used in the ordinary git sense. In the bundle it has an `id` that nit uses
internally and a `remote` that is the real clone URL.

**Branch**
: Ordinary git branch. Rules can be scoped to refs.

**Patch**
: Ordinary unified diff, as `git diff` produces. nit parses it into sections and
re-emits the original bytes of the ones that survive filtering, so a rewritten
patch differs from the author's only by the removal of whole files.
