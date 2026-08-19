import { Router } from "express";
import { createChild, listChildren, getChild } from "../controllers/childrenController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

router.use(requireAuth, requireRole("PARENT"));

router.post("/", createChild);
router.get("/", listChildren);
router.get("/:id", getChild);

export default router;
