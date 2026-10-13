import { z } from "zod";
import { objectIdSchema } from "./authorization";
export const activityKind = z.enum(["NOTIFICATION", "CALL", "SMS", "SAFETY"]);
export const packageName = z.string().min(3).max(255).regex(/^[a-zA-Z\d_]+(?:\.[a-zA-Z\d_]+)+$/);
const eventId = z.string().min(1).max(128).regex(/^[a-zA-Z\d._:-]+$/);
const timestamp = z.string().datetime({ offset: true }).refine(v => new Date(v).getTime() <= Date.now() + 300_000, "Invalid future timestamp");
const base = { eventId, eventAt: timestamp };
const identifier = { identifierHash: z.string().regex(/^[a-f\d]{64}$/).optional(), maskedIdentifier: z.string().regex(/^[*•]{2,8}\d{0,4}$/).optional(), subscriptionId: z.string().regex(/^[\d-]{1,20}$/).optional() };
export const activityBatch = z.object({ clientChildId: objectIdSchema.optional(), events: z.array(z.discriminatedUnion("kind", [
  z.object({ ...base, kind: z.literal("NOTIFICATION"), packageName, eventType: z.enum(["POSTED", "UPDATED", "REMOVED"]) }).strict(),
  z.object({ ...base, ...identifier, kind: z.literal("CALL"), direction: z.enum(["INCOMING", "OUTGOING", "MISSED", "REJECTED", "BLOCKED"]), durationSeconds: z.number().int().min(0).max(86400) }).strict(),
  z.object({ ...base, ...identifier, kind: z.literal("SMS"), direction: z.enum(["INCOMING", "OUTGOING"]) }).strict(),
  z.object({ ...base, kind: z.literal("SAFETY"), mediaType: z.enum(["IMAGE", "VIDEO"]), category: z.enum(["POTENTIAL_ADULT", "POTENTIAL_VIOLENCE", "UNCERTAIN"]), confidence: z.number().finite().min(0).max(1), modelVersion: z.string().min(1).max(100) }).strict(),
])).min(1).max(100) }).strict();
export const activityPolicyUpdate = z.object({
  notificationsEnabled: z.boolean().optional(), monitoredPackages: z.array(packageName).max(100).optional(),
  callsEnabled: z.boolean().optional(), smsEnabled: z.boolean().optional(), safetyEnabled: z.boolean().optional(),
  retentionDays: z.number().int().min(1).max(90).optional(),
  fullCommunicationHistoryEnabled:z.boolean().optional(),messageBodiesEnabled:z.boolean().optional(),contactsEnabled:z.boolean().optional(),mmsEnabled:z.boolean().optional(),initialImportDays:z.number().int().min(1).max(30).optional(),
}).strict().refine(x => Object.keys(x).length > 0, "Provide settings to update");
const access = z.enum(["GRANTED", "DENIED_OR_RESTRICTED", "RESTRICTED", "UNAVAILABLE", "UNKNOWN"]);
export const activityCapabilities = z.object({ notificationAccess: access, callLogAccess: access, smsAccess: access,
  safetyModel: z.enum(["AVAILABLE", "UNAVAILABLE"]), sourceCoverage: z.literal("SELECTED_MEDIA_ONLY"), listenerConnected: z.boolean(),
  queuedEvents: z.number().int().min(0).max(8000), droppedEvents: z.number().int().min(0).max(2147483647),
}).strict();
export function sensitivePackage(name: string): boolean { return /(?:^com\.example\.(?:childapp|parent_app)(?:\.debug|\.qa)?$|^android$|^com\.android\.|bank|wallet|authenticator|password|bitwarden|1password|lastpass)/i.test(name); }
export function approvedSafetyModels(): string[] {
  return (process.env.SAFETY_APPROVED_MODELS ?? "").split(",").map(x => x.trim())
    .filter(x => Boolean(x) && (process.env.NODE_ENV === "test" || !/(?:test|stub|fixture|demo)/i.test(x)));
}
