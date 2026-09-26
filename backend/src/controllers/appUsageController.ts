import { Response } from "express";
import { asyncHandler, AppError } from "../utils/http";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { AppUsageReport, IAppUsageItem, ICategoryUsageBreakdown } from "../models/AppUsageReport";
import { InstalledApp } from "../models/InstalledApp";
import { AppPolicy, AppCategory } from "../models/AppPolicy";
import { Device } from "../models/Device";
import { User } from "../models/User";
import { getIO } from "../socket/io";
import { getChildSocketIds, getParentSocketIds, getAllParentSocketIds } from "../socket/presence";
import { syncAppUsageReportSchema, usageReportQuerySchema } from "../utils/validation";

function getTodayDateString(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

// POST /api/children/:childId/usage/sync (Child or Parent)
export const syncDailyUsage = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.params.childId;
  if (req.user!.role === "CHILD" && req.user!.id !== childId) {
    throw new AppError("Forbidden: cannot sync usage report for another child", 403);
  }
  if (req.user!.role === "PARENT") {
    await assertParentOwnsChild(req.user!.id, childId);
  }

  const data = syncAppUsageReportSchema.parse(req.body);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).lean();

  // Calculate or ensure category breakdown
  let categoryBreakdown = data.categoryBreakdown;
  if (!categoryBreakdown || categoryBreakdown.length === 0) {
    const categoryTotals: Record<AppCategory, number> = {
      GAME: 0,
      SOCIAL: 0,
      ENTERTAINMENT: 0,
      EDUCATION: 0,
      PRODUCTIVITY: 0,
      OTHER: 0,
    };

    let totalUsage = 0;
    for (const app of data.apps) {
      const cat = (app.category as AppCategory) || "OTHER";
      categoryTotals[cat] = (categoryTotals[cat] || 0) + app.foregroundTimeSeconds;
      totalUsage += app.foregroundTimeSeconds;
    }

    categoryBreakdown = Object.entries(categoryTotals).map(([cat, total]) => ({
      category: cat as AppCategory,
      totalTimeSeconds: total,
      percentage: totalUsage > 0 ? Math.round((total / totalUsage) * 100) : 0,
    }));
  }

  // Calculate limits reached count
  let limitsReachedCount = data.limitsReachedCount || 0;
  if (limitsReachedCount === 0) {
    for (const app of data.apps) {
      if (app.dailyLimitMinutes && app.dailyLimitMinutes > 0) {
        if (app.foregroundTimeSeconds >= app.dailyLimitMinutes * 60) {
          limitsReachedCount++;
        }
      }
    }
  }

  const report = await AppUsageReport.findOneAndUpdate(
    { childId, date: data.date },
    {
      $set: {
        childId,
        deviceId: device?._id ?? null,
        date: data.date,
        totalScreenTimeSeconds: data.totalScreenTimeSeconds,
        totalDowntimeSeconds: data.totalDowntimeSeconds,
        screenOffTimeSeconds: data.screenOffTimeSeconds,
        isDevicePaused: data.isDevicePaused,
        activeScheduleDowntime: data.activeScheduleDowntime ?? null,
        blockedAttemptsCount: data.blockedAttemptsCount,
        limitsReachedCount,
        apps: data.apps,
        categoryBreakdown,
        hourlyUsage: data.hourlyUsage ?? [],
        lastSyncedAt: new Date(),
      },
    },
    { new: true, upsert: true }
  );

  // Notify parent sockets in real-time
  try {
    const io = getIO();
    const child = await User.findById(childId).select("parentId").lean();
    const parentSocketIds = child?.parentId
      ? getParentSocketIds(String(child.parentId))
      : getAllParentSocketIds();

    for (const parentSocketId of parentSocketIds) {
      io.to(parentSocketId).emit("usage_updated", {
        childId,
        date: data.date,
        report,
      });
    }
  } catch {}

  res.json({ success: true, report });
});

// GET /api/children/:childId/usage/today (Parent or Child)
export const getTodayUsageReport = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.params.childId;
  if (req.user!.role === "PARENT") {
    await assertParentOwnsChild(req.user!.id, childId);
  } else if (req.user!.role === "CHILD" && req.user!.id !== childId) {
    throw new AppError("Forbidden: cannot view usage report for another child", 403);
  }

  const query = usageReportQuerySchema.parse(req.query);
  const targetDate = query.date || getTodayDateString();

  const report = await AppUsageReport.findOne({ childId, date: targetDate }).lean();
  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).lean();
  const installedApps = await InstalledApp.find({ childId }).sort({ appName: 1 }).lean();
  const policies = await AppPolicy.find({ childId }).lean();
  const policyMap = new Map(policies.map((p) => [p.packageName, p]));

  // If a report exists, merge with installed apps/policies to ensure comprehensive view
  const recordedAppMap = new Map<string, IAppUsageItem>();
  if (report && report.apps) {
    for (const a of report.apps) {
      recordedAppMap.set(a.packageName, a);
    }
  }

  const combinedApps: IAppUsageItem[] = [];

  // Add recorded apps first
  for (const recorded of recordedAppMap.values()) {
    const pol = policyMap.get(recorded.packageName);
    combinedApps.push({
      packageName: recorded.packageName,
      appName: recorded.appName,
      category: (pol?.category || recorded.category || "OTHER") as AppCategory,
      foregroundTimeSeconds: recorded.foregroundTimeSeconds || 0,
      lastTimeUsed: recorded.lastTimeUsed ?? null,
      launchCount: recorded.launchCount || 0,
      status: pol?.status || recorded.status || "ALWAYS_ALLOWED",
      dailyLimitMinutes: pol?.dailyLimitMinutes ?? recorded.dailyLimitMinutes ?? null,
      isSystemApp: pol?.isSystemWhitelisted ?? recorded.isSystemApp ?? false,
    });
  }

  // Include installed apps with 0 usage that weren't in the report
  for (const app of installedApps) {
    if (!recordedAppMap.has(app.packageName)) {
      const pol = policyMap.get(app.packageName);
      combinedApps.push({
        packageName: app.packageName,
        appName: app.appName,
        category: (pol?.category || app.category || "OTHER") as AppCategory,
        foregroundTimeSeconds: 0,
        lastTimeUsed: null,
        launchCount: 0,
        status: pol?.status || "ALWAYS_ALLOWED",
        dailyLimitMinutes: pol?.dailyLimitMinutes ?? null,
        isSystemApp: pol?.isSystemWhitelisted ?? app.isSystemApp ?? false,
      });
    }
  }

  // Sort apps: first by foreground usage descending, then by launches, then alphabetical
  combinedApps.sort((a, b) => {
    if (b.foregroundTimeSeconds !== a.foregroundTimeSeconds) {
      return b.foregroundTimeSeconds - a.foregroundTimeSeconds;
    }
    if (b.launchCount !== a.launchCount) {
      return b.launchCount - a.launchCount;
    }
    return a.appName.localeCompare(b.appName);
  });

  const totalScreenTimeSeconds = report?.totalScreenTimeSeconds ??
    combinedApps.reduce((acc, app) => acc + app.foregroundTimeSeconds, 0);

  // Calculate total seconds elapsed today
  const now = new Date();
  const elapsedDaySeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
  const totalDowntimeSeconds = report?.totalDowntimeSeconds ??
    Math.max(0, elapsedDaySeconds - totalScreenTimeSeconds);
  const screenOffTimeSeconds = report?.screenOffTimeSeconds ?? totalDowntimeSeconds;

  // Most used app
  const mostUsedApp = combinedApps.length > 0 && combinedApps[0].foregroundTimeSeconds > 0
    ? {
        packageName: combinedApps[0].packageName,
        appName: combinedApps[0].appName,
        category: combinedApps[0].category,
        foregroundTimeSeconds: combinedApps[0].foregroundTimeSeconds,
      }
    : null;

  // Category breakdown calculation
  let categoryBreakdown: ICategoryUsageBreakdown[] = report?.categoryBreakdown ?? [];
  if (categoryBreakdown.length === 0) {
    const categoryTotals: Record<AppCategory, number> = {
      GAME: 0,
      SOCIAL: 0,
      ENTERTAINMENT: 0,
      EDUCATION: 0,
      PRODUCTIVITY: 0,
      OTHER: 0,
    };

    for (const app of combinedApps) {
      categoryTotals[app.category] = (categoryTotals[app.category] || 0) + app.foregroundTimeSeconds;
    }

    categoryBreakdown = Object.entries(categoryTotals).map(([cat, total]) => ({
      category: cat as AppCategory,
      totalTimeSeconds: total,
      percentage: totalScreenTimeSeconds > 0 ? Math.round((total / totalScreenTimeSeconds) * 100) : 0,
    }));
  }

  // Count blocked / limited
  let limitsReachedCount = 0;
  for (const app of combinedApps) {
    if (app.dailyLimitMinutes && app.dailyLimitMinutes > 0) {
      if (app.foregroundTimeSeconds >= app.dailyLimitMinutes * 60) {
        limitsReachedCount++;
      }
    }
  }

  const blockedAttemptsCount = report?.blockedAttemptsCount ?? 0;
  const isDevicePaused = device?.isPaused ?? report?.isDevicePaused ?? false;

  const responsePayload = {
    date: targetDate,
    childId,
    lastSyncedAt: report?.lastSyncedAt ?? device?.lastSeen ?? new Date(),
    summary: {
      totalScreenTimeSeconds,
      totalDowntimeSeconds,
      screenOffTimeSeconds,
      isDevicePaused,
      activeScheduleDowntime: report?.activeScheduleDowntime ?? null,
      blockedAttemptsCount,
      limitsReachedCount,
      totalAppsTracked: combinedApps.length,
      appsWithUsageCount: combinedApps.filter((a) => a.foregroundTimeSeconds > 0).length,
      mostUsedApp,
    },
    categoryBreakdown,
    hourlyUsage: report?.hourlyUsage ?? [],
    apps: combinedApps,
    device: device
      ? {
          id: device._id,
          deviceName: device.deviceName,
          platform: device.platform,
          status: device.status,
          isPaused: device.isPaused,
          lastSeen: device.lastSeen,
        }
      : null,
  };

  res.json(responsePayload);
});

// POST /api/children/:childId/usage/request-sync (Parent only)
export const requestUsageSync = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.params.childId;
  await assertParentOwnsChild(req.user!.id, childId);

  const socketIds = getChildSocketIds(childId);
  const isOnline = socketIds.length > 0;

  if (isOnline) {
    try {
      const io = getIO();
      for (const sid of socketIds) {
        io.to(sid).emit("request_usage_sync", {
          childId,
          requestedAt: new Date().toISOString(),
        });
      }
    } catch {}
  }

  res.json({
    success: true,
    sentToChild: isOnline,
    message: isOnline ? "Real-time usage sync requested" : "Child device is offline",
  });
});
