import { Response } from "express";
import { LocationRecord } from "../models/LocationRecord";
import { Device } from "../models/Device";
import { User } from "../models/User";
import { asyncHandler, AppError } from "../utils/http";
import { recordLocationSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";
import { evaluateChildGeofences } from "../services/geofenceService";

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
    evaluateChildGeofences(childId, child.parentId.toString(), locationPayload).catch((err) =>
      console.error("Error in evaluateChildGeofences (recordLocation):", err)
    );
  }

  res.status(201).json({
    childId,
    ...locationPayload,
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

  // Fallback to most recent LocationRecord if device lastLocation is not yet set
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
