/** Expiration is opt-in and applies to new records only. Never backfill history automatically. */
export function retentionExpiry(kind: "LOCATION" | "BROWSING" | "USAGE", now = new Date()): Date | undefined {
  const raw = process.env[`RETENTION_${kind}_DAYS`] ?? "0";
  const days = Number(raw);
  if (!Number.isInteger(days) || days < 0 || days > 3650) throw new Error(`Invalid RETENTION_${kind}_DAYS`);
  return days === 0 ? undefined : new Date(now.getTime() + days * 86_400_000);
}
