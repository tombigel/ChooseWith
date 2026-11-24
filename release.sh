#!/bin/zsh
# Publish a new version of Choose With.
#
#   ./release.sh 1.1.0             build, notarize, verify, tag, release, update the tap
#   ./release.sh 1.1.0 --dry-run   everything up to a verified zip; publishes nothing
#
# Before running: add a "## 1.1.0 — date" section to CHANGELOG.md and commit your
# work. Needs the notarytool keychain profile build.sh uses, and `gh` signed in.
set -euo pipefail
cd "${0:A:h}"

VERSION="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1
REPO=tombigel/ChooseWith
TAP=tombigel/homebrew-tap
CASK=Casks/choose-with.rb

die() { print -u2 "✗ $*"; exit 1; }

# --- Checks: nothing is changed until all of these pass.
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "usage: ./release.sh X.Y.Z [--dry-run]"
[[ "$(git branch --show-current)" == main ]] || die "release from the main branch"
[[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
git fetch -q --tags origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main isn't in sync with origin/main"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && die "tag v$VERSION already exists"
NOTES=$(awk -v v="$VERSION" '
  $0 ~ "^## " v "( |$)" { on = 1; next }
  on && /^## / { exit }
  on { print }' CHANGELOG.md)
[[ -n "${NOTES//[[:space:]]/}" ]] || die "add a \"## $VERSION\" section to CHANGELOG.md first"
command -v gh >/dev/null || die "install the GitHub CLI (gh)"

# --- Version and build number.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" Info.plist
print "Version $VERSION (build $BUILD)"

# --- Build, sign, notarize.
NOTARIZE=1 ./build.sh
ZIP="dist/ChooseWith-$VERSION.zip"
[[ -f "$ZIP" ]] || die "build didn't produce $ZIP"

# --- Verify the zip the way someone downloading it would get it.
CHECK=$(mktemp -d)
ditto -x -k "$ZIP" "$CHECK"
APP="$CHECK/ChooseWith.app"
codesign --verify --deep --strict "$APP" || die "signature check failed"
xcrun stapler validate "$APP" >/dev/null || die "notarization ticket missing"
spctl --assess --type execute "$APP" || die "Gatekeeper rejected the app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] \
  || die "version in the zip doesn't match"
rm -rf "$CHECK"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
print "Verified $ZIP\nSHA-256 $SHA"

if (( DRY_RUN )); then
  git checkout -- Info.plist
  print "Dry run: nothing published (Info.plist restored)."
  exit 0
fi

# --- Commit, tag, publish the release.
git commit -q -m "Release $VERSION" Info.plist
git tag -a "v$VERSION" -m "Choose With $VERSION"
git push -q origin main "v$VERSION"
BODY="$NOTES

### Install
\`brew upgrade --cask choose-with\`, or download **ChooseWith-$VERSION.zip** below, unzip, and move **ChooseWith.app** to Applications. Signed with a Developer ID and notarized by Apple. Requires macOS 13 or later.

SHA-256: \`$SHA\`"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Choose With $VERSION" --notes "$BODY"

# --- Update the Homebrew cask.
TAPDIR=$(mktemp -d)
gh repo clone "$TAP" "$TAPDIR" -- -q
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAPDIR/$CASK"
if command -v brew >/dev/null; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew style "$TAPDIR/$CASK" || die "cask style check failed (tap not pushed)"
fi
git -C "$TAPDIR" commit -q -am "choose-with $VERSION"
git -C "$TAPDIR" push -q
rm -rf "$TAPDIR"

print "Released $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
print "Homebrew: brew upgrade --cask choose-with"
