import { Router } from "express";
import {
  recordSafetyAlertsBatch,
  getSafetyAlerts,
  acknowledgeSafetyAlert,
} from "../controllers/safetyAlertController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoint (batch upload alerts)
router.post("/:childId/safety-alerts/batch", requireAuth, requireRole("CHILD"), recordSafetyAlertsBatch);

// Parent endpoints (query alerts & acknowledge)
router.get("/:childId/safety-alerts", requireAuth, requireRole("PARENT"), getSafetyAlerts);
router.patch("/:childId/safety-alerts/:alertId/acknowledge", requireAuth, requireRole("PARENT"), acknowledgeSafetyAlert);

export default router;
