import { Router } from "express";
import {
  requestAudioStream,
  getAudioStreamSession,
  stopAudioStream,
} from "../controllers/audioStreamController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

router.post("/request", requireAuth, requireRole("PARENT"), requestAudioStream);
router.get("/:id", requireAuth, getAudioStreamSession);
router.post("/:id/stop", requireAuth, stopAudioStream);

export default router;
