#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/logs build/artifacts
exec > >(tee build/logs/build-ios.log) 2>&1
python3 scripts/check_project.py
python3 scripts/build_java.py all
python3 scripts/check_project.py --built-java
python3 scripts/test_rms_host.py
plutil -lint J2MEEmulator/SupportingFiles/Info.plist
plutil -lint J2MEEmulator.xcodeproj/project.pbxproj
xcodebuild -version
xcodebuild -list -project J2MEEmulator.xcodeproj
# Xcode compiles the vendored C miniJVM and all native bridges as target sources.
# No Apple credentials, provisioning profiles or paid membership are used in CI.
xcodebuild -project J2MEEmulator.xcodeproj -scheme J2MEEmulator \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData -resultBundlePath build/Build.xcresult \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID:-org.j2mestudio.emulator}" build
APP="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/J2MEStudio.app"
test -d "$APP"
# Save the successful .app before attempting IPA validation/packaging.
ditto -c -k --sequesterRsrc --keepParent "$APP" build/artifacts/J2MEStudio-device-app.zip
python3 scripts/package_ipa.py "$APP" build/artifacts/J2MEStudio-unsigned.ipa
cp J2MEEmulator/Resources/apps/studio_diagnostics.jar build/artifacts/
shasum -a 256 build/artifacts/* > build/logs/SHA256SUMS.txt
