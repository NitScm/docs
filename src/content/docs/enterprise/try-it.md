---
title: Seeing it work
description: A demonstration environment exists. Ask, and somebody will bring it up with you.
sidebar:
  order: 7
---

There is a complete environment — a forge, the control plane, a worker, the
audit vault, both consoles — that comes up on one machine from a single Compose
stack, with a walkthrough of seventeen properties in order.

**Ask us and somebody will bring it up with you**, over a call or in your
office. It takes about five minutes to get to the part that matters.

What you will see, in that order:

- A contractor clones the repository and the paths they may not read **are not
  in what they received**. Not hidden, not stubbed, not a permission error —
  absent, and the working tree still builds.
- A push touching a path its author may not write is refused at the boundary,
  naming the rule that refused it. The forge does not move.
- The refusal appears in the audit vault within a second or two, signed by that
  deployment, somewhere the person who was refused cannot reach.
- An auditor signs in and finds there is nothing they can change.
- A legal hold is placed and deletion stops.

We do not hand out the environment itself. It is our deployment configuration
rather than a product, it uses fixed public credentials so that a walkthrough
can print them, and a copy of it in your hands would be a copy nobody maintains
for you.

## What you can run yourself, today

The community edition, which is the whole authorization layer: filtered clones,
refused pushes, the rule language, the console, every forge driver. Apache 2.0,
self-hosted, no seat count and no key.

[Install it](/start/install/) — it takes about ten minutes, and nobody needs to
be on a call with you.

The [audit vault](/enterprise/) is the part we run for you, and the part this
page's demonstration is mostly about.
