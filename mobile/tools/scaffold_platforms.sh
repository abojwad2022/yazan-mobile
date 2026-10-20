#!/usr/bin/env bash
# Generates android/ and ios/ for an app (run from the app folder; CI does this before building).
# The platform folders are generated, not hand-written, because only `flutter create` can write them
# correctly for the Flutter version in use. Usage: scaffold_platforms.sh <short-name> <dart-package>
set -euo pipefail
short="$1"; pkg="$2"
if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --org com.yazanus --project-name "$pkg" --platforms=android,ios .
  rm -f test/widget_test.dart
fi
# Application id / bundle id: com.yazanus.<short> (namespace stays as generated).
if [ -f android/app/build.gradle.kts ]; then f=android/app/build.gradle.kts; else f=android/app/build.gradle; fi
sed -i "s/applicationId = \"com.yazanus.$pkg\"/applicationId = \"com.yazanus.$short\"/; s/applicationId \"com.yazanus.$pkg\"/applicationId \"com.yazanus.$short\"/" "$f"
sed -i "s/PRODUCT_BUNDLE_IDENTIFIER = com.yazanus.$pkg;/PRODUCT_BUNDLE_IDENTIFIER = com.yazanus.$short;/; s/PRODUCT_BUNDLE_IDENTIFIER = com.yazanus.$pkg.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = com.yazanus.$short.RunnerTests;/" ios/Runner.xcodeproj/project.pbxproj
# Release builds need the INTERNET permission in the main manifest too.
m=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$m" || sed -i '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.INTERNET"\/>/' "$m"
echo "scaffolded $pkg as com.yazanus.$short"
