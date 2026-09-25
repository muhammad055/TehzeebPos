# tehzeeb_mobile

Flutter owner/manager app. Roadmap: [`../ProjectPlanMobile.md`](../ProjectPlanMobile.md).

## First-time setup (once per machine)

The `android/` and `ios/` platform folders are **not committed yet** — the M0 scaffold was
written on a machine without Flutter installed. Generate them in place (keeps existing `lib/` and `pubspec.yaml`):

```bash
cd mobile
flutter create --org com.tehzeeb --project-name tehzeeb_mobile .
flutter pub get
flutter analyze
```

Then commit the generated `android/`, `ios/`, and `test/` folders (`.gitignore` already excludes build output and local files).

### Allow plain-HTTP to the local backend (dev only)

- **Android**: in `android/app/src/main/AndroidManifest.xml`, add `android:usesCleartextTraffic="true"` to `<application>` (better: put it in a debug-only manifest at `android/app/src/debug/AndroidManifest.xml`). Production uses HTTPS.
- **iOS simulator**: add to `ios/Runner/Info.plist`
  `<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>`.

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
