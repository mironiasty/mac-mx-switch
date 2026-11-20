#!/bin/zsh
# Builds, signs with a Developer ID certificate, notarizes, staples and zips
# MacMXSwitch.app. With --publish, also creates the GitHub release v<VERSION>.
#
#   ./release.sh            build + sign + notarize → build/MacMXSwitch-<VERSION>.zip
#   ./release.sh --publish  ...and upload it as GitHub release v<VERSION>
#
# Environment:
#   SIGN_IDENTITY   codesigning identity; default: the only "Developer ID Application"
#                   identity in the keychain
#   NOTARY_PROFILE  notarytool keychain profile (default: macmxswitch-notary)
# One-time setup: see RELEASING.md.
set -e
cd "${0:A:h}"

NAME=MacMXSwitch
VERSION=$(<VERSION)
TAG=v$VERSION
APP=build/$NAME.app
ZIP=build/$NAME-$VERSION.zip
NOTARY_PROFILE=${NOTARY_PROFILE:-macmxswitch-notary}
PUBLISH=false
[[ $1 == --publish ]] && PUBLISH=true

if $PUBLISH; then
  [[ -z $(git status --porcelain) ]] || { echo "Working tree not clean; commit first." >&2; exit 1; }
  git fetch -q --tags origin
  ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG already exists; bump VERSION." >&2; exit 1; }
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { echo "HEAD is not origin/main; push first." >&2; exit 1; }
fi

if [[ -z $SIGN_IDENTITY ]]; then
  ids=("${(@f)$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p')}")
  ids=(${ids:#})
  (( ${#ids} == 1 )) || { echo "Found ${#ids} Developer ID Application identities; set SIGN_IDENTITY." >&2; printf '  %s\n' $ids >&2; exit 1; }
  SIGN_IDENTITY=$ids[1]
fi
echo "Signing with: $SIGN_IDENTITY"

./build.sh --release
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" $APP
codesign --verify --strict --verbose=2 $APP

echo "Notarizing (profile $NOTARY_PROFILE)..."
ditto -c -k --keepParent $APP $ZIP
xcrun notarytool submit $ZIP --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple $APP
spctl --assess --type execute --verbose=2 $APP

# Re-zip so the download contains the stapled ticket.
rm -f $ZIP
ditto -c -k --keepParent $APP $ZIP
shasum -a 256 $ZIP | tee $ZIP.sha256
echo "Release artifact: $ZIP"

if $PUBLISH; then
  gh release create $TAG $ZIP $ZIP.sha256 --target main --title "$NAME $VERSION" --generate-notes
fi
