#!/bin/zsh
# Downloads the pinned prebuilt Sparkle release into .build/sparkle (never committed).
# Sparkle ships self-updating; UsageBar's dev build does not use it — only packaged
# builds (SPARKLE=1 in build-app.sh) fetch, link and embed the framework.
set -euo pipefail
SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
cd "${0:A:h:h}"

DIR=".build/sparkle"
TARBALL=".build/Sparkle-${SPARKLE_VERSION}.tar.xz"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

if [[ -d "$DIR/Sparkle.framework" && -x "$DIR/bin/sign_update" ]]; then
  echo "Sparkle ${SPARKLE_VERSION} already present in $DIR"
  exit 0
fi
mkdir -p .build "$DIR"
curl -fSL -o "$TARBALL" "$URL"
echo "$SPARKLE_SHA256  $TARBALL" | shasum -a 256 -c -
tar -xf "$TARBALL" -C "$DIR" Sparkle.framework bin LICENSE
echo "Fetched Sparkle ${SPARKLE_VERSION} into $DIR"
