# Permissions, privacy and retention

The child app explains permissions during guardian setup. Missing permissions leave the associated feature unavailable; the UI does not label the device protected merely because it is connected.

- Notifications: family requests and visible foreground-service notices.
- Location: approved device fixes, accuracy and movement metadata. Fine/coarse permissions are checked; location services must be enabled. No background-location grant is claimed by initial setup.
- Usage access: foreground application activity, app limits and screen-state events.
- Accessibility: foreground-app restrictions and supported browser address/title information for family web rules/history. It never approves screen-capture prompts or obstructs Android permission/settings controls.
- Overlay: a truthful restriction explanation and temporary-access request. It does not disguise blocking as an app loading failure.
- Camera/microphone: optional and requested in a visible approval flow for that session.
- MediaProjection: fresh Android consent for every screen-share session. Android's indicators remain visible; Stop releases capture resources.
- Installed-app visibility: app inventory needed for policies. One child account is intended for one primary child device.

Credentials are in encrypted Android preferences / Flutter secure storage. Offline policy/location/browsing records are in private app SQLite storage with Android backups disabled; they are not application-level database encrypted. Stronger at-rest encryption and a reviewed bounded local-history retention policy remain backlog items.

Detected private-browsing entries are excluded from new ingestion. Detection and browser coverage are best effort. Confirmed browsing uploads are removed from the local queue. Browsing ingestion removes URL credentials, query strings and fragments before local queue/backend storage and derives the domain from the parsed URL. Titles/pathnames remain sensitive and are accessible only to the owning parent. No raw media is stored by the backend. Ordinary logs exclude tokens, full API responses and database connection strings.

## History export/deletion

`GET /api/children/:childId/history/export?kind=location|browsing|usage&limit=200&cursor=<id>` requires the owning parent. Follow `nextCursor` until null; pages are capped at 500 records and private exports use `Cache-Control: no-store`.

`DELETE /api/children/:childId/history` requires the owning parent and a JSON body with `kinds` and `confirmation: "DELETE_HISTORY"`. Location deletion also clears the cached latest device fix. The older owner-only browsing clear endpoint remains compatible. No history-deletion operation was performed against production during this work.

Full account/child deletion and a parent UI for export/deletion remain unfinished. A future implementation must coordinate live-session revocation and transactionally remove every related record.

## Opt-in retention

`RETENTION_LOCATION_DAYS`, `RETENTION_BROWSING_DAYS` and `RETENTION_USAGE_DAYS` default to zero (disabled). Valid configured values tag new ingested records with an expiration date. Existing history is never backfilled or deleted automatically. Usage expiration is refreshed on subsequent syncs.

TTL schema definitions are available, but production `autoIndex` is disabled. An operator must verify a recoverable backup and explicitly review/apply retention indexes before enabling deletion. Do not run blanket `syncIndexes()` against production. Request metadata is separate from monitoring history and expires after its bounded purpose.

`node scripts/retention-preview.cjs` (from backend, after building) is read-only: it reports policy enablement and counts of already-tagged expired records. It never creates indexes or deletes records.

Calls/SMS and private social messages are not extracted. Notification-listener monitoring would require explicit Android notification access, a guardian-selected allowlist, exclusion of passwords/OTP/payment notifications, minimal metadata and separate retention. It must not circumvent protected/redacted notifications. A privacy-preserving image/video detector needs a real on-device model, a consensual data source and measured false-positive/negative evaluation; no detection capability is claimed here.

Map tiles, reverse geocoding and directions use external map services. Coordinates for viewed routes/geocoding are sent to those providers without child names or authentication tokens; review provider privacy policies before production rollout. Offline logout clears local credentials/data immediately; server revocation is best effort while connectivity or authentication is unavailable.
