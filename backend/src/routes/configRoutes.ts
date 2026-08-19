import { Router } from "express";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";

const router = Router();

// Returns ICE server config so apps don't hardcode STUN/TURN servers.
router.get("/", requireAuth, (_req, res) => {
  const iceServers: { urls: string; username?: string; credential?: string }[] = env.stunServers.map(
    (url) => ({ urls: url })
  );
  if (env.turnUrl) {
    iceServers.push({
      urls: env.turnUrl,
      username: env.turnUsername,
      credential: env.turnCredential,
    });
  }
  res.json({ iceServers });
});

export default router;
