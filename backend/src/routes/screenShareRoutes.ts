import { Router } from "express";
import {
  requestScreenShare,
  getScreenShareSession,
  stopScreenShare,
} from "../controllers/screenShareController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

router.post("/request", requireAuth, requireRole("PARENT"), requestScreenShare);
router.get("/:id", requireAuth, getScreenShareSession);
router.post("/:id/stop", requireAuth, stopScreenShare);

export default router;
