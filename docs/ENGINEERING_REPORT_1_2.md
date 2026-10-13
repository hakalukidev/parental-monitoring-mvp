# Seftly 1.2.0 engineering report

Validated 2026-10-13, Asia/Dhaka. This records the first master prompt before the subsequent dashboard/communications/media addendum. Production was verified at 17:14:21. Source archive: `1.2.0-699f21b-working-tree`; its SHA-256 identifies the deployed uncommitted implementation precisely. The previous 1.1 report remains in `ENGINEERING_REPORT_1_1.md`.

## A. Implementation summary and required feature inventory

1. **Web normalization/filtering — implemented and tested.** HTTP API tests and native evaluator tests cover domain equivalence, exact paths, canonical URLs, IDN handling, ALLOW precedence and hostname boundaries. Complete physical-browser/OEM acceptance remains pending.
2. **Audio-only Sound Around — implemented and tested on the Infinix and Android 36 emulator.** Actual audio RTP arrived at the parent; its live state requires received packets. Both endpoint Stop paths were exercised across the local tests. No recording is implemented. Wider networks/TURN and physical Android 14+ acceptance remain pending.
3. **Call activity — implemented; physical ingestion verification pending.** Permission eligibility was observed on the Infinix, but its existing call logs were deliberately not used as automated fixtures. The 1.2 collector transfers minimized direction/time/duration/identifier metadata only.
4. **SMS activity — implemented; physical ingestion verification pending.** The Infinix reported granted SMS access. Existing messages were not queried for these tests. This version transfers direction/time/masked-identifier metadata only, without bodies.
5. **Notification activity — implemented and tested.** Synthetic notifications posted on the Infinix and emulator reached the authenticated backend through the actual listener/queue/worker. Only selected package, event type and time were transferred; the fixture's secret body was absent.
6. **Photo detection — blocked by external model/evaluation.** Selected-media infrastructure is implemented and disabled; no production detector or accuracy claim.
7. **Video detection — blocked by external model/evaluation.** Bounded sampling, resume/cancellation and corroboration infrastructure is implemented and disabled; no production detector or accuracy claim.
8. **New parent pages — implemented and tested.** Audio, calls, SMS, notifications and selected-media safety have data-backed states, child identity and configuration/history controls.
9. **Dates/times — implemented and tested in changed paths.** UTC storage/query boundaries, local display, local-calendar Today/Yesterday and honest missing timestamps. No exhaustive claim about every historical screen.
10. **Android identity/version — implemented and verified.** Both production APKs are 1.2.0, code 3, with original IDs and signers.
11. **Routine approvals — audited; routine controls remain guardian-managed.** Policy synchronization has no child approval dialogs. The separate media review still exists in 1.2 and is addressed by the subsequent addendum.
12. **Notification minimization — implemented and checked.** Stable low-importance service/session channels, bounded/deduplicated requests, only-alert-once status updates and no event-per-notification spam. OS-required indicators remain.
13. **Security regression tests — implemented and passing.** 24 backend tests include two-family ownership, role/token/session checks, strict content rejection, capability/global gates, deduplication, scoped pagination and deletion/replay behavior.
14. **Release builds — verified signed Android APKs.** 39 Flutter tests, 14 Kotlin tests, clean Flutter analysis, Android lint zero errors/56 warnings. iOS is unverified: the build reports `Application not configured for iOS`; full Xcode/CocoaPods are also unavailable.
15. **Production deployment — deployed and verified.** Public HTTPS readiness, synthetic-family authenticated checks and all preexisting record-ID preservation passed. New collectors initially remain disabled pending individual rollout verification; no payments/subscriptions were added.

## B. Important files

- Backend: `src/services/webTargets.ts`, `controllers/webRulesController.ts`, `controllers/audioSessionController.ts`, `controllers/activityController.ts`, `services/activityValidation.ts`, `services/features.ts`, `models/AudioSession.ts`, `models/ActivityPolicy.ts`, `models/ActivityEvent.ts`, `models/ActivityCapability.ts`, media leases and Socket.IO handlers; new audio/activity routes and device capabilities.
- Child: `blocker/WebAddress.kt` and `WebFilterEvaluator.kt`; `audio/AudioCheckInService.kt`; shared camera/WebRTC lifecycle and Android audio-device callbacks; `activity/ActivitySync.kt`, `ActivityMetadata.kt`, `SeftlyNotificationListener.kt`; `safety/ApprovedSafetyModel.kt`, `SelectedMediaWorker.kt`, `SafetyScores.kt`; additive SQLite v8 queues; manifest, setup/home/session screens and worker cancellation.
- Parent: `design/website_rule_editor.dart`, `family_date_time.dart`, `services/audio_check_in.dart`, `app_info.dart`, `screens/sound_around_screen.dart`, `activity_history_screen.dart`, web-rule editing, dashboard navigation, API service and installed-version platform channel.
- Verification/release: backend tests, Kotlin activity/safety/web tests, Flutter feature/editor tests, `scripts/verify_release.py`, `package_backend.sh`, `device_qa.py`, `device_fixture_api.cjs`, `run_child.py`, and the version-specific VPS backup/preparation/smoke/deploy scripts.

## C. Parent-first operation

App/web rules, schedules, limits, downtime, geofences and routine reports use guardian configuration and the device's granted access. Updating policy does not ask the child again. Optional Android notification-listener and supported call/SMS permissions are initial guardian setup. Revocation/restriction is reported honestly.

Sensitive capture in 1.2 uses a visible activation screen, existing runtime grants, mandatory fresh projection consent, foreground-service indicators and Stop. The newer addendum removes the extra Seftly confirmation; it does not turn a runtime grant into an exemption from Android foreground activation or projection requirements. See [Android foreground-service restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).

## D. Notification behavior

Routine policy/queue sync does not create notifications. Monitoring uses a stable low-importance foreground notification without heartbeat alerts. Camera/audio status uses stable session IDs and only-alert-once updates. Pending sensitive requests are bounded, expired and deduplicated. The notification collector excludes Seftly/system/security/banking packages and reads no notification extras, titles, text or reply actions. Required active capture notifications and Stop remain visible.

## E. Web filtering

`example.com`, `www.example.com`, HTTP/HTTPS roots, case, surrounding whitespace and root dots canonicalize to the same domain. Meaningful paths, query strings or nondefault ports promote a domain input to an exact URL, preserving path/query case. Fragments are ignored. Wildcard domains include apex/subdomains; legacy TLD wildcard/category/keyword and ALLOW precedence remain supported. Lookalikes do not match. Common IDNs become punycode; IDNA deviation characters require explicit ASCII punycode to avoid Android/parser disagreement. Invalid schemes, credentials, wildcards, malformed names and oversized normalized addresses fail validation.

An authenticated preview shows the actual scope before saving. Editing changes the real target/type/action. Exact URL rules require child policy protocol 2, protecting older clients from silent broadening. Browser coverage depends on supported Accessibility address extraction; evaluator correctness does not prove every browser's integration.

## F. Audio check-in

Audio reuses authenticated WebRTC signaling, participant-bound sessions, negotiation state, microphone exclusivity, expiry and disconnect cleanup. The native service adds only a microphone track; it does not open the camera. Record-start/error callbacks drive actual microphone status. The parent requests no microphone capture and shows Live only after connected transport, an audio track and positive inbound RTP packet counts; stalled receive traffic fails closed. Retry callbacks are generation-guarded.

Android 36 emulator testing received audio for over a minute, displayed Good quality and verified parent Stop. The Infinix X697 (Android 11/API 30) used Android's one-time permission dialog, streamed audio to the emulator with positive packet statistics, and ran for over two minutes. Its child Stop returned both apps to ended/off states. Test screenshots contain only the synthetic family: `docs/previews/qa-audio-live.png`, `qa-infinix-audio-parent.png`, `qa-infinix-audio-child.png`. Audio was not saved. This exercised a local signaling fixture with STUN; remote TURN availability is configured but was not thereby proven.

## G. Calls/SMS

The 1.2 public-provider collector reads only supported fields, starts from authorization, hashes identifiers, keeps at most the last four digits for display, bounds each pass/queue and schedules retries without repeated approval. Call types map incoming/outgoing/missed/rejected/blocked; SMS includes incoming/outgoing and excludes drafts. There is no contact query, SMS body, MMS attachment, default-handler impersonation or telephone recording in this release.

READ_CALL_LOG and READ_SMS are hard-restricted: installer allowlisting and actual runtime eligibility matter even for private APKs. See [Android permission definitions](https://developer.android.com/reference/android/Manifest.permission.html) and [AOSP runtime restrictions](https://source.android.com/docs/core/permissions/runtime_perms). The Infinix reported both grants, but physical provider ingestion/SIM variations were not tested with its real communications. The next addendum extends legitimately accessible fields behind explicit authorization.

## H. Notifications

The real NotificationListenerService requires Android's initial notification-access setup. Guardian policy selects packages; excluded packages cannot be enabled server-side. The collector never reads extras/content, coalesces updates for 30 seconds, bounds its key map, stores account-bound event IDs and queues offline. Worker uploads are child-authenticated; cross-family reads/configuration/deletion are denied. Permission/policy revocation purges excluded pending data. Infinix and emulator fixture posts produced distinct synchronized metadata records. See [Android NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService).

## I. Selected photo/video safety

No licensed/evaluated model is selected, downloaded or packaged. Reviewed candidates included OpenNSFW2 (port code licensing does not establish model/data suitability) and a Falconsai model card; neither supplied a verified Seftly Android quality/battery evaluation. Model accuracy, precision, recall, false-positive/negative rates, inference latency, peak memory and battery consumption are **not measured**.

The disabled pipeline accepts only explicitly selected persisted content URIs, not gallery enumeration or hidden screen access. It bounds media size/image decode/video duration/eight-frame sampling, supports cancellation/resume, uses two CPU inference threads, verifies asset hashes/tensor shapes and requires a licensed/evaluated manifest. Only categorized confidence/model metadata could upload; original media stays local. Production rejects test/stub model approvals. Deterministic Kotlin score fixtures are labeled test-only and do not establish real TensorFlow Lite inference or detection accuracy. See [OpenNSFW2](https://github.com/bhky/opennsfw2) and [Falconsai's model card](https://huggingface.co/Falconsai/nsfw_image_detection).

## J. UI and identity

New pages retain the existing Seftly Material 3 theme and light/dark/large-text behavior, actual child identity, capability/sync/queue state, date filters, pagination, deletion and safety review controls. Last completed negotiated sessions are timestamped; no successful date is invented. Installed version comes from Android metadata. Original icons/display names remain Seftly Parent/Child.

Production packages remain `com.example.parent_app` and `com.example.childapp`, versionCode 3. The signing continuity report is `ANDROID_IDENTITY_MIGRATION.md`. Separate `.qa` packages and a synthetic notification source were used for tests; real app tokens/data were not repointed or cleared. The Infinix update retained first-install time 14:15:40 and changed last-update time to 17:15:07. The signed parent 1.1-to-1.2 emulator update also succeeded.

## K. Security

All new parent endpoints authorize ownership; child uploads bind to their authenticated identity and canonical child IDs. Strict schemas reject bodies/OTPs/unknown content in the 1.2 metadata API. Global feature gates, guardian settings and actual reported capability must all allow ingestion. Identical event IDs deduplicate; retained records expire through a new collection TTL; deletion marks a cutoff against ordinary old queue replay. Existing historical retention remains untouched. Queue ownership prevents cross-account uploads; explicit logout stops workers and clears departed account caches. No raw media, phone number/body or tokens are intentionally logged.

Source-security checks and production dependency audit pass. This is not a complete historical secret audit. Previously tracked private material remains a remediation concern; signing continuity and deployed credentials must be handled deliberately.

## L. Executed verification and artifacts

- Backend: `npm test` (TypeScript build plus 24 passing tests), `npm run lint` passing, `npm audit --audit-level=high` zero vulnerabilities; the release packager executed all gates.
- Parent: `dart format`, `flutter analyze` no issues, `flutter test` 39 passing, `flutter build apk --release` successful. Normal debug build successful; an emulator storage shortage was resolved by removing only a completed QA fixture before install.
- Child: `gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleRelease` successful, 14 tests, zero lint errors/56 warnings. TensorFlow Lite/native-plugin packaging warnings remain documented, without baseline suppression.
- `python3 scripts/check_security.py`, `verify_release.py`, Python syntax and `git diff --check` passed. Original key-file blobs/certificates were checked against baseline commit `73ee98e`, including after that key was removed from current Git tracking.
- Signed APKs: `release_artifacts/seftly-parent-1.2.0.apk` (SHA-256 `d52d53fa622dbf82ef5f17bc6bc1457955636f9e977a4bb23d03f40cacac0919`) and `seftly-child-1.2.0.apk` (`49a8a207c0b18a8b1025d1c42cd3aaf999bc6865f80877e8323799f5262256be`). Public artifact metadata is `artifacts-1.2.0.json`.
- iOS command executed and failed with `Application not configured for iOS`. This workstation selects CommandLineTools and has no CocoaPods; no IPA or iOS acceptance is claimed.

## M. Production

Verified API: `https://api.hakaluki.dev`; readiness 200 and workstation TLS verification 0. Running revision `1.2.0-699f21b-working-tree`, one `parental-monitoring-backend` PM2 fork under `deploy`. Archive SHA-256 `10ea2eb76623873f6663dcddccbbd7fa3bd9ff3623177d0e50afcb2ea3c9c938`. The stable backend symlink points to `/home/deploy/seftly-releases/20261013-1.2.0-699f21b`.

Fresh restore-tested backup: `/home/deploy/seftly-releases/backups/20261013-1.2.0-73ee98e`. Application backup SHA-256 `58622270138c664f68305a62ecea90478e264f5429b2f83c412f99dd5202637f`; database backup `325a9a63bc5a66a47a782ef234af9ce3e492c5326775e18786d95d261dc248f1`. All 14 backed-up collection counts/index counts were verified through an isolated restore and its database removed. This is a live-writer logical standalone backup, not point-in-time protection.

Staging used a fresh empty database and synthetic families, including enabled audio/notification tests; it did not use production child data as feature fixtures. Production verification used temporary synthetic families and cleaned them. All preexisting IDs remained present, including 37 users and 8,020 location records. Only the new activity/audio collection indexes were applied. Environment secrets were preserved mode 0600, and no data reset/blanket index migration occurred. PM2 reload had one transient 502, then retry/readiness/authentication checks passed. The automatic rollback branch was prepared but not triggered. Application rollback is the previous 1.1 symlink target `/home/deploy/seftly-releases/20261013-73ee98e`; preserve the live database.

## N. Remaining requirements

Validate wider physical/OEM browsers, geofences, call/SMS provider ingestion, SIM differences and Android 14+ camera/audio/projection on a real phone. Verify TURN relay across separate networks. Select and license a real model, then evaluate an authorized representative dataset and Android resource cost before enabling safety. Complete iOS project/toolchain/signing if required. Remediate historically exposed secrets without breaking installed-app signing continuity. The addendum implements compact cards, expanded authorized communication history and the rule that Seftly adds no unnecessary child approval step.
