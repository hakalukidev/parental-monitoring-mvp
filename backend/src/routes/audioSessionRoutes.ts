import { Router } from "express";
import { requireAuth, requireRole } from "../middleware/auth";
import { requestAudioSession, getAudioSession, stopAudioSession } from "../controllers/audioSessionController";
const router = Router();
router.post("/request", requireAuth, requireRole("PARENT"), requestAudioSession);
router.get("/:id", requireAuth, getAudioSession);
router.post("/:id/stop", requireAuth, stopAudioSession);
export default router;
