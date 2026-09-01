import { Router } from "express";
import {
  recordLocation,
  recordLocationBatch,
  getLatestLocation,
  getLocationHistory,
} from "../controllers/locationController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoints
router.post("/record", requireAuth, requireRole("CHILD"), recordLocation);
router.post("/batch", requireAuth, requireRole("CHILD"), recordLocationBatch);

// Parent endpoints
router.get("/latest/:childId", requireAuth, requireRole("PARENT"), getLatestLocation);
router.get("/history/:childId", requireAuth, requireRole("PARENT"), getLocationHistory);

export default router;
