# Builds, signing, production and rollback

## Signing continuity

The existing local files `child-app/childapp-release-key.jks` and `parent-app/android/parentapp-release-key.jks` are preserved. They and `backend/.env` have been removed from Git tracking and are ignored. Their historical exposure remains: coordinate credential remediation with production access and installed-app signing continuity. Do not generate replacement signing identities as a build shortcut.

Each Android root accepts an ignored `key.properties`:

```properties
storeFile=../existing-release-key.jks
storePassword=<private secret>
keyAlias=<existing alias>
keyPassword=<private secret>
```

`storeFile` is relative to the app Gradle module, or absolute. Alternatively use `SEFTLY_STORE_FILE`, `SEFTLY_STORE_PASSWORD`, `SEFTLY_KEY_ALIAS`, `SEFTLY_KEY_PASSWORD` as private CI/runtime environment variables. Release tasks fail when signing configuration is missing. Debug uses a separate key and `.debug` package ID. Never install a debug package over the production package as an update.

Production versions are incremented to parent `1.1.0+2` and child code 2/name 1.1. Confirm the currently installed version before distribution; increase again if an installed release already has a higher code.

```sh
cd parent-app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

```sh
cd child-app
bash ./gradlew testDebugUnitTest lintDebug assembleRelease
```

Outputs are `parent-app/build/app/outputs/flutter-apk/app-release.apk` and `child-app/app/build/outputs/apk/release/app-release.apk`. These are universal standalone APKs. Verify signer certificates against the existing keystore and run installation-over-current-version on an authorized test device before rollout. Normal SQLite migrations preserve saved policies/history. No production-device installation is implied by an emulator debug smoke test.

The Gradle 8.13 child wrapper is restored with its official distribution checksum. Parent build dependencies are kept compatible with the existing Flutter toolchain. iOS build validation uses `flutter build ios --release --no-codesign`; installed CocoaPods/full Xcode are necessary for the existing native plugins, and Apple developer signing is required for distribution.

## Production preflight and release gates

The backend was deployed on 2026-10-13 after the user supplied VPS access. SSH, PM2, Nginx, live database connectivity, a restore-tested backup and the previous application were verified before rollout. Public HTTPS readiness and authenticated REST/Socket.IO checks passed. See [the production deployment record](PRODUCTION_DEPLOYMENT.md) for the release digest, evidence, backup and exact application rollback. The earlier workstation MongoDB ping failure did not establish an outage on the live VPS.

1. Identify the authorized host, deployment path, OS, Node version, reverse proxy and process manager. Use established infrastructure access; never guess credentials or print private environment files.
2. Verify the running release and inspect sanitized health/error counters. Check MongoDB connectivity without enabling automatic schema indexes.
3. Verify a database backup through a restore into an isolated temporary database. Record its checksum/location, restore verification and compatible previous release. Do not reset or downgrade live data.
4. Run the compilation/lint/test/audit gates. Confirm client/website contract compatibility and signing continuity.
5. Review schema changes: optional metrics/time-zone/expiration fields, media negotiation timestamps, new media leases and bounded unblock-request metadata. No existing monitoring history should expire without an explicitly configured policy and reviewed index application.
6. Supply distinct strong secrets, explicit HTTPS CORS origins, runtime TURN configuration, service-token credentials and `RELEASE_REVISION`. `TRUST_PROXY_HOPS` must match the verified proxy chain; default is zero.
7. Coordinate the new child consent-capability registration and website lookup proxy. Legacy child media requests are rejected; other authenticated monitoring features remain available. The new child must register on launch/login before approved check-ins work.

From the root, `bash scripts/package_backend.sh` builds/tests/audits and creates a release archive without runtime secrets or private keys. Its revision includes `-working-tree` because these edits have not been committed. Native dependencies must be installed on the target using `npm ci --omit=dev`; do not copy development `node_modules` between OS/architectures.

## Controlled deployment

Use the process manager and rollback mechanism actually found in preflight. Install into a new versioned release directory, retain the existing private environment separately, validate configuration/builds, then switch the application symlink or image and reload the verified process manager with minimal downtime. Do not replace the live environment with `.env.example` or apply blanket index synchronization.

The confirmed production PM2 process is `parental-monitoring-backend`, owned by `deploy`; Nginx proxies to port 4000. The deployment record identifies the user-supplied host and verified paths. For future releases, recheck those details and retain a compatible previous release before switching.

After rollout, verify HTTPS health, `/ready` database readiness, `RELEASE_REVISION`, authenticated parent/child REST and Socket.IO flows with safe accounts, ownership isolation, sanitized errors and service stability. A successful command alone is not deployment verification.

If critical checks fail, restore the previous compatible application release through the recorded manager/symlink/image rollback, preserve newly collected records and verify health. Do not attempt an unsafe database downgrade. Record failures and corrective action.

## Installation and platform limitations

Distribute signed child APKs privately; a Play Store release workflow is unnecessary. Install only on guardian-authorized devices, use the ordinary Android installer and guided permission setup. Do not instruct users to bypass system capture consent or hide privacy indicators. Vendor battery restrictions can interrupt background work; explain recovery through Android app settings.

Foreground location starts from the visible app. Boot recovery starts only permitted monitoring work; camera, microphone and MediaProjection never restart unattended. Multi-OEM testing and update installation over customer versions remain release gates. The included WebRTC plugins emit deprecation/built-in-Kotlin/Swift-package warnings; builds must be rechecked before a future Flutter or Android toolchain migration.
