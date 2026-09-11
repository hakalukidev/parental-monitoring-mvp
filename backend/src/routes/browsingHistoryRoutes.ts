import { Router } from "express";
import {
  listBrowsingHistory,
  recordBatchHistory,
  getBrowsingAnalytics,
  clearBrowsingHistory,
} from "../controllers/browsingHistoryController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoint (batch upload)
router.post("/:childId/browsing-history/batch", requireAuth, requireRole("CHILD"), recordBatchHistory);

// Parent endpoints
router.get("/:childId/browsing-history/analytics", requireAuth, requireRole("PARENT"), getBrowsingAnalytics);
router.get("/:childId/browsing-history", requireAuth, requireRole("PARENT"), listBrowsingHistory);
router.delete("/:childId/browsing-history", requireAuth, requireRole("PARENT"), clearBrowsingHistory);

export default router;
