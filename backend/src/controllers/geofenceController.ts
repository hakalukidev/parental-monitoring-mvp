import { Response } from "express";
import { Geofence } from "../models/Geofence";
import { GeofenceEvent } from "../models/GeofenceEvent";
import { User } from "../models/User";
import { asyncHandler, AppError } from "../utils/http";
import {
  createGeofenceSchema,
  updateGeofenceSchema,
  geofenceEventsQuerySchema,
} from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { getIO } from "../socket/io";
import { getChildSocketIds } from "../socket/presence";

// Helper to notify child socket of geofence changes
function notifyChildGeofenceUpdate(childId: string, action: "UPSERT" | "DELETE", geofenceData: any) {
  try {
    const io = getIO();
    const childSockets = getChildSocketIds(childId);
    for (const socketId of childSockets) {
      io.to(socketId).emit("geofence_updated", {
        action,
        geofenceId: geofenceData._id?.toString() || geofenceData.id,
        geofence: geofenceData,
      });
    }
  } catch (err) {
    // Ignore socket error if not connected
  }
}

// POST /api/children/:childId/geofences (Parent only)
export const createGeofence = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  const data = createGeofenceSchema.parse(req.body);

  const geofence = await Geofence.create({
    parentId,
    childId,
    name: data.name,
    latitude: data.latitude,
    longitude: data.longitude,
    radius: data.radius,
    address: data.address || "",
    zoneType: data.zoneType,
    triggerType: data.triggerType,
    isEnabled: data.isEnabled,
    colorHex: data.colorHex,
    schedule: data.schedule,
    lastState: "UNKNOWN",
  });

  notifyChildGeofenceUpdate(childId, "UPSERT", geofence.toObject());

  res.status(201).json({
    message: "Geofence created successfully",
    geofence,
  });
});

// GET /api/children/:childId/geofences (Parent only)
export const listGeofences = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  const geofences = await Geofence.find({ childId }).sort({ createdAt: -1 });

  res.json({
    childId,
    count: geofences.length,
    geofences,
  });
});

// GET /api/children/:childId/geofences/:id (Parent only)
export const getGeofence = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, id } = req.params;

  await assertParentOwnsChild(parentId, childId);

  const geofence = await Geofence.findOne({ _id: id, childId });
  if (!geofence) {
    throw new AppError("Geofence not found", 404);
  }

  res.json({ geofence });
});

// PUT /api/children/:childId/geofences/:id (Parent only)
export const updateGeofence = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, id } = req.params;

  await assertParentOwnsChild(parentId, childId);

  const data = updateGeofenceSchema.parse(req.body);

  const geofence = await Geofence.findOne({ _id: id, childId });
  if (!geofence) {
    throw new AppError("Geofence not found", 404);
  }

  if (data.name !== undefined) geofence.name = data.name;
  if (data.latitude !== undefined && data.latitude !== geofence.latitude) {
    geofence.latitude = data.latitude;
    geofence.lastState = "UNKNOWN"; // Reset state on coordinate change
  }
  if (data.longitude !== undefined && data.longitude !== geofence.longitude) {
    geofence.longitude = data.longitude;
    geofence.lastState = "UNKNOWN";
  }
  if (data.radius !== undefined && data.radius !== geofence.radius) {
    geofence.radius = data.radius;
    geofence.lastState = "UNKNOWN";
  }
  if (data.address !== undefined) geofence.address = data.address;
  if (data.zoneType !== undefined) geofence.zoneType = data.zoneType;
  if (data.triggerType !== undefined) geofence.triggerType = data.triggerType;
  if (data.isEnabled !== undefined) geofence.isEnabled = data.isEnabled;
  if (data.colorHex !== undefined) geofence.colorHex = data.colorHex;
  if (data.schedule !== undefined) geofence.schedule = data.schedule;

  await geofence.save();

  notifyChildGeofenceUpdate(childId, "UPSERT", geofence.toObject());

  res.json({
    message: "Geofence updated successfully",
    geofence,
  });
});

// PATCH /api/children/:childId/geofences/:id/toggle (Parent only)
export const toggleGeofence = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, id } = req.params;

  await assertParentOwnsChild(parentId, childId);

  const geofence = await Geofence.findOne({ _id: id, childId });
  if (!geofence) {
    throw new AppError("Geofence not found", 404);
  }

  geofence.isEnabled = !geofence.isEnabled;
  if (!geofence.isEnabled) {
    geofence.lastState = "UNKNOWN";
  }
  await geofence.save();

  notifyChildGeofenceUpdate(childId, "UPSERT", geofence.toObject());

  res.json({
    message: `Geofence ${geofence.isEnabled ? "enabled" : "disabled"}`,
    geofence,
  });
});

// DELETE /api/children/:childId/geofences/:id (Parent only)
export const deleteGeofence = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, id } = req.params;

  await assertParentOwnsChild(parentId, childId);

  const geofence = await Geofence.findOneAndDelete({ _id: id, childId });
  if (!geofence) {
    throw new AppError("Geofence not found", 404);
  }

  notifyChildGeofenceUpdate(childId, "DELETE", { _id: id });

  res.json({
    message: "Geofence deleted successfully",
    id,
  });
});

// GET /api/children/:childId/geofence-events (Parent only)
export const listGeofenceEvents = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  const queryParams = geofenceEventsQuerySchema.parse(req.query);

  const filter: Record<string, any> = { childId };

  if (queryParams.geofenceId) {
    filter.geofenceId = queryParams.geofenceId;
  }
  if (queryParams.eventType) {
    filter.eventType = queryParams.eventType;
  }
  if (queryParams.isRead !== undefined) {
    filter.isRead = queryParams.isRead === "true";
  }

  if (queryParams.startDate || queryParams.endDate) {
    const timeFilter: Record<string, Date> = {};
    if (queryParams.startDate) {
      timeFilter.$gte = new Date(queryParams.startDate);
    }
    if (queryParams.endDate) {
      timeFilter.$lte = new Date(queryParams.endDate);
    }
    filter.triggeredAt = timeFilter;
  }

  const skip = (queryParams.page - 1) * queryParams.limit;

  const [events, total, unreadCount] = await Promise.all([
    GeofenceEvent.find(filter)
      .sort({ triggeredAt: -1 })
      .skip(skip)
      .limit(queryParams.limit)
      .lean(),
    GeofenceEvent.countDocuments(filter),
    GeofenceEvent.countDocuments({ childId, isRead: false }),
  ]);

  res.json({
    childId,
    total,
    page: queryParams.page,
    limit: queryParams.limit,
    totalPages: Math.ceil(total / queryParams.limit),
    unreadCount,
    events,
  });
});

// PATCH /api/children/:childId/geofence-events/:id/read (Parent only)
export const markEventRead = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, id } = req.params;

  await assertParentOwnsChild(parentId, childId);

  const event = await GeofenceEvent.findOneAndUpdate(
    { _id: id, childId },
    { isRead: true },
    { new: true }
  );

  if (!event) {
    throw new AppError("Geofence event not found", 404);
  }

  res.json({ message: "Event marked as read", event });
});

// PATCH /api/children/:childId/geofence-events/mark-all-read (Parent only)
export const markAllEventsRead = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;

  await assertParentOwnsChild(parentId, childId);

  await GeofenceEvent.updateMany({ childId, isRead: false }, { isRead: true });

  res.json({ message: "All geofence events marked as read" });
});

// GET /api/children/my-geofences (Child only)
export const getMyGeofences = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.user!.id;

  const child = await User.findById(childId);
  if (!child || child.role !== "CHILD") {
    throw new AppError("Child not found", 404);
  }

  const geofences = await Geofence.find({ childId, isEnabled: true })
    .select("name latitude longitude radius zoneType triggerType colorHex schedule isEnabled")
    .lean();

  res.json({
    count: geofences.length,
    geofences,
  });
});
