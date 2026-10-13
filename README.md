# Seftly family safety

Seftly connects a Flutter parent app, a Kotlin/Compose Android child app and a TypeScript/Express/MongoDB backend. Parents manage each child's app rules, usage reports, supported-browser rules/history, location history and safety zones. Screen and camera check-ins require explicit approval on the child device. The backend relays WebRTC signaling; it does not record media.

Production IDs remain `com.example.parent_app` and `com.example.childapp`. The child is distributed as a signed standalone APK. Debug packages use `.debug` and do not replace installed production apps.

## Development

Use Node 22+, Flutter 3.44.0, Android SDK 34+ and Java 17+ (Android Studio's bundled JDK works). MongoDB is required for the backend. Install CocoaPods and full Xcode for the existing iOS plugins.

```sh
cd backend
npm ci
cp -n .env.example .env
# Supply distinct private authentication secrets before starting.
npm run dev
```

```sh
cd parent-app
flutter pub get
flutter run
```

```sh
cd child-app
# Set JAVA_HOME / ANDROID_HOME or an ignored local.properties sdk.dir.
bash ./gradlew assembleDebug
```

The default clients use `https://api.hakaluki.dev`. Release builds require normal TLS verification and reject broad cleartext traffic. For local emulator checks, the debug-only network configuration permits `10.0.2.2`, `127.0.0.1` and `localhost`.

```sh
# Child (debug only)
bash ./gradlew assembleDebug -PdevelopmentApiUrl=http://10.0.2.2:4001
# Parent (debug only)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4001 --dart-define=SOCKET_URL=http://10.0.2.2:4001
```

## Verification

```sh
cd backend
npm run build
npm run lint
npm test
npm audit --audit-level=high
```

Backend tests start their own temporary MongoDB process and use two isolated families. They never use the configured application database. The first test run may download a MongoDB binary.

```sh
cd parent-app
flutter analyze
flutter test
```

```sh
cd child-app
bash ./gradlew testDebugUnitTest lintDebug
```

From the repository root, run `python3 scripts/check_security.py`. CI runs compilation, lint, tests, formatting, dependency auditing and tracked-source security checks. Signing secrets are excluded from PR jobs.

## Releases and operational limits

Read [release and deployment instructions](docs/RELEASE.md) before generating artifacts or changing production. Existing keys are preserved locally; exposed historical keys/environment values still require a continuity-aware remediation plan. Removing a file from Git tracking does not erase Git history.

Backend 1.1.0 was deployed to `https://api.hakaluki.dev` on 2026-10-13 with a restore-tested backup and verified public authentication/Socket.IO checks. See the [deployment and rollback record](docs/PRODUCTION_DEPLOYMENT.md). Approved media check-ins require the updated child app to register consent capability version 2.

This is a single-instance Socket.IO deployment with in-memory presence. Use one child account per primary child device. Android permissions and vendor battery management can limit monitoring. Reboot recovery does not silently restart camera, microphone or screen capture. Foreground location resumes from the visible child app because while-in-use permission alone cannot authorize a background boot start.

Calls/SMS extraction, social-message extraction, a standalone Sound Around feature, notification monitoring, image/video safety inference and verified payment transactions are not complete features in this repository. Do not infer completion from related filenames or camera audio support.

## Documentation and previews

- [Architecture, API ownership and session lifecycle](docs/ARCHITECTURE.md)
- [Permissions, privacy, export and retention](docs/PRIVACY.md)
- [Builds, signing, deployment and rollback](docs/RELEASE.md)
- [Implementation checklist](docs/IMPLEMENTATION_CHECKLIST.md)
- [Engineering report](docs/ENGINEERING_REPORT.md)
- [Actual validation results and release limits](docs/VALIDATION.md)
- [Secondary milestone feasibility and platform references](docs/FUTURE_FEATURES.md)
- [Original launcher artwork and previews](assets/branding/launcher-preview.png)
- [Parent login visual baseline](parent-app/test/goldens/login.png)
- [Parent child-card visual baseline](parent-app/test/goldens/family-card.png)
