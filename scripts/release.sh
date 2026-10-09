#!/bin/sh
# Usage: scripts/release.sh <version> [notes]
# Publishes the GitHub release that installed copies update to (see Updater.swift):
# sets VERSION, commits and tags it, builds the app, uploads m_notch.zip and m_notch.zip.sha256.
# Example: scripts/release.sh 0.2.0 "Calendar shows all-day events"
set -eu
cd "$(dirname "$0")/.."

version="${1:-}"
notes="${2:-m_notch $version}"
case "$version" in
"" | *[!0-9.]* | .* | *. | *..*)
    echo "Version \"$version\" must look like 0.2.0. Usage: scripts/release.sh <version> [notes]" >&2
    exit 64
    ;;
esac
if [ -n "$(git status --porcelain)" ]; then
    echo "The working tree has uncommitted changes: commit or stash them, the release is built from the last commit." >&2
    git status --short >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
    echo "Tag v$version already exists." >&2
    exit 1
fi
branch=$(git symbolic-ref --short HEAD)

if [ "$(cat VERSION)" != "$version" ]; then
    echo "$version" > VERSION
    git commit -m "Release $version" VERSION
fi
scripts/dev.sh build
rm -rf dist
mkdir dist
ditto -c -k --keepParent build/m_notch.app dist/m_notch.zip
(cd dist && shasum -a 256 m_notch.zip > m_notch.zip.sha256)

git tag "v$version"
git push origin "$branch" "v$version"
gh release create "v$version" dist/m_notch.zip dist/m_notch.zip.sha256 \
    --title "m_notch $version" --notes "$notes" --verify-tag
echo "Released v$version"
