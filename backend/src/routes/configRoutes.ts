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
    const turnUrls = env.turnUrl.split(",").map((u) => u.trim()).filter(Boolean);
    for (const url of turnUrls) {
      iceServers.push({
        urls: url,
        username: env.turnUsername,
        credential: env.turnCredential,
      });
    }
  }
  res.json({ iceServers });
});

export default router;
