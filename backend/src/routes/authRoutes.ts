import { Router } from "express";
import rateLimit from "express-rate-limit";
import { register, login, refresh, logout, childLogin } from "../controllers/authController";
import { requireAuth } from "../middleware/auth";

const router = Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many attempts, please try again later" },
});

router.post("/register", authLimiter, register);
router.post("/login", authLimiter, login);
router.post("/child-login", authLimiter, childLogin);
router.post("/refresh", refresh);
router.post("/logout", requireAuth, logout);

export default router;
