import { Response } from "express";
import { Types } from "mongoose";
import { AuthedRequest } from "../middleware/auth";
import { Device } from "../models/Device";
import { NotificationRecord } from "../models/NotificationRecord";
import { User } from "../models/User";
import { assertParentOwnsChild } from "./childrenController";
import { asyncHandler, AppError } from "../utils/http";
import {
  syncNotificationsBatchSchema,
  notificationHistoryQuerySchema,
} from "../utils/validation";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";

// POST /api/children/:childId/notifications/batch (child only)
export const syncNotificationsBatch = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const userId = req.user!.id;
  const role = req.user!.role;

  if (role === "CHILD" && userId !== childId) {
    throw new AppError("Forbidden: cannot sync notifications for another child", 403);
  }

  const { notifications } = syncNotificationsBatchSchema.parse(req.body);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device) {
    throw new AppError("Device not registered for child", 404);
  }
  const deviceId = device._id;
  const childObjectId = new Types.ObjectId(childId);

  const bulkOps = notifications.map((n) => ({
    updateOne: {
      filter: { childId: childObjectId, externalId: n.externalId },
      update: {
        $setOnInsert: {
          childId: childObjectId,
          deviceId: deviceId,
          externalId: n.externalId,
          packageName: n.packageName,
          appName: n.appName,
          title: n.title,
          content: n.content,
          subText: n.subText || null,
          postTime: new Date(n.postTime),
        },
      },
      upsert: true,
    },
  }));

  const bulkRes = await NotificationRecord.bulkWrite(bulkOps as any);

  // Broadcast real-time notifications to active parent sockets
  if (bulkRes.upsertedCount > 0) {
    try {
      const childUser = await User.findById(childId);
      if (childUser && childUser.parentId) {
        const parentSocketIds = getParentSocketIds(childUser.parentId.toString());
        if (parentSocketIds.length > 0) {
          const io = getIO();
          const latestNotification = notifications[notifications.length - 1];
          for (const socketId of parentSocketIds) {
            io.to(socketId).emit("new_notification_activity", {
              childId,
              childName: childUser.name,
              count: bulkRes.upsertedCount,
              latest: {
                appName: latestNotification.appName,
                packageName: latestNotification.packageName,
                title: latestNotification.title,
                content: latestNotification.content,
                postTime: latestNotification.postTime,
              },
            });
          }
        }
      }
    } catch (_) {}
  }

  return res.status(201).json({
    success: true,
    processedCount: notifications.length,
    insertedCount: bulkRes.upsertedCount,
  });
});

// GET /api/children/:childId/notifications (parent only)
export const getNotifications = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const query = notificationHistoryQuerySchema.parse(req.query);

  const filter: any = { childId: new Types.ObjectId(childId) };

  if (query.packageName) {
    filter.packageName = query.packageName;
  }

  if (query.search) {
    const s = query.search.trim();
    filter.$or = [
      { appName: { $regex: s, $options: "i" } },
      { title: { $regex: s, $options: "i" } },
      { content: { $regex: s, $options: "i" } },
      { packageName: { $regex: s, $options: "i" } },
    ];
  }

  if (query.startDate || query.endDate) {
    filter.postTime = {};
    if (query.startDate) filter.postTime.$gte = new Date(query.startDate);
    if (query.endDate) filter.postTime.$lte = new Date(query.endDate);
  }

  const page = query.page;
  const limit = query.limit;
  const skip = (page - 1) * limit;

  const [notifications, total] = await Promise.all([
    NotificationRecord.find(filter)
      .sort({ postTime: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    NotificationRecord.countDocuments(filter),
  ]);

  const mapped = notifications.map((n) => ({
    id: n._id.toString(),
    externalId: n.externalId,
    packageName: n.packageName,
    appName: n.appName,
    title: n.title,
    content: n.content,
    subText: n.subText,
    postTime: n.postTime.toISOString(),
    createdAt: n.createdAt.toISOString(),
  }));

  return res.json({
    data: mapped,
    notifications: mapped,
    pagination: {
      page,
      limit,
      total,
      pages: Math.ceil(total / limit),
    },
  });
});

// DELETE /api/children/:childId/notifications (parent only)
export const clearNotifications = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const result = await NotificationRecord.deleteMany({ childId: new Types.ObjectId(childId) });

  return res.json({
    success: true,
    deletedCount: result.deletedCount,
  });
});
