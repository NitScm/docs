#!/usr/bin/env bash
#
# Start the documentation site in development mode.
#
#   ./dev.sh                  http://localhost:4321
#   ./dev.sh --port 5000      any astro dev flag is passed through
#   ./dev.sh --host           expose it on the network
#
# The Node version comes from .nvmrc, so this script and any editor, CI job or
# shell hook that reads that file all agree. Selecting it here rather than
# telling people to run "nvm use" first is what stops the site being built with
# whatever version happens to be active.
#
# The package manager is pnpm, pinned by package.json's packageManager field.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------
# nvm
# ---------------------------------------------------------------------------

# nvm is a shell function, not a binary: it has to be sourced, and a
# non-interactive shell has not read the profile that would do it.
load_nvm() {
	if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
		# shellcheck disable=SC1091
		. "$NVM_DIR/nvm.sh"
		return 0
	fi

	for candidate in "$HOME/.nvm" /usr/local/opt/nvm /usr/share/nvm; do
		if [ -s "$candidate/nvm.sh" ]; then
			export NVM_DIR="$candidate"
			# shellcheck disable=SC1091
			. "$candidate/nvm.sh"
			return 0
		fi
	done

	return 1
}

if load_nvm; then
	wanted="$(cat .nvmrc)"

	# "nvm use" fails when the version is not installed yet, which is the
	# common case on a fresh checkout. Install it rather than making a new
	# contributor read an error and guess the next command.
	if ! nvm use >/dev/null 2>&1; then
		echo "==> Node $wanted is not installed; installing it"
		nvm install
		nvm use
	fi
else
	# No nvm: run with whatever node is on PATH, but say so, because a version
	# mismatch shows up later as a confusing build error rather than as this.
	echo "==> nvm not found; using the node already on PATH"

	if ! command -v node >/dev/null 2>&1; then
		echo "no node on PATH either — install nvm, or Node $(cat .nvmrc)" >&2
		exit 1
	fi
fi

echo "==> node $(node --version)"

# ---------------------------------------------------------------------------
# pnpm
# ---------------------------------------------------------------------------

# corepack ships with Node and installs the pnpm version package.json pins, so
# nobody has to have the right one already. A pnpm already on PATH is used as
# it is: overriding a working installation would be rude, and the version skew
# a lockfile tolerates is small.
if ! command -v pnpm >/dev/null 2>&1; then
	if command -v corepack >/dev/null 2>&1; then
		echo "==> enabling pnpm through corepack"
		corepack enable pnpm
	else
		echo "no pnpm and no corepack — install pnpm, or a Node that ships corepack" >&2
		exit 1
	fi
fi

echo "==> pnpm $(pnpm --version)"

# ---------------------------------------------------------------------------
# dependencies
# ---------------------------------------------------------------------------

# pnpm-lock.yaml newer than node_modules means someone changed a dependency
# since the last install — including "someone" being a git pull.
if [ ! -d node_modules ] || [ pnpm-lock.yaml -nt node_modules ]; then
	echo "==> installing dependencies"
	pnpm install
fi

# ---------------------------------------------------------------------------
# go
# ---------------------------------------------------------------------------

# The site is served under a base path, so the dev server answers on
# http://localhost:4321/docs/ and the bare origin is a 404 — and Astro prints
# only the origin, which sends you straight to that 404. Read the base out of
# the config rather than repeating it here: two copies of a path eventually
# disagree, and this one would disagree silently.
base=$(sed -n "s/^const base = '\\(.*\\)';$/\\1/p" astro.config.mjs)

echo "==> the site is at http://localhost:4321${base}/"
echo "    (the bare origin is a 404: everything lives under ${base})"

exec pnpm run dev -- "$@"
