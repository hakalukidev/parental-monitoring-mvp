import { z } from "zod";

export const registerParentSchema = z
  .object({
    name: z.string().min(2).max(100),
    email: z.string().email(),
    password: z.string().min(8).max(128),
    confirmPassword: z.string().min(8).max(128),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"],
  });

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export const childLoginSchema = z.object({
  email: z.string().min(3), // child logs in with username, not necessarily an email
  password: z.string().min(1),
});

export const createChildSchema = z
  .object({
    name: z.string().min(2).max(100),
    username: z.string().min(3).max(50), // stored as email field internally (username@child.local pattern not required; we store raw as unique login id)
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
});

export const screenShareRequestSchema = z.object({
  childId: z.string().min(1),
});

export const cameraStreamRequestSchema = z.object({
  childId: z.string().min(1),
  cameraFacing: z.enum(["BACK", "FRONT"]).default("BACK"),
  withAudio: z.boolean().default(true),
});

export const recordLocationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracy: z.number().nonnegative().optional(),
  altitude: z.number().optional(),
  speed: z.number().nonnegative().optional(),
  heading: z.number().min(0).max(360).optional(),
  batteryLevel: z.number().min(0).max(100).optional(),
  recordedAt: z.string().or(z.date()).optional(),
});

export const recordLocationBatchSchema = z.object({
  points: z.array(recordLocationSchema).min(1).max(500),
});

export const locationHistoryQuerySchema = z.object({
  startTime: z.string().optional(),
  endTime: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(2000).default(500),
});

// App Policy Validation Schemas
export const syncInstalledAppsSchema = z.object({
  apps: z.array(
    z.object({
      packageName: z.string().min(1),
      appName: z.string().min(1),
      category: z.string().default("OTHER"),
      versionName: z.string().optional(),
      isSystemApp: z.boolean().default(false),
    })
  ),
});

export const updateAppPolicySchema = z.object({
  appName: z.string().optional(),
  category: z
    .enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"])
    .optional(),
  status: z.enum(["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"]),
  dailyLimitMinutes: z.number().min(0).max(1440).optional(),
  schedules: z
    .array(
      z.object({
        daysOfWeek: z.array(z.number().min(0).max(6)),
        startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
        endTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
      })
    )
    .optional(),
  isSystemWhitelisted: z.boolean().optional(),
});

export const bulkUpdatePolicySchema = z.object({
  category: z.enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"]),
  status: z.enum(["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"]),
  dailyLimitMinutes: z.number().min(0).max(1440).optional(),
});

export const toggleDevicePauseSchema = z.object({
  isPaused: z.boolean(),
});

// Web Block Rules Validation Schemas
export const createWebRuleSchema = z.object({
  ruleType: z.enum(["DOMAIN", "KEYWORD", "CATEGORY"]),
  target: z.string().min(1),
  action: z.enum(["BLOCK", "ALLOW"]).default("BLOCK"),
  isEnabled: z.boolean().default(true),
});

export const updateWebRuleSchema = z.object({
  action: z.enum(["BLOCK", "ALLOW"]).optional(),
  isEnabled: z.boolean().optional(),
});

// Browsing History Validation Schemas
export const recordBrowsingHistorySchema = z.object({
  url: z.string().min(1),
  domain: z.string().min(1),
  title: z.string().default(""),
  browser: z
    .enum(["CHROME", "FIREFOX", "SAMSUNG_BROWSER", "EDGE", "OPERA", "BRAVE", "OTHER"])
    .default("OTHER"),
  isIncognito: z.boolean().default(false),
  category: z
    .enum(["EDUCATION", "ENTERTAINMENT", "GAMING", "SOCIAL", "ADULT", "SUSPICIOUS", "GENERAL"])
    .optional(),
  isBlockedAttempt: z.boolean().default(false),
  blockedReason: z.string().optional(),
  visitedAt: z.string().or(z.date()).optional(),
});

export const recordBrowsingBatchSchema = z.object({
  records: z.array(recordBrowsingHistorySchema).min(1).max(500),
});

export const browsingHistoryQuerySchema = z.object({
  startDate: z.string().optional(),
  endDate: z.string().optional(),
  search: z.string().optional(),
  browser: z.string().optional(),
  isFlagged: z.string().optional(),
  isBlockedAttempt: z.string().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

// Geofence Validation Schemas
export const createGeofenceSchema = z.object({
  name: z.string().min(1).max(100),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  radius: z.number().min(30).max(20000).default(200),
  address: z.string().optional(),
  zoneType: z.enum(["SAFE_ZONE", "RESTRICTED_ZONE"]).default("SAFE_ZONE"),
  triggerType: z.enum(["EXIT", "ENTRY", "BOTH"]).default("EXIT"),
  isEnabled: z.boolean().default(true),
  colorHex: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional().default("#2196F3"),
  schedule: z
    .object({
      daysOfWeek: z.array(z.number().min(0).max(6)).default([0, 1, 2, 3, 4, 5, 6]),
      startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
      endTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
    })
    .optional(),
});

export const updateGeofenceSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  radius: z.number().min(30).max(20000).optional(),
  address: z.string().optional(),
  zoneType: z.enum(["SAFE_ZONE", "RESTRICTED_ZONE"]).optional(),
  triggerType: z.enum(["EXIT", "ENTRY", "BOTH"]).optional(),
  isEnabled: z.boolean().optional(),
  colorHex: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  schedule: z
    .object({
      daysOfWeek: z.array(z.number().min(0).max(6)),
      startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
      endTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
    })
    .optional(),
});

export const geofenceEventsQuerySchema = z.object({
  startDate: z.string().optional(),
  endDate: z.string().optional(),
  geofenceId: z.string().optional(),
  eventType: z.enum(["EXIT", "ENTRY"]).optional(),
  isRead: z.enum(["true", "false"]).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

// App Usage & Downtime Report Schemas
export const syncAppUsageItemSchema = z.object({
  packageName: z.string().min(1),
  appName: z.string().min(1),
  category: z
    .enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"])
    .default("OTHER"),
  foregroundTimeSeconds: z.number().nonnegative().default(0),
  lastTimeUsed: z.string().or(z.date()).optional().nullable(),
  launchCount: z.number().int().nonnegative().default(0),
  status: z
    .enum(["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"])
    .default("ALWAYS_ALLOWED"),
  dailyLimitMinutes: z.number().nonnegative().optional().nullable(),
  isSystemApp: z.boolean().default(false),
});

export const syncAppUsageReportSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), // YYYY-MM-DD
  totalScreenTimeSeconds: z.number().nonnegative().default(0),
  totalDowntimeSeconds: z.number().nonnegative().default(0),
  screenOffTimeSeconds: z.number().nonnegative().default(0),
  isDevicePaused: z.boolean().default(false),
  activeScheduleDowntime: z.string().optional().nullable(),
  blockedAttemptsCount: z.number().int().nonnegative().default(0),
  limitsReachedCount: z.number().int().nonnegative().default(0),
  apps: z.array(syncAppUsageItemSchema).default([]),
  categoryBreakdown: z
    .array(
      z.object({
        category: z.enum(["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"]),
        totalTimeSeconds: z.number().nonnegative(),
        percentage: z.number().nonnegative().max(100),
      })
    )
    .optional(),
  hourlyUsage: z
    .array(
      z.object({
        hour: z.number().int().min(0).max(23),
        screenTimeSeconds: z.number().nonnegative(),
      })
    )
    .optional(),
});

export const usageReportQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});
