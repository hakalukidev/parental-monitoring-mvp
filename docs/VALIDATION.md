# Validation record

Validated locally on 2026-10-13 (Asia/Dhaka), against the modified working tree based on `73ee98e9856d29666a5bc3a9e83b170079d2c695`. Commands below summarize completed runs, not suggested or fabricated checks. The backend ran on Node 26.7.0 and the parent on Flutter 3.44.0; CI targets Node 22 but has not run remotely. Sandbox access was granted for installed SDK caches, local servers and emulator operations. No physical device was selected for installation.

## Baseline and corrected failures

- Baseline Flutter: analysis passed; four existing tests passed.
- Baseline backend: direct TypeScript compilation passed, but bundled/tracked executable permissions broke npm script invocation and there was no usable lint configuration. Dependencies/scripts and lint configuration were corrected; tracked `node_modules` removed while retaining local dependencies.
- Baseline child: wrapper JAR absent, wrapper invocation incompatible and default system Java unavailable. Restored official Gradle 8.13 wrapper/distribution checksum and used Android Studio's bundled JDK.
- Interim Flutter failures included layout issues, asynchronous HTTP test-fixture handling, unreadable test fonts, and a syntax regression from an over-broad brace cleanup. Each was corrected; final analysis and normal tests reran successfully. The cleanup script is not part of the repository.
- The final isolated usage-record check caught an implementation error: the TypeScript interface/controller defined version, availability and time-zone fields, but the Mongoose schema omitted them. Those fields are now persisted, unavailable measurement defaults are null, and a new real HTTP/database regression verifies metadata, computed totals, parent availability and family-summary behavior. The updated backend suite passes 17 tests. The physical accuracy gate remains open.
- Existing emulator storage rejected the updated large parent debug APK. A separate temporary emulator was created from the installed API 36 arm64 image, leaving pre-existing apps/data and the connected physical device untouched. Virtual/emulated cameras and disabled host audio were used. Debug fixtures and login-driver failures do not count as completed end-to-end tests. The driver was corrected to dismiss the keyboard between fields; final debug builds explicitly use both local endpoints.

## Final automated checks: passed

Backend, from `backend/`:

```sh
npm run build
npm run lint
npm test
npm audit --audit-level=high
```

Compilation and lint pass. **17 tests pass, zero failures/skips.** Tests use isolated MongoMemoryServer, real Express requests and Socket.IO connections for two families. Coverage includes register/login/child creation, JWT roles and refresh/revocation, REST/socket ownership, absence of cross-family presence/history/location leaks, both media lifecycles and negotiation replay/expiry, temporary-access ownership/expiry, payload bounds, location/history deduplication and freshness, unavailable metrics, privacy export/deletion, schedules and DST day boundaries, positive policy/web/geofence operations, primary-device rename/pause preservation, persisted version-2 usage availability and simultaneous media reservation. **Audit: zero known vulnerabilities.** This is an npm dependency audit, not a full penetration test or Flutter/native dependency audit.

Parent, from `parent-app/`:

```sh
dart format lib test
flutter analyze
flutter test --update-goldens
flutter test
flutter build apk --release
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=API_BASE_URL=http://10.0.2.2:4001 \
  --dart-define=SOCKET_URL=http://10.0.2.2:4001
```

Analysis: **no issues**. **24 tests pass.** Goldens were updated, then checked in a separate normal test run. Coverage includes validation, secure password visibility, registration navigation, dark/light layouts at 320/390/800 widths with enlarged text, child cards, battery-only location parsing, loading/empty/error/status semantics, dashboard activity and selected-child navigation, and five feature empty states. Signed release and isolated debug APK builds pass. Flutter emits plugin Swift-package/Kotlin migration warnings; these are future toolchain concerns, not successful iOS compilation.

Child, from `child-app/`, with `JAVA_HOME` set to the installed Android Studio JBR:

```sh
bash ./gradlew testDebugUnitTest lintDebug assembleDebug assembleRelease \
  -PdevelopmentApiUrl=http://10.0.2.2:4001
```

Build succeeds. **8 unit tests pass, zero failures/errors/skips.** They cover ordinary/overnight schedules, local-day rollover, foreground intervals/hour allocation, independent screen-state accounting, duplicates, domain boundaries, allow overrides and disabled rules. Android lint: **zero errors, 48 warnings** (including existing deprecations/hardcoded UI strings). No Android instrumentation suite, SQLite framework migration test or multi-device benchmark was run. The endpoint property applies only to debug; release retains HTTPS production defaults.

Repository root:

```sh
python3 scripts/check_security.py
git diff --check
python3 scripts/verify_release.py
bash scripts/package_backend.sh
```

Current-source secret/TLS/signing regression checks pass; this is not a full Git-history secret audit. Whitespace check passes. Both APK identities/version codes/original certificates and unchanged original key files verify. Backend packaging reruns build/lint/tests/audit and produces an archive excluding private runtime/signing files. Packaging now stages into a fresh directory on every run; its 63 compiled files were compared byte-for-byte with the current build, with no stale/nested files or unexpected entries. Artifact checksums are in `release_artifacts/SHA256SUMS`; public certificate/build metadata is in `artifacts.json`.

## Emulator scope

`backend/test/device-server.cjs --isolated` starts a loopback-only backend with ephemeral MongoDB and random test-family credentials. The private fixture is stored outside the repository, mode 0600; credentials/tokens are not printed. `scripts/emulator_smoke.py` rejects physical-device serials and operates only on explicitly selected `.debug` apps. Do not use this fixture for production.

Initial API 36 emulator checks passed child and parent login, visible notification/location/usage setup, primary-device registration and actual authenticated ONLINE presence. Child home accurately showed unavailable enforcement setup and capture off. Updated native/Flutter apps are additionally checked on the separate QA emulator. Final media/device outcomes are recorded below; backend protocol tests alone do not establish camera/screen hardware operation.

On separate emulators, the parent displayed Stop while waiting; the child reviewed and declined a screen request, and the parent displayed Request declined. The isolated database recorded REJECTED/CHILD with no offer/answer. A subsequent request showed a fresh Android projection dialog, allowed a normal share-scope selection, and started the visible child capture service only after approval. Offer and answer were recorded, but a live transport did not establish between the two emulator NAT environments and the parent ended the session. This is a **failed live screen-stream check**, not a passing stream. Private TURN connectivity remains an external gate. A later constrained test used Android’s ordinary split-screen mode on one emulator to keep both apps active on one virtual network: fresh projection consent led to a rendered live video, a child live indicator and backend ACTIVE after offer/answer. The actual child Stop control returned the parent to Sharing stopped and recorded ENDED/CHILD. This passes local screen capture/video/Stop only; it does not turn the failed cross-emulator transport check into a pass. The live screenshot is `docs/previews/screen-split-local-emulator.png`. In the failed cross-emulator attempt, the child returned to capture-off state after teardown; subsequent Stop was unavailable because capture had already ended.

The local camera flow required child approval and the normal Android camera permission prompt. A virtual back-camera image rendered on the parent, the child displayed Your camera is streaming / Microphone is off, and the isolated database recorded ACTIVE with `withAudio: false` and both negotiation timestamps. No microphone permission was requested. A subsequent authenticated-token expiry ended the stream as SYSTEM; the child returned to capture-off state. This validates local virtual-camera/video and fail-closed expiry, not physical camera, audio, lens switching or real NAT/TURN. The rendered preview is `docs/previews/camera-split-local-emulator.png`. A later fresh session was ended by the actual child Stop button; the database recorded ENDED/CHILD. The driver initially labeled that tap as parent Stop, but database evidence corrected the interpretation. The final build adds toolbar Stop for short viewports. A fresh live session was stopped through that parent toolbar, and the backend recorded ENDED/PARENT; this confirms parent Stop separately from the earlier child Stop.

The final native release cycle encountered a transient incremental `packageRelease` worker failure without a diagnostic cause. The same test/lint/debug/release command reran successfully; the final APK was reverified. This is recorded separately from baseline failures and is not presented as an explained root cause.

Requested flow coverage:

1. Parent registration and child creation: real HTTP integration tests and isolated fixture setup pass.
2. Child/parent app login, guided notification/location/usage setup, device registration and actual ONLINE status: emulator checks pass. Accessibility/overlay enforcement setup remains unverified.
3. Actual emulator location retrieval: device/parent latest fix observed; physical accuracy and routes remain unverified.
4. Geofence CRUD/event rules, app/web policies, schedules, history/usage ingestion, temporary-access authorization: API/unit tests pass; actual phone/browser/geofence enforcement remains unverified.
5. Screen request/decline, fresh OS projection approval, local rendered video and actual child Stop: pass in the constrained local test.
6. Camera request/approval, normal camera permission, rendered virtual-camera video with microphone off and expiry teardown: pass in the constrained local test. Both actual child Stop and parent toolbar Stop were verified by their recorded stopping participants.
7. Token expiry and disconnect teardown: backend regressions and observed local camera expiry pass. Full network-off/reconnect and child reboot recovery flows were not completed.
8. Logout/access-refresh revocation and two-family isolation: backend regressions pass. Real-device logout/background completion and customer APK migration remain unverified.

The isolated emulator stored app inventory/policies and a daily usage report. Its missing metadata exposed the schema gap described above; the corrected persistence/parent-response path was then verified by the new integration test. The complete requested end-to-end matrix remains incomplete. Automated backend tests verify registration/child creation, ownership isolation, CRUD, sync, temporary access and signaling states. They do not substitute for actual phone app/browser restrictions, physical location/geofence crossings, real media tracks, network/reboot recovery or installing over customer APKs.

## Production backend deployment

On 2026-10-13 at 12:26:56 Asia/Dhaka, the tested backend archive was deployed to the user-supplied VPS using the verified `deploy` PM2 process and existing Nginx proxy. Node 20.20.2 installed the release's production dependencies. Before rollout, a database backup was restored into an isolated namespace and all 12 document/index counts matched; staged authentication, ownership and Socket.IO checks passed against a separate restored copy.

Public HTTPS readiness returned HTTP 200, revision `73ee98e-working-tree`, TLS verification result 0, including a separate workstation check. Two temporary production test families passed registration, parent/child login, refresh, device registration, role/ownership isolation, protected lookup, authenticated Socket.IO through Nginx, location isolation, rejected cross-family mutations, both consent/signaling lifecycles, Stop/replay rejection and logout revocation. Synthetic SDP exercised signaling; this does not prove physical video/TURN. All synthetic records and QA databases were removed. Every backed-up pre-existing record ID across all 12 live collections remained present afterward. PM2 stayed online with only the expected deployment restart.

An initial database-tools URI constrained restore namespace discovery, yielding zero restored documents; verification rejected that result, and the corrected restore passed before deployment. The PM2 fork reload produced one transient HTTP 502; subsequent retry, public smoke tests and readiness passed. The previous application and private restore-tested backups are retained. Application rollback is scripted but was not exercised on the live service. See [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) for precise paths, checksums, configuration changes and remaining acceptance limits.

## Failed or blocked

- `flutter build ios --release --no-codesign`: **failed**, “Application not configured for iOS.” Restored missing workspace/Podfile infrastructure, but full Xcode is absent (`xcodebuild -version` reports CommandLineTools) and CocoaPods is unavailable. iOS native-plugin compilation, bundle/signing and simulator/device behavior remain unverified. No IPA produced.
- Earlier workstation database connectivity check: **failed** with `MongoServerSelectionError`; no URI was printed. Subsequent VPS access verified the actual live database and enabled the completed backend deployment described above. The earlier failure did not establish a live database outage.
- Real TURN/NAT, physical Android/OEM permission/reboot/background/enforcement, production update/data preservation and full 23-flow acceptance matrix: **not completed**.
- Remote GitHub CI: **configured, not executed in this task**. No push or remote run is claimed.
- Website/real payments and secondary milestones: source/credentials/authorized integration/model evaluation unavailable; see `FUTURE_FEATURES.md` and the engineering report.

The final isolated database check found zero open screen/camera sessions. The task-owned debug apps, temporary QA emulator, loopback fixture/MongoDB and private fixture credentials were stopped/removed after testing; the original emulator and connected physical device were preserved.
