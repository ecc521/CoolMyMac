#!/bin/bash
set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CoolMyMac-App"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/CoolMyMac.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
APP_PATH="$EXPORT_PATH/CoolMyMac.app"
DMG_PATH="$BUILD_DIR/CoolMyMac.dmg"

# Keychain Profile Name for Notarization
# See `xcrun notarytool store-credentials --help` for setup
NOTARY_PROFILE="CoolMyMac-Notary"

echo "🧹 Cleaning previous builds..."
rm -rf "$BUILD_DIR"

echo "📦 Archiving CoolMyMac..."
cd "$PROJECT_DIR"
xcodebuild archive \
  -scheme CoolMyMac \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  | xcpretty || xcodebuild archive -scheme CoolMyMac -configuration Release -archivePath "$ARCHIVE_PATH"

echo "✍️ Exporting and Code Signing..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "../scripts/ExportOptions.plist" \
  | xcpretty || xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist "../scripts/ExportOptions.plist"

echo "💿 Creating DMG..."
if ! command -v create-dmg &> /dev/null; then
    echo "create-dmg not found. Installing via homebrew..."
    brew install create-dmg
fi

create-dmg \
  --volname "CoolMyMac" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "CoolMyMac.app" 150 190 \
  --hide-extension "CoolMyMac.app" \
  --app-drop-link 450 190 \
  "$DMG_PATH" \
  "$APP_PATH"

echo "🛂 Notarizing DMG..."
# Check if notarytool profile exists
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &> /dev/null; then
    echo "⚠️ Notary profile '$NOTARY_PROFILE' not found!"
    echo "Please set up your Apple ID credentials for notarization by running:"
    echo "xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id \"your@email.com\" --team-id \"G24X82SAVJ\" --password \"app-specific-password\""
    echo ""
    echo "Then run this script again. Your un-notarized DMG is available at: $DMG_PATH"
    exit 1
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "📎 Stapling Notarization Ticket..."
xcrun stapler staple "$DMG_PATH"

echo "✅ DMG ready at: $DMG_PATH"

# Read version from Info.plist
VERSION=$(defaults read "$EXPORT_PATH/CoolMyMac.app/Contents/Info.plist" CFBundleShortVersionString)
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

echo ""
echo "📋 Version:  $VERSION"
echo "🔑 SHA256:   $SHA256"

echo ""
echo "🚀 Publishing GitHub release v$VERSION..."
REPO="ecc521/CoolMyMac"
gh release create "v$VERSION" \
  --repo "$REPO" \
  --title "CoolMyMac v$VERSION" \
  --generate-notes \
  "$DMG_PATH"

echo ""
echo "🍺 Updating Homebrew cask..."
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK="$REPO_ROOT/homebrew-coolmymac/Casks/coolmymac.rb"
sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" "$CASK"
cd "$REPO_ROOT/homebrew-coolmymac"
git add Casks/coolmymac.rb
git commit -m "chore: Update submodule for $VERSION release"
git push
cd "$REPO_ROOT"
git add homebrew-coolmymac
git commit -m "chore: Update submodule for $VERSION release"
git push

echo ""
echo "✅ Done! Release v$VERSION is live."
