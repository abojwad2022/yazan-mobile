#!/usr/bin/env bash
# Generates android/ and ios/ for an app (run from the app folder; CI does this before building).
# The platform folders are generated, not hand-written, because only `flutter create` can write them
# correctly for the Flutter version in use. Works on Linux and macOS (perl, not GNU-only sed).
# Usage: scaffold_platforms.sh <short-name> <dart-package> <display-name>
set -euo pipefail
short="$1"; pkg="$2"; label="${3:-$2}"
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
# Encrypted local database (SQLCipher) and Keystore-backed key: API 23+ is the floor, whatever Flutter's own default is
# (maxOf/Math.max keeps a higher Flutter default). Idempotent: the patterns no longer match once rewritten.
perl -pi -e 's/\bminSdk\s*=\s*flutter\.minSdkVersion\b/minSdk = maxOf(flutter.minSdkVersion, 23)/' "$f"
perl -pi -e 's/\bminSdkVersion\s+flutter\.minSdkVersion\b/minSdkVersion Math.max(flutter.minSdkVersion, 23)/' "$f"
grep -Eq 'minSdk(Version)?\s*=?\s*(maxOf|Math\.max)\(flutter\.minSdkVersion, 23\)' "$f" \
  || { echo "scaffold: could not set minSdk 23 in $f (flutter create changed its template?)" >&2; exit 1; }
# No cloud/device backup: a restored database or key store on another phone cannot be opened (the key stays in the Keystore).
perl -pi -e 's/android:allowBackup="true"/android:allowBackup="false"/' "$m"
grep -q 'android:allowBackup' "$m" || perl -pi -e 's/<application\b/<application android:allowBackup="false"/' "$m"
grep -q 'android:allowBackup="false"' "$m" \
  || { echo "scaffold: could not set allowBackup=false in $m" >&2; exit 1; }
grep -n 'minSdk' "$f" | head -2
grep -n 'applicationId' "$f" | head -2
grep -n 'PRODUCT_BUNDLE_IDENTIFIER' ios/Runner.xcodeproj/project.pbxproj | head -3
# App lock (local_auth, Admin app): biometric permission, an Activity that can host the system prompt, Face ID text.
# Harmless for apps that do not use local_auth. Idempotent; fails loudly if a template changed.
grep -q 'android.permission.USE_BIOMETRIC' "$m" || perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"\/>/' "$m"
grep -q 'android.permission.USE_BIOMETRIC' "$m" \
  || { echo "scaffold: could not add USE_BIOMETRIC to $m" >&2; exit 1; }
act=$(find android/app/src/main \( -name 'MainActivity.kt' -o -name 'MainActivity.java' \) | head -1)
[ -n "$act" ] || { echo "scaffold: no MainActivity found under android/app/src/main" >&2; exit 1; }
perl -pi -e 's/\bio\.flutter\.embedding\.android\.FlutterActivity\b/io.flutter.embedding.android.FlutterFragmentActivity/; s/:\s*FlutterActivity\(\)/: FlutterFragmentActivity()/; s/extends FlutterActivity\b/extends FlutterFragmentActivity/' "$act"
grep -q 'FlutterFragmentActivity' "$act" \
  || { echo "scaffold: could not make $act a FlutterFragmentActivity (flutter create changed its template?)" >&2; exit 1; }
ip=ios/Runner/Info.plist
grep -q 'NSFaceIDUsageDescription' "$ip" || perl -0pi -e 's/<\/dict>(\s*<\/plist>)/\t<key>NSFaceIDUsageDescription<\/key>\n\t<string>Unlock the app with Face ID.<\/string>\n<\/dict>$1/' "$ip"
grep -q 'NSFaceIDUsageDescription' "$ip" \
  || { echo "scaffold: could not add NSFaceIDUsageDescription to $ip" >&2; exit 1; }
# Ring check QR scanner (mobile_scanner, Store app only): camera permission, the camera marked optional so
# phones without one can still install the app (typing the serial works there), and the iOS prompt text.
# Idempotent; fails loudly if a template changed.
if [ "$pkg" = "yazan_store" ]; then
  grep -q 'android.permission.CAMERA' "$m" || perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.CAMERA"\/>/' "$m"
  grep -q 'android.permission.CAMERA' "$m" \
    || { echo "scaffold: could not add CAMERA to $m" >&2; exit 1; }
  grep -q 'android.hardware.camera"' "$m" || perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-feature android:name="android.hardware.camera" android:required="false"\/>/' "$m"
  grep -q 'android.hardware.camera" android:required="false"' "$m" \
    || { echo "scaffold: could not mark the camera optional in $m" >&2; exit 1; }
  grep -q 'NSCameraUsageDescription' "$ip" || perl -0pi -e 's/<\/dict>(\s*<\/plist>)/\t<key>NSCameraUsageDescription<\/key>\n\t<string>The camera reads the QR code on your YAZAN ring certificate to check the ring.<\/string>\n<\/dict>$1/' "$ip"
  grep -q 'NSCameraUsageDescription' "$ip" \
    || { echo "scaffold: could not add NSCameraUsageDescription to $ip" >&2; exit 1; }
fi
export LABEL="$label"
# What the home screen shows under the icon.
perl -pi -e 's/android:label="[^"]*"/android:label="$ENV{LABEL}"/' android/app/src/main/AndroidManifest.xml
perl -0pi -e 's/(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*/$1$ENV{LABEL}/; s/(<key>CFBundleName<\/key>\s*<string>)[^<]*/$1$ENV{LABEL}/' ios/Runner/Info.plist
# The store's mark as the launcher icon (assets/icon/icon.png, set in pubspec.yaml).
dart run flutter_launcher_icons
echo "scaffolded $pkg as com.yazanus.$short"
