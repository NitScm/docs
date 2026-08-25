---
title: Trying the whole thing
description: The complete enterprise environment on one machine, in one command, with a walkthrough that proves each property.
sidebar:
  order: 7
---

Everything — a forge, the control plane, a worker, the audit vault, both
consoles — comes up on one machine from a single Compose stack.

```sh
git clone https://github.com/NitScm/nit-enterprise-infra
cd nit-enterprise-infra/docker
docker compose up -d --build
docker compose logs -f vault-bootstrap deployment-bootstrap
```

The first build takes a few minutes: two Go modules and a web application. After
that it is seconds.

| | |
| --- | --- |
| Audit vault console | http://localhost:4300 |
| nit console | http://localhost:4200 |
| nit API | http://localhost:8080 |
| Gitea, standing in for your forge | http://localhost:3000 |

Both bootstraps print what you need: an invitation that creates the vault's first
owner, and three developer accounts with deliberately different access.

## The five minutes worth spending

Sign in to the vault console with the invitation. Then be `bob`, a backend
engineer who may not read production secrets:

```
$ nit clone backend-api
3 file(s) updated
3 file(s) withheld by policy
```

`secrets/`, `infra/production/` and `.github/` are not there. Not hidden — never
sent.

Then try to take one:

```
$ mkdir -p secrets && echo 'TOKEN=stolen' > secrets/prod.env
$ git add -A && git commit -m 'take a secret'
$ nit push -m 'should not land'
nit: the patch touches paths you may not change

  secrets/prod.env (create)
      refused by rule secrets-are-platform-only
      Production secrets and infrastructure are owned by the platform team.
```

The forge did not move. And within a second or two the refusal is in the vault
console, with the rule that produced it — the point being that the record is
already somewhere bob cannot reach.

## The full walkthrough

`docker/VERIFICATION.md` in that repository goes through twelve properties in
order, with the output you should see, including:

- Taking a batch out of the vault and watching the check report it missing.
- Signing in as an auditor and finding there is nothing they can change.
- Placing a legal hold and watching deletion stop.

It was executed against the stack rather than written from the code, so a step
that gives you something different is a genuine difference.

## What this is not

A production deployment. The stack uses fixed, public credentials so the printed
instructions can include them, and `docker compose down -v` removes everything.

For a real deployment, [going to production](/guides/production/) covers the free
edition's requirements, and the commercial settings are documented in the pages
above.
