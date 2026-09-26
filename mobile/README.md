# tehzeeb_mobile

Flutter owner/manager app. Roadmap: [`../ProjectPlanMobile.md`](../ProjectPlanMobile.md).

## Setup

Platform folders (`android/`, `ios/`) are committed and `flutter analyze` is clean. On a new machine:

```bash
cd mobile
flutter pub get
flutter analyze && flutter test
```

Cleartext HTTP to the local dev backend is already allowed for **debug builds only**
(`android/app/src/debug/AndroidManifest.xml`, `NSAllowsLocalNetworking` in `ios/Runner/Info.plist`).
Release builds must use an HTTPS `API_BASE_URL`.

**iOS on the Mac:** open `ios/Runner.xcworkspace` in Xcode once, select a Team under Signing & Capabilities
(bundle id `com.tehzeeb.tehzeebMobile`), then `cd ios && pod install` if CocoaPods hasn't run.

**Mac (Intel) note:** see `CLAUDE.md` → "Mac dev setup". Short version: Flutter 3.47.5 in `~/Developer/flutter`, Xcode 26.6 *Universal*, CocoaPods 1.17 as a user gem (`PATH=$HOME/.gem/ruby/2.6.0/bin:$PATH`, `LANG=en_US.UTF-8`), install on a phone with
`flutter run --release -d <device-id> --dart-define=API_BASE_URL=http://<mac-hostname>.local:5050/api` (release mode; use the `.local` hostname; keep the phone unlocked; backend on `http://0.0.0.0:5050`).

**Windows dev box note:** if `flutter.bat` fails with "blocked by group policy" it is calling PowerShell.
Run the tool directly instead: `dart.exe --disable-dart-dev <flutter>/bin/cache/flutter_tools.snapshot <args>`
with `FLUTTER_ROOT` set.

## Run against the local backend

Start Postgres + backend (see root `CLAUDE.md`), then:

```bash
# Android emulator (10.0.2.2 = host machine)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5050/api

# iOS simulator
flutter run --dart-define=API_BASE_URL=http://localhost:5050/api
```

Sign in with an `owner` or `admin` account (create an owner in the web app: Users → Owner).
`cashier` accounts get a "not allowed" screen by design.
