import { Router } from "express";
import {
  syncNotificationsBatch,
  getNotifications,
  clearNotifications,
} from "../controllers/notificationController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoint (batch upload notifications)
router.post("/:childId/notifications/batch", requireAuth, requireRole("CHILD"), syncNotificationsBatch);

// Parent endpoints (query & clear notifications)
router.get("/:childId/notifications", requireAuth, requireRole("PARENT"), getNotifications);
router.delete("/:childId/notifications", requireAuth, requireRole("PARENT"), clearNotifications);

export default router;
