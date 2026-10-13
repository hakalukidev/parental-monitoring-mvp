import { ingestLocation } from "../services/locationIngestion";
import { Response } from "express";
import { LocationRecord } from "../models/LocationRecord";
import { Device } from "../models/Device";
import { asyncHandler } from "../utils/http";
import {
  recordLocationSchema,
  recordLocationBatchSchema,
  locationHistoryQuerySchema,
} from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { getIO } from "../socket/io";
import { getParentSocketIds, getChildSocketIds } from "../socket/presence";

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

// Both upload paths use the same validation, ordering and deduplication logic.
export const recordLocation = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const record = await ingestLocation(req.user!.id, recordLocationSchema.parse(req.body));
  res.status(201).json(record);
});
export const recordLocationBatch = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { points } = recordLocationBatchSchema.parse(req.body);
  for (const point of [...points].sort((a, b) => new Date(a.recordedAt ?? 0).getTime() - new Date(b.recordedAt ?? 0).getTime())) await ingestLocation(req.user!.id, point);
  res.status(201).json({ count: points.length });
});

// GET /api/location/latest/:childId (Parent only)
export const getLatestLocation = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  // Check device first for cached last location
  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (device?.lastLocation && typeof device.lastLocation.latitude === "number" && typeof device.lastLocation.longitude === "number" && device.lastLocation.recordedAt) {
    res.json({
      childId,
      location: device.lastLocation,
      deviceStatus: getChildSocketIds(childId).length ? "ONLINE" : "OFFLINE",
      isStale: Date.now() - new Date(device.lastLocation.recordedAt).getTime() > 300_000,
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
      deviceStatus: getChildSocketIds(childId).length ? "ONLINE" : "OFFLINE",
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
    deviceStatus: getChildSocketIds(childId).length ? "ONLINE" : "OFFLINE",
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
