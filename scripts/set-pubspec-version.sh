#!/usr/bin/env bash
# Sync pubspec.yaml's version to a semantic-release version.
# Usage: set-pubspec-version.sh <semver> [pubspec-path]
#
# Flutter versions are `versionName+buildCode`. The build code must increase
# monotonically for app-store uploads, so we derive it deterministically from
# the semver: M*10000 + m*100 + p (assumes minor/patch < 100). Because
# semantic-release only ever bumps the version upward, the build code is
# guaranteed to increase too.
set -euo pipefail

VERSION="${1:?usage: set-pubspec-version.sh <semver> [pubspec-path]}"
PUBSPEC="${2:-pubspec.yaml}"

# Strip any pre-release / build metadata before splitting (e.g. 1.2.3-beta.1 -> 1.2.3)
CORE="${VERSION%%[-+]*}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CORE"
BUILD=$(( MAJOR * 10000 + MINOR * 100 + PATCH ))

tmp="$(mktemp)"
awk -v v="$VERSION" -v b="$BUILD" '
  /^version:[[:space:]]/ && !done { print "version: " v "+" b; done=1; next }
  { print }
' "$PUBSPEC" > "$tmp"
mv "$tmp" "$PUBSPEC"

echo "pubspec.yaml version -> ${VERSION}+${BUILD}"
