import { Router } from "express";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";
import { featureEnabled } from "../services/features";
import { approvedSafetyModels } from "../services/activityValidation";
import { communicationKeyAvailable } from "../services/communicationPrivacy";

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
  res.json({ iceServers, mediaProtocolVersion: 2, webRuleProtocolVersion: 2, consentRequired: true,
    features: { audioCheckIn: featureEnabled("AUDIO"), notificationActivity: featureEnabled("NOTIFICATIONS"), callSmsActivity: featureEnabled("CALL_SMS")||(featureEnabled("COMMUNICATIONS")&&communicationKeyAvailable()),communicationHistory:featureEnabled("COMMUNICATIONS")&&communicationKeyAvailable(), mediaSafety: featureEnabled("SAFETY") && approvedSafetyModels().length > 0 } });
});

export default router;
