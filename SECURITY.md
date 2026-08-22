# Security policy — nit-docs

This is a static documentation site. Its own attack surface is small. Its
capacity to cause harm is not, and that distinction shapes what we consider a
vulnerability here.

## Reporting

**Do not open a public issue** for anything that would let someone attack a nit
deployment.

Use GitHub's private vulnerability reporting (Security → Report a
vulnerability), or email **`SECURITY_CONTACT_TO_BE_SET`**.

Acknowledgement within 3 working days; an initial assessment within 10.

Issues in nit itself belong in [nit's SECURITY.md](https://github.com/NitScm/nit/blob/main/SECURITY.md);
issues in the operations console in
[the console's SECURITY.md](https://github.com/NitScm/nit-console/blob/main/SECURITY.md).

## The finding that matters most: documentation that is wrong about security

**Documentation that tells a reader to do something unsafe is a security issue
in this repository**, and it is by far the most likely one. Report it privately
if it would help someone attack an existing deployment; a public issue is fine
if it would only affect someone following the page in the future.

Examples of what we want to hear:

- A page that omits a step which leaves a deployment exposed — a `known_hosts`
  that is never verified, a `StrictHostKeyChecking` left off, a secret shown
  inline in a file whose mode is never mentioned.
- A page that understates a requirement. nit's guarantees assume its machine
  account is the **only** writer and the repository is private. Any page that
  reads as though those are optional is a bug of this class.
- An example that would work in production and should not — a fixed secret, a
  permissive CORS origin, a wildcard.
- A claim about what nit protects that the code does not actually deliver. If a
  page promises a guarantee that is not implemented, that is the most serious
  finding this repository can have, and we would rather hear it from you than
  from a customer.

We have already corrected pages for this reason: a claim that audit retention
was handled by partitions when nothing pruned the table, and a systemd example
using a variable nit does not expand. Both were wrong in the direction of making
things look safer than they were. That is the direction to look in.

## The site's own surface

Small, and deliberately kept that way.

**In scope:**

- Anything that gets script into the built site that is not in the source —
  through a build dependency, a Markdown rendering path, or a Starlight
  component.
- A build that emits a request to a third-party origin. The site should be
  self-contained.
- A supply-chain compromise in a build dependency reaching `dist/`.

**Not in scope:**

- Missing security headers on however you happen to host the static output.
  Configure your host; there is nothing this repository can do about it.
- Denial of service against a static site.
- The absence of authentication. It is public documentation.

## What this site must never contain

Called out because it is easy to add by accident while writing an example:

- Real credentials, tokens, keys or hostnames from any actual deployment.
- Fingerprints, keys or checksums presented as verified when they were copied
  from memory rather than checked. Where a value must be verified by the reader,
  the page says so and tells them against what — for example, GitHub's published
  SSH key fingerprints rather than whatever `ssh-keyscan` happened to answer.
- Example secrets that are not obviously examples.

If you find any of these, that is a report, not a typo.

## Supported versions

The site is built from `main` and deployed from it. There are no versioned
releases to support.
