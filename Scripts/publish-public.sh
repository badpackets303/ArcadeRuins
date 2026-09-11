#!/bin/bash
# Exports the committed tree into the working copy of the public repository, badpackets303/ArcadeRuins.
#
# The public repository starts clean (owner's decision, 2026-09-11): no history from this private
# repository, which carries the owner's personal email on early commits and AudioKit's own files.
# Left out on every export:
#   upstream/                  AudioKit Synth One's tree, which includes AudioKit's Audiobus API key.
#                              Scripts/fetch-references.sh fetches it instead.
#   docs/reference/appstore/   AudioKit's App Store screenshots, with their wordmark.
#
# This commits in the public working copy but never pushes. Pushing is a separate, deliberate step.
#
#   Scripts/publish-public.sh [path to public working copy]   (default: ../ArcadeRuins-public)
set -euo pipefail
cd "$(dirname "$0")/.."
PRIVATE_ROOT=$(pwd)
PUBLIC=${1:-"$PRIVATE_ROOT/../ArcadeRuins-public"}

if [ -n "$(git status --porcelain)" ]; then
    echo "✋ Uncommitted changes. The export is taken from HEAD, so commit first." >&2
    exit 1
fi
HEAD_SHORT=$(git rev-parse --short HEAD)

mkdir -p "$PUBLIC"
if [ ! -d "$PUBLIC/.git" ]; then
    git -C "$PUBLIC" init --quiet --initial-branch=main
    echo "Initialised a new repository at $PUBLIC"
fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
git archive HEAD | tar -x -C "$STAGING"
rm -rf "$STAGING/upstream" "$STAGING/docs/reference/appstore"
printf '\n# AudioKit Synth One, fetched by Scripts/fetch-references.sh; not part of this repository\nupstream/\n' >> "$STAGING/.gitignore"

# Mirror the export into the working copy, keeping only its .git.
rsync -a --delete --exclude '/.git' "$STAGING/" "$PUBLIC/"

# Nothing from the excluded paths may reach the public tree.
if [ -e "$PUBLIC/upstream" ] || [ -e "$PUBLIC/docs/reference/appstore" ]; then
    echo "✋ An excluded path is present in $PUBLIC" >&2
    exit 1
fi

git -C "$PUBLIC" add -A
if git -C "$PUBLIC" diff --cached --quiet; then
    echo "Nothing changed since the last export."
    exit 0
fi
git -C "$PUBLIC" commit --quiet -m "Arcade Ruins, from the private working repository at $HEAD_SHORT"
echo "Committed in $PUBLIC: $(git -C "$PUBLIC" log --oneline -1)"
echo "$(git -C "$PUBLIC" ls-files | wc -l | tr -d ' ') files. Not pushed."
