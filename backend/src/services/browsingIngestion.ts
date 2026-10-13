import { retentionExpiry } from "./retention";
import { z } from "zod";
import { recordBrowsingHistorySchema } from "../utils/validation";
import { BrowsingHistoryRecord } from "../models/BrowsingHistoryRecord";
import { Device } from "../models/Device";
import { User } from "../models/User";
import { AppError } from "../utils/http";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";

const queues = new Map<string, Promise<unknown>>();
export async function ingestBrowsing(childId: string, records: z.input<typeof recordBrowsingHistorySchema>[]) {
  const previous = queues.get(childId) ?? Promise.resolve();
  const task = previous.catch(() => undefined).then(async () => {
    const child = await User.findById(childId);
    if (!child || child.role !== "CHILD") throw new AppError("Child unavailable", 403);
    const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).lean();
    const inserted = [];
    for (const raw of records) {
      const data = recordBrowsingHistorySchema.parse(raw);
      if (data.isIncognito) continue;
      const url = new URL(data.url);
      // Credentials, fragments and query strings may contain private tokens/search text.
      url.username = ""; url.password = ""; url.hash = ""; url.search = "";
      const payload = { ...data, url: url.toString(), domain: url.hostname.toLowerCase(), visitedAt: data.visitedAt ? new Date(data.visitedAt) : new Date() };
      const existing = await BrowsingHistoryRecord.findOne({ childId, url: payload.url, visitedAt: payload.visitedAt });
      if (existing) continue;
      const record = await BrowsingHistoryRecord.create({ ...payload, expiresAt: retentionExpiry("BROWSING"), childId, deviceId: device?._id ?? null });
      inserted.push(record);
      if (child.parentId) for (const id of getParentSocketIds(child.parentId.toString())) {
        getIO().to(id).emit("new_browsing_activity", { childId, record });
        if (record.isBlockedAttempt || ["ADULT", "SUSPICIOUS"].includes(record.category ?? "GENERAL")) getIO().to(id).emit("suspicious_web_alert", { childId, childName: child.name, record });
      }
    }
    return inserted;
  });
  queues.set(childId, task);
  try { return await task; } finally { if (queues.get(childId) === task) queues.delete(childId); }
}
