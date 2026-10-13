import { Types } from "mongoose";
import { Device } from "../models/Device";
import { localDayBounds } from "../services/calendar";
import { ingestBrowsing } from "../services/browsingIngestion";
import { Response } from "express";
import { asyncHandler, AppError } from "../utils/http";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { BrowsingHistoryRecord } from "../models/BrowsingHistoryRecord";
import {
  recordBrowsingBatchSchema,
  browsingHistoryQuerySchema,
} from "../utils/validation";

// GET /api/children/:childId/browsing-history (Parent only)
export const listBrowsingHistory = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;
  await assertParentOwnsChild(parentId, childId);

  const query = browsingHistoryQuerySchema.parse(req.query);
  const filter: any = { childId };

  if (query.startDate || query.endDate) {
    filter.visitedAt = {};
    if (query.startDate) filter.visitedAt.$gte = new Date(query.startDate);
    if (query.endDate) filter.visitedAt.$lte = new Date(query.endDate);
  }

  if (query.search && query.search.trim()) {
    const s = query.search.trim().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    filter.$or = [
      { url: { $regex: s, $options: "i" } },
      { domain: { $regex: s, $options: "i" } },
      { title: { $regex: s, $options: "i" } },
    ];
  }

  if (query.browser) {
    filter.browser = query.browser.toUpperCase();
  }

  if (query.isFlagged === "true") {
    filter.category = { $in: ["ADULT", "SUSPICIOUS"] };
  }

  if (query.isBlockedAttempt === "true") {
    filter.isBlockedAttempt = true;
  }

  const skip = (query.page - 1) * query.limit;
  const [records, total] = await Promise.all([
    BrowsingHistoryRecord.find(filter)
      .sort({ visitedAt: -1 })
      .skip(skip)
      .limit(query.limit)
      .lean(),
    BrowsingHistoryRecord.countDocuments(filter),
  ]);

  res.json({
    records,
    total,
    page: query.page,
    totalPages: Math.ceil(total / query.limit),
  });
});

// POST /api/children/:childId/browsing-history/batch (Child only)
export const recordBatchHistory = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.params.childId;
  if (req.user!.role !== "CHILD" || req.user!.id !== childId) {
    throw new AppError("Forbidden: can only record history for yourself", 403);
  }

  const data = recordBrowsingBatchSchema.parse(req.body);
  const inserted = await ingestBrowsing(childId, data.records);
  res.json({ success: true, count: inserted.length });
});

// GET /api/children/:childId/browsing-history/analytics (Parent only)
export const getBrowsingAnalytics = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;
  await assertParentOwnsChild(parentId, childId);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 }).select("timeZone").lean();
  const { start, end } = localDayBounds(device?.timeZone ?? "UTC");
  const todayFilter = { childId: new Types.ObjectId(childId), visitedAt: { $gte: start, $lt: end } };

  const [totalVisited, blockedAttempts, topDomainsRaw, categoryBreakdownRaw] = await Promise.all([
    BrowsingHistoryRecord.countDocuments(todayFilter),
    BrowsingHistoryRecord.countDocuments({ ...todayFilter, isBlockedAttempt: true }),
    BrowsingHistoryRecord.aggregate([
      { $match: todayFilter },
      { $group: { _id: "$domain", count: { $sum: 1 } } },
      { $sort: { count: -1 } },
      { $limit: 5 },
    ]),
    BrowsingHistoryRecord.aggregate([
      { $match: todayFilter },
      { $group: { _id: "$category", count: { $sum: 1 } } },
      { $sort: { count: -1 } },
    ]),
  ]);

  const topDomains = topDomainsRaw.map((item) => ({
    domain: item._id,
    count: item.count,
    percentage: totalVisited > 0 ? Math.round((item.count / totalVisited) * 100) : 0,
  }));

  const categoryDistribution: Record<string, number> = {};
  for (const item of categoryBreakdownRaw) {
    categoryDistribution[item._id || "GENERAL"] = item.count;
  }

  res.json({
    totalVisited,
    blockedAttempts,
    topDomains,
    categoryDistribution,
  });
});

// DELETE /api/children/:childId/browsing-history (Parent only)
export const clearBrowsingHistory = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;
  await assertParentOwnsChild(parentId, childId);

  await BrowsingHistoryRecord.deleteMany({ childId });
  res.json({ success: true, message: "Browsing history cleared" });
});
