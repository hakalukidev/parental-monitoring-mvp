# Seftly 1.3.0 completion report

2026-10-13, Asia/Dhaka. Main implementation and production rollout are complete. The user ended additional QA; remaining acceptance checks below are explicitly unverified. The [1.2 master implementation report](ENGINEERING_REPORT_1_2.md) preserves its full A–N report and 15-feature inventory; this addendum supersedes its communications, media-confirmation, dashboard, version and rollout status.

## A. Supported call/SMS history

Implemented the public Android call/SMS provider collectors, encrypted offline queue, authenticated ingestion, encrypted backend storage and parent history pages. Calls include available number/contact, direction, timestamp, duration, provider ID and phone/SIM account fields. Missing duration is reported as unknown. SMS includes incoming/outgoing direction, available address/contact/body, provider/thread identifiers, read/delivery state and timestamps. Android's SMS provider supplies already-assembled message bodies; Unicode/long-body preservation has unit coverage.

The parent can configure collection, message content, contact names, bounded initial import (1–30 days) and retention; search, paging, caller/thread grouping, daily/weekly statistics and category deletion are implemented. Historical metadata remains accessible. Existing families default to detailed collection off; enabling server infrastructure does not automatically authorize new content collection.

MMS supports accessible provider text and metadata, including attachment counts; attachments remain on-device. Missing or inaccessible text is not represented as complete content. Actual MMS ingestion, outgoing-provider changes, multipart radio delivery and OEM/provider-specific fields are not physically verified. Private app/VoIP stores, deleted records and telephone audio are unsupported.

Synthetic Android 36 emulator evidence: one missed call and three received SMS records reached the backend; normal bodies were preserved and the OTP body was withheld. SMS/dialer default roles remained false. Infinix API 30 permission eligibility was observed earlier, but its private call/SMS history was not used as QA data. Android sensitive-permission eligibility varies by OS/installer; this app neither impersonates a default handler nor bypasses permission restrictions.

Numbers, names and bodies are AES-GCM encrypted in the Android Keystore-backed queue and backend storage, with an independent private backend key. Search/group indexes use keyed digests. TLS, child-account binding, parent ownership, bounded queues and expiring deletion tombstones protect transfer/history. Security-message filtering occurs before queueing and again on the server; it is conservative and cannot guarantee recognition of every secret.

## B. Media controls

Removed Seftly's per-session Allow button. Existing camera/microphone grants are reused; foreground requests can activate immediately after authenticated session checks. Android 11+ background sensor restrictions may require opening the app; missing/revoked grants still require Android's dialog. Screen sharing always requests Android MediaProjection consent. No projection token is persisted/reused and no Accessibility auto-approval is implemented.

Two Infinix QA audio sessions reached actual inbound RTP at the emulator parent using one microphone grant. Parent Stop and child Stop passed. A physical screen session directly opened Android's projection dialog and rendered the synthetic child home; Stop worked. The second screen session reached capture, but its fresh dialog was not observed by the agent, so repeat-dialog acceptance is unverified. Physical camera acceptance is unverified; the final emulator camera attempt ended before rendered video could be verified. Earlier 1.1 virtual-camera evidence is historical and does not establish this flow's acceptance.

Visible foreground capture notices, sensor indicators and Stop remain. Disconnect/expiry/participant checks have backend coverage. No live audio/video recording or storage is implemented. TURN relay behavior, broader network conditions, API 26–29 automatic background activation and a physical Android 14+ device remain unverified.

## C. Child notifications

Routine policy/history synchronization produces no per-event notification. Monitoring/capture notices use stable IDs, low importance and only-alert-once updates. Android-required device actions remain available through a bounded, deduplicated low-importance request notice and the child home. Required active-capture indicators and Stop remain visible.

## D. Compact dashboard

Child rows start collapsed; tapping toggles one expanded child, and refreshing status retains the selected child. Compact identity/status/last-seen rows replace the large first-view cards; expanded controls retain correct child identity, battery/location/usage information when actually reported and the existing Seftly theme.

Golden screenshots: [three collapsed, light](../parent-app/test/goldens/dashboard-collapsed-light.png), [dark](../parent-app/test/goldens/dashboard-collapsed-dark.png), [expanded, light](../parent-app/test/goldens/dashboard-expanded-light.png), [dark](../parent-app/test/goldens/dashboard-expanded-dark.png), [small screen](../parent-app/test/goldens/dashboard-small.png). Tests cover 1/2/3/5/10 children, long names, 320px screens, tablet width, light/dark, 2× text, scroll reachability, empty state, routing and refresh selection.

## E. Executed checks

- Backend: `npm run build`, `npm run lint`, `npm test`: 27 passed; release packaging and `npm audit --audit-level=high`: zero vulnerabilities.
- Parent: `flutter analyze`: no issues; complete `flutter test` run: 61 passed. Final targeted dashboard run: 19 passed, including the subsequently added small-screen golden; these overlap the full run.
- Child: Gradle debug unit tests: 18 passed; debug/release builds and lint completed with zero errors, 59 debug/60 release warnings. Remaining lint warnings are recorded in generated Android lint reports; no blanket dependency upgrade was attempted.
- Current-source security guard, signing/package/version verification and whitespace checks passed. Signing identities match retained baseline `73ee98e`.
- Interim failures: expected golden differences after UI wording changes, an old action test that assumed expanded cards, emulator storage exhaustion and the provider dirty-flag refresh bug were corrected. Synthetic SMS refresh then reached the backend. Some UI driver steps targeted the wrong restart label or a changed phone screen; they were not counted as passes.
- QA capture was stopped when the phone changed screens. The driver now checks focused windows as well as activities before reading test UI. No additional QA was performed after the user's stop instruction.

## F. Main code paths

Backend: `src/controllers/communicationController.ts`, `services/communicationPrivacy.ts`, `services/communicationValidation.ts`, `models/CommunicationRecord.ts`, `models/CommunicationCapability.ts`, `routes/communicationRoutes.ts`, activity policy/config gates and security tests.

Child: `communication/CommunicationSync.kt`, `CommunicationQueue.kt`, `CommunicationCipher.kt`, `CommunicationPrivacy.kt`, `CommunicationObservers.kt`, `consent/MediaActivationPolicy.kt`, `SessionConsentController.kt`, `SessionConsentActivity.kt`, setup/home/service/API integration and unit tests.

Parent: `lib/screens/dashboard_screen.dart`, `communication_history_screen.dart`, media screens, API service and dashboard/history widget tests. First-prompt web, notification, audio and safety infrastructure changes are detailed in the 1.2 report.

## G. Release artifacts and devices

- Parent: `release_artifacts/seftly-parent-1.3.0.apk`; `com.example.parent_app`; code 4; SHA-256 `1e2177324e7179a991ae6d489588b552fe5b59128eaf82bd713081e215394cc6`.
- Child: `release_artifacts/seftly-child-1.3.0.apk`; `com.example.childapp`; code 4; SHA-256 `ae7f23c2c514a06a3238abd9d36ada1269495d87921e96bb00499ca1ef7af2d9`.

Both APKs preserve original IDs and signing certificates. The real Infinix child was updated to 1.3.0/code 4 without clearing data; its first-install time remained 14:15:40, and the update time was 18:52:48. Signed parent 1.3.0 and the normal production-API parent debug app were installed on the emulator. The production child and normal parent debug app were opened. Temporary QA apps and the local fixture backend were removed/stopped at the user's request.

Code changes are present in the workspace. No new agent-created Git commit, push or remote CI result is claimed.

## H. Production

Backend revision `1.3.0-699f21b-working-tree` was verified at 18:45:27 Asia/Dhaka on `https://api.hakaluki.dev`. Archive SHA-256: `3287e5f53e1b1b63226b2958881e27d4110f4d9e65a6a930a6cd4226641b1063`. Audio, selected notification metadata and communications infrastructure are enabled; safety remains disabled. Guardian collection settings remain opt-in.

Fresh root-only application/database backups were restored into an isolated verification database; counts/index counts matched and the temporary database was removed. Application backup SHA-256 `83198168ac5a1eccd512ac2b04c0857bf1509127d94959f920711f5be426c327`; database archive SHA-256 `12acb73e9a696b624c6412a538e71f505eda50141280e2d4d23162f247440325`. This was a logical standalone backup with live writers, not a point-in-time snapshot.

Staging and public production checks used two synthetic families: TLS/readiness/revision, authentication/refresh/logout, role/ownership checks, normalized website rules, media signaling/Stop/replay, selected notification metadata and detailed SMS encryption/search/security filtering/deletion. Synthetic records were cleaned up. All preexisting record IDs were retained, including 37 users and 8,081 location records. Only the new communications collection's indexes were applied. One transient 502 during PM2 reload cleared on retry.

Stable path `/home/deploy/parental-monitoring-mvp/backend` points to `/home/deploy/seftly-releases/20261013-1.3.0-699f21b`; previous 1.2 release is retained for rollback. The automatic application rollback branch was prepared but was not exercised. Existing JWT/database/TURN credentials were preserved; the independent communications key remains private on the VPS.

## I. Remaining limits

A licensed, evaluated on-device photo/video safety model has not been selected/shipped: infrastructure exists, but actual detection stays disabled. Android may revoke/auto-reset permissions or require fresh consent/foreground activation; granting once cannot exempt the app from those rules. iOS build/signing, full physical/OEM monitoring acceptance, real TURN relay evidence, MMS attachments and private encrypted-app communications remain unsupported or unverified as described above. Payments/subscriptions were excluded.
