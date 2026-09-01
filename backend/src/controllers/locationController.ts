import { Response } from "express";
import { LocationRecord } from "../models/LocationRecord";
import { Device } from "../models/Device";
import { User } from "../models/User";
import { asyncHandler, AppError } from "../utils/http";
import {
  recordLocationSchema,
  recordLocationBatchSchema,
  locationHistoryQuerySchema,
} from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";

// Helper function to broadcast live location to connected parent sockets
export function broadcastChildLocation(
  childId: string,
  parentId: string,
  locationData: {
    latitude: number;
    longitude: number;
    accuracy?: number;
    altitude?: number;
    speed?: number;
    heading?: number;
    batteryLevel?: number;
    recordedAt: Date;
  }
) {
  try {
    const parentSocketIds = getParentSocketIds(parentId);
    const io = getIO();
    for (const socketId of parentSocketIds) {
      io.to(socketId).emit("child_location_update", {
        childId,
        ...locationData,
      });
    }
  } catch {
    // Ignore socket broadcast errors if IO is not initialized yet
  }
}

// POST /api/location/record (Child only)
export const recordLocation = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.user!.id;
  const data = recordLocationSchema.parse(req.body);

  const child = await User.findById(childId);
  if (!child || child.role !== "CHILD") throw new AppError("Child not found", 404);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  const recordedDate = data.recordedAt ? new Date(data.recordedAt) : new Date();

  const record = await LocationRecord.create({
    childId,
    deviceId: device?._id || null,
    latitude: data.latitude,
    longitude: data.longitude,
    accuracy: data.accuracy,
    altitude: data.altitude,
    speed: data.speed,
    heading: data.heading,
    batteryLevel: data.batteryLevel,
    recordedAt: recordedDate,
  });

  const locationPayload = {
    latitude: data.latitude,
    longitude: data.longitude,
    accuracy: data.accuracy,
    altitude: data.altitude,
    speed: data.speed,
    heading: data.heading,
    batteryLevel: data.batteryLevel,
    recordedAt: recordedDate,
  };

  if (device) {
    device.lastLocation = locationPayload;
    device.lastSeen = new Date();
    await device.save();
  }

  if (child.parentId) {
    broadcastChildLocation(childId, child.parentId.toString(), locationPayload);
  }

  res.status(201).json({
    id: record._id,
    childId: record.childId,
    ...locationPayload,
  });
});

// POST /api/location/batch (Child only)
export const recordLocationBatch = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.user!.id;
  const { points } = recordLocationBatchSchema.parse(req.body);

  const child = await User.findById(childId);
  if (!child || child.role !== "CHILD") throw new AppError("Child not found", 404);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });

  const docs = points.map((p) => ({
    childId,
    deviceId: device?._id || null,
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    altitude: p.altitude,
    speed: p.speed,
    heading: p.heading,
    batteryLevel: p.batteryLevel,
    recordedAt: p.recordedAt ? new Date(p.recordedAt) : new Date(),
  }));

  const inserted = await LocationRecord.insertMany(docs);

  if (docs.length > 0) {
    // Sort to find the latest point in the batch
    const latestDoc = [...docs].sort(
      (a, b) => b.recordedAt.getTime() - a.recordedAt.getTime()
    )[0];

    if (device) {
      device.lastLocation = latestDoc;
      device.lastSeen = new Date();
      await device.save();
    }

    if (child.parentId) {
      broadcastChildLocation(childId, child.parentId.toString(), latestDoc);
    }
  }

  res.status(201).json({
    count: inserted.length,
    message: `Recorded ${inserted.length} location points`,
  });
});

// GET /api/location/latest/:childId (Parent only)
export const getLatestLocation = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  // Check device first for cached last location
  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (device?.lastLocation) {
    res.json({
      childId,
      location: device.lastLocation,
      deviceStatus: device.status,
      lastSeen: device.lastSeen,
    });
    return;
  }

  // Fallback to most recent LocationRecord
  const latestRecord = await LocationRecord.findOne({ childId }).sort({ recordedAt: -1 });
  if (!latestRecord) {
    res.json({
      childId,
      location: null,
      deviceStatus: device?.status || "OFFLINE",
      lastSeen: device?.lastSeen || null,
    });
    return;
  }

  res.json({
    childId,
    location: {
      latitude: latestRecord.latitude,
      longitude: latestRecord.longitude,
      accuracy: latestRecord.accuracy,
      altitude: latestRecord.altitude,
      speed: latestRecord.speed,
      heading: latestRecord.heading,
      batteryLevel: latestRecord.batteryLevel,
      recordedAt: latestRecord.recordedAt,
    },
    deviceStatus: device?.status || "OFFLINE",
    lastSeen: device?.lastSeen || null,
  });
});

// GET /api/location/history/:childId (Parent only)
export const getLocationHistory = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  const queryParams = locationHistoryQuerySchema.parse(req.query);

  const filter: Record<string, unknown> = { childId };

  if (queryParams.startTime || queryParams.endTime) {
    const timeFilter: Record<string, Date> = {};
    if (queryParams.startTime) {
      timeFilter.$gte = new Date(queryParams.startTime);
    }
    if (queryParams.endTime) {
      timeFilter.$lte = new Date(queryParams.endTime);
    }
    filter.recordedAt = timeFilter;
  } else {
    // Default to last 24 hours if no time range provided
    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    filter.recordedAt = { $gte: oneDayAgo };
  }

  const records = await LocationRecord.find(filter)
    .sort({ recordedAt: 1 }) // Chronological order for breadcrumb route rendering
    .limit(queryParams.limit)
    .lean();

  const points = records.map((r) => ({
    id: r._id,
    latitude: r.latitude,
    longitude: r.longitude,
    accuracy: r.accuracy,
    altitude: r.altitude,
    speed: r.speed,
    heading: r.heading,
    batteryLevel: r.batteryLevel,
    recordedAt: r.recordedAt,
  }));

  res.json({
    childId,
    count: points.length,
    points,
  });
});
