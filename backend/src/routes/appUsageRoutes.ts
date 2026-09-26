import { Router } from "express";
import {
  syncDailyUsage,
  getTodayUsageReport,
  requestUsageSync,
} from "../controllers/appUsageController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child or Parent can sync usage data
router.post("/:childId/usage/sync", requireAuth, syncDailyUsage);

// Parent (or Child) can view today's detailed usage and downtime report
router.get("/:childId/usage/today", requireAuth, getTodayUsageReport);

// Parent can request immediate usage sync from child device over socket
router.post(
  "/:childId/usage/request-sync",
  requireAuth,
  requireRole("PARENT"),
  requestUsageSync
);

export default router;
