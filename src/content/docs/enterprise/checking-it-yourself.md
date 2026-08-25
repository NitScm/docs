---
title: Checking it yourself
description: Verifying the whole archive against the key your own deployment generated — needing nothing from us but the bytes.
sidebar:
  order: 3
---

Everything the vault shows you is us describing our own archive. That is worth
something, and it is not worth much: we are the party being checked.

This is you checking it, on your machine, with a key we have never held.

## Where the key comes from

When a deployment is registered, **it generates its own key pair** and sends us
only the public half:

```
$ nitd-ee -generate-audit-key > /etc/nit/audit.key
$ chmod 600 /etc/nit/audit.key
$ cat /etc/nit/audit.key
# Keep this file. Mode 600, and never send it anywhere.
#
#   NIT_AUDIT_VAULT_KEY_FILE=/path/to/this/file
#
# Send only the public key below to whoever runs the vault. They register it and
# return an instance id for NIT_AUDIT_VAULT_INSTANCE.
#
# public key: nitv-pk-L3BXugyaq2o/IcQ9YehNjERaxnNq3XRwpS3EaUMF92s

nitv-sk-tL9s6Q6f4tHdxPjLbz9FATFRaRH6aBmCXPCzyRW45AE
```

You paste the `nitv-pk-` line into the console. The `nitv-sk-` line stays on your
machine, and there is no field anywhere in our service that could hold it.

If we generated that pair for you, we would have seen the private half, and
every claim on the previous page would rest on our word that we forgot it.

## Running the check

Create a read token on the console's **Access** screen, then:

```
$ nitd-ee -verify-audit-archive -token nitv_…
3 batch(es), 4 record(s) checked against this deployment's key
```

It reads every stored batch, verifies each signature against the key your
deployment holds, and walks the numbering for holes.

It exits non-zero if anything fails, so it belongs in a scheduled job as much as
in an auditor's hands.

## What it catches

**A record that was altered after we stored it.** Editing a stored batch — even
one character, even by somebody with database access — invalidates a signature
nobody but your deployment can produce:

```
$ nitd-ee -verify-audit-archive -token nitv_…
FAILED batch 4 received 2026-08-25T18:44:13Z
1 batch(es), 3 record(s) checked against this deployment's key
nitd-ee: 1 stored batch(es) do not verify against this deployment's key
```

**A batch that went missing.** Every batch is numbered within its sending run, so
a hole between two batches you still have is visible.

**A key we registered that you did not generate.** The check compares the public
key we report against the one derived from your own signing key, and says so:

```
1 batch(es) are attributed to a key that is not this deployment's:
  vi_b33e103000656b0a6aaaffc9 -> nitv-pk-11kDWA1WaykmQWz3mf0MfGmWBdPDEP3nn9dDwFKo0Ho

That is expected if this account has other deployments. If it does not, it means
somebody registered a key you did not generate.
```

It verifies against **your** key and never against the one we reported. Checking
a signature with a key the checked party chose proves nothing.

**A run whose beginning is missing with no deletion on record.** Retention
removes oldest first, so an archive that starts partway through is normal — but
only if a deletion actually happened. The check asks us whether one did, and a
vault covering up a loss would have to enter a deletion it never made, against a
retention policy you can read.

## Where to keep the key

It is the one secret whose disclosure would let somebody else write records in
your deployment's name.

- A file, mode 600, named by `NIT_AUDIT_VAULT_KEY_FILE`.
- Not an environment variable if you can avoid it: those are visible in
  `docker inspect`, in `ps` on some systems, and in crash reporters that dump the
  environment.
- Back it up. Losing it does not lose your archive — everything already sent
  still verifies against the public half we hold — but you cannot send more
  under that identity, and you would register a new deployment to continue.
