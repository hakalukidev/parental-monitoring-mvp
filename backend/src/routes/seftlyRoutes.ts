import { Router } from "express";
import { requireAuth, requireRole } from "../middleware/auth";
import {
  seftlyChildDashboard,
  seftlyChildLogin,
  seftlyGetChild,
  seftlyLookupChild,
  seftlyParentChildren,
  seftlyParentLogin,
  seftlyChangeEmail,
  seftlyChangePassword,
  requireSeftlyServiceToken,
  seftlyAdminParentChildren,
  seftlySyncPremium,
} from "../controllers/seftlyController";

const router = Router();

// These routes are the public/domain-facing Seftly app contract.
router.post("/parent/login", seftlyParentLogin);
router.post("/child/login", seftlyChildLogin);
router.get("/parent/childs", requireAuth, requireRole("PARENT"), seftlyParentChildren);
router.get("/parent/children", requireAuth, requireRole("PARENT"), seftlyParentChildren);
router.get("/child/lookup", seftlyLookupChild);
router.get("/child", requireAuth, requireRole("PARENT"), seftlyGetChild);
router.get("/child/dashboard", requireAuth, requireRole("CHILD"), seftlyChildDashboard);
router.patch("/account/email", requireAuth, seftlyChangeEmail);
router.patch("/account/password", requireAuth, seftlyChangePassword);
router.get("/admin/parent-child", requireSeftlyServiceToken, seftlyAdminParentChildren);
router.patch("/child/:id/premium", requireSeftlyServiceToken, seftlySyncPremium);

export default router;
