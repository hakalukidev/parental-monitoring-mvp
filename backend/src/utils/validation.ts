import { z } from "zod";
import { objectIdSchema } from "../services/authorization";

const timestampSchema = z.string().datetime({ offset: true }).or(z.date()).refine((v) => Number.isFinite(new Date(v).getTime()) && new Date(v).getTime() <= Date.now() + 300_000, "Invalid or future timestamp");
const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((v) => Number.isFinite(new Date(v).getTime()) && new Date(v).toISOString().slice(0, 10) === v, "Invalid calendar date");
export const timezoneSchema = z.string().max(100).refine((v) => { try { new Intl.DateTimeFormat("en", { timeZone: v }); return true; } catch { return false; } }, "Invalid time zone");


export const registerParentSchema = z
  .object({
    name: z.string().trim().min(2).max(100),
    email: z.string().trim().email().max(254).toLowerCase(),
    password: z.string().min(8).max(128),
    confirmPassword: z.string().min(8).max(128),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"],
  });

export const loginSchema = z.object({
  email: z.string().trim().email().max(254).toLowerCase(),
  password: z.string().min(1).max(255).max(128),
});

export const childLoginSchema = z.object({
  email: z.string().trim().min(3).max(254).toLowerCase(), // child logs in with username, not necessarily an email
  password: z.string().min(1).max(255).max(128),
});

export const createChildSchema = z
  .object({
    name: z.string().trim().min(2).max(100),
    username: z.string().trim().min(3).max(50).regex(/^[a-zA-Z0-9._-]+$/), // stored as email field internally (username@child.local pattern not required; we store raw as unique login id)
    password: z.string().min(8).max(128),
    confirmPassword: z.string().min(8).max(128),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"],
  });

export const registerDeviceSchema = z.object({
  deviceName: z.string().min(1).max(100),
  platform: z.string().min(1).max(50).default("Android"),
  timeZone: timezoneSchema.optional(),
  mediaConsentVersion: z.number().finite().int().min(1).max(2).optional(),
});

export const screenShareRequestSchema = z.object({
  childId: objectIdSchema,
});

export const cameraStreamRequestSchema = z.object({
  childId: objectIdSchema,
  cameraFacing: z.enum(["BACK", "FRONT"]).default("BACK"),
  withAudio: z.boolean().default(false),
});

export const recordLocationSchema = z.object({
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
  accuracy: z.number().finite().nonnegative().optional(),
  altitude: z.number().finite().optional(),
  speed: z.number().finite().nonnegative().optional(),
  heading: z.number().finite().min(0).max(360).optional(),
  batteryLevel: z.number().finite().min(0).max(100).optional(),
  recordedAt: timestampSchema.optional(),
});

export const recordLocationBatchSchema = z.object({
  points: z.array(recordLocationSchema).min(1).max(500),
});

export const locationHistoryQuerySchema = z.object({
  startTime: timestampSchema.optional(),
  endTime: timestampSchema.optional(),
  limit: z.coerce.number().int().min(1).max(2000).default(500),
});

export const appIconSchema = z.string().max(24576).refine((encoded) => {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) return false;
  const png = Buffer.from(encoded, "base64");
  return png.length >= 24 && png.length <= 16384 && png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) && png.readUInt32BE(16) > 0 && png.readUInt32BE(16) <= 96 && png.readUInt32BE(20) > 0 && png.readUInt32BE(20) <= 96;
}, "Use a small PNG app icon");

// App Policy Validation Schemas
export const syncInstalledAppsSchema = z.object({
  apps: z.array(
    z.object({
      packageName: z.string().min(1).max(255),
      appName: z.string().min(1).max(255),
      category: z.string().default("OTHER"),
      versionName: z.string().optional(),
      isSystemApp: z.boolean().default(false),
      iconPngBase64: appIconSchema.optional(),
    })
  ),
});

export const updateAppPolicySchema = z.object({
  appName: z.string().optional(),
  category: z
    .enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"])
    .optional(),
  status: z.enum(["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"]),
  dailyLimitMinutes: z.number().finite().int().min(1).max(1440).optional(),
  schedules: z
    .array(
      z.object({
        daysOfWeek: z.array(z.number().finite().int().min(0).max(6)).min(1).max(7),
        startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
        endTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
      })
    )
    .optional(),
  isSystemWhitelisted: z.boolean().optional(),
}).superRefine((data, ctx) => {
  if (data.status === "TIME_LIMITED" && data.dailyLimitMinutes === undefined) ctx.addIssue({ code: "custom", path: ["dailyLimitMinutes"], message: "A daily limit is required" });
  if (data.status === "SCHEDULED" && !data.schedules?.length) ctx.addIssue({ code: "custom", path: ["schedules"], message: "At least one schedule is required" });
});

export const bulkUpdatePolicySchema = z.object({
  category: z.enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"]),
  status: z.enum(["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"]),
  dailyLimitMinutes: z.number().finite().int().min(1).max(1440).optional(),
}).superRefine((data, ctx) => {
  if (data.status === "SCHEDULED") ctx.addIssue({ code: "custom", path: ["status"], message: "Configure schedules per app" });
  if (data.status === "TIME_LIMITED" && data.dailyLimitMinutes === undefined) ctx.addIssue({ code: "custom", path: ["dailyLimitMinutes"], message: "A daily limit is required" });
});

export const toggleDevicePauseSchema = z.object({
  isPaused: z.boolean(),
});

// Web Block Rules Validation Schemas
export const createWebRuleSchema = z.object({
  ruleType: z.enum(["DOMAIN", "KEYWORD", "CATEGORY"]),
  target: z.string().min(1).max(255),
  action: z.enum(["BLOCK", "ALLOW"]).default("BLOCK"),
  isEnabled: z.boolean().default(true),
});

export const updateWebRuleSchema = z.object({
  action: z.enum(["BLOCK", "ALLOW"]).optional(),
  isEnabled: z.boolean().optional(),
});

// Browsing History Validation Schemas
export const recordBrowsingHistorySchema = z.object({
  url: z.string().url().max(4096).refine((v) => ["http:", "https:"].includes(new URL(v).protocol), "Only web URLs are supported"),
  domain: z.string().min(1).max(255),
  title: z.string().max(300).default(""),
  browser: z
    .enum(["CHROME", "FIREFOX", "SAMSUNG_BROWSER", "EDGE", "OPERA", "BRAVE", "OTHER"])
    .default("OTHER"),
  isIncognito: z.boolean().default(false),
  category: z
    .enum(["EDUCATION", "ENTERTAINMENT", "GAMING", "SOCIAL", "ADULT", "SUSPICIOUS", "GENERAL"])
    .optional(),
  isBlockedAttempt: z.boolean().default(false),
  blockedReason: z.string().max(300).optional(),
  visitedAt: timestampSchema.optional(),
});

export const recordBrowsingBatchSchema = z.object({
  records: z.array(recordBrowsingHistorySchema).min(1).max(500),
});

export const browsingHistoryQuerySchema = z.object({
  startDate: timestampSchema.optional(),
  endDate: timestampSchema.optional(),
  search: z.string().max(100).optional(),
  browser: z.string().optional(),
  isFlagged: z.string().optional(),
  isBlockedAttempt: z.string().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

// Geofence Validation Schemas
export const createGeofenceSchema = z.object({
  name: z.string().min(1).max(100),
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
  radius: z.number().finite().min(30).max(20000).default(200),
  address: z.string().optional(),
  zoneType: z.enum(["SAFE_ZONE", "RESTRICTED_ZONE"]).default("SAFE_ZONE"),
  triggerType: z.enum(["EXIT", "ENTRY", "BOTH"]).default("EXIT"),
  isEnabled: z.boolean().default(true),
  colorHex: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional().default("#2196F3"),
  schedule: z
    .object({
      daysOfWeek: z.array(z.number().finite().int().min(0).max(6)).min(1).max(7).default([0, 1, 2, 3, 4, 5, 6]),
      startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
      endTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
    })
    .optional(),
});

export const updateGeofenceSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  latitude: z.number().finite().min(-90).max(90).optional(),
  longitude: z.number().finite().min(-180).max(180).optional(),
  radius: z.number().finite().min(30).max(20000).optional(),
  address: z.string().optional(),
  zoneType: z.enum(["SAFE_ZONE", "RESTRICTED_ZONE"]).optional(),
  triggerType: z.enum(["EXIT", "ENTRY", "BOTH"]).optional(),
  isEnabled: z.boolean().optional(),
  colorHex: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  schedule: z
    .object({
      daysOfWeek: z.array(z.number().finite().int().min(0).max(6)).min(1).max(7),
      startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
      endTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
    })
    .optional(),
});

export const geofenceEventsQuerySchema = z.object({
  startDate: timestampSchema.optional(),
  endDate: timestampSchema.optional(),
  geofenceId: z.string().optional(),
  eventType: z.enum(["EXIT", "ENTRY"]).optional(),
  isRead: z.enum(["true", "false"]).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

// App Usage & Downtime Report Schemas
export const syncAppUsageItemSchema = z.object({
  packageName: z.string().min(1).max(255),
  appName: z.string().min(1).max(255),
  category: z
    .enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"])
    .default("OTHER"),
  foregroundTimeSeconds: z.number().finite().nonnegative().max(90000).default(0),
  lastTimeUsed: timestampSchema.optional().nullable(),
  launchCount: z.number().finite().int().nonnegative().default(0),
  status: z
    .enum(["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"])
    .default("ALWAYS_ALLOWED"),
  dailyLimitMinutes: z.number().finite().nonnegative().optional().nullable(),
  isSystemApp: z.boolean().default(false),
});

export const syncAppUsageReportSchema = z.object({
  date: dateSchema, // YYYY-MM-DD
  totalScreenTimeSeconds: z.number().finite().nonnegative().max(90000).default(0),
  timeZone: timezoneSchema.default("UTC"),
  usageAvailable: z.boolean().default(true),
  metricsVersion: z.number().finite().int().min(1).max(2).default(1),
  totalDowntimeSeconds: z.number().finite().nonnegative().max(90000).nullable().default(null),
  screenOffTimeSeconds: z.number().finite().nonnegative().max(90000).nullable().default(null),
  isDevicePaused: z.boolean().default(false),
  activeScheduleDowntime: z.string().optional().nullable(),
  blockedAttemptsCount: z.number().finite().int().nonnegative().default(0),
  limitsReachedCount: z.number().finite().int().nonnegative().default(0),
  apps: z.array(syncAppUsageItemSchema).max(1000).default([]),
  categoryBreakdown: z
    .array(
      z.object({
        category: z.enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"]),
        totalTimeSeconds: z.number().finite().nonnegative(),
        percentage: z.number().finite().nonnegative().max(100),
      })
    )
    .optional(),
  hourlyUsage: z
    .array(
      z.object({
        hour: z.number().finite().int().min(0).max(23),
        screenTimeSeconds: z.number().finite().nonnegative(),
      })
    )
    .optional(),
});

export const usageReportQuerySchema = z.object({
  date: dateSchema.optional(),
  timeZone: timezoneSchema.optional(),
});
