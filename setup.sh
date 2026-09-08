#!/usr/bin/env bash
set -euo pipefail

# cspell:words flutterfire redir tlsv

# Cloud development environment for prep_book.
# The environment is defined by merry-setup and pinned to an immutable revision:
# https://github.com/AndrewDongminYoo/merry-setup
#
# To move to a newer merry-setup:
#   1. Confirm the new commit is an ancestor of merry-setup's default branch. GitHub serves
#      commits from across a repository's fork network, so a SHA that resolves under this
#      URL does not by itself prove it is upstream work.
#   2. Set MERRY_SETUP_REVISION to the full commit SHA and MERRY_SETUP_SHA256 to the
#      SHA-256 of bin/merry-setup at that commit. The two move together: a mismatched pair
#      aborts below rather than running code nothing vouched for.
# The options below describe this project and change only when its toolchain does.

readonly MERRY_SETUP_REVISION=a946d67a2071735250fc244842bcd4015052ec47
readonly MERRY_SETUP_SHA256=d3282112f6f42b3b46b086538546e6423b83509b6e0730d6876904feea699197
readonly MERRY_SETUP_URL="https://raw.githubusercontent.com/AndrewDongminYoo/merry-setup/${MERRY_SETUP_REVISION}/bin/merry-setup"
readonly MERRY_SETUP_BIN="${HOME}/.merry-setup/bin/merry-setup-${MERRY_SETUP_REVISION}"

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

sha256_of() {
	sha256sum -- "$1" | awk '{print $1}'
}

[[ ${MERRY_SETUP_REVISION} =~ ^[0-9a-f]{40}$ ]] || die "MERRY_SETUP_REVISION must be a full commit SHA."
[[ ${MERRY_SETUP_SHA256} =~ ^[0-9a-f]{64}$ ]] || die "MERRY_SETUP_SHA256 must be a lowercase SHA-256 digest."

# Both guards below hash, so these are needed on a cache hit as well. curl is not: it is
# checked inside the download branch, which is the only path that reaches the network.
for required_cmd in sha256sum awk; do
	command -v "${required_cmd}" >/dev/null 2>&1 ||
		die "'${required_cmd}' is required to verify merry-setup."
done

# Download to a file and publish it by rename, so a partial transfer never becomes the executable.
if [[ ! -x ${MERRY_SETUP_BIN} ]]; then
	command -v curl >/dev/null 2>&1 || die "curl is required to download merry-setup."
	mkdir -p -- "${MERRY_SETUP_BIN%/*}"
	staged="$(mktemp "${MERRY_SETUP_BIN}.XXXXXX")"
	if ! curl --fail --silent --show-error --location \
		--proto '=https' --proto-redir '=https' --tlsv1.2 \
		--retry 3 --retry-delay 2 \
		--output "${staged}" "${MERRY_SETUP_URL}"; then
		rm -f -- "${staged}"
		die "Failed to download merry-setup ${MERRY_SETUP_REVISION}."
	fi
	# Checked before the rename, so a body that is not the pinned one never lands at the
	# cache path. The revision SHA already binds the URL to one blob, but only GitHub's
	# serving layer enforces that binding; nothing on this machine does. A proxy
	# intercepting TLS with a CA the container trusts satisfies every other constraint
	# here and fails this one.
	staged_sha256="$(sha256_of "${staged}")"
	if [[ ${staged_sha256} != "${MERRY_SETUP_SHA256}" ]]; then
		rm -f -- "${staged}"
		die "SHA-256 mismatch for the merry-setup ${MERRY_SETUP_REVISION} download: expected ${MERRY_SETUP_SHA256}, got ${staged_sha256}."
	fi
	chmod 0755 "${staged}"
	mv -f -- "${staged}" "${MERRY_SETUP_BIN}"
fi

# Re-checked on every run rather than only after a download: the cache is a plain file under
# $HOME, and hashing 52 KB costs less than trusting whatever now sits at that path.
cached_sha256="$(sha256_of "${MERRY_SETUP_BIN}")"
[[ ${cached_sha256} == "${MERRY_SETUP_SHA256}" ]] ||
	die "SHA-256 mismatch for ${MERRY_SETUP_BIN}: expected ${MERRY_SETUP_SHA256}, got ${cached_sha256}. Delete it and re-run."

# very_good_cli is the one extra global tool this project needs: CLAUDE.md makes
# `very_good test --coverage` the command that decides whether a line is uncovered.
# bloc_tools stays a dev dependency, because CI reaches it with `dart run`.
#
# No `--precache`: the supported targets are iOS and Android, the web target was
# removed, and none of them build on a Linux container. Omitting the option skips
# the precache step outright rather than downloading artifacts nothing here uses.
#
# No melos and no flutterfire bundle: this is a single package, and the first
# release excludes every cloud account, sync, and backend.
exec "${MERRY_SETUP_BIN}" setup \
	--sdk flutter \
	--bootstrap flutter \
	--persist-path bashrc \
	--dart-package very_good_cli
