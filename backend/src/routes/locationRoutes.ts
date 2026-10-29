import { Router } from "express";
import {
  recordLocation,
  getLatestLocation,
} from "../controllers/locationController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoints
router.post("/record", requireAuth, requireRole("CHILD"), recordLocation);

// Parent endpoints
router.get("/latest/:childId", requireAuth, requireRole("PARENT"), getLatestLocation);

export default router;
