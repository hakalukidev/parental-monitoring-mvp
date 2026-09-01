import { Router } from "express";
import {
  requestCameraStream,
  getCameraStreamSession,
  stopCameraStream,
} from "../controllers/cameraStreamController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

router.post("/request", requireAuth, requireRole("PARENT"), requestCameraStream);
router.get("/:id", requireAuth, getCameraStreamSession);
router.post("/:id/stop", requireAuth, stopCameraStream);

export default router;
