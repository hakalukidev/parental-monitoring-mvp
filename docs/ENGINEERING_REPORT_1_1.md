# Seftly engineering report

Validation date: 2026-10-13, Asia/Dhaka. Baseline: clean `main`, commit `73ee98e9856d29666a5bc3a9e83b170079d2c695`. Changes remain in the working tree; no commit or push is claimed. The backend working-tree archive was subsequently deployed using user-supplied VPS access; this report distinguishes that verified backend rollout from wider mobile/website acceptance.

## A. Executive summary

Implemented a shared Flutter design system across all 13 parent screens, original parent/child launcher artwork, clearer child login/setup/status/restriction screens, explicit child approval for screen/camera sessions, and substantial backend/client security and reliability fixes. Existing production Android package IDs and signing identities are preserved. Local automated checks pass: 17 backend integration tests, 24 Flutter tests and 8 Kotlin unit tests. Signed Android releases and a backend deployment archive have been generated.

Backend production deployment **occurred** on 2026-10-13 at 12:26:56 Asia/Dhaka after verified VPS access, a restore-tested database backup and staged acceptance. Public readiness, authenticated REST/Socket.IO, family isolation, signaling/Stop and revocation checks passed; all pre-existing backed-up record IDs remained present. See [the deployment record](PRODUCTION_DEPLOYMENT.md). iOS compilation, physical-device/OEM enforcement, real NAT/TURN video, website compatibility, historical-secret remediation and the complete end-to-end matrix remain release gates. Secondary milestone features are classified below; they are not represented as complete.

## B. UI improvements

Parent screens updated: login, registration, child creation, family dashboard, location/route history, safety-zone list and editor, app policies, web rules, browsing history, app usage, screen sharing and camera streaming. The shared components live in `parent-app/lib/design/seftly_theme.dart` and `seftly_widgets.dart`; screens remain in `parent-app/lib/screens/` and retain existing API-backed navigation.

The Material 3 theme uses teal, restrained tonal surfaces, consistent spacing, typography, inputs, buttons, cards and dialogs, with light/dark schemes. Authentication forms resize/scroll and dispose controllers. Validation, password visibility, submission state and errors are clearer. Child creation includes setup guidance. The dashboard has Family/Activity navigation, per-child identity and honest connection/sync/access/usage/location states, four primary actions and expandable additional tools. Missing data remains unknown. Loading, empty, error and retry states use shared components. Large screens have bounded content width; small screens and enlarged text reduce action columns. Local notification permission is requested through an explicit dashboard action.

Usage labels distinguish foreground app use from actual display-on time. Media viewers require connected transport and a received video track before showing live status, distinguish pending approval from connecting, offer Stop during waiting/live states and release resources when leaving. Camera Stop is also available in the toolbar for short viewports. Camera requests choose a lens and opt into microphone audio; audio defaults off throughout the parent API, backend schema and native capture entry points. The lens label describes the requested lens, not confirmed camera hardware.

Child changes cover guided permissions, readable login, a truthful home status, pending check-in review, active capture Stop controls and a restriction screen that explains family rules instead of showing a fake loading failure. Camera/microphone permissions are session-specific; screen capture uses Android's own prompt each time.

Previews: [parent login](../parent-app/test/goldens/login.png), [child card](../parent-app/test/goldens/family-card.png), [launcher artwork](../assets/branding/launcher-preview.png), and emulator images in `docs/previews/`. Golden snapshots were regenerated with real Roboto/Material fonts and passed a normal comparison run afterward. Selected goldens and child home were visually inspected. Widget checks cover 320/390/800 widths, light/dark modes and enlarged text; they do not prove every route on every device is flawless.

## C. App icons

Original shield artwork differentiates a teal parent/family mark from a blue child/star mark. Reproducible source and preview live in `assets/branding/` and `scripts/generate_branding.py`. Android installations include legacy density PNGs, circular PNGs, adaptive foreground/background resources and manifest round-icon references for both apps. Parent iOS AppIcon sets, web/favicon assets and macOS icons were updated; iOS launcher images are opaque at required sizes. Parent Android launch artwork and native notification glyphs were updated. No third-party brand assets were copied. iOS/launcher masking across hardware and OEM launchers remains unverified.

## D. Security fixes

### 1. Cross-family Socket.IO data and controls

**Original problem/root cause:** authenticated sockets could join or act on identifiers without consistently enforcing parent-child ownership; broad event forwarding could disclose presence or monitoring records.

**Files/solution:** `backend/src/socket/index.ts`, `socket/presence.ts`, `services/authorization.ts`, and affected controllers now derive identity from validated tokens, verify live role/token version, scope forwarding to the owning parent's socket IDs, and authorize each child/session control. No public presence broadcast remains.

**Validation/result:** real HTTP/Socket.IO tests with two separate families reject unauthorized joins, session controls, policy/location/history access and unblock responses; unauthorized recipients receive no presence or record events. Passed locally. **Remaining risk:** single-instance in-memory presence; multi-instance deployment needs a reviewed shared adapter/state design.

### 2. Unauthorized, replayed or misleading media sessions

**Original problem/root cause:** session room access and signaling lacked complete participant/state checks; acceptance could be treated as live, stale events could affect another session, and simultaneous requests were not atomically reserved.

**Files/solution:** media controllers, `models/MediaLease.ts`, `services/mediaSessions.ts`, authorization and socket handlers enforce owner/participant identity, child-only accept/reject/offer, parent-only answer, bounded states/expiry and one-shot negotiation. Intrinsic MongoDB `_id` uniqueness reserves one request per kind/child. Stop, expiry and last-participant disconnect release leases and notify both sides. Parent viewers match the exact current session, ignore callbacks after closing, display Stop as soon as a request exists and require real transport/video state. New clients require protocol 2; new backend requests require child consent capability 2.

**Validation/result:** both media lifecycles, expiry, duplicate accept/offer/answer, wrong role/owner and concurrent reservation tests passed. Local split-screen emulator capture/video reached ACTIVE for screen and camera with microphone off; child Stop, parent toolbar Stop and token-expiry teardown were observed. APK builds passed. **Remaining risk:** hardware capture, real NAT/TURN, camera switch confirmation and disconnect recovery need device acceptance. Database state cannot independently prove that a modified client displayed the OS consent UI.

### 3. Automatic screen/camera permission handling

**Original problem/root cause:** the child contained an invisible capture activity and Accessibility logic that automated projection approval.

**Files/solution:** removed `InvisibleScreenCaptureActivity.kt` and Accessibility prompt automation/anti-tamper interception. Added `consent/SessionConsentController.kt` and `SessionConsentActivity.kt`; modified monitoring, capture/camera services, manifest and child home. A request produces a visible review notification/control. Fresh explicit approval and Android permission/projection flows precede capture. Capture services are non-sticky, have visible notices and real Stop controls, and do not cache projection grants or restart media at boot.

**Validation/result:** source guard and Android compilation/lint passed; backend rejects legacy media clients. Emulator denial, fresh OS projection approval, local rendered screen/virtual-camera video and child capture Stop were verified; the two-emulator live transport check failed after SDP negotiation. Details are recorded in `VALIDATION.md`. **Remaining risk:** full Android/OEM instrumentation matrix remains incomplete.

### 4. TLS verification bypass

**Original problem/root cause:** Flutter accepted invalid certificates and Kotlin accepted arbitrary hostnames, allowing impersonated servers.

**Files/solution:** removed overrides from `parent-app/lib/main.dart`, native `data/ApiClient.kt` and `socket/SocketManager.kt`; Android release manifests disallow cleartext. Parent release endpoint validation requires HTTPS. Debug-only cleartext is scoped to explicit loopback/emulator hosts; child development endpoint overrides are debug-only.

**Validation/result:** regression scan and release builds passed; public readiness returned HTTP 200 with TLS verification result 0. The production Nginx reverse-proxy configuration was inspected during rollout. **Remaining risk:** no active TLS interception test was performed.

### 5. Signing credentials and repository secrets

**Original problem/root cause:** environment files, keystores, dependency trees and literal signing passwords were tracked; documentation also contained a password.

**Files/solution:** `.gitignore`, both Gradle signing configurations, `ai/` documentation and security scripts. Removed `.env`, keystores and `backend/node_modules` from Git tracking while preserving local files. Signing reads ignored properties/private environment variables and release tasks fail without complete configuration. Debug IDs/keys are separate. Release version codes are 2.

**Validation/result:** APK signer SHA-256 was compared against each preserved key; original key file hashes match baseline Git blobs and production IDs/version codes match expectations. Current tracked-source regression scan passes. **Remaining risk:** Git history still exposes credentials/keys. An initial task read also exposed a signing password in tool output; subsequent checks avoid printing private values. This was disclosed during execution. No key rotation/history rewrite was attempted; installed-app continuity and production recovery must guide remediation.

### 6. Authentication, revocation and website premium identity

**Original problem/root cause:** logout did not reliably invalidate issued credentials/socket access; legacy login/lookup and premium updates had inconsistent protections.

**Files/solution:** auth middleware/controllers, JWT utilities, `seftlyController.ts`, routes and socket IO helpers. JWT payloads/HS256 are validated against live users and token versions. Logout/password changes increment the version and disconnect user sockets. Role-specific login paths share rate limiting. Child lookup requires a service token and returns minimal fields; premium changes require the same child ID and identifier, with constant-time token comparison. Clients coordinate refresh rather than racing requests.

**Validation/result:** role, malformed/forged token, refresh/logout revocation, lookup and premium mismatch tests pass. Authentication, revocation and private lookup were also checked on the deployed API. **Remaining risk:** production website source is unavailable; its server proxy must supply the new private service credential for lookup/premium integration. Website compatibility was not established by the backend rollout. Premium synchronization is not merchant transaction verification. Offline logout clears local credentials immediately; server revocation is best effort when connectivity/authentication is unavailable.

### 7. Malformed payloads, abuse and disclosure through errors

**Original problem/root cause:** unbounded IDs/URLs/signals/numbers and raw API/log output could expose private data or overload handlers.

**Files/solution:** validation utilities, socket validation/handlers, server configuration/error handling and native networking. Validate object IDs, calendar days/IANA zones, finite coordinates, bounded usage/app inventories, URL protocols and signaling shape/size. PNG thumbnails have strict encoded/decoded/header/dimension limits. Add HTTP/login limiting, socket event budget and 100 KB Engine.IO payload cap. Errors use non-sensitive codes and ordinary logs omit tokens, full responses and database URIs. Production configuration fails for missing/weak/duplicate authentication secrets or broad/non-HTTPS CORS.

**Validation/result:** invalid payload/time/role/abuse regressions, lint, compilation and source checks pass. Backend dependency audit reports zero known vulnerabilities. **Remaining risk:** these checks are not a penetration test or a complete historical/third-party dependency review.

### 8. Privacy, export and deletion

**Original problem/root cause:** URL credentials/query strings, private browsing and unbounded monitoring retention lacked consistent minimization; deletion/export coverage was limited.

**Files/solution:** browsing ingestion/local database, privacy controller/routes, retention helper/models and read-only preview script. Strip URL credentials/query/fragment; exclude detected incognito entries. Confirmed browsing uploads leave the local queue. Add owner-only bounded cursor exports and explicitly confirmed scoped history deletion, including clearing cached latest location. Retention defaults disabled, tags only new records when configured, and does not backfill history. Production automatic index creation is disabled.

**Validation/result:** ownership, export pagination/minimization and explicit deletion tests pass against isolated records. Production customer history was not deleted and location/browsing/usage retention remains disabled. Only the new unblock-request metadata expiry index was applied; temporary deployment-test records were removed. **Remaining risk:** full account deletion and export/deletion UI are unfinished; private SQLite is sandboxed with backups disabled but lacks application-level encryption. Incognito/browser detection is best effort. Backup/index review is required before history retention activation.

## E. Reliability and bug fixes

- Corrected a missing Mongoose schema definition that silently discarded report version, availability and time zone. The schema now persists these fields and defaults unmeasured durations to null; a real HTTP/database regression confirms stored values and parent/family availability responses. No legacy history was backfilled.
- Foreground usage is calculated from Android event intervals clipped to local-day/hour boundaries; open intervals, duplicate events, screen transitions and rollover are tested. Screen-off is independent and nullable. No elapsed-time-minus-app-usage downtime is invented; unsupported pause/downtime metrics remain unavailable. Legacy report versions are marked unverified.
- Child IANA zones drive usage, browsing and geofence schedules. Overnight schedules belong to their starting day and use exclusive end boundaries. Backend day boundaries handle 23/25-hour DST days.
- Missing limits/usage permission fail with a setup explanation rather than guessed defaults. Critical/default phone/home/settings components remain accessible. A ten-second foreground policy recheck applies time limits and schedule changes without needing another app-window event. Actual OEM blocking behavior remains unverified.
- Web matching uses domain boundaries and explicit allow overrides; disabled rules do not apply. Browser instrumentation remains best effort, not universal network/DNS filtering.
- Shared location/history ingestion deduplicates REST/socket replay. Older offline fixes cannot replace newer latest location or generate fresh crossings. Geofence evaluation respects configured triggers/schedules and does not fabricate fresh movement from heartbeats.
- SQLite migration is additive; policies/history are not dropped. Location queues are bounded and delete only confirmed uploads. Temporary grants use elapsed/wall-clock expiry and a boot binding. Framework migration/update behavior still needs production-version device testing.
- Primary device registration preserves pause state when its display name changes. Presence is based on current authenticated connections. Battery-only updates do not fabricate coordinates or crash parent parsing.
- Monitoring and media sockets have separate callbacks; one media service does not overwrite monitoring listeners. Services stop on failures/disconnect, cached capture grants are absent and foreground location starts from visible UI. Inventory uploads are batched/cached. Parent HTTP operations have bounded timeouts and single-flight refresh.

## F. Test results

See [validation record](VALIDATION.md) for actual commands and end-to-end limits. Final local results: backend build/lint and **17/17** tests pass; `npm audit --audit-level=high` reports **0** vulnerabilities; Flutter analysis has **no issues**, formatting passes and **24/24** tests pass; Kotlin **8/8** tests pass, Android lint has **0 errors** and warnings are recorded in validation. Android debug/release builds pass. Tracked-source security scan and `git diff --check` pass.

The original missing Gradle wrapper, npm executable/lint configuration and Java-selection failures were corrected. A cleanup-induced Dart syntax failure and interim layout/test-fixture failures were corrected and rechecked; they are not reported as current passes without rerunning. iOS build failed. Remote CI execution, physical devices, installation over customer releases, multi-OEM/background behavior, real TURN and full production end-to-end tests are blocked or unverified, not passed.

## G. Build artifacts

- Signed parent: `release_artifacts/seftly-parent-1.1.0.apk`, also `parent-app/build/app/outputs/flutter-apk/app-release.apk`; production ID `com.example.parent_app`, version code 2.
- Signed child: `release_artifacts/seftly-child-1.1.0.apk`, also `child-app/app/build/outputs/apk/release/app-release.apk`; production ID `com.example.childapp`, version code 2.
- Public signature/checksum metadata: `release_artifacts/artifacts.json`.
- Backend archive: `release_artifacts/backend-73ee98e-working-tree.tgz`, with compiled code, package/lock files, environment example and revision marker; no private environment or keys.
- Emulator debug APKs are separate `.debug` packages using local test endpoints. Signed production APKs were verified but **not installed over an existing production app**. No IPA, Play publication or Apple distribution was produced.

Artifacts are ignored generated files retained in this workspace. The backend archive was uploaded and deployed; APKs remain local and have not been installed or published as part of that rollout. The archive digest identifies the deployed build; its working-tree label does not identify a new commit. Mobile builds use the existing API hostname. The updated child must launch/register consent capability version 2 for approved media check-ins.

## H. Production deployment

**Deployment occurred:** yes, backend only. **Version/method:** 1.1.0, revision `73ee98e-working-tree`, archive SHA-256 `5aeaf0112f67ada09809918c3356de7093a4732f71cf1df31c893881cfa95bbb`; staged native dependency installation, application-path symlink switch, reload and save of PM2 `parental-monitoring-backend` under `deploy`. **Target:** user-supplied `163.227.239.88`; Nginx to port 4000. **Public readiness:** HTTP 200, normal TLS verification, expected revision and ready database.

Two synthetic families passed public parent/child authentication, refresh, ownership/role checks, Socket.IO through Nginx, isolated location events, media consent/signaling/Stop/replay rejection and logout revocation. Synthetic SDP checks do not prove real device media or TURN. Temporary users/records and isolated databases were removed. All pre-existing backup record IDs across 12 collections remained present. Existing authentication/database/TURN secrets were preserved; HTTPS CORS, proxy/revision settings and a private service credential were configured. Historical monitoring retention stayed disabled.

The old application and dependencies remain at `/home/deploy/parental-monitoring-mvp/backend.rollback-20261013-73ee98e`. Private application/database backups at `/home/deploy/seftly-releases/backups/20261013-73ee98e` were verified through an isolated restore with matching document/index counts. The backup was logical with live writers; it is not a cluster point-in-time snapshot. Immediate failure rollback is scripted but was not needed/exercised on production. See [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) for evidence, checksums and exact rollback instructions. An initial namespace-limited restore and a transient reload HTTP 502 were caught and corrected/retried before final acceptance. No signing identity or payment activation changed.

## I. External work still required

Coordinate production secrets/history remediation while preserving APK signing continuity. Verify the preserved runtime TURN configuration with real devices/NAT. Provide website/checkout source, configure its private service-token proxy and supply merchant verification requirements before payment activation. Install/update signed apps on authorized physical test devices and verify persisted accounts/data/permissions and current installed version codes. Supply full Xcode, CocoaPods and Apple signing access for iOS. Decide notification/content collection scope and approve a lawful supported integration before secondary features are built.

## J. Milestone completion table

Statuses describe the actual feature, including verification limits; no BDT milestone is declared fully accepted.

| Milestone | Item | Classification | Evidence / remaining acceptance work |
| --- | --- | --- | --- |
| 1 | Sound Around Child | Not implemented | Camera audio is optional; no separate audio-only feature. |
| 1 | Location and route tracking | Implemented but unverified | APIs, replay/freshness fixes, parent map/history and child queue exist; physical route/accuracy/background tests remain. |
| 1 | App/game and web blocking | Implemented but unverified | Policy/web CRUD and matching tests pass; actual browser/OEM enforcement remains. |
| 1 | Downtime and app time limits | Partially implemented | Limits/schedules implemented and unit/API tested; measured pause/downtime duration unavailable and real device enforcement pending. |
| 1 | Geofencing | Implemented but unverified | Ownership/CRUD, schedules and event logic tested locally; actual boundary-entry/exit location accuracy not verified. |
| 1 | Browsing history | Implemented but unverified | Ingestion/privacy/dedup/ownership tested; browser coverage/incognito behavior needs devices. |
| 1 | Usage reports | Partially implemented | Foreground intervals and calendar corrections tested; physical accuracy and true display-on/pause metrics remain. |
| 1 | Parent UI | Implemented and tested | All 13 screens updated, analysis and 24 tests pass; broader visual/device acceptance remains. |
| 2 | Calls/SMS monitoring | Not implemented | No collection pipeline; supported permissions/distribution/integration must be selected. |
| 2 | Social content monitoring | Not implemented | Requires authorized provider integration or explicit sharing; no private-message extraction. |
| 2 | Viewing app notifications | Not implemented | Transparent notification-listener design documented; no listener/data/viewer implemented. |
| 3 | Live screen mirroring | Implemented and tested | Local rendered video, fresh OS consent, denial and child Stop pass; physical/NAT/TURN acceptance remains. |
| 3 | Remote camera | Implemented and tested | Local virtual-camera video with audio off, child approval, child/parent Stop and expiry pass; physical hardware/audio/TURN/lens confirmation remains. |
| 3 | Inappropriate image/video detection | Not implemented | No validated model, dataset or measured accuracy; privacy-preserving evaluation design documented. |
| 4 | Website | Blocked by external requirements | Website source/access absent; backend compatibility routes were reviewed/hardened. |
| 4 | Payment integration | Partially implemented | Protected premium synchronization exists; real merchant-verified payment flow absent. |
| 4 | Production improvements/optimization | Partially implemented | Backend deployed with restored-backup/staging/public API verification; wider performance/mobile/website acceptance remains. |

See [secondary feature assessment](FUTURE_FEATURES.md) for primary-source platform references and supported alternatives. Notification access is not equivalent to complete social-message access; general image labels are not a validated safety detector.

## K. Remaining backlog

1. **Release blocker for wider rollout:** coordinate updated child consent capability, website lookup/service-token proxy and historical credential remediation with signing continuity. The backend has passed staged and public API acceptance; website and installed-mobile acceptance remain.
2. **Release blocker:** physical update/install checks, real screen/camera/Stop and TURN/NAT tests, Android permission revocation, reboot/network recovery, browser/web-rule and same-app time-limit enforcement across supported OS/OEMs. Complete the full end-to-end matrix.
3. **High:** full account/child deletion, parent history export/deletion UI, stronger local storage protection, refresh-assisted native logout after access expiry and reviewed legacy cache retention. Review/apply retention indexes only with configured policy and verified backup.
4. **High:** confirmed camera-lens state, device-scoped enrollment, durable/distributed presence/ingestion, measured screen-on/pause metrics, geofence boundary jitter and background-location lifecycle acceptance.
5. **Platform:** full iOS toolchain/build/signing, OEM launcher masking/accessibility review, plugin/toolchain deprecation migration and CI execution on the remote repository.
6. **Secondary scope:** explicitly approved notification listener, audio-only check-in, supported calls/SMS/social integrations, evaluated on-device content model and merchant-verified payments. Dependencies and privacy gates are documented; these are not ready-to-enable switches.
