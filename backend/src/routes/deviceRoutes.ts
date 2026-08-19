import { Router } from "express";
import { registerDevice } from "../controllers/devicesController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

router.post("/register", requireAuth, requireRole("CHILD"), registerDevice);

export default router;
