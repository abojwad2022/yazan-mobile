#!/usr/bin/env bash
# Generates android/ and ios/ for an app (run from the app folder; CI does this before building).
# The platform folders are generated, not hand-written, because only `flutter create` can write them
# correctly for the Flutter version in use. Works on Linux and macOS (perl, not GNU-only sed).
# Usage: scaffold_platforms.sh <short-name> <dart-package>
set -euo pipefail
short="$1"; pkg="$2"
if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --org com.yazanus --project-name "$pkg" --platforms=android,ios .
  rm -f test/widget_test.dart
fi
# Application id / bundle id: com.yazanus.<short> (namespace stays as generated).
if [ -f android/app/build.gradle.kts ]; then f=android/app/build.gradle.kts; else f=android/app/build.gradle; fi
perl -pi -e "s/com\.yazanus\.\Q$pkg\E\"/com.yazanus.$short\"/ if /applicationId/" "$f"
perl -pi -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.yazanus\.\Q$pkg\E(\.RunnerTests)?;/PRODUCT_BUNDLE_IDENTIFIER = com.yazanus.$short\$1;/" ios/Runner.xcodeproj/project.pbxproj
# Release builds need the INTERNET permission in the main manifest too.
m=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$m" || perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.INTERNET"\/>/' "$m"
grep -n 'applicationId' "$f" | head -2
grep -n 'PRODUCT_BUNDLE_IDENTIFIER' ios/Runner.xcodeproj/project.pbxproj | head -3
echo "scaffolded $pkg as com.yazanus.$short"
