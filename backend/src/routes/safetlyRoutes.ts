import { Router } from "express";
import { requireAuth, requireRole } from "../middleware/auth";
import {
  safetlyChildDashboard,
  safetlyChildLogin,
  safetlyGetChild,
  safetlyLookupChild,
  safetlyParentChildren,
  safetlyParentLogin,
  safetlyChangeEmail,
  safetlyChangePassword,
  requireSafetlyServiceToken,
  safetlyAdminParentChildren,
  safetlySyncPremium,
} from "../controllers/safetlyController";

const router = Router();

// These routes are the public/domain-facing Safetly app contract.
router.post("/parent/login", safetlyParentLogin);
router.post("/child/login", safetlyChildLogin);
router.get("/parent/childs", requireAuth, requireRole("PARENT"), safetlyParentChildren);
router.get("/parent/children", requireAuth, requireRole("PARENT"), safetlyParentChildren);
router.get("/child/lookup", safetlyLookupChild);
router.get("/child", requireAuth, requireRole("PARENT"), safetlyGetChild);
router.get("/child/dashboard", requireAuth, requireRole("CHILD"), safetlyChildDashboard);
router.patch("/account/email", requireAuth, safetlyChangeEmail);
router.patch("/account/password", requireAuth, safetlyChangePassword);
router.get("/admin/parent-child", requireSafetlyServiceToken, safetlyAdminParentChildren);
router.patch("/child/:id/premium", requireSafetlyServiceToken, safetlySyncPremium);

export default router;
