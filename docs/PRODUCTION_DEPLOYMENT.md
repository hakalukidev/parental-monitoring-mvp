# Production deployment — 2026-10-13

Backend **1.1.0** was deployed and verified at **12:26:56 Asia/Dhaka** (06:26:56 UTC). The public API is `https://api.hakaluki.dev`. `/ready` returns HTTP 200, `status: ready`, revision `73ee98e-working-tree`; workstation verification used normal TLS validation (result 0).

## Release and process

- VPS: `163.227.239.88`, hostname `vps1.hakaluki.dev`, Linux x86_64.
- Runtime: Node `20.20.2`, npm `10.8.2`.
- PM2: `parental-monitoring-backend`, owned by `deploy`, one fork-mode instance. The recorded restart count increased from 28300 to 28301 for this rollout; subsequent checks found it online without another restart.
- Stable application path: `/home/deploy/parental-monitoring-mvp/backend`.
- That path now links to `/home/deploy/seftly-releases/20261013-73ee98e`.
- Archive: `backend-73ee98e-working-tree.tgz`; SHA-256 `5aeaf0112f67ada09809918c3356de7093a4732f71cf1df31c893881cfa95bbb`. This digest identifies the deployed working-tree build; no new Git commit or push is claimed.
- Installed native production dependencies on the VPS using `npm ci --omit=dev`. PM2's saved process configuration was updated after verification. Nginx and the existing certificate were preserved.

The original database, JWT/session secrets and TURN credentials were preserved. The new private runtime environment uses explicit HTTPS CORS origins for `hakaluki.dev`, `www.hakaluki.dev` and `api.hakaluki.dev`, one trusted Nginx proxy hop, the release revision, and disabled location/browsing/usage retention. A new private server-to-server service credential was configured because the previous environment lacked one. Secret values and the supplied SSH password are not recorded here.

Only the new `unblockrequests.expiresAt` metadata expiry index was created. Historical monitoring indexes were not synchronized or changed. Camera/screen sessions require child consent capability version 2; install the updated child APK and launch/sign in before using those check-ins. Website lookup/premium integrations must supply the private service credential through their server proxy; their source and checkout behavior were not verified.

## Backup and verification

Private backup directory: `/home/deploy/seftly-releases/backups/20261013-73ee98e`.

- `backend-before.tgz`: original application, dependencies and runtime environment; SHA-256 `10e36383c22cc0288eb8ea37460f50bec486163503ebfffc7767197b482a37ac`.
- `database-backup.tgz`: MongoDB logical backup; SHA-256 `d419ca1e04d20bc17ccf02739aa7b0a9e47bd9907f57dca286efe6c56df95468`.
- `runtime.env`, `pm2-before.json` and `verification.json`: private recovery configuration and verification evidence.

The database backup was restored into a new temporary namespace on the VPS. All 12 collections matched the backup's BSON document counts and index counts. It is a standalone logical backup taken while live writers remained active, not a cluster-wide point-in-time snapshot. The verification namespace was removed afterward.

The staged application then passed checks against a separate restored database before PM2 was switched. Public production checks passed with two temporary synthetic families: registration, parent/child login, refresh, device registration, family listing, role checks, cross-family REST isolation, protected lookup, authenticated Socket.IO through Nginx, location event isolation, rejected unauthorized mutations, screen/camera signaling consent and lifecycle, Stop/replay rejection, and logout revocation. These checks exercised signaling with synthetic SDP; they did not capture real device video or establish TURN/NAT success.

A final check found every pre-existing record ID from the backup still present across all 12 production collections, including all 37 users. Synthetic users and their records were removed; no temporary QA database remained. Customer history was not deleted or reset. Signed APKs remain local artifacts; this backend deployment did not install or publish mobile apps.

On-server evidence: `/home/deploy/seftly-releases/stage-verification.json`, `production-verification.json`, `data-preservation.json`, and the backup's `verification.json`. An initial restore attempt restored zero documents because the database component of the tools URI constrained namespace discovery; verification caught it, the restore URI was corrected, and all counts/indexes were checked successfully before deployment. There was one transient HTTP 502 during the PM2 fork restart; retry and subsequent public checks passed.

## Application rollback

The previous application remains at `/home/deploy/parental-monitoring-mvp/backend.rollback-20261013-73ee98e`, with its dependencies and original environment. Its repository revision was `269eb9ed684f84ad56d327fe5c1c836565502a6d`. The deployment script automatically restores this directory if immediate release verification fails; that branch was not needed or exercised on production.

For an operator-authorized rollback, first verify that the live path is still the recorded symlink and that the rollback directory exists. Then, as root:

```sh
set -e
test "$(readlink /home/deploy/parental-monitoring-mvp/backend)" = /home/deploy/seftly-releases/20261013-73ee98e
test -d /home/deploy/parental-monitoring-mvp/backend.rollback-20261013-73ee98e
unlink /home/deploy/parental-monitoring-mvp/backend
mv /home/deploy/parental-monitoring-mvp/backend.rollback-20261013-73ee98e /home/deploy/parental-monitoring-mvp/backend
runuser -u deploy -- pm2 reload parental-monitoring-backend --update-env
curl --retry 5 --retry-delay 1 --retry-all-errors -fsS https://api.hakaluki.dev/health
runuser -u deploy -- pm2 save
```

Do not restore/downgrade the live database for an application rollback. Preserve newly collected records. These commands apply only to the recorded deployment layout; reassess them after a later release.
