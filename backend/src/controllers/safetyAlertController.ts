import { Response } from "express";
import { Types } from "mongoose";
import { AuthedRequest } from "../middleware/auth";
import { Device } from "../models/Device";
import { SafetyAlert, SafetySeverity, SafetyAlertType } from "../models/SafetyAlert";
import { User } from "../models/User";
import { assertParentOwnsChild } from "./childrenController";
import { asyncHandler, AppError } from "../utils/http";
import {
  recordSafetyAlertsBatchSchema,
  safetyAlertQuerySchema,
} from "../utils/validation";
import { getIO } from "../socket/io";
import { getParentSocketIds, getChildSocketIds } from "../socket/presence";
import { AppPolicy } from "../models/AppPolicy";
import { InstalledApp } from "../models/InstalledApp";

// POST /api/children/:childId/safety-alerts/batch (child only)
export const recordSafetyAlertsBatch = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const userId = req.user!.id;
  const role = req.user!.role;

  if (role === "CHILD" && userId !== childId) {
    throw new AppError("Forbidden: cannot record safety alerts for another child", 403);
  }

  const { alerts } = recordSafetyAlertsBatchSchema.parse(req.body);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device) {
    throw new AppError("Device not registered for child", 404);
  }
  const deviceId = device._id;
  const childObjectId = new Types.ObjectId(childId);

  const bulkOps = alerts.map((alert) => ({
    updateOne: {
      filter: { childId: childObjectId, externalId: alert.externalId },
      update: {
        $setOnInsert: {
          childId: childObjectId,
          deviceId: deviceId,
          externalId: alert.externalId,
          alertType: alert.alertType as SafetyAlertType,
          packageName: alert.packageName || null,
          appName: alert.appName || null,
          confidenceScore: alert.confidenceScore,
          severity: alert.severity as SafetySeverity,
          isAcknowledged: false,
          acknowledgedAt: null,
          timestamp: new Date(alert.timestamp),
        },
      },
      upsert: true,
    },
  }));

  const bulkRes = await SafetyAlert.bulkWrite(bulkOps as any);

  // Automatically enforce AppPolicy status = BLOCKED for offending applications
  for (const alert of alerts) {
    if (
      alert.packageName &&
      alert.packageName !== "com.android.providers.media" &&
      !alert.packageName.startsWith("com.android.systemui") &&
      !alert.packageName.includes("launcher") &&
      alert.packageName !== "android"
    ) {
      try {
        const policy = await AppPolicy.findOneAndUpdate(
          { childId: childObjectId, packageName: alert.packageName },
          {
            $set: {
              status: "BLOCKED",
              appName: alert.appName || alert.packageName,
            },
          },
          { upsert: true, new: true }
        );

        await InstalledApp.updateOne(
          { childId: childObjectId, packageName: alert.packageName },
          {
            $setOnInsert: {
              appName: alert.appName || alert.packageName,
              category: "OTHER",
              syncedAt: new Date(),
            },
          },
          { upsert: true }
        ).catch(() => {});

        // Broadcast policy_updated event to child socket
        const io = getIO();
        for (const cSocketId of getChildSocketIds(childId)) {
          io.to(cSocketId).emit("policy_updated", {
            type: "APP_POLICY",
            packageName: alert.packageName,
            policy,
          });
        }
      } catch (err) {
        console.error("Error auto-blocking offending app on safety alert:", err);
      }
    }
  }

  // Broadcast real-time urgent safety alerts to active parent sockets
  if (bulkRes.upsertedCount > 0) {
    const child = await User.findById(childId);
    if (child && child.parentId) {
      const parentSocketIds = getParentSocketIds(child.parentId.toString());
      for (const sId of parentSocketIds) {
        getIO().to(sId).emit("safety_alert_triggered", {
          childId,
          childName: child.name,
          newAlertCount: bulkRes.upsertedCount,
          latestAlert: alerts[0],
        });
      }
    }
  }

  res.status(200).json({
    success: true,
    processedCount: alerts.length,
    upsertedCount: bulkRes.upsertedCount,
  });
});

// GET /api/children/:childId/safety-alerts (parent only)
export const getSafetyAlerts = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const query = safetyAlertQuerySchema.parse(req.query);

  const filter: any = { childId };

  if (query.severity) {
    filter.severity = query.severity;
  }

  if (query.isAcknowledged !== undefined) {
    filter.isAcknowledged = query.isAcknowledged === "true";
  }

  if (query.startDate || query.endDate) {
    filter.timestamp = {};
    if (query.startDate) filter.timestamp.$gte = new Date(query.startDate);
    if (query.endDate) filter.timestamp.$lte = new Date(query.endDate);
  }

  const page = query.page;
  const limit = query.limit;
  const skip = (page - 1) * limit;

  const [alerts, total, unacknowledgedCount] = await Promise.all([
    SafetyAlert.find(filter).sort({ timestamp: -1 }).skip(skip).limit(limit),
    SafetyAlert.countDocuments(filter),
    SafetyAlert.countDocuments({ childId, isAcknowledged: false }),
  ]);

  res.status(200).json({
    alerts,
    total,
    unacknowledgedCount,
    page,
    totalPages: Math.ceil(total / limit) || 1,
  });
});

// PATCH /api/children/:childId/safety-alerts/:alertId/acknowledge (parent only)
export const acknowledgeSafetyAlert = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId, alertId } = req.params;
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const alert = await SafetyAlert.findOneAndUpdate(
    { _id: alertId, childId },
    { isAcknowledged: true, acknowledgedAt: new Date() },
    { new: true }
  );

  if (!alert) {
    throw new AppError("Safety alert not found", 404);
  }

  res.status(200).json({ success: true, alert });
});
