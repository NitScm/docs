---
title: Running it at scale
description: Object storage instead of a shared disk, one projection cache across the fleet, and group membership from your own directory.
sidebar:
  order: 6
---

None of this is a feature you demonstrate to anybody. It is the difference
between a deployment that holds and one that does not, and it matters at a size
the free edition was not built for.

Everything here is off unless you turn it on. With nothing set, the commercial
binaries assemble exactly what the free ones assemble — which is what makes
removing the licence a matter of swapping a binary back. Features go, data does
not.

## Object storage instead of a shared disk

The control plane writes an authorized patch and a worker reads it back. In the
free edition that is a directory both can see — a shared volume, or NFS.

That works, and it is a single point of failure with a filesystem's semantics.
Point the deployment at S3-compatible storage instead:

```
NIT_S3_BUCKET=nit-blobs
NIT_S3_ENDPOINT=https://s3.eu-west-1.amazonaws.com
NIT_S3_REGION=eu-west-1
```

Credentials are optional. Unset, the AWS SDK's own chain applies — environment,
shared config, instance role. **Prefer a role**: a role has no secret to leak.

It works with MinIO, Ceph and Garage as well as AWS. Set `NIT_S3_PATH_STYLE=true`
for an endpoint that is an IP address or does not do virtual-host buckets.

We never create the bucket. A bucket has a lifecycle policy and an access policy
that belong to whoever runs the storage, and a service that made one for you
would be making those decisions on your behalf.

**Both are supported, permanently.** A customer without object storage is not
running a degraded configuration — the directory is a first-class choice, and
the conformance suite that proves one correct is the one that proves the other.

## One projection cache across the fleet

When five hundred developers pull after a release, the same filtered view is
computed over and over.

The free edition caches per process, which already collapses that: the pull
requests arrive within minutes, on the same handful of workers. Set
`NIT_PULL_CACHE=shared` where that stops being true — workers that come and go,
where "the same handful" is neither.

It shares the database your deployment already has, and stores only descriptors.
The patches themselves stay wherever you put them, so it works identically over a
mounted directory and over object storage.

One table, created by `nitd-ee -init-schema`. A migration stays a step an
operator takes, in both editions.

## Group membership from your directory

Your policy bundle names groups: *the platform team owns secrets*. In the free
edition, who is in that group is a list in a YAML file, maintained by hand.

The commercial edition reads membership from your directory instead. **The rules
stay in git** — authored in files, reviewed like code, versioned and
rollbackable. Only the answer to *who is in this group* comes from elsewhere.

That split is deliberate. A rule that lived in a directory would be a rule
changed by somebody clicking a checkbox, with no review and no history. What you
gain is that the day somebody leaves, they leave — rather than staying in a file
until a person remembers.

:::caution[Not available yet]
The mechanism is written and tested. The connectors — Okta, Entra, Active
Directory — are not: each needs a real directory to verify against, and we will
not ship one we have only read the documentation for.

If you have a directory and want this, talk to us; building it against yours is
how it gets built correctly.
:::

## What we have not built

Said here rather than left to be discovered:

- **Directory connectors**, above.
- **A hosted control plane.** Today you run the deployment and we hold the audit
  trail. Splitting the control plane so that we run part of it is a larger piece
  of work and a different set of trade-offs.
- **Exports into a SIEM from our side.** Your deployment can send to one
  directly — `audit.Sink` is a public interface in the free edition and always
  has been. What we have not written is us forwarding on your behalf.
