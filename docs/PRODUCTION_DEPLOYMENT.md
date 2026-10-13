# Current production deployment — 1.3.0

Verified 2026-10-13 at 18:45:27 Asia/Dhaka. Public API: `https://api.hakaluki.dev`; readiness revision: `1.3.0-699f21b-working-tree`.

PM2 `parental-monitoring-backend` runs under `deploy`. The stable backend path links to `/home/deploy/seftly-releases/20261013-1.3.0-699f21b`. Previous 1.2 release is retained. Backups are root-only under `/home/deploy/seftly-releases/backups/20261013-1.3.0-699f21b`; restore verification passed. Secrets were preserved; a separate private communications key was added.

Audio, selected notification metadata and communications infrastructure are enabled; guardian collection is opt-in. Safety remains off because no evaluated model is shipped. Staging/public authentication, ownership, encrypted history, media signaling and synthetic cleanup passed; every preexisting record ID was retained. Only new communications indexes were applied. Automatic rollback was prepared but not exercised; one reload-time 502 cleared on retry.

[Detailed release, backup digests and limitations](ENGINEERING_REPORT_1_3.md#h-production). [Historical 1.1 deployment](PRODUCTION_DEPLOYMENT_1_1.md). The deployed archive identifies uncommitted working-tree code; no new Git push is claimed.
