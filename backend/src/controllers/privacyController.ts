import { Response } from "express";
import { z } from "zod";
import { AuthedRequest } from "../middleware/auth";
import { asyncHandler } from "../utils/http";
import { ownedChild, objectIdSchema } from "../services/authorization";
import { LocationRecord } from "../models/LocationRecord";
import { BrowsingHistoryRecord } from "../models/BrowsingHistoryRecord";
import { AppUsageReport } from "../models/AppUsageReport";

const kinds = z.enum(["location", "browsing", "usage"]);
export const exportHistory = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await ownedChild({ userId: req.user!.id, role: req.user!.role }, req.params.childId);
  const query = z.object({ kind: kinds, limit: z.coerce.number().int().min(1).max(500).default(200), cursor: objectIdSchema.optional() }).parse(req.query);
  const filter = { childId: req.params.childId, ...(query.cursor ? { _id: { $gt: query.cursor } } : {}) };
  const records = query.kind === "location"
    ? await LocationRecord.find(filter).sort({ _id: 1 }).limit(query.limit + 1).select("latitude longitude accuracy speed recordedAt").lean()
    : query.kind === "browsing"
      ? await BrowsingHistoryRecord.find(filter).sort({ _id: 1 }).limit(query.limit + 1).select("url domain title category browser isBlockedAttempt visitedAt").lean()
      : await AppUsageReport.find(filter).sort({ _id: 1 }).limit(query.limit + 1).select("date timeZone totalScreenTimeSeconds screenOffTimeSeconds totalDowntimeSeconds apps lastSyncedAt metricsVersion usageAvailable").lean();
  const page = records.slice(0, query.limit);
  res.setHeader("Cache-Control", "no-store");
  res.json({ kind: query.kind, childId: req.params.childId, records: page, nextCursor: records.length > query.limit ? page[page.length - 1]._id.toString() : null });
});

// Explicit, scoped user action. Never invoked by startup or a deployment migration.
export const deleteHistory = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await ownedChild({ userId: req.user!.id, role: req.user!.role }, req.params.childId);
  const data = z.object({ kinds: z.array(kinds).min(1).max(3), confirmation: z.literal("DELETE_HISTORY") }).parse(req.body);
  const result: Record<string, number> = {};
  for (const kind of new Set(data.kinds)) {
    const filter = { childId: req.params.childId };
    const deleted = kind === "location" ? await LocationRecord.deleteMany(filter) : kind === "browsing" ? await BrowsingHistoryRecord.deleteMany(filter) : await AppUsageReport.deleteMany(filter);
    result[kind] = deleted.deletedCount;
    if (kind === "location") {
      const { Device } = await import("../models/Device");
      await Device.updateMany(filter, { $unset: { lastLocation: "" } });
    }
  }
  res.json({ deleted: result });
});
