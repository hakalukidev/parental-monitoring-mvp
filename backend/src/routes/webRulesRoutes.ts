import { Router } from "express";
import {
  listWebRules,
  createWebRule,
  updateWebRule,
  deleteWebRule,
  getMyWebRules,
} from "../controllers/webRulesController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoint
router.get("/my-web-rules", requireAuth, requireRole("CHILD"), getMyWebRules);

// Parent endpoints
router.get("/:childId/web-rules", requireAuth, requireRole("PARENT"), listWebRules);
router.post("/:childId/web-rules", requireAuth, requireRole("PARENT"), createWebRule);
router.put("/:childId/web-rules/:ruleId", requireAuth, requireRole("PARENT"), updateWebRule);
router.delete("/:childId/web-rules/:ruleId", requireAuth, requireRole("PARENT"), deleteWebRule);

export default router;
