import { Router } from "express";
import {
  syncCallsBatch,
  syncSmsBatch,
  reportCapabilities,
  getCapabilities,
  getCalls,
  getSms,
} from "../controllers/communicationController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoints (batch upload)
router.post("/:childId/communication/calls/batch", requireAuth, requireRole("CHILD"), syncCallsBatch);
router.post("/:childId/communication/sms/batch", requireAuth, requireRole("CHILD"), syncSmsBatch);
router.post("/:childId/communication/capabilities", requireAuth, reportCapabilities);

// Parent endpoints (retrieval with query params)
router.get("/:childId/communication/capabilities", requireAuth, getCapabilities);
router.get("/:childId/communication/calls", requireAuth, requireRole("PARENT"), getCalls);
router.get("/:childId/communication/sms", requireAuth, requireRole("PARENT"), getSms);

export default router;
