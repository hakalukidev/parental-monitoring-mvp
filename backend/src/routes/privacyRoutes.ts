import { Router } from "express";
import { requireAuth, requireRole } from "../middleware/auth";
import { exportHistory, deleteHistory } from "../controllers/privacyController";
const router = Router();
router.get("/:childId/history/export", requireAuth, requireRole("PARENT"), exportHistory);
router.delete("/:childId/history", requireAuth, requireRole("PARENT"), deleteHistory);
export default router;
