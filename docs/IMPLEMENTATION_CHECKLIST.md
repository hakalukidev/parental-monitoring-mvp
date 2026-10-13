# Seftly implementation record

Baseline: clean `main`, commit `73ee98e9856d29666a5bc3a9e83b170079d2c695`.

- [x] Inspect repository, screen inventory, API/socket contracts and tracked secret exposure.
- [x] Record baseline toolchain checks and distinguish fixed/interim failures.
- [x] Unified parent design system across all 13 screens; local widget/visual checks.
- [x] Distinct parent/child launcher assets and previews; Android builds.
- [x] Child setup/status and explicit media-consent implementation.
- [x] Socket ownership, validation, lifecycle and abuse protections with local regression tests.
- [x] Authentication, protected premium synchronization, TLS and current-source secret hardening.
- [x] Usage, schedules, location and offline-sync fixes; physical/OEM acceptance still pending.
- [x] Owner history deletion/export APIs and disabled-by-default retention tooling; no production data deletion.
- [x] Backend integration tests (17), Flutter tests (24), Kotlin policy/usage/web tests (8).
- [x] Signed APK builds, original identity verification and backend release packaging.
- [x] Verified VPS/PM2/Nginx, restore-tested backup, controlled backend deployment and public authenticated REST/Socket.IO checks; see `PRODUCTION_DEPLOYMENT.md`.
- [x] CI configured and architecture/privacy/release documentation updated.
- [x] A–K engineering report and evidence-based milestone table.

Implementation checks above do not mark production acceptance complete. Open gates:

- [x] Production access, restore-tested backup, retained application rollback and controlled backend deployment. Actual rollback execution and complete physical-client acceptance remain unverified.
- [ ] Historical-secret remediation with signing continuity.
- [ ] Physical-device update installation, permission/OEM/background/browser accuracy testing.
- [ ] Full end-to-end matrix and real NAT/private TURN media checks.
- [ ] iOS compilation/signing and launcher inspection with full Xcode/CocoaPods.
- [ ] Parent export/deletion UI and complete account/child deletion.
- [ ] Website checkout source/compatibility and merchant-verified payment activation.
- [ ] Secondary milestone features and validated on-device content model.
- [ ] Remote CI execution.

## Baseline findings

- Backend bundled/tracked node_modules executable permissions prevent `npm run build`; direct compilation passed and npm/lint commands were subsequently repaired.
- Flutter SDK cache writes need sandbox escalation; baseline and final checks completed with authorized SDK-cache access.
- System Java command cannot find a runtime; Android Studio contains a bundled JDK.
- ADB cannot bind its local listener inside the sandbox.
- Initially, no production SSH host was configured. User-supplied VPS details and credentials subsequently enabled the verified backend deployment recorded in `PRODUCTION_DEPLOYMENT.md`.
- Environment files, release keystores and signing passwords appear in Git. Values must never be included in this record. Local keys must be preserved for existing APK updates; removing tracked files does not erase Git history.
