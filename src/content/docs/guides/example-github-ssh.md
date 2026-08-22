---
title: "Worked example: GitHub over SSH"
description: A complete project — machine account, host keys, workers, policy bundle — with a validation dataset that proves the rules do what they claim.
sidebar:
  order: 8
---

One repository on github.com, reached over SSH. Three developers with
deliberately different access. Two workers. And a validation dataset you can run
before anyone depends on it.

Every file below also ships in the repository under
[`examples/github-ssh/`](https://github.com/NitScm/nit/tree/main/examples/github-ssh),
so you can copy the directory rather than the code blocks.

## What this builds

`acme/payments` is a private repository containing a payments service. Three
people work on it:

| | Group | Owns |
| --- | --- | --- |
| **maya** | `api`, `engineering` | `src/api/` |
| **raj** | `ledger`, `engineering` | `src/ledger/` |
| **nadia** | `platform`, `engineering` | Everything, including credentials and CI |

Everyone reads `src/`, `docs/` and `go.mod`. Nobody except nadia reads
`secrets/` or `deploy/terraform/` — those files are not merely unwritable, they
are **absent from maya's and raj's clones**.

nit is the only writer of `main`. Everyone pushes through it.

## Why SSH changes so little

nit's git operations are plain clone, fetch and push, and for an `ssh://` remote
the forge driver **returns the URL untouched** — git resolves the credential
from its own configuration, exactly as it would for a developer.

So nit does not manage keys. There is no `ssh_key` setting and no `known_hosts`
setting — those are git's and OpenSSH's business. What nit does offer is
`git.ssh_command`, a passthrough that hands git the whole `GIT_SSH_COMMAND`, so
a deployment can keep its configuration in one file instead of splitting it
between `nit.yaml` and a systemd `Environment=` line.

:::note[There is no GitHub-specific driver yet]
`forge: github` currently resolves to the generic driver, which is enough for
the whole push and pull cycle. A specific driver only buys the shortcuts —
reading a branch tip without cloning, opening a pull request — and neither is
needed here. Declaring `github` costs nothing and is right the day one exists.
:::

---

## 1. The machine account and its key

nit pushes as one machine identity. Not a person's account: it should cover
exactly the repositories in the bundle, and it should not stop working the day
someone leaves.

```sh
ssh-keygen -t ed25519 -N '' -C 'nit@acme' -f ./secrets/id_ed25519
chmod 400 ./secrets/id_ed25519
```

`-N ''` is not laziness. The worker runs git with `GIT_TERMINAL_PROMPT=0`, so a
passphrase prompt becomes an error rather than a worker hanging with a branch
leased until its lease expires. If your policy requires a passphrase, run an
agent and give the worker `SSH_AUTH_SOCK` instead — but not a bare encrypted key.

Then register the **public** half on GitHub, one of two ways:

**A deploy key on the repository** — Settings → Deploy keys → *Add deploy key*,
with **Allow write access** ticked. Tightest scope: it works on this repository
and nowhere else. One key per repository.

**A machine user's account key** — a real GitHub account added as a collaborator
with **Write**. One key for many repositories, at the cost of an account that
must be managed like any other.

Start with deploy keys and move to a machine user when the count annoys you.

## 2. Host keys, which are not optional

```sh
ssh-keyscan github.com > known_hosts
ssh-keygen -lf known_hosts
```

Now **compare that output against the fingerprints GitHub publishes** (Docs →
Authentication → *GitHub's SSH key fingerprints*). `ssh-keyscan` trusts whatever
answers it, so accepting its output unchecked reproduces exactly the
machine-in-the-middle you are guarding against. It is a thirty-second step,
once.

A worker without a verified `known_hosts` and with host key checking relaxed
will happily push your repository to whoever answers on port 22.

## 3. Locking the repository down

nit's guarantees end the moment a developer can push to `main` directly.

1. **Settings → Collaborators** — the machine account (or the deploy key) has
   **Write**. maya, raj and nadia have **Read** at most.
2. **Settings → Branches → Add rule** for `main`: enable *Restrict who can push*
   and list only nit's identity.
3. **Settings → General** — the repository is **Private**. nit hides files
   *inside* a repository; it cannot hide a public one.

:::danger[Audit the ways around it]
A GitHub Actions workflow with `contents: write`, another deploy key with write
access, and admins who can bypass branch protection are all doors past nit.
They matter as much as the collaborator list.
:::

## 4. The dataset

Seed the repository with a tree that exercises every rule:

```sh
git clone git@github.com:acme/payments.git && cd payments

mkdir -p src/api src/ledger docs deploy/terraform secrets .github/workflows

cat > src/api/handlers.go      <<< 'package api // HTTP surface'
cat > src/api/routes.go        <<< 'package api // routing table'
cat > src/ledger/posting.go    <<< 'package ledger // double-entry posting'
cat > src/ledger/reconcile.go  <<< 'package ledger // daily reconciliation'
cat > docs/architecture.md     <<< '# Architecture'
cat > docs/runbook.md          <<< '# Runbook'
cat > deploy/terraform/main.tf <<< '# production infrastructure'
cat > secrets/stripe.env       <<< 'STRIPE_SECRET_KEY=sk_live_do_not_share'
cat > secrets/hsm-pin.txt      <<< '000000'
cat > go.mod                   <<< 'module github.com/acme/payments'
cat > .gitattributes           <<< '* text=auto'
cat > .github/workflows/ci.yml <<< 'name: ci'

git add -A && git commit -m "seed" && git push
```

Twelve files across six areas. Each one is there to make a specific rule
observable: `secrets/` proves read filtering, `.github/` proves the CI guard,
`src/ledger/` proves that read and write are different questions.

## 5. The policy bundle

Four files. Keep them in their own git repository, reviewed like code.

```yaml title="policy/users.yaml"
- id: maya
  email: maya@acme.example
  forge_logins:
    github: maya-acme

- id: raj
  email: raj@acme.example
  forge_logins:
    github: raj-acme

- id: nadia
  email: nadia@acme.example
  forge_logins:
    github: nadia-acme
```

```yaml title="policy/groups.yaml"
- id: engineering
  description: Everyone who writes code here
  members: [maya, raj, nadia]

- id: api
  description: Owns the HTTP surface
  members: [maya]

- id: ledger
  description: Owns double-entry posting and reconciliation
  members: [raj]

- id: platform
  description: Owns deployment, CI and payment credentials
  members: [nadia]
```

```yaml title="policy/repositories.yaml"
- id: payments
  remote: ssh://git@github.com/acme/payments.git
  forge: github
  default_branch: main
```

The `ssh://` form is what tells the driver to leave the URL alone. The scp-like
shorthand `git@github.com:acme/payments.git` also works, since it never matches
the `http://` or `https://` prefixes the driver injects into — but write the
explicit URL, because it says what it means.

```yaml title="policy/repositories/payments/rules.yaml"
- id: engineering-reads-the-codebase
  subject: { type: group, id: engineering }
  paths: [src/, docs/, go.mod]
  actions: [read]
  effect: allow

- id: api-team-owns-the-api
  subject: { type: group, id: api }
  paths: [src/api/]
  actions: [read, write, create, delete]
  effect: allow
  description: The API team owns src/api.

- id: ledger-team-owns-the-ledger
  subject: { type: group, id: ledger }
  paths: [src/ledger/]
  actions: [read, write, create, delete]
  effect: allow
  description: The ledger team owns src/ledger.

- id: the-ledger-is-owned-by-its-team
  subject: { type: any }
  except:
    - { type: group, id: ledger }
    - { type: group, id: platform }
  paths: [src/ledger/]
  actions: [write, create, delete]
  effect: deny
  description: >-
    Posting and reconciliation are owned by the ledger team. Read the code
    freely; open a pull request in #payments-ledger to change it.

- id: engineering-improves-the-docs
  subject: { type: group, id: engineering }
  paths: [docs/]
  actions: [read, write, create]
  effect: allow

- id: platform-owns-the-repository
  subject: { type: group, id: platform }
  paths: ["**"]
  actions: [read, write, create, delete, admin]
  effect: allow

- id: credentials-are-platform-only
  subject: { type: any }
  except:
    - { type: group, id: platform }
  paths: [secrets/, deploy/terraform/]
  actions: [read, write, create, delete, admin]
  effect: deny
  description: >-
    Payment credentials and production infrastructure are held by the platform
    team. Open a request in #payments-platform to have a change applied.
```

Four things to notice.

**The exemption is `except`, not a competing allow.** Deny always wins, so an
allow for the platform team would be swallowed by this deny. `platform-owns-the-repository`
grants them access; `except` is what stops the deny reaching them.

**`the-ledger-is-owned-by-its-team` is redundant — deliberately.** Nothing grants
maya write on `src/ledger/`, so the default deny already refuses her. But a
default deny has no rule and no message, and all she would be told is *not
authorized*. The explicit rule is what turns that into a sentence she can act
on. Write one wherever people will plausibly bump into a boundary.

**`admin` matters.** The CI guard requires it, so without
`platform-owns-the-repository` granting `admin`, *nobody* could ever change
`.github/workflows/ci.yml` — including the people who are supposed to.

**Every rule carries a `description` where a denial is likely.** It is printed to
the developer who was refused. A denial nobody can act on becomes a support
ticket.

```sh
nitctl policy validate ./policy
```

```
bundle ok
  version:      sha256:1e9b72f6feb474a1
  repositories: 1
```

## 6. The workers

```yaml title="nit.yaml"
database:
  url_file: /run/secrets/nit-database-url

policy:
  dir: /etc/nit/policy
  reload: 30s

storage:
  blob_dir: /var/lib/nit/blobs
  work_dir: /var/lib/nit/work

security:
  sync_key_file: /run/secrets/nit-sync-key

queue:
  lease_duration: 5m
  max_attempts: 3

git:
  ssh_command: >-
    ssh -i /run/secrets/nit-ssh-key
    -o IdentitiesOnly=yes
    -o UserKnownHostsFile=/etc/nit/ssh/known_hosts
    -o StrictHostKeyChecking=yes
    -o BatchMode=yes

log:
  level: info
```

`forge.token` stays unset: it is the HTTPS credential, the SSH key does that job
here, and an unused secret is one more thing to rotate.

`blob_dir` **must be the same storage `nitd` writes to.** `nitd` stores the
authorized patch and the worker reads it back; two separate directories produce
`missing_patch` on every push. Across hosts that means a shared volume.

`lease_duration: 5m` because the lease has to survive a clone. Too short and a
large repository loses its task mid-flight, forever; too long and a crashed
worker blocks its branch for that long.

### Mounting the key

The command itself is already in `nit.yaml` above; compose only has to deliver
the files it names.

```yaml title="compose.yaml"
services:
  worker:
    volumes:
      - ./nit.yaml:/etc/nit/nit.yaml:ro
      - ./policy:/etc/nit/policy:ro
      - ./known_hosts:/etc/nit/ssh/known_hosts:ro

    secrets: [nit-ssh-key, nit-database-url, nit-sync-key]

    deploy:
      replicas: 2

secrets:
  # Mode 0400. OpenSSH refuses a private key that anyone else can read, and the
  # failure is a permissions error that reads nothing like an SSH problem.
  nit-ssh-key:
    file: ./secrets/id_ed25519
```

Every option in that command earns its place:

| | |
| --- | --- |
| `-i` + `IdentitiesOnly=yes` | Without it ssh offers every key it can find, and on a host with an agent the wrong one goes first — GitHub then answers as whatever account that key belongs to |
| `UserKnownHostsFile` + `StrictHostKeyChecking=yes` | The verified host keys from step 2, and the refusal to accept anything else |
| `BatchMode=yes` | A prompt becomes an error instead of a hang |

Under systemd, the same thing:

```ini title="/etc/systemd/system/nit-worker.service"
[Service]
ExecStart=/usr/local/bin/nit-worker -config /etc/nit/nit.yaml
LoadCredential=ssh-key:/etc/nit/ssh/id_ed25519
Environment=NIT_GIT_SSH_COMMAND=ssh -i %d/ssh-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/nit/ssh/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes
```

The command moves to `Environment=` here for one reason: **nit does not expand
variables inside configuration values.** `%d` is a systemd specifier and systemd
expands it in its own unit file, so a credential path only systemd knows has to
arrive that way. Keep it in `nit.yaml` instead if you write the literal path —
`LoadCredential` mounts it at `/run/credentials/nit-worker.service/ssh-key`.

:::note[The environment still wins]
`NIT_GIT_SSH_COMMAND` overrides the file, as every nit setting does, and a
configured value overrides a plain `GIT_SSH_COMMAND` the host happens to export.
Leave `git.ssh_command` empty and nothing is set at all, so a machine already
configured through `~/.ssh/config` keeps working.
:::

### Starting it

```sh
nitctl migrate                     # first, and separately

docker compose -f ../../deploy/production/compose.base.yaml \
               -f compose.yaml up -d
```

Prove SSH works before blaming nit for anything:

```sh
docker compose exec worker sh -lc \
  'GIT_SSH_COMMAND="$GIT_SSH_COMMAND" git ls-remote ssh://git@github.com/acme/payments.git main'
```

A SHA means the key, the host keys and the permissions are all correct, and
every later failure is nit's to explain.

---

## 7. Validation, part one: the rules, offline

This is the dataset to keep. Eighteen cases, one per line, each with the access
it is supposed to produce.

```bash title="check-policy.sh"
#!/usr/bin/env bash
set -uo pipefail

BUNDLE="${1:-./policy}"
REPO=payments

CASES=$(cat <<'EOF'
maya   src/api/handlers.go            write   ALLOW
maya   src/api/metrics.go             create  ALLOW
maya   src/ledger/posting.go          read    ALLOW
maya   src/ledger/posting.go          write   DENY
maya   docs/runbook.md                write   ALLOW
maya   go.mod                         read    ALLOW
maya   go.mod                         write   DENY
maya   secrets/stripe.env             read    DENY
maya   deploy/terraform/main.tf       read    DENY
maya   .github/workflows/ci.yml       write   DENY
maya   .gitattributes                 admin   DENY
raj    src/ledger/reconcile.go        write   ALLOW
raj    src/api/handlers.go            read    ALLOW
raj    src/api/handlers.go            write   DENY
raj    secrets/hsm-pin.txt            read    DENY
nadia  secrets/stripe.env             read    ALLOW
nadia  deploy/terraform/main.tf       write   ALLOW
nadia  .github/workflows/ci.yml       admin   ALLOW
EOF
)

failures=0

while read -r user path action expected; do
  [ -z "$user" ] && continue

  got=$(nitctl policy explain "$BUNDLE" \
    -repo "$REPO" -user "$user" -path "$path" -action "$action" |
    awk '/^  (ALLOW|DENY)/ { print $1; exit }')

  if [ "$got" = "$expected" ]; then
    printf '  ok    %-6s %-8s %s\n' "$user" "$action" "$path"
  else
    printf '  FAIL  %-6s %-8s %s — expected %s, got %s\n' \
      "$user" "$action" "$path" "$expected" "${got:-nothing}"
    failures=$((failures + 1))
  fi
done <<<"$CASES"

echo
[ "$failures" -eq 0 ] && { echo "all cases match"; exit 0; }
echo "$failures case(s) did not match the expected access"
exit 1
```

```sh
./check-policy.sh ./policy
```

```
  ok    maya   write    src/api/handlers.go
  ok    maya   create   src/api/metrics.go
  ok    maya   read     src/ledger/posting.go
  ok    maya   write    src/ledger/posting.go
  ok    maya   write    docs/runbook.md
  ok    maya   read     go.mod
  ok    maya   write    go.mod
  ok    maya   read     secrets/stripe.env
  ok    maya   read     deploy/terraform/main.tf
  ok    maya   write    .github/workflows/ci.yml
  ok    maya   admin    .gitattributes
  ok    raj    write    src/ledger/reconcile.go
  ok    raj    read     src/api/handlers.go
  ok    raj    write    src/api/handlers.go
  ok    raj    read     secrets/hsm-pin.txt
  ok    nadia  read     secrets/stripe.env
  ok    nadia  write    deploy/terraform/main.tf
  ok    nadia  admin    .github/workflows/ci.yml

all cases match
```

**Run this in the policy repository's CI.** It needs no server, no database and
no forge — only the files — which is exactly why it belongs there. Widen a rule
by accident:

```diff
- paths: [docs/]
+ paths: [docs/, go.mod]
```

and it says so, and exits non-zero:

```
  FAIL  maya   write    go.mod — expected DENY, got ALLOW

1 case(s) did not match the expected access
```

Adding a case is adding a line. The cases that matter most are the **denials**:
an allow that stops working is reported by a developer within the hour, while a
deny that stops working is reported by nobody.

### Reading one decision

```sh
nitctl policy explain ./policy -repo payments -user maya -path secrets/stripe.env
```

```
maya on secrets/stripe.env (payments)
groups: api, engineering

  DENY  read    denied by rule credentials-are-platform-only (denied_by_rule: secrets/)
          Payment credentials and production infrastructure are held by the platform team. Open a request in #payments-platform to have a change applied.
  DENY  write   denied by rule credentials-are-platform-only (denied_by_rule: secrets/)
  …
```

Compare with the same path for nadia:

```
nadia on secrets/stripe.env (payments)
groups: engineering, platform

  ALLOW read    allowed by rule platform-owns-the-repository (allowed_by_rule: **)
```

Both name the rule. A grant is as worth attributing as a denial — it is how you
find the rule that is wider than you thought.

---

## 8. Validation, part two: the system, live

```sh
nitctl token create -user maya  -label validation
nitctl token create -user raj   -label validation
```

### Read filtering is real absence

```sh
nit login https://nit.acme.example      # as maya
nit clone payments && cd payments
```

```
Cloned payments into ./payments
7 file(s) updated
5 file(s) withheld by policy
```

Seven of the twelve seeded files: `src/` (four), `docs/` (two) and `go.mod`.
Five withheld — the three under `secrets/` and `deploy/terraform/`, plus
`.gitattributes` and `.github/workflows/ci.yml`, which no rule grants anyone
outside `platform` a `read` on. **Closed by default** is not a slogan: a path
nobody wrote a rule for is a path nobody reads.

```sh
ls secrets/ deploy/terraform/
# → No such file or directory
```

✔ **The files are not there.** Not unwritable, not hidden by a hook — absent
from the working tree, from the index, and from every object in `.git`. The
count is reported; the paths are not, because naming them would leak the
structure the read rules exist to hide.

`git log` shows one synchronization commit, not upstream's history. This is a
*projection*, not a clone.

### An authorized push

```sh
echo 'package api // rate limiting' > src/api/handlers.go
git commit -qam "local work"

nit push --check
nit push -m "Add rate limiting to the ingest endpoint"
```

```
1 file(s) would be pushed, 0 refused
Pushed 1 file(s) to payments@main as 1e7d246954f0
```

On the forge, verify **who** it is attributed to and that it can be traced back:

```sh
git --git-dir=payments.git log -1 --format='%an <%ae>' refs/heads/main
git --git-dir=payments.git log -1 --format='%B' refs/heads/main
```

```
maya <maya@acme.example>
```

```
Add rate limiting to the ingest endpoint

Nit-User: maya
Nit-Request: 01J8Z3Q2M7C4V9K1
Nit-Task: be59af45-9694-416e-ace2-da5cffc7f145
Nit-Policy-Version: sha256:1e9b72f6feb474a1
Nit-Base-Commit: 9f2c1ab4e5d6
Nit-Workspace: ws_7f3a91
```

✔ **Authored by the authenticated identity**, never by the patch's `From:` line,
and carrying its own provenance — see
[what lands on the forge](/concepts/push-and-pull/#what-lands-on-the-forge).

### An unauthorized push

maya can read `src/ledger/posting.go`. She cannot write it. Record the tip
first, so you can prove the forge does not move:

```sh
before=$(git --git-dir=payments.git rev-parse refs/heads/main)

echo 'package ledger // tweak' > src/ledger/posting.go
git commit -qam "touch the ledger"
nit push -m "small fix"
```

```
nit: 1 path(s) are not authorized for this user

  src/ledger/posting.go (write)
      refused by rule the-ledger-is-owned-by-its-team
      Posting and reconciliation are owned by the ledger team. Read the code freely; open a pull request in #payments-ledger to change it.
```

```sh
[ "$before" = "$(git --git-dir=payments.git rev-parse refs/heads/main)" ] && echo "forge unchanged"
```

✔ **The whole push was refused and nothing was queued.** Not stripped of the
offending file — that would publish, under maya's name, a commit that compiles
differently from the one she tested.

### The CI guard

```sh
echo 'name: ci # tweak' > .github/workflows/ci.yml
git commit -qam "ci tweak"
nit push -m "ci"
```

```
nit: 1 path(s) are not authorized for this user

  .github/workflows/ci.yml (admin)
      guard: protected_path
```

✔ **The guard escalated the requirement to `admin`,** which maya does not have.
No rule in the bundle mentions `.github/`: write access to a CI definition is
read access to the whole repository, because a job runs with a full checkout and
can print anything it likes.

### Filtering on the way back

As raj, change something maya cannot read *and* something she can:

```sh
nit push -m "reconciliation fix and a doc note"     # touches src/ledger/ and docs/
```

Then, as maya:

```sh
nit pull
```

```
Updated payments@main to 4f2a9c1b7e30
1 file(s) updated
1 file(s) withheld by policy
```

✔ **The docs change arrived; the ledger change did not** — and maya learns that
something was withheld without learning what.

### The audit trail closes the loop

```sh
nitctl audit -repository payments -since 1h
```

```
WHEN                 ACTOR   ACTION             REPOSITORY@BRANCH   PATH                    RULE
2026-08-01 10:35:29  maya    push.applied       payments@main
2026-08-01 10:34:02  maya    push.denied_path   payments@main       .github/workflows/ci.yml
2026-08-01 10:33:14  maya    push.denied_path   payments@main       src/ledger/posting.go   ledger-team-owns-the-ledger
2026-08-01 10:33:14  maya    push.rejected      payments@main
```

Every record carries the policy version in force at the time, so a past decision
replays against exactly the rules that produced it.

---

## When SSH is the problem

Everything here is git and OpenSSH, so the failures are theirs, not nit's.

| What you see | What it is |
| --- | --- |
| `Permission denied (publickey)` | The public half is not on the repository or account, or `-i` points at the wrong file. Test with `git ls-remote` before suspecting nit. |
| The same, but only from the container | The key is mounted but not readable by the worker's uid, or is mode 0644 — OpenSSH refuses a key others can read. |
| `Host key verification failed` | `known_hosts` is missing, unmounted, or was written for a different host. |
| Tasks fail instantly with a clone error naming only the branch | Deliberate: the authenticated remote is a credential and git quotes the URL it was given. Raise the worker's log level to see more. |
| A worker hangs, then the task retries | A passphrase prompt without `BatchMode=yes`, or a lease shorter than the clone. |
| It works for one repository and not another | A deploy key is scoped to one repository. A second repository needs its own, or a machine user. |
| `read-only repository` on push | The deploy key was added without *Allow write access*. It cannot be edited — delete it and add it again. |

```sh
NIT_LOG_LEVEL=debug nit-worker
```

## Next

- [Connecting a forge](/guides/forges/) — GitLab, Gitea and the rest.
- [Going to production](/guides/production/) — the full checklist.
- [Writing a policy bundle](/guides/policy-bundles/) — the rule model in depth.
