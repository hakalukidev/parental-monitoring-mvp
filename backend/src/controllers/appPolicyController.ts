import { Response } from "express";
import { asyncHandler, AppError } from "../utils/http";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { AppPolicy, AppCategory } from "../models/AppPolicy";
import { InstalledApp } from "../models/InstalledApp";
import { Device } from "../models/Device";
import { getIO } from "../socket/io";
import { getChildSocketIds } from "../socket/presence";
import {
  syncInstalledAppsSchema,
  updateAppPolicySchema,
  bulkUpdatePolicySchema,
  toggleDevicePauseSchema,
} from "../utils/validation";

// POST /api/children/:childId/apps/sync (Child or Parent)
export const syncInstalledApps = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.params.childId;
  if (req.user!.role === "CHILD" && req.user!.id !== childId) {
    throw new AppError("Forbidden: cannot sync apps for another child", 403);
  }
  if (req.user!.role === "PARENT") {
    await assertParentOwnsChild(req.user!.id, childId);
  }

  const { apps } = syncInstalledAppsSchema.parse(req.body);

  const bulkOps = apps.map((app) => ({
    updateOne: {
      filter: { childId, packageName: app.packageName },
      update: {
        $set: {
          appName: app.appName,
          category: app.category,
          versionName: app.versionName,
          isSystemApp: app.isSystemApp,
          syncedAt: new Date(),
        },
      },
      upsert: true,
    },
  }));

  if (bulkOps.length > 0) {
    await InstalledApp.bulkWrite(bulkOps);
  }

  // Ensure default AppPolicy exists for all synced apps
  const existingPolicies = await AppPolicy.find({
    childId,
    packageName: { $in: apps.map((a) => a.packageName) },
  }).select("packageName");

  const existingSet = new Set(existingPolicies.map((p) => p.packageName));
  const newPolicies = apps
    .filter((a) => !existingSet.has(a.packageName))
    .map((a) => ({
      childId,
      packageName: a.packageName,
      appName: a.appName,
      category: (a.category as AppCategory) || "OTHER",
      status: "ALWAYS_ALLOWED",
      isSystemWhitelisted: a.isSystemApp,
    }));

  if (newPolicies.length > 0) {
    await AppPolicy.insertMany(newPolicies, { ordered: false }).catch(() => {});
  }

  res.json({ success: true, count: apps.length });
});

// GET /api/children/:childId/apps (Parent only)
export const listChildApps = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;
  await assertParentOwnsChild(parentId, childId);

  const installedApps = await InstalledApp.find({ childId }).sort({ appName: 1 }).lean();
  const policies = await AppPolicy.find({ childId }).lean();
  const policyMap = new Map(policies.map((p) => [p.packageName, p]));

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).lean();

  const combined = installedApps.map((app) => {
    const policy = policyMap.get(app.packageName);
    return {
      packageName: app.packageName,
      appName: app.appName,
      category: policy?.category || app.category || "OTHER",
      status: policy?.status || "ALWAYS_ALLOWED",
      dailyLimitMinutes: policy?.dailyLimitMinutes,
      schedules: policy?.schedules || [],
      isSystemWhitelisted: policy?.isSystemWhitelisted || app.isSystemApp,
      versionName: app.versionName,
      syncedAt: app.syncedAt,
    };
  });

  res.json({
    apps: combined,
    isPaused: device?.isPaused ?? false,
  });
});

// PUT /api/children/:childId/apps/:packageName/policy (Parent only)
export const updateAppPolicy = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, packageName } = req.params;
  await assertParentOwnsChild(parentId, childId);

  const data = updateAppPolicySchema.parse(req.body);

  const policy = await AppPolicy.findOneAndUpdate(
    { childId, packageName },
    {
      $set: {
        ...(data.appName ? { appName: data.appName } : {}),
        ...(data.category ? { category: data.category } : {}),
        status: data.status,
        dailyLimitMinutes: data.dailyLimitMinutes,
        schedules: data.schedules ?? [],
        ...(data.isSystemWhitelisted !== undefined
          ? { isSystemWhitelisted: data.isSystemWhitelisted }
          : {}),
      },
    },
    { new: true, upsert: true }
  );

  // Notify child via socket
  try {
    const io = getIO();
    for (const socketId of getChildSocketIds(childId)) {
      io.to(socketId).emit("policy_updated", {
        type: "APP_POLICY",
        packageName,
        policy,
      });
    }
  } catch {}

  res.json({ policy });
});

// POST /api/children/:childId/apps/bulk-policy (Parent only)
export const bulkUpdatePolicy = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId } = req.params;
  await assertParentOwnsChild(parentId, childId);

  const data = bulkUpdatePolicySchema.parse(req.body);

  const result = await AppPolicy.updateMany(
    { childId, category: data.category, isSystemWhitelisted: false },
    {
      $set: {
        status: data.status,
        ...(data.dailyLimitMinutes !== undefined
          ? { dailyLimitMinutes: data.dailyLimitMinutes }
          : {}),
      },
    }
  );

  // Notify child via socket
  try {
    const io = getIO();
    for (const socketId of getChildSocketIds(childId)) {
      io.to(socketId).emit("policy_updated", {
        type: "BULK_UPDATE",
        category: data.category,
        status: data.status,
      });
    }
  } catch {}

  res.json({ success: true, modifiedCount: result.modifiedCount });
});

// POST /api/children/:childId/pause (Parent only)
export const toggleDevicePause = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId } = req.params;
  await assertParentOwnsChild(parentId, childId);

  const data = toggleDevicePauseSchema.parse(req.body);

  await Device.updateMany({ childId }, { $set: { isPaused: data.isPaused } });

  // Real-time broadcast to child
  try {
    const io = getIO();
    for (const socketId of getChildSocketIds(childId)) {
      io.to(socketId).emit("instant_lockdown_toggle", {
        isPaused: data.isPaused,
      });
    }
  } catch {}

  res.json({ success: true, isPaused: data.isPaused });
});

// GET /api/children/my-policies (Child only)
export const getMyPolicies = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.user!.id;
  const policies = await AppPolicy.find({ childId }).lean();
  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).lean();

  res.json({
    policies,
    isPaused: device?.isPaused ?? false,
  });
});
