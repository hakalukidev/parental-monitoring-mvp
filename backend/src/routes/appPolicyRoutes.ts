import { Router } from "express";
import {
  syncInstalledApps,
  listChildApps,
  updateAppPolicy,
  bulkUpdatePolicy,
  toggleDevicePause,
  getMyPolicies,
} from "../controllers/appPolicyController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoints
router.post("/:childId/apps/sync", requireAuth, syncInstalledApps);
router.get("/my-policies", requireAuth, requireRole("CHILD"), getMyPolicies);

// Parent endpoints
router.get("/:childId/apps", requireAuth, requireRole("PARENT"), listChildApps);
router.put(
  "/:childId/apps/:packageName/policy",
  requireAuth,
  requireRole("PARENT"),
  updateAppPolicy
);
router.post(
  "/:childId/apps/bulk-policy",
  requireAuth,
  requireRole("PARENT"),
  bulkUpdatePolicy
);
router.post("/:childId/pause", requireAuth, requireRole("PARENT"), toggleDevicePause);

export default router;
