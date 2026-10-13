import { retentionExpiry } from "./retention";
import { z } from "zod";
import { recordLocationSchema } from "../utils/validation";
import { LocationRecord } from "../models/LocationRecord";
import { Device } from "../models/Device";
import { User } from "../models/User";
import { AppError } from "../utils/http";
import { evaluateChildGeofences } from "./geofenceService";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";

// Serialize ingestion from REST/socket within this single-instance service.
// Multi-instance operation requires shared queues plus validated unique-index migration.
const queues = new Map<string, Promise<unknown>>();
export async function ingestLocation(childId: string, raw: z.input<typeof recordLocationSchema>) {
  const previous = queues.get(childId) ?? Promise.resolve();
  const task = previous.catch(() => undefined).then(async () => {
    const data = recordLocationSchema.parse(raw);
    const child = await User.findById(childId);
    if (!child || child.role !== "CHILD") throw new AppError("Child unavailable", 403);
    const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).lean();
    const location = { ...data, recordedAt: data.recordedAt ? new Date(data.recordedAt) : new Date() };
    const filter = { childId, recordedAt: location.recordedAt, latitude: data.latitude, longitude: data.longitude };
    const existing = await LocationRecord.findOne(filter);
    if (existing) return existing;
    const record = await LocationRecord.create({ ...location, expiresAt: retentionExpiry("LOCATION"), childId, deviceId: device?._id ?? null });
    // An offline batch must never overwrite a newer known fix or trigger a live alert.
    const changed = await Device.updateMany({ childId, $or: [{ "lastLocation.recordedAt": { $lt: location.recordedAt } }, { "lastLocation.recordedAt": null }] }, { $set: { lastLocation: location } });
    if (changed.modifiedCount && child.parentId) {
      for (const id of getParentSocketIds(child.parentId.toString())) getIO().to(id).emit("child_location_update", { childId, ...location });
      if (Date.now() - location.recordedAt.getTime() <= 5 * 60_000) await evaluateChildGeofences(childId, child.parentId.toString(), location);
    }
    return record;
  });
  queues.set(childId, task);
  try { return await task; } finally { if (queues.get(childId) === task) queues.delete(childId); }
}
