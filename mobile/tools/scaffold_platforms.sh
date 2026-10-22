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
# Admin app only: Android FLAG_SECURE on the whole window, so the OS blanks the task-switcher thumbnail
# and refuses screenshots / screen recording of customer and order data. Patches the Kotlin template's
# body-less `class MainActivity : FlutterFragmentActivity()` (rewritten just above). Idempotent (skipped
# once FLAG_SECURE is there); fails loudly if the template changed. iOS has no equivalent without native
# code; see the note in lib/src/security/app_lock_scope.dart.
if [ "$pkg" = "yazan_admin" ]; then
  if ! grep -q 'FLAG_SECURE' "$act"; then
    case "$act" in
      *.kt) ;;
      *) echo "scaffold: FLAG_SECURE patch expects a Kotlin MainActivity, found $act" >&2; exit 1 ;;
    esac
    perl -0pi -e 's/^(import io\.flutter\.embedding\.android\.FlutterFragmentActivity)[ \t]*\r?$/$1\nimport android.os.Bundle\nimport android.view.WindowManager/m; s/^(class MainActivity\s*:\s*FlutterFragmentActivity\(\))[ \t]*\r?$/$1 {\n    override fun onCreate(savedInstanceState: Bundle?) {\n        super.onCreate(savedInstanceState)\n        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)\n    }\n}/m' "$act"
  fi
  grep -q '^import android\.os\.Bundle' "$act" \
    && grep -q '^import android\.view\.WindowManager' "$act" \
    && grep -q 'override fun onCreate(savedInstanceState: Bundle?)' "$act" \
    && grep -q 'window\.setFlags(WindowManager\.LayoutParams\.FLAG_SECURE, WindowManager\.LayoutParams\.FLAG_SECURE)' "$act" \
    || { echo "scaffold: could not set FLAG_SECURE in $act (flutter create changed its template?)" >&2; exit 1; }
fi
# Sign-in through the website (flutter_web_auth_2 5.x, both apps): the site redirects to
# com.yazanus.<short>://auth?code=...; on Android the package's CallbackActivity must own THIS app's scheme
# only (com.yazanus.store in the Store app, com.yazanus.admin in the Admin app). Manifest entry as in the
# package README; its optional intent-filter label is left out so the display-name rewrite below cannot
# touch it. iOS needs no Info.plist URL type: the scheme is handed to ASWebAuthenticationSession.
# Inside <application>, idempotent, fails loudly.
export AUTH_SCHEME="com.yazanus.$short"
if ! grep -q 'com.linusu.flutter_web_auth_2.CallbackActivity' "$m"; then
  perl -0pi -e 's#(\n?[ \t]*</application>)#\n        <activity\n            android:name="com.linusu.flutter_web_auth_2.CallbackActivity"\n            android:exported="true"\n            android:taskAffinity="">\n            <intent-filter>\n                <action android:name="android.intent.action.VIEW" />\n                <category android:name="android.intent.category.DEFAULT" />\n                <category android:name="android.intent.category.BROWSABLE" />\n                <data android:scheme="$ENV{AUTH_SCHEME}" />\n            </intent-filter>\n        </activity>$1#' "$m"
fi
perl -0ne 'my $s = quotemeta $ENV{AUTH_SCHEME}; my $n = () = /flutter_web_auth_2\.CallbackActivity/g; my $schemes = () = /<data android:scheme="com\.yazanus\.[a-z]+"/g; exit((/<application\b.*<activity\s+android:name="com\.linusu\.flutter_web_auth_2\.CallbackActivity"\s+android:exported="true"[^>]*>\s*<intent-filter>.*?<action android:name="android\.intent\.action\.VIEW" \/>.*?<category android:name="android\.intent\.category\.BROWSABLE" \/>.*?<data android:scheme="$s" \/>.*?<\/intent-filter>\s*<\/activity>.*<\/application>/s && $n == 1 && $schemes == 1) ? 0 : 1)' "$m" \
  || { echo "scaffold: could not add the flutter_web_auth_2 CallbackActivity for $AUTH_SCHEME (and no other app scheme) inside <application> in $m" >&2; exit 1; }
# The package README advises taskAffinity="" on every exported Activity; Flutter's MainActivity template has it.
perl -0ne 'exit(/<activity\b[^>]*android:name="\.MainActivity"[^>]*android:taskAffinity=""/s ? 0 : 1)' "$m" \
  || echo "scaffold: warning: MainActivity has no android:taskAffinity=\"\" in $m (flutter_web_auth_2 advises it)" >&2
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
  # Google MLKit (used by mobile_scanner 5.x on iOS) ships no arm64 simulator slice, so its pods
  # build x86_64 only for the simulator; build the app the same way or it cannot find Pods_Runner.
  # Simulator only: device builds keep arm64.
  for xc in ios/Flutter/Debug.xcconfig ios/Flutter/Release.xcconfig; do
    grep -q 'EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]' "$xc" || printf '\nEXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64\n' >> "$xc"
    grep -q 'EXCLUDED_ARCHS\[sdk=iphonesimulator\*\] = arm64' "$xc" \
      || { echo "scaffold: could not exclude arm64 simulator in $xc" >&2; exit 1; }
  done
fi
# Website links from the sign-in screen and the account page (url_launcher, Store app): the Terms, the Privacy Policy
# and /account-deletion/ open in the browser. Android 11+ package visibility for https VIEW intents, as in the
# url_launcher README (a second <queries> element is merged with the template's). Google sign-in (google_sign_in 7.x,
# Credential Manager) needs no manifest entry. Idempotent; fails loudly.
if [ "$pkg" = "yazan_store" ]; then
  grep -q '<data android:scheme="https" />' "$m" || perl -0pi -e 's#(\n?[ \t]*</manifest>)#\n    <queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW" />\n            <data android:scheme="https" />\n        </intent>\n    </queries>$1#' "$m"
  grep -q '<data android:scheme="https" />' "$m" \
    || { echo "scaffold: could not add the https <queries> entry to $m" >&2; exit 1; }
fi
export LABEL="$label"
# What the home screen shows under the icon.
perl -pi -e 's/android:label="[^"]*"/android:label="$ENV{LABEL}"/' android/app/src/main/AndroidManifest.xml
perl -0pi -e 's/(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*/$1$ENV{LABEL}/; s/(<key>CFBundleName<\/key>\s*<string>)[^<]*/$1$ENV{LABEL}/' ios/Runner/Info.plist
# The store's mark as the launcher icon (assets/icon/icon.png, set in pubspec.yaml).
dart run flutter_launcher_icons
echo "scaffolded $pkg as com.yazanus.$short"
