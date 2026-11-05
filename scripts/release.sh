#!/bin/zsh
# Publishes the committed work as one GitHub release: scripts/release.sh 0.1.1
# CHANGELOG.md's top section must be "## Unreleased"; it becomes "## <version> (<date>)" and its bullets are the
# release notes. Sets the app version, commits, tags, pushes main and the tag, creates the GitHub Release.
set -euo pipefail
cd "${0:A:h:h}"
v=${1:?usage: scripts/release.sh X.Y.Z}
[[ -z $(git status --porcelain) ]] || { echo "Uncommitted changes: commit them first." >&2; exit 1; }
grep -q '^## Unreleased' CHANGELOG.md || { echo "CHANGELOG.md has no '## Unreleased' section." >&2; exit 1; }
git rev-parse -q --verify "refs/tags/v$v" >/dev/null && { echo "v$v already exists." >&2; exit 1; }
sed -i '' -E "s|(<key>CFBundleShortVersionString</key><string>)[^<]*|\1$v|; s|(<key>CFBundleVersion</key><string>)[^<]*|\1$v|" scripts/build-app.sh
sed -i '' "s|^## Unreleased.*|## $v ($(date +%F))|" CHANGELOG.md
sed -i '' -E "s|^Version [^ ]+, [^.]*\.|Version $v, released $(date +%F).|" STATUS.md
notes=$(awk '/^## /{n++; next} n==1' CHANGELOG.md)
git commit -qam "Release v$v"
git tag "v$v"
git push -q origin main "v$v"
gh release create "v$v" --title "v$v" --notes "$notes" >/dev/null
echo "Released v$v: $(gh release view "v$v" --json url -q .url)"
