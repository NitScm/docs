#!/usr/bin/env node
//
// The public documentation must never name a private repository.
//
// This site is published. A page telling a customer to clone
// `nit-enterprise-infra` is a page telling them to clone our commercial
// deployment configuration — and the one that did also named a URL that does
// not exist, so what a reader actually got was a 404 and a bad impression.
//
// Both halves are the same failure: the public site knowing about the private
// side at all. A grep is enough to prevent it, and a grep is what nobody
// remembers to run.
//
//   node scripts/check-private.mjs      (after a build)

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const dist = join(root, 'dist');

// Private repositories and the working-directory names they go by. A customer
// may know the *products* exist — the audit vault is sold — but never the
// repository, because there is nothing at the other end of it for them.
const forbidden = [
  'nit-enterprise-infra',
  'nit-enterprise-exploitation',
  'NitScm/nit-enterprise',
  'NitScm/infra-enterprise',
  'NitScm/ui-vault-console-enterprise',
];

try {
  statSync(dist);
} catch {
  console.error('\x1b[31mNo dist/. Run the build first.\x1b[0m');
  process.exit(1);
}

let found = 0;

for (const file of htmlFiles(dist)) {
  const text = readFileSync(file, 'utf8');

  for (const name of forbidden) {
    if (!text.includes(name)) continue;

    const line = text.split('\n').find((l) => l.includes(name)) ?? '';

    console.error(
      `\x1b[31m${relative(root, file)} names ${name}\x1b[0m\n` +
        `  ${line.trim().slice(0, 160)}`,
    );

    found++;
  }
}

if (found > 0) {
  console.error(
    `\n\x1b[31m${found} reference(s) to a private repository.\x1b[0m\n` +
      'This site is published. Say the capability exists; never name the\n' +
      'repository, and never tell a reader to clone one they cannot reach.',
  );
  process.exit(1);
}

console.log('\x1b[32mThe public documentation names no private repository.\x1b[0m');

function htmlFiles(dir) {
  const out = [];

  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) out.push(...htmlFiles(path));
    else if (entry.name.endsWith('.html')) out.push(path);
  }

  return out;
}
