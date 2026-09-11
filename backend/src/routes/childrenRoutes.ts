import { Router } from "express";
import { createChild, listChildren, getChild } from "../controllers/childrenController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

const parentAuth = [requireAuth, requireRole("PARENT")];

router.post("/", ...parentAuth, createChild);
router.get("/", ...parentAuth, listChildren);
router.get("/:id", ...parentAuth, getChild);

export default router;
